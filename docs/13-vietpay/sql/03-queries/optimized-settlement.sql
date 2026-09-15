-- ============================================================================
-- VietPay — Optimized Settlement Query
-- File:    sql/03-queries/optimized-settlement.sql
-- Author:  DBA Team
-- Created: 2026-06-23
-- Engine:  PostgreSQL 15+
-- Purpose: Optimized monthly settlement aggregation on 50M+ rows.
-- ============================================================================

-- ############################################################################
-- APPROACH 1: Direct Query with Covering Index
-- ############################################################################
-- Prerequisites:
--   • idx_txn_settlement_covering index exists (from performance-indexes.sql)
--   • VACUUM has run recently (for index-only scan effectiveness)
--
-- When to use:
--   • Real-time data needed (no staleness tolerance)
--   • Ad-hoc queries with varying date ranges
--   • Acceptable latency: < 1 second (with index), < 200ms (partitioned)
-- ############################################################################

-- ============================================================================
-- 1A. Optimized Settlement Query (Non-partitioned table)
-- ============================================================================
-- The covering partial index idx_txn_settlement_covering ensures:
--   1. Partition-like pruning via WHERE status = 'SETTLED' (partial index)
--   2. Index-Only Scan via INCLUDE (currency, amount)
--   3. No heap access when visibility map is current

SELECT
    source_wallet_id    AS wallet_id,
    currency,
    SUM(amount)         AS total_amount,
    COUNT(*)            AS transaction_count,
    MIN(created_at)     AS first_txn,
    MAX(created_at)     AS last_txn
FROM transactions
WHERE status     = 'SETTLED'
  AND created_at >= :month_start          -- e.g., '2026-01-01'::timestamptz
  AND created_at <  :month_end            -- e.g., '2026-02-01'::timestamptz
GROUP BY source_wallet_id, currency
ORDER BY total_amount DESC;

-- ============================================================================
-- 1B. Same query on Partitioned Table
-- ============================================================================
-- PostgreSQL automatically performs PARTITION PRUNING, scanning only the
-- matching monthly partition(s).

SELECT
    source_wallet_id    AS wallet_id,
    currency,
    SUM(amount)         AS total_amount,
    COUNT(*)            AS transaction_count,
    MIN(created_at)     AS first_txn,
    MAX(created_at)     AS last_txn
FROM transactions_partitioned
WHERE status     = 'SETTLED'
  AND created_at >= :month_start
  AND created_at <  :month_end
GROUP BY source_wallet_id, currency
ORDER BY total_amount DESC;


-- ############################################################################
-- APPROACH 2: Materialized View for Pre-aggregation
-- ############################################################################
-- When to use:
--   • Dashboard / reporting that tolerates slight staleness (e.g., 1-hour lag)
--   • Repeated queries with same parameters (avoid re-scanning)
--   • Very high query frequency (e.g., 100+ dashboard users hitting same data)
--   • Cross-month aggregations or complex JOINs on settlement data
--
-- Trade-offs:
--   • Storage overhead: ~100 bytes per wallet×currency×month row
--   • Refresh cost: REFRESH CONCURRENTLY takes ~2-5 seconds on 50M rows
--   • Data staleness: up to refresh interval (configurable)
-- ############################################################################

-- ============================================================================
-- 2A. Create Materialized View — Monthly Settlement Summary
-- ============================================================================

CREATE MATERIALIZED VIEW IF NOT EXISTS mv_monthly_settlement AS
SELECT
    date_trunc('month', created_at)::DATE   AS settlement_month,
    source_wallet_id                        AS wallet_id,
    currency,
    SUM(amount)                             AS total_amount,
    SUM(fee_amount)                         AS total_fees,
    COUNT(*)                                AS transaction_count,
    MIN(created_at)                         AS first_transaction_at,
    MAX(created_at)                         AS last_transaction_at,
    MAX(settled_at)                         AS last_settled_at
FROM transactions
WHERE status = 'SETTLED'
  AND source_wallet_id IS NOT NULL
GROUP BY
    date_trunc('month', created_at)::DATE,
    source_wallet_id,
    currency
WITH DATA;

-- ============================================================================
-- 2B. Unique Index (required for REFRESH CONCURRENTLY)
-- ============================================================================
-- REFRESH CONCURRENTLY requires at least one unique index covering all
-- rows of the materialized view.

CREATE UNIQUE INDEX IF NOT EXISTS uq_mv_settlement_key
    ON mv_monthly_settlement (settlement_month, wallet_id, currency);

-- Additional indexes for common query patterns
CREATE INDEX IF NOT EXISTS idx_mv_settlement_month
    ON mv_monthly_settlement (settlement_month);

CREATE INDEX IF NOT EXISTS idx_mv_settlement_wallet
    ON mv_monthly_settlement (wallet_id, settlement_month DESC);

-- ============================================================================
-- 2C. Query the Materialized View
-- ============================================================================
-- This is a near-instant lookup (<10ms) regardless of underlying table size.

SELECT
    wallet_id,
    currency,
    total_amount,
    total_fees,
    transaction_count,
    first_transaction_at,
    last_transaction_at
FROM mv_monthly_settlement
WHERE settlement_month = :month_start::DATE      -- e.g., '2026-01-01'
ORDER BY total_amount DESC;


-- ############################################################################
-- APPROACH 2D: Refresh Strategies
-- ############################################################################

-- ============================================================================
-- Strategy 1: Scheduled Refresh (pg_cron)
-- ============================================================================
-- Refresh every hour during business hours, every 4 hours overnight.
-- CONCURRENTLY allows reads during refresh (no lock on the view).

-- Business hours (7 AM - 11 PM, every hour)
-- SELECT cron.schedule(
--     'refresh-mv-settlement-biz',
--     '0 7-23 * * *',
--     $$REFRESH MATERIALIZED VIEW CONCURRENTLY mv_monthly_settlement$$
-- );

-- Overnight (every 4 hours)
-- SELECT cron.schedule(
--     'refresh-mv-settlement-night',
--     '0 0,4 * * *',
--     $$REFRESH MATERIALIZED VIEW CONCURRENTLY mv_monthly_settlement$$
-- );

-- ============================================================================
-- Strategy 2: Event-Driven Refresh (Trigger-based)
-- ============================================================================
-- Refresh when a threshold of new SETTLED transactions is reached.
-- Uses a counter table to track changes since last refresh.

CREATE TABLE IF NOT EXISTS mv_refresh_tracker (
    view_name       VARCHAR(128)    PRIMARY KEY,
    changes_since   INT             NOT NULL DEFAULT 0,
    last_refresh    TIMESTAMPTZ     NOT NULL DEFAULT now(),
    refresh_threshold INT           NOT NULL DEFAULT 1000
);

INSERT INTO mv_refresh_tracker (view_name, refresh_threshold)
VALUES ('mv_monthly_settlement', 1000)
ON CONFLICT (view_name) DO NOTHING;

-- Trigger function: increment counter on transaction settlement
CREATE OR REPLACE FUNCTION fn_track_settlement_changes()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.status = 'SETTLED' AND (OLD IS NULL OR OLD.status <> 'SETTLED') THEN
        UPDATE mv_refresh_tracker
           SET changes_since = changes_since + 1
         WHERE view_name = 'mv_monthly_settlement';
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_track_settlement ON transactions;
CREATE TRIGGER trg_track_settlement
    AFTER INSERT OR UPDATE OF status ON transactions
    FOR EACH ROW
    EXECUTE FUNCTION fn_track_settlement_changes();

-- ============================================================================
-- Strategy 2 — Refresh function (call periodically or on-demand)
-- ============================================================================

CREATE OR REPLACE FUNCTION fn_refresh_mv_if_needed(p_view_name VARCHAR DEFAULT 'mv_monthly_settlement')
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
DECLARE
    v_changes   INT;
    v_threshold INT;
    v_last      TIMESTAMPTZ;
BEGIN
    SELECT changes_since, refresh_threshold, last_refresh
      INTO v_changes, v_threshold, v_last
      FROM mv_refresh_tracker
     WHERE view_name = p_view_name
       FOR UPDATE;               -- lock row during refresh decision

    -- Refresh if threshold exceeded OR last refresh > 1 hour ago
    IF v_changes >= v_threshold
       OR v_last < now() - INTERVAL '1 hour'
    THEN
        EXECUTE format('REFRESH MATERIALIZED VIEW CONCURRENTLY %I', p_view_name);

        UPDATE mv_refresh_tracker
           SET changes_since = 0,
               last_refresh  = now()
         WHERE view_name = p_view_name;

        RAISE NOTICE 'Refreshed % (% changes accumulated)', p_view_name, v_changes;
        RETURN TRUE;
    END IF;

    RETURN FALSE;
END;
$$;

-- ============================================================================
-- Strategy 3: Hybrid — Direct query for current month, MV for historical
-- ============================================================================
-- Best of both worlds: real-time accuracy for current month,
-- instant lookups for historical months.

-- Current month (real-time):
-- Use Approach 1A/1B

-- Historical months (pre-aggregated):
SELECT
    wallet_id,
    currency,
    total_amount,
    transaction_count
FROM mv_monthly_settlement
WHERE settlement_month = '2026-01-01'::DATE;

-- Combined view for seamless access:
CREATE OR REPLACE VIEW v_settlement_report AS
    -- Historical data from materialized view
    SELECT
        settlement_month,
        wallet_id,
        currency,
        total_amount,
        total_fees,
        transaction_count,
        'MATERIALIZED'::TEXT AS data_source
    FROM mv_monthly_settlement
    WHERE settlement_month < date_trunc('month', now())::DATE

    UNION ALL

    -- Current month from live data
    SELECT
        date_trunc('month', created_at)::DATE   AS settlement_month,
        source_wallet_id                        AS wallet_id,
        currency,
        SUM(amount)                             AS total_amount,
        SUM(fee_amount)                         AS total_fees,
        COUNT(*)                                AS transaction_count,
        'LIVE'::TEXT                             AS data_source
    FROM transactions
    WHERE status = 'SETTLED'
      AND source_wallet_id IS NOT NULL
      AND created_at >= date_trunc('month', now())
    GROUP BY
        date_trunc('month', created_at)::DATE,
        source_wallet_id,
        currency;

COMMENT ON VIEW v_settlement_report
    IS 'Unified settlement view: historical months from MV (instant), '
       'current month from live table (real-time). '
       'Use: SELECT * FROM v_settlement_report WHERE settlement_month = ...';

-- ============================================================================
-- End of optimized-settlement.sql
-- ============================================================================
