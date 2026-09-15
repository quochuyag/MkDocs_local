-- ============================================================================
-- VietPay — Core Schema: Audit Trail
-- File:    sql/01-schema/05-audit-trail.sql
-- Author:  DBA Team
-- Created: 2026-06-23
-- Engine:  PostgreSQL 15+
-- Purpose: Capture every data change on critical tables in an append-only
--          audit log. Required by PCI-DSS, Vietnamese SBV regulations, and
--          internal compliance policies.
-- ============================================================================

-- ============================================================================
-- 1. AUDIT_LOG TABLE
-- ============================================================================
-- Design rationale:
--   • BIGSERIAL id provides a monotonically increasing ordering for replay.
--   • table_name + record_id identify the source row (record_id stored as
--     TEXT to accommodate both UUID and BIGINT PKs).
--   • old_values / new_values store the full row as JSONB for forensic
--     reconstruction. NULL for INSERT (no old) and DELETE (no new).
--   • changed_by, ip_address, user_agent are populated from session
--     variables set by the application layer via SET LOCAL.
--   • This table is APPEND-ONLY — a trigger blocks UPDATE and DELETE.
-- ============================================================================

CREATE TABLE IF NOT EXISTS audit_log (
    id              BIGSERIAL       PRIMARY KEY,
    table_name      VARCHAR(128)    NOT NULL,
    record_id       TEXT            NOT NULL,
    action          VARCHAR(10)     NOT NULL,
    old_values      JSONB,
    new_values      JSONB,
    changed_by      UUID,                           -- account ID or system user
    ip_address      INET,
    user_agent      TEXT,
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT now(),

    -- ── Check Constraints ──────────────────────────────────────────────
    CONSTRAINT ck_audit_action
        CHECK (action IN ('INSERT', 'UPDATE', 'DELETE')),

    -- INSERT must have new_values; DELETE must have old_values
    CONSTRAINT ck_audit_values_presence
        CHECK (
            (action = 'INSERT' AND old_values IS NULL AND new_values IS NOT NULL)
            OR (action = 'UPDATE' AND old_values IS NOT NULL AND new_values IS NOT NULL)
            OR (action = 'DELETE' AND old_values IS NOT NULL AND new_values IS NULL)
        )
);

-- ── Indexes ────────────────────────────────────────────────────────────
-- Lookup audit history for a specific record
CREATE INDEX IF NOT EXISTS idx_audit_table_record
    ON audit_log (table_name, record_id, created_at DESC);

-- Who made changes (compliance investigations)
CREATE INDEX IF NOT EXISTS idx_audit_changed_by
    ON audit_log (changed_by, created_at DESC)
    WHERE changed_by IS NOT NULL;

-- Time-range queries (daily/monthly compliance reports)
CREATE INDEX IF NOT EXISTS idx_audit_created_at
    ON audit_log (created_at);

-- Action-type filtering
CREATE INDEX IF NOT EXISTS idx_audit_action
    ON audit_log (action);

-- ============================================================================
-- 2. IMMUTABILITY TRIGGER — Prevent UPDATE / DELETE on audit_log
-- ============================================================================

CREATE OR REPLACE FUNCTION fn_audit_log_immutable()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION
        'audit_log is append-only. % operations are forbidden. '
        'This is required for regulatory compliance.',
        TG_OP
        USING ERRCODE = 'restrict_violation';
    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_audit_log_immutable ON audit_log;
CREATE TRIGGER trg_audit_log_immutable
    BEFORE UPDATE OR DELETE ON audit_log
    FOR EACH ROW
    EXECUTE FUNCTION fn_audit_log_immutable();

-- ============================================================================
-- 3. GENERIC AUDIT TRIGGER FUNCTION
-- ============================================================================
-- Attach this trigger to any table to automatically log changes.
-- The application MUST set session-level variables before DML:
--
--   SET LOCAL app.current_user_id  = '<uuid>';
--   SET LOCAL app.client_ip        = '192.168.1.1';
--   SET LOCAL app.user_agent       = 'VietPay-iOS/3.2.1';
--
-- If the variables are not set, the audit log entry will have NULLs for
-- those columns (the operation is NOT blocked).
-- ============================================================================

CREATE OR REPLACE FUNCTION fn_audit_trigger()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER                    -- runs with table owner privileges
SET search_path = public
AS $$
DECLARE
    v_record_id     TEXT;
    v_old_values    JSONB := NULL;
    v_new_values    JSONB := NULL;
    v_changed_by    UUID  := NULL;
    v_ip            INET  := NULL;
    v_ua            TEXT  := NULL;
BEGIN
    -- ── Extract record ID from the PK column ───────────────────────
    -- Convention: primary key is the first column named 'id'
    IF TG_OP = 'DELETE' THEN
        v_record_id := (row_to_json(OLD) ->> 'id');
    ELSE
        v_record_id := (row_to_json(NEW) ->> 'id');
    END IF;

    -- ── Capture old / new row data ─────────────────────────────────
    IF TG_OP IN ('UPDATE', 'DELETE') THEN
        v_old_values := to_jsonb(OLD);
    END IF;

    IF TG_OP IN ('INSERT', 'UPDATE') THEN
        v_new_values := to_jsonb(NEW);
    END IF;

    -- For UPDATE: skip audit if no columns actually changed
    IF TG_OP = 'UPDATE' AND v_old_values = v_new_values THEN
        RETURN NEW;
    END IF;

    -- ── Read session variables (safe — returns NULL if not set) ────
    BEGIN
        v_changed_by := current_setting('app.current_user_id', true)::UUID;
    EXCEPTION WHEN OTHERS THEN
        v_changed_by := NULL;
    END;

    BEGIN
        v_ip := current_setting('app.client_ip', true)::INET;
    EXCEPTION WHEN OTHERS THEN
        v_ip := NULL;
    END;

    v_ua := current_setting('app.user_agent', true);

    -- ── Insert audit record ────────────────────────────────────────
    INSERT INTO audit_log (
        table_name,
        record_id,
        action,
        old_values,
        new_values,
        changed_by,
        ip_address,
        user_agent
    ) VALUES (
        TG_TABLE_NAME,
        v_record_id,
        TG_OP,
        v_old_values,
        v_new_values,
        v_changed_by,
        v_ip,
        v_ua
    );

    -- Return the appropriate row
    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    ELSE
        RETURN NEW;
    END IF;
END;
$$;

-- ============================================================================
-- 4. ATTACH AUDIT TRIGGERS TO CORE TABLES
-- ============================================================================
-- Using AFTER triggers so the audit log captures the final committed state.
-- Each table gets its own named trigger for independent management.
-- ============================================================================

-- ── accounts ───────────────────────────────────────────────────────────
DROP TRIGGER IF EXISTS trg_audit_accounts ON accounts;
CREATE TRIGGER trg_audit_accounts
    AFTER INSERT OR UPDATE OR DELETE ON accounts
    FOR EACH ROW
    EXECUTE FUNCTION fn_audit_trigger();

-- ── wallets ────────────────────────────────────────────────────────────
DROP TRIGGER IF EXISTS trg_audit_wallets ON wallets;
CREATE TRIGGER trg_audit_wallets
    AFTER INSERT OR UPDATE OR DELETE ON wallets
    FOR EACH ROW
    EXECUTE FUNCTION fn_audit_trigger();

-- ── transactions ───────────────────────────────────────────────────────
DROP TRIGGER IF EXISTS trg_audit_transactions ON transactions;
CREATE TRIGGER trg_audit_transactions
    AFTER INSERT OR UPDATE OR DELETE ON transactions
    FOR EACH ROW
    EXECUTE FUNCTION fn_audit_trigger();

-- ============================================================================
-- 5. AUDIT LOG PARTITIONING (Optional — recommended for high-volume)
-- ============================================================================
-- For production systems with >1M audit entries/month, convert audit_log
-- to a partitioned table (range by created_at, monthly). This is left as
-- a separate migration script because it requires recreating the table.
--
-- Example (run as a separate migration):
--
--   CREATE TABLE audit_log_partitioned (
--       LIKE audit_log INCLUDING ALL
--   ) PARTITION BY RANGE (created_at);
--
--   CREATE TABLE audit_log_y2026m06
--       PARTITION OF audit_log_partitioned
--       FOR VALUES FROM ('2026-06-01') TO ('2026-07-01');
--
-- ============================================================================

-- ============================================================================
-- End of 05-audit-trail.sql
-- ============================================================================
