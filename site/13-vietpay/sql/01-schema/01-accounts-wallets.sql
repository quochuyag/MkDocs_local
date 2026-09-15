-- ============================================================================
-- VietPay — Core Schema: Accounts & Wallets
-- File:    sql/01-schema/01-accounts-wallets.sql
-- Author:  DBA Team
-- Created: 2026-06-23
-- Engine:  PostgreSQL 15+
-- Purpose: Define the foundational account and wallet tables for the
--          VietPay digital wallet platform.
-- ============================================================================

-- Enable UUID generation (idempotent)
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================================
-- 1. ACCOUNTS — Represents a registered user / entity
-- ============================================================================
-- Design rationale:
--   • UUID primary key avoids sequential-ID enumeration attacks.
--   • KYC level gates which operations / limits a user may access.
--   • status enum is modelled as a CHECK constraint rather than a separate
--     lookup table because the set is small, stable, and controlled by code.
--   • updated_at is auto-managed via trigger to guarantee consistency.
-- ============================================================================

CREATE TABLE IF NOT EXISTS accounts (
    id              UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    email           VARCHAR(255)    NOT NULL,
    phone_number    VARCHAR(20),
    full_name       VARCHAR(255)    NOT NULL,
    status          VARCHAR(20)     NOT NULL DEFAULT 'ACTIVE',
    kyc_level       SMALLINT        NOT NULL DEFAULT 0,
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ     NOT NULL DEFAULT now(),

    -- ── Constraints ────────────────────────────────────────────────────
    CONSTRAINT ck_accounts_status
        CHECK (status IN ('ACTIVE', 'SUSPENDED', 'CLOSED', 'PENDING_VERIFICATION')),

    CONSTRAINT ck_accounts_kyc_level
        CHECK (kyc_level BETWEEN 0 AND 3)
        -- 0 = unverified, 1 = basic, 2 = enhanced, 3 = full
);

-- Unique indexes — enforce business rules at DB level
CREATE UNIQUE INDEX IF NOT EXISTS uq_accounts_email
    ON accounts (lower(email));

CREATE UNIQUE INDEX IF NOT EXISTS uq_accounts_phone
    ON accounts (phone_number)
    WHERE phone_number IS NOT NULL;

-- Lookup by status (partial — only non-CLOSED accounts are queried often)
CREATE INDEX IF NOT EXISTS idx_accounts_status
    ON accounts (status)
    WHERE status <> 'CLOSED';

-- Covering index for common profile lookups
CREATE INDEX IF NOT EXISTS idx_accounts_created_at
    ON accounts (created_at);

-- ============================================================================
-- 2. WALLETS — Each account may hold multiple currency wallets
-- ============================================================================
-- Design rationale:
--   • (account_id, currency) is unique — one wallet per currency per account.
--   • Three-balance model:
--       balance           = total ledger balance (always matches ledger sum)
--       available_balance  = balance − holds / pending debits
--       pending_balance    = funds awaiting settlement / clearance
--   • All balances are NUMERIC(19,4) to handle large fiat amounts with
--     sub-cent precision (important for FX and fee calculations).
--   • CHECK constraints prevent negative balances at the row level.
--     Application logic must still use SELECT … FOR UPDATE to avoid races.
-- ============================================================================

CREATE TABLE IF NOT EXISTS wallets (
    id                  UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    account_id          UUID            NOT NULL,
    currency            VARCHAR(3)      NOT NULL,       -- ISO 4217
    balance             NUMERIC(19,4)   NOT NULL DEFAULT 0,
    available_balance   NUMERIC(19,4)   NOT NULL DEFAULT 0,
    pending_balance     NUMERIC(19,4)   NOT NULL DEFAULT 0,
    status              VARCHAR(20)     NOT NULL DEFAULT 'ACTIVE',
    created_at          TIMESTAMPTZ     NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ     NOT NULL DEFAULT now(),

    -- ── Foreign Keys ───────────────────────────────────────────────────
    CONSTRAINT fk_wallets_account
        FOREIGN KEY (account_id) REFERENCES accounts (id)
        ON DELETE RESTRICT          -- never cascade-delete financial data
        ON UPDATE CASCADE,

    -- ── Check Constraints ──────────────────────────────────────────────
    CONSTRAINT ck_wallets_balance_non_negative
        CHECK (balance >= 0),

    CONSTRAINT ck_wallets_available_balance_non_negative
        CHECK (available_balance >= 0),

    CONSTRAINT ck_wallets_pending_balance_non_negative
        CHECK (pending_balance >= 0),

    CONSTRAINT ck_wallets_available_le_balance
        CHECK (available_balance <= balance),

    CONSTRAINT ck_wallets_status
        CHECK (status IN ('ACTIVE', 'FROZEN', 'CLOSED')),

    CONSTRAINT ck_wallets_currency_upper
        CHECK (currency = upper(currency) AND length(currency) = 3)
);

-- Business rule: one wallet per currency per account
CREATE UNIQUE INDEX IF NOT EXISTS uq_wallets_account_currency
    ON wallets (account_id, currency);

-- FK look-up acceleration
CREATE INDEX IF NOT EXISTS idx_wallets_account_id
    ON wallets (account_id);

-- Currency-level reporting
CREATE INDEX IF NOT EXISTS idx_wallets_currency
    ON wallets (currency);

-- Active wallets are queried far more often
CREATE INDEX IF NOT EXISTS idx_wallets_status_active
    ON wallets (status)
    WHERE status = 'ACTIVE';

-- ============================================================================
-- 3. TRIGGER: Auto-update `updated_at` column
-- ============================================================================
-- Reusable trigger function — will also be attached to other tables.
-- ============================================================================

CREATE OR REPLACE FUNCTION fn_set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$;

-- Attach to accounts
DROP TRIGGER IF EXISTS trg_accounts_updated_at ON accounts;
CREATE TRIGGER trg_accounts_updated_at
    BEFORE UPDATE ON accounts
    FOR EACH ROW
    EXECUTE FUNCTION fn_set_updated_at();

-- Attach to wallets
DROP TRIGGER IF EXISTS trg_wallets_updated_at ON wallets;
CREATE TRIGGER trg_wallets_updated_at
    BEFORE UPDATE ON wallets
    FOR EACH ROW
    EXECUTE FUNCTION fn_set_updated_at();

-- ============================================================================
-- End of 01-accounts-wallets.sql
-- ============================================================================
