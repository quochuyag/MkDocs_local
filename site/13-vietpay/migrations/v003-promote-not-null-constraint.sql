-- =============================================================================
-- V003__promote_not_null_constraint.sql
-- Phase 3: CONTRACT — Promote settlement_batch_id to NOT NULL
-- =============================================================================
--
-- MIGRATION CONTEXT:
--   Table: transactions (50M+ rows)
--   Pre-condition: V002 backfill is COMPLETE, zero NULL rows remaining
--   Goal:  Enforce NOT NULL on settlement_batch_id without downtime
--
-- APP BEHAVIOR DURING THIS PHASE:
--   ┌─────────────────────────────────────────────────────────────────────┐
--   │  App is now reading and writing the NEW schema shape exclusively.  │
--   │  All code paths include settlement_batch_id.                       │
--   │  Old code paths (that ignore settlement_batch_id) are removed.     │
--   │  After this migration, INSERT without settlement_batch_id FAILS.   │
--   └─────────────────────────────────────────────────────────────────────┘
--
-- STRATEGY: The "NOT VALID + VALIDATE" pattern (PG 12+)
--   ═══════════════════════════════════════════════════════════════════════
--   PostgreSQL 12+ recognizes validated CHECK constraints when you run
--   ALTER TABLE ... SET NOT NULL. If a matching validated CHECK exists,
--   PG skips the full table scan that SET NOT NULL normally requires.
--
--   This gives us the best of both worlds:
--     1. CHECK NOT VALID: Instant, no table scan, enforces for NEW rows
--     2. VALIDATE CONSTRAINT: ShareUpdateExclusiveLock only (no DML blocking)
--     3. SET NOT NULL: Instant because validated CHECK already proves it
--   ═══════════════════════════════════════════════════════════════════════
--
-- LOCK ANALYSIS:
--   Step 1 (ADD CONSTRAINT NOT VALID): AccessExclusiveLock, but instant
--   Step 2 (VALIDATE CONSTRAINT):      ShareUpdateExclusiveLock (no DML block)
--   Step 3 (SET NOT NULL):             AccessExclusiveLock, but instant (PG 12+)
--   Step 4 (DROP CHECK):              AccessExclusiveLock, but instant
--
-- IDEMPOTENCY: All steps check for existing constraints/state
-- ESTIMATED DURATION: Step 2 takes ~2-5 minutes (full scan under light lock)
-- ROLLBACK: See U003__rollback_constraint.sql
-- =============================================================================

-- Tight lock timeout: if there's lock contention, fail fast
SET lock_timeout = '5s';
SET statement_timeout = '30s';

-- =============================================================================
-- PRE-FLIGHT CHECK: Ensure no NULL rows remain
-- =============================================================================
-- If this fails, the backfill (V002) is incomplete. DO NOT proceed.
DO $$
DECLARE
    v_null_count BIGINT;
BEGIN
    SELECT count(*) INTO v_null_count
    FROM transactions
    WHERE settlement_batch_id IS NULL;

    IF v_null_count > 0 THEN
        RAISE EXCEPTION '[V003] PRE-FLIGHT FAILED: % rows still have NULL settlement_batch_id. '
                         'Run V002 backfill to completion before proceeding.', v_null_count;
    END IF;

    RAISE NOTICE '[V003] Pre-flight check passed: 0 NULL rows.';
END
$$;

-- =============================================================================
-- Step 1: ADD CHECK CONSTRAINT (NOT VALID)
-- =============================================================================
-- This is an instant metadata operation. It does NOT scan the table.
-- From this moment forward, any INSERT/UPDATE that sets settlement_batch_id 
-- to NULL will be rejected.
--
-- Lock: AccessExclusiveLock, but held for microseconds.
-- =============================================================================
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'chk_transactions_settlement_batch_id_not_null'
          AND conrelid = 'transactions'::regclass
    ) THEN
        ALTER TABLE transactions
            ADD CONSTRAINT chk_transactions_settlement_batch_id_not_null
            CHECK (settlement_batch_id IS NOT NULL)
            NOT VALID;

        RAISE NOTICE '[V003] CHECK constraint added (NOT VALID) — new writes enforced.';
    ELSE
        RAISE NOTICE '[V003] CHECK constraint already exists. Skipping creation.';
    END IF;
END
$$;

-- =============================================================================
-- Step 2: VALIDATE CONSTRAINT (full table scan under light lock)
-- =============================================================================
-- VALIDATE scans all existing rows to verify the CHECK is satisfied.
-- 
-- Lock: ShareUpdateExclusiveLock
--   - Does NOT block: SELECT, INSERT, UPDATE, DELETE
--   - DOES block: Other DDL, VACUUM FULL, another VALIDATE
--   - This is the key reason this approach is safe for production
--
-- Duration: ~2-5 minutes for 50M rows (depends on I/O and table size)
-- 
-- After validation, PG marks the constraint as convalidated = true,
-- which enables the optimization in Step 3.
-- =============================================================================

-- Remove statement timeout for the validation scan
SET statement_timeout = '0';
-- Keep lock timeout tight — if we can't get the lock, retry later
SET lock_timeout = '10s';

DO $$
DECLARE
    v_is_validated BOOLEAN;
BEGIN
    -- Check if already validated
    SELECT convalidated INTO v_is_validated
    FROM pg_constraint
    WHERE conname = 'chk_transactions_settlement_batch_id_not_null'
      AND conrelid = 'transactions'::regclass;

    IF v_is_validated IS NULL THEN
        RAISE EXCEPTION '[V003] CHECK constraint not found. Run Step 1 first.';
    END IF;

    IF NOT v_is_validated THEN
        RAISE NOTICE '[V003] Validating CHECK constraint (full table scan, light lock)...';
        RAISE NOTICE '[V003] This may take 2-5 minutes on 50M rows. DML is NOT blocked.';

        ALTER TABLE transactions
            VALIDATE CONSTRAINT chk_transactions_settlement_batch_id_not_null;

        RAISE NOTICE '[V003] CHECK constraint validated successfully.';
    ELSE
        RAISE NOTICE '[V003] CHECK constraint already validated. Skipping.';
    END IF;
END
$$;

-- =============================================================================
-- Step 3: SET NOT NULL (instant with validated CHECK — PG 12+)
-- =============================================================================
-- PostgreSQL 12+ optimization:
--   When a validated CHECK (col IS NOT NULL) exists, ALTER TABLE SET NOT NULL
--   does NOT perform a table scan. It simply adds the NOT NULL marker
--   to the column metadata. This is instant.
--
-- Lock: AccessExclusiveLock, but held for microseconds.
--
-- Reference: https://www.postgresql.org/docs/current/sql-altertable.html
--   "SET NOT NULL may only be applied to a column provided no existing row
--    contains a null value. Ordinarily this is checked during ALTER TABLE
--    by scanning the entire table; however, if a valid CHECK constraint
--    is found which proves no NULL can exist, then the table scan is skipped."
-- =============================================================================

SET lock_timeout = '5s';
SET statement_timeout = '30s';

DO $$
DECLARE
    v_is_nullable TEXT;
BEGIN
    SELECT is_nullable INTO v_is_nullable
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name   = 'transactions'
      AND column_name  = 'settlement_batch_id';

    IF v_is_nullable = 'YES' THEN
        ALTER TABLE transactions
            ALTER COLUMN settlement_batch_id SET NOT NULL;

        RAISE NOTICE '[V003] Column settlement_batch_id is now NOT NULL.';
    ELSE
        RAISE NOTICE '[V003] Column settlement_batch_id is already NOT NULL. Skipping.';
    END IF;
END
$$;

-- =============================================================================
-- Step 4: DROP the CHECK constraint (no longer needed)
-- =============================================================================
-- The NOT NULL column constraint is now enforced at the column level.
-- The CHECK constraint was only a stepping stone and can be removed.
--
-- Lock: AccessExclusiveLock, but instant (metadata change only).
-- =============================================================================
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'chk_transactions_settlement_batch_id_not_null'
          AND conrelid = 'transactions'::regclass
    ) THEN
        ALTER TABLE transactions
            DROP CONSTRAINT chk_transactions_settlement_batch_id_not_null;

        RAISE NOTICE '[V003] CHECK constraint dropped (NOT NULL is now column-level).';
    ELSE
        RAISE NOTICE '[V003] CHECK constraint already dropped. Skipping.';
    END IF;
END
$$;

-- =============================================================================
-- Step 5: Validate the FK constraint (if not already validated in V001)
-- =============================================================================
-- Now that all rows have a valid settlement_batch_id, we can fully validate
-- the FK constraint that was added NOT VALID in V001.
-- =============================================================================
DO $$
DECLARE
    v_is_validated BOOLEAN;
BEGIN
    SELECT convalidated INTO v_is_validated
    FROM pg_constraint
    WHERE conname = 'fk_transactions_settlement_batch_id'
      AND conrelid = 'transactions'::regclass;

    IF v_is_validated = false THEN
        -- Reset statement timeout for FK scan (can take 2-5 min on 50M rows)
        EXECUTE 'SET statement_timeout = ''0''';
        RAISE NOTICE '[V003] Validating FK constraint fk_transactions_settlement_batch_id...';


        ALTER TABLE transactions
            VALIDATE CONSTRAINT fk_transactions_settlement_batch_id;

        RAISE NOTICE '[V003] FK constraint validated.';
    ELSIF v_is_validated = true THEN
        RAISE NOTICE '[V003] FK constraint already validated. Skipping.';
    ELSE
        RAISE NOTICE '[V003] FK constraint not found. Skipping validation.';
    END IF;
END
$$;

-- =============================================================================
-- Step 6: Clean up the partial index (no longer needed after backfill)
-- =============================================================================
-- The partial index on (id) WHERE settlement_batch_id IS NULL was created
-- in V001 to speed up the backfill. Now that there are no NULL rows,
-- this index is empty and useless.
-- =============================================================================
DROP INDEX CONCURRENTLY IF EXISTS idx_transactions_settlement_batch_id_null;

-- Reset timeouts
RESET lock_timeout;
RESET statement_timeout;

-- =============================================================================
-- POST-MIGRATION VERIFICATION:
-- =============================================================================
--
-- 1. Verify NOT NULL is enforced:
--    SELECT column_name, is_nullable 
--    FROM information_schema.columns 
--    WHERE table_name = 'transactions' AND column_name = 'settlement_batch_id';
--    -- Expected: is_nullable = 'NO'
--
-- 2. Verify CHECK constraint is gone (replaced by column NOT NULL):
--    SELECT conname, convalidated 
--    FROM pg_constraint 
--    WHERE conrelid = 'transactions'::regclass 
--      AND conname LIKE '%settlement%';
--    -- Expected: only fk_transactions_settlement_batch_id (validated = true)
--
-- 3. Verify partial index is dropped:
--    SELECT indexname FROM pg_indexes 
--    WHERE tablename = 'transactions' 
--      AND indexname = 'idx_transactions_settlement_batch_id_null';
--    -- Expected: no rows
--
-- 4. Test that NULL insert is rejected:
--    INSERT INTO transactions (id, settlement_batch_id, ...) 
--    VALUES (gen_random_uuid(), NULL, ...);
--    -- Expected: ERROR: null value in column "settlement_batch_id"
--
-- 5. Final index status:
--    SELECT indexname, indexdef FROM pg_indexes 
--    WHERE tablename = 'transactions' AND indexname LIKE '%settlement%';
--    -- Expected: idx_transactions_settlement_batch_id only
-- =============================================================================
