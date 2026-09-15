---
title: 'ADR-001: Kiến trúc Dữ liệu cho Nền tảng Thanh toán VietPay'
course: 13-vietpay
source: vietpay/docs/adr/001-data-architecture.md
---

# ADR-001: Kiến trúc Dữ liệu cho Nền tảng Thanh toán VietPay
## Architecture Decision Record — Data Architecture

---

| Metadata | Value |
|---|---|
| **Status** | Proposed |
| **Date** | 2026-06-23 |
| **Decision Makers** | Database Architecture Team |
| **Consulted** | Engineering, Security, Compliance |
| **Informed** | Product, Operations |

---

## 1. Bối cảnh (Context)

VietPay là nền tảng thanh toán fintech phục vụ hàng triệu người dùng tại Việt Nam. Hệ thống cần xử lý:

- **~50 triệu** transactions hiện có, tăng trưởng **~2 triệu/tháng**
- Payment processing (transfers, deposits, withdrawals, refunds)
- Double-entry ledger cho tính toàn vẹn tài chính
- Tích hợp với nhiều payment providers (Visa, Mastercard, banking APIs)
- Tuân thủ quy định NHNN (Ngân hàng Nhà nước Việt Nam) và PCI-DSS

### Thách thức chính
1. **Data Integrity**: Không được mất hay sai lệch số liệu tài chính
2. **Performance**: Hàng triệu giao dịch/ngày, latency < 100ms
3. **Compliance**: PCI-DSS, SOX, quy định NHNN
4. **Scalability**: Tăng trưởng 10x trong 3 năm tới
5. **Multi-service Architecture**: Nhiều microservices cùng truy cập dữ liệu

---

## 2. Yếu tố Quyết định (Decision Drivers)

| # | Driver | Mức ưu tiên | Giải thích |
|---|---|---|---|
| D1 | **Financial data correctness** | 🔴 Critical | Sai 1 đồng = vi phạm pháp luật |
| D2 | **Regulatory compliance** | 🔴 Critical | PCI-DSS, NHNN regulations |
| D3 | **Performance at scale** | 🟡 High | 50M+ rows, ~2000 TPS peak |
| D4 | **Operational safety** | 🟡 High | Zero-downtime deployments |
| D5 | **Developer productivity** | 🟢 Medium | Schema evolution, tooling |
| D6 | **Cost efficiency** | 🟢 Medium | Infrastructure & licensing costs |

---

## 3. Quyết định (Decisions)

---

### Decision 1: Tiêu chuẩn Mô hình hóa Dữ liệu (Modelling Standards)

#### 3.1.1 Naming Conventions

| Quy tắc | Ví dụ | Lý do |
|---|---|---|
| **snake_case** cho tất cả identifiers | `wallet_id`, `created_at` | PostgreSQL fold identifiers to lowercase; snake_case tránh cần quoting |
| **Plural** table names | `accounts`, `transactions` | Tập hợp records, nhất quán với Rails/Django conventions |
| **Verb-noun** cho functions | `fn_check_idempotency()` | Phân biệt functions với tables |
| **Prefix** cho indexes | `idx_`, `uq_`, `chk_` | Nhanh chóng nhận diện object type |
| **Prefix** cho triggers | `trg_` | Phân biệt triggers |
| **FK suffix** | `_id` | `wallet_id` → references `wallets.id` |

```sql
-- ✅ Đúng chuẩn
CREATE TABLE wallets (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    account_id  UUID NOT NULL REFERENCES accounts(id),
    currency    VARCHAR(3) NOT NULL,
    balance     NUMERIC(19,4) NOT NULL DEFAULT 0,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ❌ Sai chuẩn
CREATE TABLE "Wallets" (
    WalletID    INT AUTO_INCREMENT,
    AccountID   INT,
    Balance     FLOAT,
    CreatedDate DATETIME
);
```

#### 3.1.2 Primary Key Strategy: UUID vs BIGSERIAL

**Quyết định: UUID v4 (`gen_random_uuid()`)**

| Tiêu chí | UUID | BIGSERIAL |
|---|---|---|
| **Uniqueness across services** | ✅ Globally unique | ❌ Only per-table |
| **Security** | ✅ Non-guessable | ❌ Sequential, predictable |
| **Distributed generation** | ✅ Client-side, no DB roundtrip | ❌ Requires DB sequence |
| **Storage** | ❌ 16 bytes | ✅ 8 bytes |
| **Index performance** | ❌ Random inserts, page splits | ✅ Sequential, append-only |
| **Merge/migration** | ✅ No conflicts | ❌ Conflicts likely |

**Mitigation cho UUID performance:**
- Sử dụng `UUIDv7` (time-ordered) khi PostgreSQL 17+ hỗ trợ native, hoặc `uuid_generate_v7()` extension
- B-tree index trên UUID vẫn hiệu quả cho workload hiện tại (50M rows)
- Partition by `created_at` giảm index size per partition

**Lý do chọn UUID cho fintech:**
- Microservices cần tạo ID trước khi gọi DB (idempotency pattern)
- Merge data từ nhiều regions/shards trong tương lai
- PCI-DSS yêu cầu non-predictable identifiers cho financial records

#### 3.1.3 Xử lý Tiền tệ (Money Handling)

**Quyết định: `NUMERIC(19,4)` — KHÔNG BAO GIỜ dùng FLOAT/DOUBLE**

```sql
-- ✅ Đúng
amount    NUMERIC(19,4) NOT NULL CHECK (amount > 0)
balance   NUMERIC(19,4) NOT NULL DEFAULT 0

-- ❌ SAI — Gây sai lệch tài chính
amount    FLOAT       -- 0.1 + 0.2 = 0.30000000000000004
balance   DOUBLE      -- Tương tự
amount    DECIMAL(10,2)-- Không đủ precision cho large amounts
```

| Specification | Giá trị |
|---|---|
| **Precision** | 19 digits — hỗ trợ đến 999,999,999,999,999.9999 (đủ cho mọi loại tiền) |
| **Scale** | 4 decimal places — hỗ trợ sub-cent calculations, forex rates |
| **Maximum value** | ~10^15 — đủ cho GBP/USD/VND amounts |

**Lý do 4 decimal places thay vì 2:**
- Forex conversion cần precision cao hơn (1 USD = 24,345.5000 VND)
- Partial refunds, fee calculations có thể tạo sub-cent amounts
- ISO 4217 standard: một số currency dùng 3-4 decimal places (KWD, BHD)

#### 3.1.4 Timestamp Strategy

**Quyết định: Luôn dùng `TIMESTAMPTZ` (timestamp with time zone), lưu trữ UTC**

```sql
created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()  -- Luôn UTC internally
updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()

-- Application phải SET timezone = 'UTC' khi connect
-- Display timezone conversion ở frontend layer
```

**Lý do:**
- PostgreSQL lưu `TIMESTAMPTZ` nội bộ là UTC, convert khi hiển thị
- `TIMESTAMP` (without timezone) KHÔNG convert → nguy hiểm khi server timezone thay đổi
- Fintech regulations yêu cầu timestamp chính xác cho audit trail
- Vietnam timezone (ICT, UTC+7) → cần rõ ràng khi đối soát với partners ở timezone khác

#### 3.1.5 Enum Handling

**Quyết định: `VARCHAR` + `CHECK` constraints (thay vì PostgreSQL `ENUM` type)**

```sql
-- ✅ CHECK constraint — dễ evolve
status VARCHAR(20) NOT NULL DEFAULT 'PENDING'
    CHECK (status IN ('PENDING', 'PROCESSING', 'SETTLED', 'FAILED', 'REVERSED'))

-- ❌ PostgreSQL ENUM — khó thêm/xóa values
CREATE TYPE transaction_status AS ENUM ('PENDING', 'PROCESSING', 'SETTLED');
-- Thêm value: ALTER TYPE ... ADD VALUE (không thể trong transaction!)
-- Xóa value: Phải tạo type mới, migrate toàn bộ data
```

**Lý do chọn CHECK constraint:**
- `ALTER TYPE ... ADD VALUE` không thể chạy trong transaction → phá vỡ migration workflow
- `DROP VALUE` từ ENUM không được support → stuck với stale values
- CHECK constraint có thể modify trong migration bình thường
- Trade-off: CHECK không tận dụng được internal enum ID (nhỏ hơn VARCHAR), nhưng với index covering, performance impact minimal

#### 3.1.6 Soft Delete vs Hard Delete

**Quyết định: KHÔNG soft delete cho financial records — dùng status-based lifecycle + audit log**

```sql
-- Financial records KHÔNG BAO GIỜ bị DELETE
-- Transactions: status lifecycle (PENDING → SETTLED → REVERSED)
-- Wallets: status = 'CLOSED' (không xóa)
-- Accounts: status = 'DEACTIVATED' (không xóa)

-- Audit log: append-only, KHÔNG thể UPDATE hay DELETE
CREATE RULE prevent_audit_update AS ON UPDATE TO audit_log DO INSTEAD NOTHING;
CREATE RULE prevent_audit_delete AS ON DELETE TO audit_log DO INSTEAD NOTHING;
```

**Lý do:**
- PCI-DSS Section 10: Transaction logs phải được giữ ít nhất 1 năm, accessible trong 3 tháng
- NHNN quy định: Dữ liệu giao dịch phải lưu giữ tối thiểu 5 năm
- Soft delete (`deleted_at IS NOT NULL`) phức tạp hóa mọi query, dễ quên filter → data leak
- Status-based approach tự nhiên hơn cho financial lifecycle

---

### Decision 2: Strong vs Eventual Consistency

#### 3.2.1 Consistency Map

```
┌─────────────────────────────────────────────────────────────┐
│              STRONG CONSISTENCY (SERIALIZABLE)                │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │ • Ledger entries creation (double-entry)                 │ │
│  │ • Wallet balance updates (debit/credit)                  │ │
│  │ • Idempotency key check + transaction creation           │ │
│  │ • Settlement batch processing                            │ │
│  └─────────────────────────────────────────────────────────┘ │
├─────────────────────────────────────────────────────────────┤
│           READ COMMITTED (Default for reads)                 │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │ • Wallet balance display (read from replica OK)          │ │
│  │ • Transaction history listing                            │ │
│  │ • Account profile reads                                  │ │
│  └─────────────────────────────────────────────────────────┘ │
├─────────────────────────────────────────────────────────────┤
│            EVENTUAL CONSISTENCY (Async)                       │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │ • Settlement reporting aggregation                       │ │
│  │ • Analytics & dashboards                                 │ │
│  │ • Notification delivery                                  │ │
│  │ • Webhook event processing                               │ │
│  │ • Fraud scoring (near real-time, < 5s delay OK)          │ │
│  └─────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

#### 3.2.2 Transaction Isolation cho Financial Operations

**Critical path: Tạo giao dịch mới**

```sql
-- SERIALIZABLE isolation cho ledger operations
BEGIN ISOLATION LEVEL SERIALIZABLE;

-- 1. Check idempotency key (prevent duplicate)
SELECT * FROM idempotency_keys 
WHERE account_id = :account_id AND idempotency_key = :key
FOR UPDATE;

-- 2. Lock source wallet (ordered by wallet_id to prevent deadlock)
SELECT * FROM wallets WHERE id = :source_wallet_id FOR UPDATE;
SELECT * FROM wallets WHERE id = :dest_wallet_id FOR UPDATE;

-- 3. Check sufficient balance
-- 4. Create transaction record
-- 5. Create ledger entries (debit + credit, sum = 0)
-- 6. Update wallet balances
-- 7. Record idempotency key

COMMIT;  -- DEFERRABLE constraint trigger validates zero-sum here
```

**Lý do dùng SERIALIZABLE:**
- Double-entry ledger YÊU CẦU tất cả entries trong 1 transaction là atomic
- Race condition giữa 2 transfers cùng wallet phải được serialized
- PostgreSQL SSI (Serializable Snapshot Isolation) hiệu quả cho short transactions
- Retry logic ở application layer cho serialization failures

> **Lưu ý:** `SELECT ... FOR UPDATE` dưới SERIALIZABLE có thể xem là dư thừa (SSI đã ngăn write skew). Tuy nhiên, ta vẫn dùng FOR UPDATE để:
> - Đảm bảo **deterministic lock ordering** (tránh deadlock)
> - Là fallback nếu app vô tình dùng READ COMMITTED trong một số code paths
> - Không gây overhead đáng kể cho short transactions

#### 3.2.3 CQRS Pattern (Command Query Responsibility Segregation)

**Quyết định: Áp dụng CQRS cho reporting workload**

```
┌──────────────┐     ┌──────────────────┐     ┌─────────────────┐
│  Application │────▸│  Primary DB      │────▸│  CDC Stream     │
│  (Commands)  │     │  (Write Model)   │     │  (Debezium)     │
└──────────────┘     └──────────────────┘     └────────┬────────┘
                                                        │
                                                        ▼
┌──────────────┐     ┌──────────────────┐     ┌─────────────────┐
│  Reporting   │◂────│  Read Replicas   │◂────│  Kafka Topics   │
│  Dashboard   │     │  + Materialized  │     │  (Events)       │
│  (Queries)   │     │    Views         │     │                 │
└──────────────┘     └──────────────────┘     └─────────────────┘
```

| Model | Store | Consistency | Use Cases |
|---|---|---|---|
| **Write Model** | PostgreSQL Primary | Strong (SERIALIZABLE) | Transactions, ledger, balance updates |
| **Read Model (Hot)** | PostgreSQL Replica | Near real-time (< 1s lag) | Balance display, transaction history |
| **Read Model (Warm)** | Materialized Views | Refreshed every 5 min | Settlement reports, monthly summaries |
| **Read Model (Cold)** | Data Warehouse (BigQuery/Redshift) | Eventual (hourly ETL) | Analytics, compliance reports, ML features |

#### 3.2.4 Saga Pattern cho Distributed Transactions

Khi giao dịch liên quan đến nhiều services (ví dụ: VietPay → Bank API → Notification):

```
Choreography-based Saga (preferred for VietPay):

1. Payment Service:  CREATE transaction (status=PENDING)
        │
        ▼ Event: payment.initiated
2. Bank Gateway:     Call bank API
        │
        ├── Success ──▸ Event: bank.approved
        │                  │
        │                  ▼
        │              3. Ledger Service: Create ledger entries + update balances
        │                  │
        │                  ▼ Event: ledger.posted
        │              4. Payment Service: UPDATE status = SETTLED
        │                  │
        │                  ▼ Event: payment.settled
        │              5. Notification: Send success notification
        │
        └── Failure ──▸ Event: bank.declined
                           │
                           ▼
                       3. Payment Service: UPDATE status = FAILED
                           │
                           ▼ Event: payment.failed
                       4. Compensation: Reverse any partial changes
```

**Lý do dùng Choreography over Orchestration:**
- Decoupled: Mỗi service tự quyết định based on events
- No single point of failure (orchestrator)
- Phù hợp với event-driven architecture
- Trade-off: Harder to trace full flow → cần distributed tracing (Jaeger/Tempo)

---

### Decision 3: Data Contracts giữa Microservices

#### 3.3.1 Schema Registry

**Quyết định: Confluent Schema Registry với Avro serialization cho Kafka events**

```
┌─────────────┐    ┌──────────────┐    ┌─────────────┐
│  Producer   │───▸│  Schema      │◂───│  Consumer   │
│  Service    │    │  Registry    │    │  Service    │
│             │    │              │    │             │
│ Serialize   │    │ • Validate   │    │ Deserialize │
│ with Avro   │    │ • Version    │    │ with Avro   │
│ schema v2   │    │ • Compat     │    │ schema v1+  │
└─────────────┘    └──────────────┘    └─────────────┘
```

**Event Schema Example:**

```avro
{
  "type": "record",
  "name": "TransactionSettled",
  "namespace": "vn.vietpay.events.payment",
  "version": 2,
  "fields": [
    {"name": "transaction_id", "type": "string", "doc": "UUID of the transaction"},
    {"name": "wallet_id", "type": "string"},
    {"name": "amount", "type": {"type": "bytes", "logicalType": "decimal", "precision": 19, "scale": 4}},
    {"name": "currency", "type": "string"},
    {"name": "settled_at", "type": {"type": "long", "logicalType": "timestamp-millis"}},
    {"name": "settlement_batch_id", "type": ["null", "string"], "default": null, "doc": "Added in v2"}
  ]
}
```

#### 3.3.2 Compatibility Rules

**Quyết định: BACKWARD compatibility mode (default)**

| Compatibility Mode | Cho phép | Không cho phép |
|---|---|---|
| **BACKWARD** (mặc định) | Thêm field optional (có default) | Xóa required field |
| | Xóa field optional | Thêm required field không có default |
| | Widen type (int → long) | Narrow type (long → int) |
| **FULL** (cho critical events) | Chỉ thêm/xóa optional fields | Mọi breaking change |

```
Schema Evolution Rules cho VietPay:

✅ ALLOWED (non-breaking):
   - Thêm field mới với default value
   - Thêm optional field (nullable)
   - Thêm new enum value (cuối danh sách)
   - Deprecate field (giữ lại, thêm @deprecated annotation)

❌ FORBIDDEN (breaking):
   - Xóa required field
   - Rename field
   - Thay đổi field type (int → string)
   - Thay đổi field semantics (amount cents → amount dollars)
```

#### 3.3.3 Versioning Strategy

**API Versioning: URI-based major versions + header-based minor versions**

```
# Major version trong URI (breaking changes)
POST /api/v2/transactions

# Minor version trong header (non-breaking)
Accept: application/vnd.vietpay.v2.3+json

# Event versioning trong topic name
Topic: vietpay.payments.transaction-settled.v2
```

**Schema Version Lifecycle:**

```
┌────────────┐    ┌────────────┐    ┌────────────┐    ┌────────────┐
│  DRAFT     │──▸ │  ACTIVE    │──▸ │ DEPRECATED │──▸ │  RETIRED   │
│            │    │            │    │            │    │            │
│ Dev/Test   │    │ Production │    │ Sunset     │    │ Removed    │
│ only       │    │ use        │    │ period     │    │ from       │
│            │    │            │    │ (90 days)  │    │ registry   │
└────────────┘    └────────────┘    └────────────┘    └────────────┘
```

#### 3.3.4 Contract Testing

**Consumer-Driven Contract Testing (Pact framework)**

```
Workflow:
1. Consumer định nghĩa expectations (Pact file)
2. Pact file được publish lên Pact Broker
3. Provider CI/CD verify contracts
4. Breaking changes → CI fails BEFORE deploy
```

```json
// Pact contract example
{
  "consumer": { "name": "notification-service" },
  "provider": { "name": "payment-service" },
  "interactions": [
    {
      "description": "a settled transaction event",
      "upon_receiving": "TransactionSettled event",
      "with": {
        "body": {
          "transaction_id": "uuid-string",
          "amount": "decimal-string",
          "currency": "VND",
          "settled_at": "iso-8601-timestamp"
        }
      },
      "will_respond_with": {
        "status": "consumed",
        "required_fields": ["transaction_id", "amount", "currency"]
      }
    }
  ]
}
```

#### 3.3.5 Data Contract Definition Format

Mỗi microservice PHẢI publish data contract document:

```yaml
# data-contract.yaml — Payment Service
apiVersion: datacontract/v1
kind: DataContract
metadata:
  name: payment-transactions
  owner: payment-team
  version: 2.1.0
  status: active
  
spec:
  # Database schema contract
  tables:
    - name: transactions
      classification: PII  # Contains financial data
      retention: 5 years   # NHNN requirement
      columns:
        - name: id
          type: UUID
          required: true
          immutable: true
          
        - name: amount
          type: NUMERIC(19,4)
          required: true
          constraints:
            - "amount > 0"
          
        - name: status
          type: VARCHAR(20)
          required: true
          allowed_values: [PENDING, PROCESSING, SETTLED, FAILED, REVERSED]
          
  # Event contract
  events:
    - name: TransactionSettled
      topic: vietpay.payments.transaction-settled.v2
      schema: avro
      compatibility: BACKWARD
      
  # SLA contract
  sla:
    availability: 99.95%
    latency_p99: 100ms
    throughput: 2000 TPS
```

#### 3.3.6 Migration Playbook khi Contracts thay đổi

```
1. PROPOSAL PHASE (1 tuần)
   - RFC document mô tả thay đổi
   - Impact analysis: services nào bị ảnh hưởng
   - Review bởi affected team leads

2. PREPARATION PHASE (1-2 tuần)  
   - Schema Registry: publish new schema version (DRAFT)
   - Contract tests: update Pact files
   - Consumer services: prepare to handle new + old format

3. ROLLOUT PHASE (gradual, 1-2 tuần)
   - Producer: dual-write old + new format
   - Feature flag: consumers switch to new format
   - Monitor error rates per consumer

4. CLEANUP PHASE (sau 90 ngày sunset)
   - Mark old schema DEPRECATED
   - Remove dual-write code
   - After sunset: mark RETIRED
   
5. EMERGENCY ROLLBACK (bất kỳ lúc nào)
   - Producer: revert to old schema only
   - Consumer: rollback feature flag
   - No data loss (old format always available during transition)
```

---

## 4. Hệ quả (Consequences)

### 4.1 Hệ quả tích cực

| # | Consequence | Impact |
|---|---|---|
| 1 | **Financial integrity by design** | Schema constraints enforce correctness — không phụ thuộc vào application logic |
| 2 | **Audit compliance built-in** | Append-only audit trail + immutable ledger đáp ứng PCI-DSS, NHNN |
| 3 | **Safe schema evolution** | Expand-contract pattern + Schema Registry cho phép evolve mà không break consumers |
| 4 | **Performance at scale** | Partitioning + covering indexes + CQRS cho phép scale read/write independently |
| 5 | **Polyglot flexibility** | Right tool for each job — PostgreSQL cho OLTP, MongoDB cho events, Neo4j cho fraud |
| 6 | **Observable by default** | Comprehensive metrics + SLOs cho phép proactive incident prevention |

### 4.2 Hệ quả tiêu cực (Trade-offs)

| # | Trade-off | Mitigation |
|---|---|---|
| 1 | **UUID performance** | UUIDv7 (time-ordered) + partitioning giảm random I/O |
| 2 | **SERIALIZABLE overhead** | Chỉ dùng cho financial critical path, retry logic cho serialization failures |
| 3 | **Operational complexity** | Multiple database systems (PG + MongoDB + Neo4j) → cần specialized DBA skills |
| 4 | **Schema Registry dependency** | Schema Registry cluster phải highly available → add Kafka dependency |
| 5 | **Contract testing overhead** | Thêm CI/CD step → chấp nhận slower builds cho safety |
| 6 | **Eventual consistency complexity** | CQRS + Saga pattern phức tạp hơn monolithic transaction → cần distributed tracing |

---

## 5. Compliance Mapping (Tuân thủ Quy định)

### 5.1 PCI-DSS Requirements

| PCI-DSS Section | Requirement | Implementation |
|---|---|---|
| **3.4** | Render PAN unreadable | Encrypt sensitive data at rest (TDE/pgcrypto) |
| **6.5** | Secure coding | SQL injection prevention (parameterized queries), input validation |
| **8.5** | Unique identification | UUID-based identifiers, audit trail with `changed_by` |
| **10.1** | Audit trails | `audit_log` table with trigger-based capture |
| **10.2** | Log events | All CRUD operations logged with timestamp, user, IP |
| **10.5** | Secure audit trails | Append-only (no UPDATE/DELETE via rules), integrity via checksums |
| **10.7** | Retain logs 1 year | Partition-based retention + archival to cold storage |

### 5.2 NHNN Regulations (Ngân hàng Nhà nước)

| Quy định | Yêu cầu | Implementation |
|---|---|---|
| **Thông tư 35/2016** | Lưu trữ dữ liệu giao dịch ≥ 5 năm | Partition retention policy, archival to S3/GCS |
| **Thông tư 39/2014** | Bảo mật dữ liệu khách hàng | Encryption at rest + transit, column-level access control |
| **QĐ 630/QĐ-NHNN** | Giao dịch điện tử phải có xác nhận | Idempotency keys + transaction receipts |
| **Nghị định 35/2007** | Báo cáo giao dịch đáng ngờ | Neo4j fraud detection + automated reporting |

---

## 6. Tài liệu Tham khảo (References)

1. PostgreSQL Documentation: Transaction Isolation — https://www.postgresql.org/docs/current/transaction-iso.html
2. Martin Kleppmann, "Designing Data-Intensive Applications" (O'Reilly, 2017)
3. Pat Helland, "Life beyond Distributed Transactions" (CIDR, 2007)
4. PCI Security Standards Council, "PCI DSS v4.0" — https://www.pcisecuritystandards.org
5. NHNN Thông tư 35/2016/TT-NHNN
6. Confluent Schema Registry Documentation — https://docs.confluent.io/platform/current/schema-registry/
7. Michael Nygard, "Documenting Architecture Decisions" (2011)


---

!!! info "Nguồn gốc"
    `vietpay/docs/adr/001-data-architecture.md`
