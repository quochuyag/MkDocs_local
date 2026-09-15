-- ============================================================================
-- VietPay — Performance Optimization: Indexes & Partitioning
-- File:    sql/02-indexes/performance-indexes.sql
-- Author:  DBA Team
-- Created: 2026-06-23
-- Engine:  PostgreSQL 15+
-- Purpose: Optimize the monthly settlement aggregation query on 50M+ rows.
--
-- Target query (adapted to actual schema using source_wallet_id):
--   SELECT source_wallet_id, currency, SUM(amount)
--     FROM transactions
--    WHERE status = 'SETTLED'
--      AND created_at >= :month_start
--      AND created_at <  :month_end
--    GROUP BY source_wallet_id, currency;
-- ============================================================================

-- ############################################################################
-- PART A: COVERING PARTIAL INDEX (Non-partitioned approach)
-- ############################################################################
-- Use this if you are NOT partitioning the transactions table (e.g., existing
-- system that cannot be easily migrated to partitioning).
-- ############################################################################

-- ============================================================================
-- A1. Covering Partial Index for Settlement Query
-- ============================================================================
-- WHY partial?
--   • Only rows with status = 'SETTLED' are relevant. On a typical VietPay
--     workload, SETTLED transactions comprise ~60-70% of total rows.
--     However, queries NEVER scan non-SETTLED rows, so a partial index
--     eliminates 30-40% of index bloat.
--
-- WHY covering (INCLUDE)?
--   • The query needs: wallet_id, currency, amount (for GROUP BY / SUM).
--   • By INCLUDEing amount and currency in the index, PostgreSQL can
--     answer the entire query with an INDEX-ONLY SCAN — never touching
--     the heap (table pages).
--   • This is critical at 50M rows: avoiding random I/O to the heap
--     can reduce query time from minutes to seconds.
--
-- Column order: created_at first because the range filter is the most
-- selective predicate (narrows to ~1/12 of data for monthly queries).
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_txn_settlement_covering
    ON transactions (created_at, source_wallet_id)
    INCLUDE (currency, amount)
    WHERE status = 'SETTLED';

-- EXPLAIN ANALYZE prediction (non-partitioned, 50M rows, ~70% SETTLED):
--
-- BEFORE (no index, Seq Scan):
-- ┌────────────────────────────────────────────────────────────────────┐
-- │ HashAggregate                                                     │
-- │   Group Key: source_wallet_id, currency                            │
-- │   →  Seq Scan on transactions                                     │
-- │        Filter: status = 'SETTLED' AND created_at >= '2026-01-01'  │
-- │                AND created_at < '2026-02-01'                      │
-- │        Rows Removed by Filter: ~47,000,000                        │
-- │   Planning Time: 0.2 ms                                           │
-- │   Execution Time: ~45,000 ms  (45 seconds)                       │
-- └────────────────────────────────────────────────────────────────────┘
--
-- AFTER (with idx_txn_settlement_covering):
-- ┌────────────────────────────────────────────────────────────────────┐
-- │ HashAggregate                                                     │
-- │   Group Key: wallet_id, currency                                  │
-- │   →  Index Only Scan using idx_txn_settlement_covering            │
-- │        Index Cond: created_at >= '2026-01-01'                     │
-- │                    AND created_at < '2026-02-01'                  │
-- │        Heap Fetches: 0  (if VACUUM is current)                    │
-- │   Planning Time: 0.3 ms                                           │
-- │   Execution Time: ~800 ms  (< 1 second)                          │
-- └────────────────────────────────────────────────────────────────────┘
--
-- Estimated speedup: ~50x

-- ============================================================================
-- A2. Composite Index for Status + Type Reports
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_txn_status_type_created
    ON transactions (status, type, created_at DESC)
    INCLUDE (amount, currency);

-- ============================================================================
-- A3. Index for Wallet-Level Settlement History
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_txn_wallet_settled
    ON transactions (source_wallet_id, settled_at DESC)
    INCLUDE (amount, currency, fee_amount)
    WHERE status = 'SETTLED' AND source_wallet_id IS NOT NULL;


-- ############################################################################
-- PART B: TABLE PARTITIONING (Recommended for 50M+ rows)
-- ############################################################################
-- Range partitioning by created_at (monthly). This is the RECOMMENDED
-- approach for tables exceeding 10M rows with time-based query patterns.
--
-- Benefits:
--   1. Partition pruning — monthly query only scans 1 partition (~4M rows)
--      instead of the entire 50M row table.
--   2. Efficient bulk operations — DROP old partitions instead of DELETE.
--   3. Parallel scans per partition.
--   4. Smaller per-partition indexes → better cache hit ratio.
--
-- Trade-offs:
--   1. Slightly more complex DDL management.
--   2. Cross-partition queries (e.g., last 90 days) scan multiple partitions.
--   3. Unique constraints must include the partition key.
-- ############################################################################

-- ============================================================================
-- B1. Create Partitioned Transactions Table
-- ============================================================================
-- NOTE: This is a MIGRATION script. In production, you would:
--   1. Create the new partitioned table
--   2. Migrate data in batches
--   3. Swap table names (rename)
--   4. Drop old table
--
-- For a fresh install, use this directly as the transactions table.
-- ============================================================================

CREATE TABLE IF NOT EXISTS transactions_partitioned (
    id                      UUID            NOT NULL DEFAULT gen_random_uuid(),
    reference_number        VARCHAR(50)     NOT NULL,
    idempotency_key_id      UUID,
    source_wallet_id        UUID,
    destination_wallet_id   UUID,
    type                    VARCHAR(20)     NOT NULL,
    amount                  NUMERIC(19,4)   NOT NULL,
    currency                VARCHAR(3)      NOT NULL,
    fee_amount              NUMERIC(19,4)   NOT NULL DEFAULT 0,
    status                  VARCHAR(20)     NOT NULL DEFAULT 'PENDING',
    description             TEXT,
    metadata                JSONB           DEFAULT '{}',
    settlement_batch_id     VARCHAR(50),
    created_at              TIMESTAMPTZ     NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ     NOT NULL DEFAULT now(),
    settled_at              TIMESTAMPTZ,

    -- PK must include partition key
    CONSTRAINT pk_txn_part PRIMARY KEY (id, created_at),

    -- Same CHECK constraints as original
    CONSTRAINT ck_txn_part_type
        CHECK (type IN ('TRANSFER', 'DEPOSIT', 'WITHDRAWAL', 'PAYMENT', 'REFUND')),
    CONSTRAINT ck_txn_part_status
        CHECK (status IN ('PENDING', 'PROCESSING', 'SETTLED', 'FAILED', 'REVERSED')),
    CONSTRAINT ck_txn_part_amount_positive
        CHECK (amount > 0),
    CONSTRAINT ck_txn_part_fee_non_negative
        CHECK (fee_amount >= 0),
    CONSTRAINT ck_txn_part_currency_upper
        CHECK (currency = upper(currency) AND length(currency) = 3)

) PARTITION BY RANGE (created_at);

-- ============================================================================
-- B2. Create Monthly Partitions
-- ============================================================================
-- Generate partitions for 2025-H2 through 2026-H2 (13 months).
-- In production, automate partition creation via pg_partman or pg_cron.
-- ============================================================================

CREATE TABLE IF NOT EXISTS transactions_y2025m07
    PARTITION OF transactions_partitioned
    FOR VALUES FROM ('2025-07-01') TO ('2025-08-01');

CREATE TABLE IF NOT EXISTS transactions_y2025m08
    PARTITION OF transactions_partitioned
    FOR VALUES FROM ('2025-08-01') TO ('2025-09-01');

CREATE TABLE IF NOT EXISTS transactions_y2025m09
    PARTITION OF transactions_partitioned
    FOR VALUES FROM ('2025-09-01') TO ('2025-10-01');

CREATE TABLE IF NOT EXISTS transactions_y2025m10
    PARTITION OF transactions_partitioned
    FOR VALUES FROM ('2025-10-01') TO ('2025-11-01');

CREATE TABLE IF NOT EXISTS transactions_y2025m11
    PARTITION OF transactions_partitioned
    FOR VALUES FROM ('2025-11-01') TO ('2025-12-01');

CREATE TABLE IF NOT EXISTS transactions_y2025m12
    PARTITION OF transactions_partitioned
    FOR VALUES FROM ('2025-12-01') TO ('2026-01-01');

CREATE TABLE IF NOT EXISTS transactions_y2026m01
    PARTITION OF transactions_partitioned
    FOR VALUES FROM ('2026-01-01') TO ('2026-02-01');

CREATE TABLE IF NOT EXISTS transactions_y2026m02
    PARTITION OF transactions_partitioned
    FOR VALUES FROM ('2026-02-01') TO ('2026-03-01');

CREATE TABLE IF NOT EXISTS transactions_y2026m03
    PARTITION OF transactions_partitioned
    FOR VALUES FROM ('2026-03-01') TO ('2026-04-01');

CREATE TABLE IF NOT EXISTS transactions_y2026m04
    PARTITION OF transactions_partitioned
    FOR VALUES FROM ('2026-04-01') TO ('2026-05-01');

CREATE TABLE IF NOT EXISTS transactions_y2026m05
    PARTITION OF transactions_partitioned
    FOR VALUES FROM ('2026-05-01') TO ('2026-06-01');

CREATE TABLE IF NOT EXISTS transactions_y2026m06
    PARTITION OF transactions_partitioned
    FOR VALUES FROM ('2026-06-01') TO ('2026-07-01');

CREATE TABLE IF NOT EXISTS transactions_y2026m07
    PARTITION OF transactions_partitioned
    FOR VALUES FROM ('2026-07-01') TO ('2026-08-01');

-- Default partition for rows outside defined ranges
CREATE TABLE IF NOT EXISTS transactions_default
    PARTITION OF transactions_partitioned DEFAULT;

-- ============================================================================
-- B3. Indexes on Partitioned Table
-- ============================================================================
-- PostgreSQL automatically creates per-partition indexes when you create
-- an index on the parent partitioned table.
-- ============================================================================

-- Unique reference number (must include partition key)
CREATE UNIQUE INDEX IF NOT EXISTS uq_txn_part_reference
    ON transactions_partitioned (reference_number, created_at);

-- Settlement covering index (same strategy as Part A, but per-partition)
CREATE INDEX IF NOT EXISTS idx_txn_part_settlement
    ON transactions_partitioned (created_at, source_wallet_id)
    INCLUDE (currency, amount)
    WHERE status = 'SETTLED';

-- Settlement query aggregates by source_wallet_id (outflows from wallet).
-- In the partitioned table, we may want both:
CREATE INDEX IF NOT EXISTS idx_txn_part_source_wallet
    ON transactions_partitioned (source_wallet_id, created_at DESC)
    WHERE source_wallet_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_txn_part_dest_wallet
    ON transactions_partitioned (destination_wallet_id, created_at DESC)
    WHERE destination_wallet_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_txn_part_status
    ON transactions_partitioned (status, created_at DESC);

-- ============================================================================
-- B4. Automatic Partition Creation Function
-- ============================================================================
-- Schedule via pg_cron to run on the 25th of each month, creating
-- next month's partition proactively.
-- ============================================================================

CREATE OR REPLACE FUNCTION fn_create_next_month_partition()
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    v_next_month    DATE;
    v_month_after   DATE;
    v_table_name    TEXT;
BEGIN
    v_next_month  := date_trunc('month', now() + INTERVAL '1 month')::DATE;
    v_month_after := (v_next_month + INTERVAL '1 month')::DATE;
    v_table_name  := 'transactions_y'
                     || to_char(v_next_month, 'YYYY')
                     || 'm'
                     || to_char(v_next_month, 'MM');

    -- Check if partition already exists
    IF NOT EXISTS (
        SELECT 1 FROM pg_class WHERE relname = v_table_name
    ) THEN
        EXECUTE format(
            'CREATE TABLE %I PARTITION OF transactions_partitioned '
            'FOR VALUES FROM (%L) TO (%L)',
            v_table_name,
            v_next_month,
            v_month_after
        );
        RAISE NOTICE 'Created partition: %', v_table_name;
    ELSE
        RAISE NOTICE 'Partition % already exists', v_table_name;
    END IF;
END;
$$;

-- Schedule: run on 25th of every month at 00:00
-- SELECT cron.schedule('create-txn-partition', '0 0 25 * *',
--     $$SELECT fn_create_next_month_partition()$$);

-- EXPLAIN ANALYZE prediction (partitioned, monthly query):
--
-- ┌────────────────────────────────────────────────────────────────────┐
-- │ HashAggregate                                                     │
-- │   Group Key: source_wallet_id, currency                            │
-- │   →  Index Only Scan using transactions_y2026m01_settlement_idx   │
-- │        Index Cond: created_at >= '2026-01-01'                     │
-- │                    AND created_at < '2026-02-01'                  │
-- │        Heap Fetches: 0                                            │
-- │   Planning Time: 0.5 ms                                           │
-- │   Execution Time: ~200 ms  (partition pruning + index-only scan) │
-- └────────────────────────────────────────────────────────────────────┘
--
-- Only 1 out of 13 partitions is scanned!
-- Estimated speedup vs non-partitioned: ~4x additional improvement
-- Total vs original Seq Scan: ~200x improvement

-- ============================================================================
-- End of performance-indexes.sql
-- ============================================================================
