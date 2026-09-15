-- =============================================================================
-- V001__add_settlement_batch_id_expand.sql
-- Phase 1: EXPAND — Add nullable settlement_batch_id column
-- =============================================================================
--
-- MIGRATION CONTEXT:
--   Table: transactions (50M rows, ~2M new rows/month)
--   Goal:  Add settlement_batch_id UUID NOT NULL via expand-contract pattern
--   This Phase: Add column as NULLABLE (instant metadata-only change in PG 11+)
--
-- APP BEHAVIOR DURING THIS PHASE:
--   ┌─────────────────────────────────────────────────────────────┐
--   │  App continues reading OLD schema shape.                   │
--   │  The new column is IGNORED by the application.             │
--   │  SELECT queries do NOT include settlement_batch_id.        │
--   │  INSERT statements do NOT provide settlement_batch_id.     │
--   │  No application deployment is required for this phase.     │
--   └─────────────────────────────────────────────────────────────┘
--
-- LOCK ANALYSIS:
--   - ADD COLUMN (nullable, no default): AccessExclusiveLock, but instant
--     (PG 11+ stores NULL as metadata, no table rewrite)
--   - CREATE TABLE IF NOT EXISTS: brief AccessExclusiveLock on pg_class
--   - CREATE INDEX CONCURRENTLY: ShareUpdateExclusiveLock (does NOT block DML)
--
-- IDEMPOTENCY: All statements use IF NOT EXISTS / conditional logic
-- ESTIMATED DURATION: < 5 seconds (excluding concurrent index build)
-- ROLLBACK: See U001__rollback_expand.sql
-- =============================================================================

-- Guard: Prevent long waits for locks during peak traffic.
-- If we can't acquire the lock in 5 seconds, fail fast and retry later.
SET lock_timeout = '5s';

-- Set a reasonable statement timeout for DDL (excluding CONCURRENTLY)
SET statement_timeout = '30s';

BEGIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- Step 1: Create the settlement_batches reference table
-- ─────────────────────────────────────────────────────────────────────────────
-- This table groups transactions into settlement batches for reconciliation.
-- It is the parent table that settlement_batch_id will reference.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS settlement_batches (
    id              UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    batch_reference VARCHAR(64)     NOT NULL,           -- Human-readable batch ID (e.g., "SB-20260623-001")
    status          VARCHAR(32)     NOT NULL DEFAULT 'PENDING',  -- PENDING, PROCESSING, COMPLETED, FAILED
    currency        VARCHAR(3)      NOT NULL,           -- ISO 4217 currency code
    total_amount    NUMERIC(19, 4)  NOT NULL DEFAULT 0, -- Sum of all transaction amounts in the batch
    total_count     INTEGER         NOT NULL DEFAULT 0, -- Number of transactions in the batch
    settled_at      TIMESTAMPTZ,                        -- When the batch was settled
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ     NOT NULL DEFAULT now(),
    -- Ensure batch references are unique
    CONSTRAINT uq_settlement_batches_reference UNIQUE (batch_reference)
);

-- Add a comment for documentation
COMMENT ON TABLE settlement_batches IS 
    'Groups transactions into settlement batches for bank reconciliation. '
    'Created as part of V001 expand-contract migration.';

-- ─────────────────────────────────────────────────────────────────────────────
-- Step 2: Add settlement_batch_id column to transactions (NULLABLE)
-- ─────────────────────────────────────────────────────────────────────────────
-- In PostgreSQL 11+, adding a nullable column with no default is a 
-- metadata-only operation. It does NOT rewrite the table, does NOT scan 
-- existing rows, and completes in milliseconds regardless of table size.
--
-- The AccessExclusiveLock is held for only microseconds.
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
BEGIN
    -- Check if column already exists (idempotent)
    IF NOT EXISTS (
        SELECT 1 
        FROM information_schema.columns 
        WHERE table_schema = 'public' 
          AND table_name   = 'transactions' 
          AND column_name  = 'settlement_batch_id'
    ) THEN
        ALTER TABLE transactions 
            ADD COLUMN settlement_batch_id UUID;
        
        RAISE NOTICE '[V001] Column settlement_batch_id added to transactions table.';
    ELSE
        RAISE NOTICE '[V001] Column settlement_batch_id already exists. Skipping.';
    END IF;
END
$$;

-- Add column documentation
COMMENT ON COLUMN transactions.settlement_batch_id IS 
    'FK to settlement_batches.id. Added in V001 (expand phase). '
    'Will become NOT NULL after backfill in V003.';

-- ─────────────────────────────────────────────────────────────────────────────
-- Step 3: Add foreign key constraint (NOT VALID to avoid full table scan)
-- ─────────────────────────────────────────────────────────────────────────────
-- NOT VALID means:
--   - PG will enforce the FK for NEW/UPDATED rows immediately
--   - PG will NOT scan existing rows (which are all NULL anyway)
--   - We can VALIDATE later after backfill if desired
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM information_schema.table_constraints 
        WHERE constraint_name = 'fk_transactions_settlement_batch_id'
          AND table_name = 'transactions'
    ) THEN
        ALTER TABLE transactions
            ADD CONSTRAINT fk_transactions_settlement_batch_id
            FOREIGN KEY (settlement_batch_id)
            REFERENCES settlement_batches (id)
            NOT VALID;
        
        RAISE NOTICE '[V001] FK constraint fk_transactions_settlement_batch_id added (NOT VALID).';
    ELSE
        RAISE NOTICE '[V001] FK constraint fk_transactions_settlement_batch_id already exists. Skipping.';
    END IF;
END
$$;

COMMIT;

-- ─────────────────────────────────────────────────────────────────────────────
-- Step 4: Create index CONCURRENTLY (must be outside transaction block)
-- ─────────────────────────────────────────────────────────────────────────────
-- CREATE INDEX CONCURRENTLY:
--   - Takes ShareUpdateExclusiveLock (does NOT block INSERT/UPDATE/DELETE)
--   - Builds the index in the background with two table scans
--   - May take 5-15 minutes on 50M rows depending on I/O
--   - Safe for production — only blocks other DDL, not DML
--
-- NOTE: If this fails midway, a INVALID index will be left behind.
--       Check with: SELECT * FROM pg_indexes WHERE indexname = '...' 
--       and pg_index.indisvalid. Drop and recreate if invalid.
-- ─────────────────────────────────────────────────────────────────────────────

-- Reset timeouts for long-running concurrent index build
SET lock_timeout = '10s';
SET statement_timeout = '0';  -- No timeout for CONCURRENTLY operations

-- Index on settlement_batch_id for:
--   - FK lookups (when querying settlement_batches)
--   - Filtering transactions by batch
--   - The upcoming backfill query (WHERE settlement_batch_id IS NULL)
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_transactions_settlement_batch_id
    ON transactions (settlement_batch_id);

-- Partial index to speed up the backfill query in V002
-- This index only includes rows where settlement_batch_id IS NULL,
-- so it shrinks as the backfill progresses. Very efficient.
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_transactions_settlement_batch_id_null
    ON transactions (id)
    WHERE settlement_batch_id IS NULL;

-- ─────────────────────────────────────────────────────────────────────────────
-- Step 5: Validate the foreign key constraint (outside transaction)
-- ─────────────────────────────────────────────────────────────────────────────
-- VALIDATE scans existing rows to verify FK integrity.
-- Since all existing rows have NULL (which satisfies FK), this is fast.
-- Takes ShareUpdateExclusiveLock — does NOT block DML.
-- ─────────────────────────────────────────────────────────────────────────────
-- Note: We skip FK validation here because all values are NULL.
-- The FK will be validated organically as the backfill runs, since 
-- NOT VALID already enforces for new writes. Full VALIDATE can be
-- done after backfill in V003 if desired.

-- Reset timeouts to defaults
RESET lock_timeout;
RESET statement_timeout;

-- =============================================================================
-- POST-MIGRATION VERIFICATION (run manually):
-- =============================================================================
-- 
-- 1. Verify column exists:
--    SELECT column_name, data_type, is_nullable 
--    FROM information_schema.columns 
--    WHERE table_name = 'transactions' AND column_name = 'settlement_batch_id';
--
-- 2. Verify indexes are valid:
--    SELECT indexname, indexdef 
--    FROM pg_indexes 
--    WHERE tablename = 'transactions' AND indexname LIKE '%settlement%';
--
--    SELECT indexrelid::regclass, indisvalid 
--    FROM pg_index 
--    WHERE indexrelid::regclass::text LIKE '%settlement%';
--
-- 3. Verify FK constraint:
--    SELECT conname, convalidated 
--    FROM pg_constraint 
--    WHERE conname = 'fk_transactions_settlement_batch_id';
--
-- 4. Verify settlement_batches table:
--    SELECT * FROM information_schema.tables 
--    WHERE table_name = 'settlement_batches';
-- =============================================================================
