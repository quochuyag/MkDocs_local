-- ============================================================================
-- VietPay — Core Schema: Transactions
-- File:    sql/01-schema/03-transactions.sql
-- Author:  DBA Team
-- Created: 2026-06-23
-- Engine:  PostgreSQL 15+
-- Purpose: Central transactions table that records every financial operation
--          (transfer, deposit, withdrawal, payment, refund).
-- ============================================================================

-- ============================================================================
-- 1. TRANSACTIONS
-- ============================================================================
-- Design rationale:
--   • reference_number is a human-readable, externally-shareable ID
--     (e.g., "TXN-20260623-ABCD1234"). UUID id is the internal PK.
--   • idempotency_key_id links to the idempotency_keys table so that
--     retried requests return the original result without double-posting.
--   • source / destination wallets are nullable to support one-sided ops:
--       - DEPOSIT:    source is NULL  (money comes from external)
--       - WITHDRAWAL: destination is NULL (money leaves to external)
--       - TRANSFER:   both populated
--   • metadata JSONB stores payment-method-specific details (card last-4,
--     bank reference, QR payload, etc.) without schema changes.
--   • settlement_batch_id groups transactions for end-of-day settlement.
-- ============================================================================

CREATE TABLE IF NOT EXISTS transactions (
    id                      UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
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

    -- ── Foreign Keys ───────────────────────────────────────────────────
    CONSTRAINT fk_txn_source_wallet
        FOREIGN KEY (source_wallet_id) REFERENCES wallets (id)
        ON DELETE RESTRICT,

    CONSTRAINT fk_txn_destination_wallet
        FOREIGN KEY (destination_wallet_id) REFERENCES wallets (id)
        ON DELETE RESTRICT,

    -- idempotency FK added in 04-idempotency.sql after table creation

    -- ── Check Constraints ──────────────────────────────────────────────
    CONSTRAINT ck_txn_type
        CHECK (type IN ('TRANSFER', 'DEPOSIT', 'WITHDRAWAL', 'PAYMENT', 'REFUND')),

    CONSTRAINT ck_txn_status
        CHECK (status IN ('PENDING', 'PROCESSING', 'SETTLED', 'FAILED', 'REVERSED')),

    CONSTRAINT ck_txn_amount_positive
        CHECK (amount > 0),

    CONSTRAINT ck_txn_fee_non_negative
        CHECK (fee_amount >= 0),

    CONSTRAINT ck_txn_currency_upper
        CHECK (currency = upper(currency) AND length(currency) = 3),

    -- Deposits have no source; withdrawals have no destination
    CONSTRAINT ck_txn_wallet_presence
        CHECK (
            CASE type
                WHEN 'DEPOSIT'    THEN source_wallet_id IS NULL
                                       AND destination_wallet_id IS NOT NULL
                WHEN 'WITHDRAWAL' THEN source_wallet_id IS NOT NULL
                                       AND destination_wallet_id IS NULL
                WHEN 'TRANSFER'   THEN source_wallet_id IS NOT NULL
                                       AND destination_wallet_id IS NOT NULL
                                       AND source_wallet_id <> destination_wallet_id
                WHEN 'PAYMENT'    THEN source_wallet_id IS NOT NULL
                                       AND destination_wallet_id IS NOT NULL
                WHEN 'REFUND'     THEN source_wallet_id IS NOT NULL
                                       AND destination_wallet_id IS NOT NULL
                ELSE TRUE
            END
        ),

    -- settled_at must be set when status = SETTLED
    CONSTRAINT ck_txn_settled_at_consistency
        CHECK (
            (status = 'SETTLED' AND settled_at IS NOT NULL)
            OR
            (status <> 'SETTLED')
        )
);

-- ── Unique Constraints ─────────────────────────────────────────────────
CREATE UNIQUE INDEX IF NOT EXISTS uq_txn_reference_number
    ON transactions (reference_number);

-- ── Indexes ────────────────────────────────────────────────────────────

-- Most common query pattern: find transactions by wallet (either side)
CREATE INDEX IF NOT EXISTS idx_txn_source_wallet
    ON transactions (source_wallet_id, created_at DESC)
    WHERE source_wallet_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_txn_destination_wallet
    ON transactions (destination_wallet_id, created_at DESC)
    WHERE destination_wallet_id IS NOT NULL;

-- Status-based filtering (operations dashboard, settlement processing)
CREATE INDEX IF NOT EXISTS idx_txn_status
    ON transactions (status, created_at DESC);

-- Settlement batch lookup
CREATE INDEX IF NOT EXISTS idx_txn_settlement_batch
    ON transactions (settlement_batch_id)
    WHERE settlement_batch_id IS NOT NULL;

-- Date range queries (reporting, compliance)
CREATE INDEX IF NOT EXISTS idx_txn_created_at
    ON transactions (created_at);

-- Type + status for aggregated reporting
CREATE INDEX IF NOT EXISTS idx_txn_type_status
    ON transactions (type, status);

-- Idempotency key lookup
CREATE INDEX IF NOT EXISTS idx_txn_idempotency_key
    ON transactions (idempotency_key_id)
    WHERE idempotency_key_id IS NOT NULL;

-- JSONB metadata — GIN index for flexible querying
CREATE INDEX IF NOT EXISTS idx_txn_metadata
    ON transactions USING gin (metadata jsonb_path_ops);

-- ============================================================================
-- 2. ADD FK from ledger_entries → transactions
-- ============================================================================
-- This ALTER is placed here because ledger_entries is created before
-- transactions (file ordering). We add the FK post-hoc.
-- ============================================================================

ALTER TABLE ledger_entries
    DROP CONSTRAINT IF EXISTS fk_ledger_transaction;

ALTER TABLE ledger_entries
    ADD CONSTRAINT fk_ledger_transaction
        FOREIGN KEY (transaction_id) REFERENCES transactions (id)
        ON DELETE RESTRICT;

-- ============================================================================
-- 3. STATUS TRANSITION GUARD TRIGGER
-- ============================================================================
-- Enforces a valid state machine:
--   PENDING → PROCESSING → SETTLED
--                        → FAILED
--   SETTLED → REVERSED
-- Any other transition is rejected.
-- ============================================================================

CREATE OR REPLACE FUNCTION fn_txn_status_transition()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    -- Allow no-op (same status)
    IF OLD.status = NEW.status THEN
        RETURN NEW;
    END IF;

    -- Define valid transitions
    IF     (OLD.status = 'PENDING'    AND NEW.status = 'PROCESSING')
        OR (OLD.status = 'PROCESSING' AND NEW.status IN ('SETTLED', 'FAILED'))
        OR (OLD.status = 'SETTLED'    AND NEW.status = 'REVERSED')
        OR (OLD.status = 'PENDING'    AND NEW.status = 'FAILED')
    THEN
        -- Auto-set settled_at when transitioning to SETTLED
        IF NEW.status = 'SETTLED' AND NEW.settled_at IS NULL THEN
            NEW.settled_at = now();
        END IF;
        RETURN NEW;
    END IF;

    RAISE EXCEPTION
        'Invalid transaction status transition: % → %',
        OLD.status, NEW.status
        USING ERRCODE = 'check_violation';
END;
$$;

DROP TRIGGER IF EXISTS trg_txn_status_transition ON transactions;
CREATE TRIGGER trg_txn_status_transition
    BEFORE UPDATE OF status ON transactions
    FOR EACH ROW
    EXECUTE FUNCTION fn_txn_status_transition();

-- ============================================================================
-- 4. Auto-update updated_at (reuse function from 01-accounts-wallets.sql)
-- ============================================================================

DROP TRIGGER IF EXISTS trg_txn_updated_at ON transactions;
CREATE TRIGGER trg_txn_updated_at
    BEFORE UPDATE ON transactions
    FOR EACH ROW
    EXECUTE FUNCTION fn_set_updated_at();

-- ============================================================================
-- End of 03-transactions.sql
-- ============================================================================
