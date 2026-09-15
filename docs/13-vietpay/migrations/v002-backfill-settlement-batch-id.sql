-- =============================================================================
-- V002__backfill_settlement_batch_id.sql
-- Phase 2: BACKFILL — Populate settlement_batch_id for existing 50M rows
-- =============================================================================
--
-- MIGRATION CONTEXT:
--   Table: transactions (50M existing rows, ~2M new rows/month)
--   Goal:  Fill settlement_batch_id for all rows WHERE it IS NULL
--   Strategy: ID-based batching with configurable batch size and sleep
--
-- APP BEHAVIOR DURING THIS PHASE:
--   ┌─────────────────────────────────────────────────────────────────────┐
--   │  BEFORE this migration: Deploy app version with DUAL-WRITE logic.  │
--   │                                                                     │
--   │  The app MUST now:                                                  │
--   │    - On INSERT: Write settlement_batch_id (new column)             │
--   │    - On SELECT: Read from BOTH old and new columns                 │
--   │    - Handle NULL settlement_batch_id gracefully (old rows)          │
--   │                                                                     │
--   │  New rows inserted during backfill already have settlement_batch_id │
--   │  set by the application. The backfill only updates old rows.        │
--   └─────────────────────────────────────────────────────────────────────┘
--
-- LOCK ANALYSIS:
--   - Each batch: RowExclusiveLock on updated rows only
--   - No table-level locks beyond normal DML
--   - Advisory lock prevents concurrent backfill runs
--
-- PERFORMANCE IMPACT:
--   - Batch size: 10,000 rows (configurable)
--   - Sleep between batches: 100ms (configurable)
--   - Estimated duration: 50M / 10K = 5,000 batches × ~200ms = ~17 minutes
--   - WAL generation: ~modest (only 1 UUID column updated per row)
--   - Uses partial index idx_transactions_settlement_batch_id_null
--
-- IDEMPOTENCY:
--   - Only updates rows WHERE settlement_batch_id IS NULL
--   - Safe to re-run after interruption (picks up where it left off)
--   - Advisory lock prevents double-execution
--
-- ROLLBACK: See U002__rollback_backfill.sql
-- =============================================================================

DO $$
DECLARE
    -- ═══════════════════════════════════════════════════════════════════════
    -- CONFIGURATION — Adjust these for your production environment
    -- ═══════════════════════════════════════════════════════════════════════
    v_batch_size       CONSTANT INTEGER  := 10000;   -- Rows per batch
    v_sleep_seconds    CONSTANT NUMERIC  := 0.1;     -- Sleep between batches (100ms)
    v_advisory_lock_id CONSTANT BIGINT   := 2024062301; -- Unique ID for this migration

    -- ═══════════════════════════════════════════════════════════════════════
    -- RUNTIME VARIABLES
    -- ═══════════════════════════════════════════════════════════════════════
    v_rows_updated     BIGINT   := 0;
    v_total_updated    BIGINT   := 0;
    v_total_remaining  BIGINT   := 0;
    v_batch_number     INTEGER  := 0;
    v_start_time       TIMESTAMPTZ;
    v_batch_start      TIMESTAMPTZ;
    v_elapsed          INTERVAL;
    v_min_id           UUID;
    v_max_id           UUID;
    v_default_batch_id UUID;

BEGIN
    v_start_time := clock_timestamp();

    -- ─────────────────────────────────────────────────────────────────────
    -- Step 0: Acquire advisory lock to prevent concurrent backfill runs
    -- ─────────────────────────────────────────────────────────────────────
    -- pg_try_advisory_lock returns TRUE if lock acquired, FALSE if already held.
    -- This prevents two DBAs accidentally running the backfill simultaneously.
    IF NOT pg_try_advisory_lock(v_advisory_lock_id) THEN
        RAISE EXCEPTION '[V002] Another backfill process is already running. '
                         'Advisory lock ID % is held.', v_advisory_lock_id;
    END IF;

    RAISE NOTICE '[V002] ════════════════════════════════════════════════════════';
    RAISE NOTICE '[V002] Starting settlement_batch_id backfill';
    RAISE NOTICE '[V002] Batch size: %, Sleep: %s', v_batch_size, v_sleep_seconds;
    RAISE NOTICE '[V002] Start time: %', v_start_time;
    RAISE NOTICE '[V002] ════════════════════════════════════════════════════════';

    -- ─────────────────────────────────────────────────────────────────────
    -- Step 1: Count remaining rows (for progress tracking)
    -- ─────────────────────────────────────────────────────────────────────
    -- Uses the partial index idx_transactions_settlement_batch_id_null
    SELECT count(*) INTO v_total_remaining
    FROM transactions
    WHERE settlement_batch_id IS NULL;

    RAISE NOTICE '[V002] Rows to backfill: %', v_total_remaining;

    IF v_total_remaining = 0 THEN
        RAISE NOTICE '[V002] No rows to backfill. Migration is already complete.';
        PERFORM pg_advisory_unlock(v_advisory_lock_id);
        RETURN;
    END IF;

    -- ─────────────────────────────────────────────────────────────────────
    -- Step 2: Ensure a default settlement batch exists for historical data
    -- ─────────────────────────────────────────────────────────────────────
    -- All pre-existing transactions are assigned to a "HISTORICAL" batch.
    -- This is a business decision: existing transactions that were never
    -- part of a settlement batch get grouped into one.
    INSERT INTO settlement_batches (id, batch_reference, status, currency, total_amount, total_count)
    VALUES (
        '00000000-0000-0000-0000-000000000001'::UUID,
        'SB-HISTORICAL-BACKFILL',
        'COMPLETED',
        'VND',
        0,
        0
    )
    ON CONFLICT (batch_reference) DO NOTHING;

    v_default_batch_id := '00000000-0000-0000-0000-000000000001'::UUID;
    RAISE NOTICE '[V002] Using default batch ID: %', v_default_batch_id;

    -- ─────────────────────────────────────────────────────────────────────
    -- Step 3: Batch-update loop using ID-based ranges
    -- ─────────────────────────────────────────────────────────────────────
    -- Strategy: Use a CTE-based approach that selects a batch of IDs 
    -- WHERE settlement_batch_id IS NULL, then updates only those rows.
    --
    -- Why ID-based instead of ctid?
    --   - ctid can change during VACUUM
    --   - ID-based is stable across concurrent operations
    --   - Works with the partial index on (id) WHERE settlement_batch_id IS NULL
    --
    -- Why not a single UPDATE?
    --   - A single UPDATE on 50M rows would hold RowExclusiveLock for minutes
    --   - Generates massive WAL, risking replication lag
    --   - Blocks autovacuum, leading to table bloat
    --   - Batching lets other transactions interleave
    -- ─────────────────────────────────────────────────────────────────────
    LOOP
        v_batch_number := v_batch_number + 1;
        v_batch_start  := clock_timestamp();

        -- Update a batch of rows using CTE for precise row selection.
        -- The FOR UPDATE SKIP LOCKED prevents deadlocks with concurrent DML.
        WITH batch AS (
            SELECT id
            FROM transactions
            WHERE settlement_batch_id IS NULL
            ORDER BY id
            LIMIT v_batch_size
            FOR UPDATE SKIP LOCKED
        )
        UPDATE transactions t
        SET settlement_batch_id = v_default_batch_id,
            updated_at = now()
        FROM batch b
        WHERE t.id = b.id;

        GET DIAGNOSTICS v_rows_updated = ROW_COUNT;
        v_total_updated := v_total_updated + v_rows_updated;

        -- Exit when no more rows to update
        EXIT WHEN v_rows_updated = 0;

        -- Progress logging every 50 batches (500K rows)
        IF v_batch_number % 50 = 0 THEN
            v_elapsed := clock_timestamp() - v_start_time;
            RAISE NOTICE '[V002] Progress: batch=%, updated=% / %, elapsed=%',
                v_batch_number,
                v_total_updated,
                v_total_remaining,
                v_elapsed;
        END IF;

        -- Yield CPU/IO to other connections
        -- pg_sleep releases all lightweight locks during sleep
        PERFORM pg_sleep(v_sleep_seconds);

        -- Safety: commit-and-continue behavior
        -- In PG, DO blocks run in a single transaction by default.
        -- However, Flyway wraps this in a transaction. If that's a concern,
        -- consider running this script via psql with autocommit or using
        -- dblink for autonomous transactions.
        --
        -- For Flyway: The entire backfill runs in one transaction.
        -- If this is too large, run this script outside Flyway via:
        --   psql -f V002__backfill_settlement_batch_id.sql
        -- with each batch as its own transaction (see alternative below).
    END LOOP;

    -- ─────────────────────────────────────────────────────────────────────
    -- Step 4: Final summary
    -- ─────────────────────────────────────────────────────────────────────
    v_elapsed := clock_timestamp() - v_start_time;
    RAISE NOTICE '[V002] ════════════════════════════════════════════════════════';
    RAISE NOTICE '[V002] Backfill COMPLETE';
    RAISE NOTICE '[V002] Total rows updated: %', v_total_updated;
    RAISE NOTICE '[V002] Total batches: %', v_batch_number;
    RAISE NOTICE '[V002] Total elapsed: %', v_elapsed;
    RAISE NOTICE '[V002] ════════════════════════════════════════════════════════';

    -- ─────────────────────────────────────────────────────────────────────
    -- Step 5: Update the settlement_batches counter
    -- ─────────────────────────────────────────────────────────────────────
    UPDATE settlement_batches
    SET total_count = v_total_updated,
        updated_at  = now()
    WHERE id = v_default_batch_id;

    -- Release advisory lock
    PERFORM pg_advisory_unlock(v_advisory_lock_id);

    RAISE NOTICE '[V002] Advisory lock released. Backfill finished successfully.';
END
$$;

-- =============================================================================
-- ALTERNATIVE: Autonomous-Transaction Backfill (run via psql, NOT Flyway)
-- =============================================================================
-- If the single-transaction approach causes issues (WAL pressure, long-running 
-- transaction holding back VACUUM), use this shell-script approach instead:
--
--   #!/bin/bash
--   BATCH_SIZE=10000
--   while true; do
--     UPDATED=$(psql -t -A -c "
--       WITH batch AS (
--         SELECT id FROM transactions
--         WHERE settlement_batch_id IS NULL
--         ORDER BY id LIMIT $BATCH_SIZE
--         FOR UPDATE SKIP LOCKED
--       )
--       UPDATE transactions t
--       SET settlement_batch_id = '00000000-0000-0000-0000-000000000001'::UUID,
--           updated_at = now()
--       FROM batch b WHERE t.id = b.id
--       RETURNING 1;
--     " | wc -l)
--     echo "Updated: $UPDATED rows"
--     if [ "$UPDATED" -eq "0" ]; then
--       echo "Backfill complete!"
--       break
--     fi
--     sleep 0.1
--   done
--
-- This commits after each batch, reducing WAL and VACUUM pressure.
-- =============================================================================

-- =============================================================================
-- POST-BACKFILL VERIFICATION:
-- =============================================================================
--
-- 1. Check remaining NULLs (should be 0, or only very recent concurrent inserts):
--    SELECT count(*) FROM transactions WHERE settlement_batch_id IS NULL;
--
-- 2. Check total rows with value:
--    SELECT count(*) FROM transactions WHERE settlement_batch_id IS NOT NULL;
--
-- 3. Verify replication lag didn't spike:
--    SELECT client_addr, state, sent_lsn, write_lsn, flush_lsn, replay_lsn,
--           (sent_lsn - replay_lsn) AS replication_lag
--    FROM pg_stat_replication;
--
-- 4. Check table bloat after backfill:
--    SELECT schemaname, relname, n_dead_tup, last_autovacuum
--    FROM pg_stat_user_tables WHERE relname = 'transactions';
--
-- 5. Consider running VACUUM (not FULL) after backfill:
--    VACUUM (VERBOSE) transactions;
-- =============================================================================
