-- ============================================================================
-- VietPay — Core Schema: Idempotency Keys
-- File:    sql/01-schema/04-idempotency.sql
-- Author:  DBA Team
-- Created: 2026-06-23
-- Engine:  PostgreSQL 15+
-- Purpose: Prevent duplicate financial operations caused by network retries,
--          client bugs, or user double-clicks. Each mutating API call must
--          include an idempotency key; the server stores the result and
--          returns it verbatim on subsequent attempts.
-- ============================================================================

-- ============================================================================
-- 1. IDEMPOTENCY_KEYS
-- ============================================================================
-- Design rationale:
--   • (account_id, idempotency_key) is unique — each account's keys are
--     scoped independently, so two different users can use the same string.
--   • request_hash stores a SHA-256 of the request body. On a retry we
--     compare the hash; if it differs from the original, we reject the
--     request (prevents key reuse with different payloads).
--   • response_status + response_body cache the original HTTP response
--     so a replay can be served without re-executing business logic.
--   • expires_at defaults to 48 hours. A background job (pg_cron) purges
--     expired rows to keep the table small.
-- ============================================================================

CREATE TABLE IF NOT EXISTS idempotency_keys (
    id                  UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    idempotency_key     VARCHAR(255)    NOT NULL,
    account_id          UUID            NOT NULL,
    request_hash        VARCHAR(64),                -- SHA-256 hex digest
    response_status     SMALLINT,                   -- HTTP status code
    response_body       JSONB,
    locked_at           TIMESTAMPTZ,                -- in-flight lock
    created_at          TIMESTAMPTZ     NOT NULL DEFAULT now(),
    expires_at          TIMESTAMPTZ     NOT NULL DEFAULT now() + INTERVAL '48 hours',

    -- ── Foreign Keys ───────────────────────────────────────────────────
    CONSTRAINT fk_idempotency_account
        FOREIGN KEY (account_id) REFERENCES accounts (id)
        ON DELETE CASCADE,      -- if account is deleted, keys go with it

    -- ── Check Constraints ──────────────────────────────────────────────
    CONSTRAINT ck_idempotency_expires_after_created
        CHECK (expires_at > created_at),

    CONSTRAINT ck_idempotency_key_not_empty
        CHECK (length(trim(idempotency_key)) > 0)
);

-- ── Unique: one key per account ────────────────────────────────────────
CREATE UNIQUE INDEX IF NOT EXISTS uq_idempotency_account_key
    ON idempotency_keys (account_id, idempotency_key);

-- ── Index for TTL cleanup job ──────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_idempotency_expires_at
    ON idempotency_keys (expires_at)
    WHERE response_status IS NOT NULL;      -- only completed requests

-- ── Index for lock-check on in-flight requests ─────────────────────────
CREATE INDEX IF NOT EXISTS idx_idempotency_locked
    ON idempotency_keys (locked_at)
    WHERE locked_at IS NOT NULL;

-- ============================================================================
-- 2. ADD FK from transactions → idempotency_keys
-- ============================================================================

ALTER TABLE transactions
    DROP CONSTRAINT IF EXISTS fk_txn_idempotency_key;

ALTER TABLE transactions
    ADD CONSTRAINT fk_txn_idempotency_key
        FOREIGN KEY (idempotency_key_id) REFERENCES idempotency_keys (id)
        ON DELETE SET NULL;

-- ============================================================================
-- 3. TTL CLEANUP FUNCTION
-- ============================================================================
-- Call via pg_cron:
--   SELECT cron.schedule('cleanup-idempotency', '0 3 * * *',
--          $$SELECT fn_cleanup_expired_idempotency_keys()$$);
--
-- This deletes expired keys in batches to avoid long-running transactions
-- and excessive WAL generation.
-- ============================================================================

CREATE OR REPLACE FUNCTION fn_cleanup_expired_idempotency_keys(
    p_batch_size INT DEFAULT 5000
)
RETURNS INT
LANGUAGE plpgsql
AS $$
DECLARE
    v_deleted INT := 0;
    v_batch   INT;
BEGIN
    LOOP
        DELETE FROM idempotency_keys
         WHERE id IN (
                   SELECT id
                     FROM idempotency_keys
                    WHERE expires_at < now()
                    LIMIT p_batch_size
                    FOR UPDATE SKIP LOCKED
               );

        GET DIAGNOSTICS v_batch = ROW_COUNT;
        v_deleted := v_deleted + v_batch;

        EXIT WHEN v_batch < p_batch_size;   -- no more rows to delete

        -- Yield to other transactions between batches
        PERFORM pg_sleep(0.1);
    END LOOP;

    RAISE NOTICE 'Cleaned up % expired idempotency keys', v_deleted;
    RETURN v_deleted;
END;
$$;

COMMENT ON FUNCTION fn_cleanup_expired_idempotency_keys(INT)
    IS 'Batch-delete expired idempotency keys. Default batch size 5000. '
       'Schedule via pg_cron to run daily during off-peak hours.';

-- ============================================================================
-- 4. IDEMPOTENCY LOOKUP FUNCTION
-- ============================================================================
-- Application layer calls this to check whether a request is a replay.
-- Returns the cached response if the key exists and hasn't expired.
-- ============================================================================

CREATE OR REPLACE FUNCTION fn_check_idempotency(
    p_account_id        UUID,
    p_idempotency_key   VARCHAR(255),
    p_request_hash      VARCHAR(64)
)
RETURNS TABLE (
    is_duplicate    BOOLEAN,
    is_conflict     BOOLEAN,        -- same key, different payload
    response_status SMALLINT,
    response_body   JSONB
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_record idempotency_keys%ROWTYPE;
BEGIN
    SELECT *
      INTO v_record
      FROM idempotency_keys ik
     WHERE ik.account_id       = p_account_id
       AND ik.idempotency_key  = p_idempotency_key
       AND ik.expires_at       > now();

    IF NOT FOUND THEN
        -- Fresh request
        RETURN QUERY SELECT FALSE, FALSE, NULL::SMALLINT, NULL::JSONB;
        RETURN;
    END IF;

    -- Key exists — check if payload matches
    IF v_record.request_hash IS DISTINCT FROM p_request_hash THEN
        -- Same key, different request body → conflict (HTTP 422)
        RETURN QUERY SELECT TRUE, TRUE, v_record.response_status, v_record.response_body;
        RETURN;
    END IF;

    -- Exact duplicate — return cached response
    RETURN QUERY SELECT TRUE, FALSE, v_record.response_status, v_record.response_body;
END;
$$;

-- ============================================================================
-- End of 04-idempotency.sql
-- ============================================================================
