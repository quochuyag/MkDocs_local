---
title: VietPay — Entity-Relationship Diagram
course: 13-vietpay
source: vietpay/docs/er-diagram.md
---

# VietPay — Entity-Relationship Diagram

> **Domain:** Digital Wallet & Payments Platform  
> **Database:** PostgreSQL 15+  
> **Last Updated:** 2026-06-23

## Core Data Model

```mermaid
erDiagram
    accounts ||--o{ wallets : "owns"
    accounts ||--o{ idempotency_keys : "generates"
    wallets ||--o{ ledger_entries : "has entries"
    wallets ||--o{ transactions : "source"
    wallets ||--o{ transactions : "destination"
    transactions ||--|{ ledger_entries : "produces"
    transactions }o--|| idempotency_keys : "linked via"
    accounts ||--o{ audit_log : "changes tracked"
    wallets ||--o{ audit_log : "changes tracked"
    transactions ||--o{ audit_log : "changes tracked"

    accounts {
        UUID id PK
        VARCHAR email UK "lowercase unique"
        VARCHAR phone_number UK "nullable unique"
        VARCHAR full_name "NOT NULL"
        VARCHAR status "ACTIVE|SUSPENDED|CLOSED|PENDING_VERIFICATION"
        SMALLINT kyc_level "0-3"
        TIMESTAMPTZ created_at "DEFAULT now()"
        TIMESTAMPTZ updated_at "auto-trigger"
    }

    wallets {
        UUID id PK
        UUID account_id FK "→ accounts.id"
        VARCHAR currency "ISO 4217, 3 chars"
        NUMERIC balance "≥ 0, NUMERIC(19,4)"
        NUMERIC available_balance "≥ 0, ≤ balance"
        NUMERIC pending_balance "≥ 0"
        VARCHAR status "ACTIVE|FROZEN|CLOSED"
        TIMESTAMPTZ created_at "DEFAULT now()"
        TIMESTAMPTZ updated_at "auto-trigger"
    }

    transactions {
        UUID id PK
        VARCHAR reference_number UK "human-readable"
        UUID idempotency_key_id FK "→ idempotency_keys.id"
        UUID source_wallet_id FK "→ wallets.id (nullable)"
        UUID destination_wallet_id FK "→ wallets.id (nullable)"
        VARCHAR type "TRANSFER|DEPOSIT|WITHDRAWAL|PAYMENT|REFUND"
        NUMERIC amount "greater than 0"
        VARCHAR currency "ISO 4217"
        NUMERIC fee_amount "≥ 0"
        VARCHAR status "PENDING|PROCESSING|SETTLED|FAILED|REVERSED"
        TEXT description "optional"
        JSONB metadata "flexible attributes"
        VARCHAR settlement_batch_id "nullable"
        TIMESTAMPTZ created_at "DEFAULT now()"
        TIMESTAMPTZ updated_at "auto-trigger"
        TIMESTAMPTZ settled_at "set when SETTLED"
    }

    ledger_entries {
        UUID id PK
        UUID transaction_id FK "→ transactions.id"
        UUID wallet_id FK "→ wallets.id"
        VARCHAR entry_type "DEBIT|CREDIT"
        NUMERIC amount "greater than 0"
        NUMERIC balance_after "≥ 0"
        TEXT description "optional"
        TIMESTAMPTZ created_at "DEFAULT now()"
    }

    idempotency_keys {
        UUID id PK
        VARCHAR idempotency_key "NOT NULL"
        UUID account_id FK "→ accounts.id"
        VARCHAR request_hash "SHA-256 hex"
        SMALLINT response_status "HTTP status"
        JSONB response_body "cached response"
        TIMESTAMPTZ locked_at "in-flight lock"
        TIMESTAMPTZ created_at "DEFAULT now()"
        TIMESTAMPTZ expires_at "DEFAULT +48h"
    }

    audit_log {
        BIGSERIAL id PK
        VARCHAR table_name "source table"
        TEXT record_id "PK of source row"
        VARCHAR action "INSERT|UPDATE|DELETE"
        JSONB old_values "nullable"
        JSONB new_values "nullable"
        UUID changed_by "nullable"
        INET ip_address "client IP"
        TEXT user_agent "client agent"
        TIMESTAMPTZ created_at "DEFAULT now()"
    }
```

## Relationship Summary

| Relationship | Cardinality | Description |
|---|---|---|
| `accounts` → `wallets` | 1 : N | Mỗi tài khoản có nhiều ví (mỗi loại tiền tệ một ví) |
| `accounts` → `idempotency_keys` | 1 : N | Mỗi tài khoản tạo nhiều idempotency key |
| `wallets` → `ledger_entries` | 1 : N | Mỗi ví có nhiều bút toán sổ cái |
| `wallets` → `transactions` (source) | 1 : N | Ví nguồn cho nhiều giao dịch |
| `wallets` → `transactions` (dest) | 1 : N | Ví đích cho nhiều giao dịch |
| `transactions` → `ledger_entries` | 1 : 2+ | Mỗi giao dịch tạo ≥ 2 bút toán (DEBIT + CREDIT) |
| `idempotency_keys` → `transactions` | 1 : 0..1 | Mỗi key liên kết tối đa 1 giao dịch |
| Core tables → `audit_log` | 1 : N | Mỗi thay đổi được ghi lại trong audit log |

## Data Flow Overview

```mermaid
flowchart LR
    subgraph Client
        A["API Request\n+ Idempotency Key"]
    end

    subgraph Application Layer
        B["Check\nIdempotency"]
        C["Validate\n& Authorize"]
        D["Execute\nTransaction"]
    end

    subgraph Database Layer
        E["idempotency_keys"]
        F["transactions"]
        G["ledger_entries\n(DEBIT + CREDIT)"]
        H["wallets\n(balance update)"]
        I["audit_log"]
    end

    A --> B
    B --> E
    B -->|New Request| C
    B -->|Duplicate| A
    C --> D
    D --> F
    F --> G
    G --> H
    F --> I
    H --> I
```

## Key Design Decisions

| Decision | Rationale |
|---|---|
| UUID primary keys | Không thể đoán được, an toàn cho API công khai, merge dễ dàng giữa các DB |
| Three-balance model (balance / available / pending) | Hỗ trợ authorization holds, pending settlements |
| Double-entry ledger | Đảm bảo toàn vẹn tài chính: tổng DEBIT luôn = tổng CREDIT |
| Append-only ledger & audit | Tuân thủ PCI-DSS, quy định NHNN Việt Nam |
| Idempotency with TTL | Ngăn chặn giao dịch trùng lặp, tự dọn dẹp key hết hạn |
| Status state machine trigger | Chỉ cho phép chuyển trạng thái hợp lệ, ngăn chặn data corruption |


---

!!! info "Nguồn gốc"
    `vietpay/docs/er-diagram.md`
