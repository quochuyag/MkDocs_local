-- ============================================================================
-- VietPay — Core Schema: Double-Entry Ledger
-- File:    sql/01-schema/02-ledger.sql
-- Author:  DBA Team
-- Created: 2026-06-23
-- Engine:  PostgreSQL 15+
-- Purpose: Implement a double-entry bookkeeping ledger where every financial
--          movement produces exactly two entries (DEBIT + CREDIT) that net
--          to zero. This is the single source of truth for all money movement.
-- ============================================================================

-- ============================================================================
-- 1. LEDGER_ENTRIES — Immutable financial journal
-- ============================================================================
-- Design rationale:
--   • Each row records one leg of a double-entry pair.
--   • amount is always > 0; the direction is captured by entry_type.
--   • balance_after stores the wallet's running balance at the time the
--     entry was posted, enabling point-in-time balance reconstruction
--     without scanning the full ledger.
--   • Entries are append-only — no UPDATE / DELETE is ever permitted.
--     This is enforced by a trigger (see section 3).
-- ============================================================================

CREATE TABLE IF NOT EXISTS ledger_entries (
    id              UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    transaction_id  UUID            NOT NULL,       -- FK added after transactions table
    wallet_id       UUID            NOT NULL,
    entry_type      VARCHAR(10)     NOT NULL,
    amount          NUMERIC(19,4)   NOT NULL,
    balance_after   NUMERIC(19,4)   NOT NULL,
    description     TEXT,
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT now(),

    -- ── Foreign Keys ───────────────────────────────────────────────────
    CONSTRAINT fk_ledger_wallet
        FOREIGN KEY (wallet_id) REFERENCES wallets (id)
        ON DELETE RESTRICT,

    -- ── Check Constraints ──────────────────────────────────────────────
    CONSTRAINT ck_ledger_entry_type
        CHECK (entry_type IN ('DEBIT', 'CREDIT')),

    CONSTRAINT ck_ledger_amount_positive
        CHECK (amount > 0),

    CONSTRAINT ck_ledger_balance_after_non_negative
        CHECK (balance_after >= 0)
);

-- ── Indexes ────────────────────────────────────────────────────────────
-- Fast lookup of all entries for a given transaction (verify zero-sum)
CREATE INDEX IF NOT EXISTS idx_ledger_transaction_id
    ON ledger_entries (transaction_id);

-- Wallet statement / balance reconstruction
CREATE INDEX IF NOT EXISTS idx_ledger_wallet_id_created
    ON ledger_entries (wallet_id, created_at DESC);

-- Covering index for wallet reconciliation queries
CREATE INDEX IF NOT EXISTS idx_ledger_wallet_type_amount
    ON ledger_entries (wallet_id, entry_type)
    INCLUDE (amount, balance_after);

-- Time-range scans (regulatory reports)
CREATE INDEX IF NOT EXISTS idx_ledger_created_at
    ON ledger_entries (created_at);

-- ============================================================================
-- 2. IMMUTABILITY TRIGGER — Prevent UPDATE / DELETE on ledger_entries
-- ============================================================================
-- Financial regulations require an immutable audit trail. This trigger
-- rejects any attempt to modify or delete existing ledger rows.
-- ============================================================================

CREATE OR REPLACE FUNCTION fn_ledger_immutable()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION
        'ledger_entries is append-only. % operations are not permitted.',
        TG_OP
        USING ERRCODE = 'restrict_violation';
    RETURN NULL;        -- never reached
END;
$$;

DROP TRIGGER IF EXISTS trg_ledger_no_update ON ledger_entries;
CREATE TRIGGER trg_ledger_no_update
    BEFORE UPDATE OR DELETE ON ledger_entries
    FOR EACH ROW
    EXECUTE FUNCTION fn_ledger_immutable();

-- ============================================================================
-- 3. ZERO-SUM ENFORCEMENT
-- ============================================================================
-- After all entries for a transaction are inserted (typically in a single
-- statement or within a DEFERRED constraint check), we verify that
-- SUM(CASE WHEN entry_type = 'DEBIT' THEN amount ELSE -amount END) = 0.
--
-- Implementation: a CONSTRAINT TRIGGER that fires AFTER INSERT and is
-- DEFERRABLE INITIALLY DEFERRED so all entries in the same transaction
-- (SQL transaction) are visible when the check runs at COMMIT time.
-- ============================================================================

CREATE OR REPLACE FUNCTION fn_check_ledger_zero_sum()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_net NUMERIC(19,4);
BEGIN
    SELECT COALESCE(
               SUM(CASE
                       WHEN entry_type = 'DEBIT'  THEN  amount
                       WHEN entry_type = 'CREDIT' THEN -amount
                   END),
               0
           )
      INTO v_net
      FROM ledger_entries
     WHERE transaction_id = NEW.transaction_id;

    IF v_net <> 0 THEN
        RAISE EXCEPTION
            'Ledger balance violation: transaction % has net = % (must be 0)',
            NEW.transaction_id, v_net
            USING ERRCODE = 'check_violation';
    END IF;

    RETURN NULL;        -- AFTER trigger, return value ignored
END;
$$;

DROP TRIGGER IF EXISTS trg_ledger_zero_sum ON ledger_entries;
CREATE CONSTRAINT TRIGGER trg_ledger_zero_sum
    AFTER INSERT ON ledger_entries
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW
    EXECUTE FUNCTION fn_check_ledger_zero_sum();

-- ============================================================================
-- 4. INTEGRITY VERIFICATION FUNCTION — check_ledger_balance()
-- ============================================================================
-- On-demand reconciliation: compares every wallet's stored balance against
-- the net of its ledger entries. Returns all wallets where a discrepancy
-- exists. An empty result set means the ledger is fully consistent.
--
-- Usage:  SELECT * FROM check_ledger_balance();
-- Schedule this via pg_cron for nightly reconciliation.
-- ============================================================================

CREATE OR REPLACE FUNCTION check_ledger_balance()
RETURNS TABLE (
    wallet_id           UUID,
    stored_balance      NUMERIC(19,4),
    ledger_balance      NUMERIC(19,4),
    discrepancy         NUMERIC(19,4)
)
LANGUAGE plpgsql
STABLE                  -- does not modify data; safe for read replicas
AS $$
BEGIN
    RETURN QUERY
    SELECT
        w.id                                        AS wallet_id,
        w.balance                                   AS stored_balance,
        COALESCE(
            SUM(CASE
                    WHEN le.entry_type = 'CREDIT' THEN  le.amount
                    WHEN le.entry_type = 'DEBIT'  THEN -le.amount
                END),
            0
        )                                           AS ledger_balance,
        w.balance - COALESCE(
            SUM(CASE
                    WHEN le.entry_type = 'CREDIT' THEN  le.amount
                    WHEN le.entry_type = 'DEBIT'  THEN -le.amount
                END),
            0
        )                                           AS discrepancy
    FROM wallets w
    LEFT JOIN ledger_entries le ON le.wallet_id = w.id
    GROUP BY w.id, w.balance
    HAVING w.balance <> COALESCE(
               SUM(CASE
                       WHEN le.entry_type = 'CREDIT' THEN  le.amount
                       WHEN le.entry_type = 'DEBIT'  THEN -le.amount
                   END),
               0
           );
END;
$$;

COMMENT ON FUNCTION check_ledger_balance()
    IS 'Returns wallets where stored balance diverges from ledger-computed '
       'balance. Empty result = fully consistent. Run nightly via pg_cron.';

-- ============================================================================
-- 5. HELPER: Compute wallet balance from ledger (for ad-hoc verification)
-- ============================================================================

CREATE OR REPLACE FUNCTION fn_wallet_ledger_balance(p_wallet_id UUID)
RETURNS NUMERIC(19,4)
LANGUAGE SQL
STABLE
AS $$
    SELECT COALESCE(
               SUM(CASE
                       WHEN entry_type = 'CREDIT' THEN  amount
                       WHEN entry_type = 'DEBIT'  THEN -amount
                   END),
               0
           )
      FROM ledger_entries
     WHERE wallet_id = p_wallet_id;
$$;

-- ============================================================================
-- End of 02-ledger.sql
-- ============================================================================
