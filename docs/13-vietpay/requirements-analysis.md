---
title: 📋 Take Home Assessment — Database
course: 13-vietpay
source: vietpay/requirements_analysis.md
---

# 📋 Take Home Assessment — Database
## Enterprise Database Architect – Fintech

---

## 🎯 Mục tiêu (Objective)

Thiết kế **lớp dữ liệu cốt lõi** (core data layer) cho một **nền tảng thanh toán fintech** (fintech payments platform).

> **QUAN TRỌNG:** Đây là bài tập **thiết kế và SQL**, KHÔNG phải xây dựng ứng dụng.

Trọng tâm đánh giá:
- Mô hình hóa dữ liệu tài chính (financial data modelling)
- Tư duy về hiệu suất (performance reasoning)
- Di chuyển hệ thống live an toàn (safe live migration)
- Chọn đúng công cụ lưu trữ cho từng tác vụ (right store for each job)

### Deliverable tổng thể
Một **Git repository** chứa:
- SQL scripts
- Migration files
- Diagrams (ER diagram)
- Written design notes (`.md`)

---

## 📦 Bối cảnh được cung cấp (Provided Context)

### Bảng hiện có
Nền tảng thanh toán đã có bảng `transactions` với:
- **~50 triệu rows** hiện tại
- Tăng trưởng **~2 triệu rows/tháng**

```sql
transactions(id, wallet_id, type, amount, currency, status, created_at)
```

### Truy vấn báo cáo chậm (Slow Reporting Query)
Truy vấn phổ biến đang **chậm trên production**:

```sql
SELECT wallet_id, currency, SUM(amount) 
FROM transactions
WHERE status = 'SETTLED' 
  AND created_at >= :month_start 
  AND created_at < :month_end
GROUP BY wallet_id, currency;
```

---

## 📝 Các Task Chi Tiết

---

### Task 1: Relational Core Model (Mô hình quan hệ cốt lõi)

#### Yêu cầu
Thiết kế **PostgreSQL schema chuẩn hóa** (normalised) cho domain wallet/payments bao gồm:

| Thành phần | Mô tả |
|---|---|
| **Accounts/Wallets** | Quản lý tài khoản và ví điện tử |
| **Double-entry Ledger** | Sổ cái ghi kép — mỗi giao dịch phải có 2 entry (debit + credit) |
| **Transactions** | Bảng giao dịch chính |
| **Idempotency Keys** | Khóa đảm bảo không xử lý trùng lặp request |
| **Audit Trail** | Nhật ký kiểm toán, ghi lại mọi thay đổi |

#### Deliverables
- **DDL files** — SQL files tạo schema
- **ER Diagram** — Sơ đồ quan hệ thực thể (image hoặc text)
- **Giải thích integrity guarantees**:
  - Sổ cái luôn cân bằng (ledger always balances) — `SUM(debit) = SUM(credit)` mọi lúc
  - Request trùng lặp không thể post 2 lần (duplicate request cannot post twice)
  - Chiến lược indexing kèm lý do

> **Gợi ý kỹ thuật:**
> - Double-entry: Mỗi transaction tạo ít nhất 2 `ledger_entries` (debit/credit) với tổng bằng 0
> - Idempotency: Unique constraint trên `idempotency_key` để reject duplicate
> - Audit: Trigger hoặc CDC (Change Data Capture) để ghi lại mọi thay đổi

---

### Task 2: Query & Performance (Tối ưu truy vấn & hiệu suất)

#### Yêu cầu
Tối ưu hóa **settlement query** cho bảng 50M-row:

1. **Cung cấp truy vấn cải tiến** + **indexes hỗ trợ** và/hoặc **chiến lược partitioning**
2. **Giải thích cách xác nhận cải thiện:**
   - Query plan thay đổi như thế nào (EXPLAIN ANALYZE)
   - Chi phí của index: write overhead, kích thước

#### Hướng tiếp cận gợi ý

| Phương pháp | Chi tiết |
|---|---|
| **Composite Index** | `CREATE INDEX idx_txn_settled ON transactions(status, created_at) INCLUDE (wallet_id, currency, amount);` |
| **Partial Index** | `CREATE INDEX idx_txn_settled_only ON transactions(created_at) WHERE status = 'SETTLED';` |
| **Table Partitioning** | Range partitioning theo `created_at` (monthly) |
| **Materialized View** | Pre-aggregate kết quả theo tháng |

> **Lưu ý:** Cần cân nhắc trade-off giữa Read performance vs Write overhead, Storage cost vs Query speed, Maintenance complexity vs Simplicity

---

### Task 3: Zero-Downtime Migration (Di chuyển không downtime)

#### Yêu cầu
Cung cấp **expand-contract migration** cụ thể để thêm cột `NOT NULL` (`settlement_batch_id`) vào bảng `transactions` (50M rows) dưới **production load thực tế**.

#### Các bước bắt buộc

| Pha | Mô tả | Yêu cầu |
|---|---|---|
| **1. Expand** | Thêm cột nullable + default | Không lock bảng |
| **2. Backfill** | Cập nhật rows cũ theo batch | Idempotent, không gây lock escalation |
| **3. Dual-write** | App ghi cả cột cũ và mới | Xác định rõ app đọc old vs new shape |
| **4. Constraint promotion** | Thêm NOT NULL constraint | Validate constraint, không full table lock |
| **5. Rollback plan** | Kế hoạch rollback mỗi pha | Mỗi bước phải reversible |

#### Yêu cầu về Scripts
- ✅ **Idempotent** — chạy lại không lỗi
- ✅ **Reversible** — có rollback script
- ✅ Ghi rõ **khi nào app đọc old vs new shape**

> **⚠️ CẢNH BÁO:** Đây là task quan trọng nhất về mặt operational safety. Migration script phải thực sự zero-downtime, không chỉ trên lý thuyết.

---

### Task 4: Polyglot Modelling (Mô hình đa dạng công cụ)

#### 4a. MongoDB — Document Store

**Yêu cầu:** Mô hình hóa 1 use case mà document store phù hợp hơn relational.

**Ví dụ gợi ý:**
- Raw webhook/event payloads
- Append-only audit event log

**Phải giải thích:** Tại sao chọn MongoDB thay vì PostgreSQL JSONB column?

| Tiêu chí so sánh | MongoDB | PostgreSQL JSONB |
|---|---|---|
| Schema flexibility | Native document model | Column trong relational table |
| Horizontal scaling | Built-in sharding | Limited (logical replication) |
| Query patterns | Rich document queries | GIN index, limited |
| Operational overhead | Separate system | Same database |

#### 4b. Neo4j — Graph Database

**Yêu cầu:** Mô hình hóa 1 relationship use case.

**Ví dụ gợi ý:**
- Merchant referral network
- Fraud-ring detection

**Deliverables:**
- Graph model (nodes + relationships)
- 1–2 Cypher queries
- Giải thích tại sao đây thực sự là **graph problem**

> **Gợi ý:** Graph database vượt trội khi cần traverse nhiều mức quan hệ (multi-hop relationships) — ví dụ: tìm fraud ring qua 3+ hops trong mạng lưới giao dịch.

---

### Task 5: Observability (Giám sát & Quan sát)

#### Yêu cầu
Định nghĩa **key metrics và SLOs** cho Grafana dashboard của fintech database.

#### Metrics cần bao phủ

| Metric | Mô tả | Ví dụ SLO |
|---|---|---|
| **Latency** | Thời gian phản hồi query | p99 < 100ms cho OLTP |
| **Throughput** | Số transactions/giây | ≥ 1000 TPS |
| **Replication Lag** | Độ trễ replica | < 1 giây |
| **Lock Contention** | Tần suất lock wait | < 0.1% queries bị block |
| **Settlement Lag** | Thời gian settlement | < 5 phút |
| **Capacity** | Disk usage, connections, memory | < 80% disk usage |

#### Alerts & Thresholds
- Định nghĩa ngưỡng cảnh báo (warning + critical)
- Giải thích **tại sao** chọn ngưỡng đó

---

### Task 6: Design Write-up — ADR (Architecture Decision Record)

#### Yêu cầu
Viết một **ADR ngắn gọn** bao gồm:

1. **Modelling Standards** — Tiêu chuẩn mô hình hóa dữ liệu
2. **Strong vs Eventual Consistency** — Lựa chọn mô hình nhất quán
3. **Data Contracts** — Cách định nghĩa hợp đồng dữ liệu giữa microservices để schema changes không phá vỡ consumers

> **QUAN TRỌNG:** ADR phải trả lời: Khi một service thay đổi schema, làm sao đảm bảo các consumers khác không bị ảnh hưởng?

---

## 🛠 Công cụ khuyến nghị (Recommended Tools)

| Lĩnh vực | Công cụ |
|---|---|
| Relational | **PostgreSQL** (MySQL acceptable) |
| Document | **MongoDB** |
| Graph | **Neo4j** (Cypher) |
| Migrations | **Flyway** hoặc **Liquibase** |
| Observability | **Grafana** (+ Prometheus hoặc equivalent) |

---

## ✅ Tiêu chí đánh giá (Evaluation Criteria)

| # | Tiêu chí | Mô tả |
|---|---|---|
| 1 | **Fintech Data Correctness** | Double-entry integrity, idempotent posting, audit & reconciliation trails — **enforced by schema, not by hope** |
| 2 | **Performance Reasoning** | Đúng index/partition cho workload, khả năng đọc query plan |
| 3 | **Safe Change** | Migration thực sự zero-downtime và reversible, rollback ở mọi bước |
| 4 | **Right Tool for the Job** | Relational vs Document vs Graph — chọn với **justification rõ ràng**, không theo trend |
| 5 | **Written Communication** | Role này nặng về documentation; **độ rõ ràng của notes quan trọng ngang SQL** |

> **⚠️ Lưu ý đặc biệt về tiêu chí #5:** Kỹ năng viết tài liệu được đánh giá ngang với kỹ năng SQL. Cần chú ý clarity, structure, và reasoning trong mọi design notes.

---

## ⏰ Timeline & Submission

| Hạng mục | Chi tiết |
|---|---|
| **Deadline** | 3 ngày (72 giờ) kể từ khi nhận email |
| **Version Control** | Commit thường xuyên, message mô tả rõ reasoning |
| **Submission** | Reply email với link GitHub repository public |
| **README** | Top-level README index tất cả deliverables cho từng task |

> **Lưu ý:** **Không cần** xây dựng ứng dụng chạy được. Thiết kế thực tế, có lý luận tốt với SQL hoạt động và giải thích rõ ràng là đúng yêu cầu.

---

## 📁 Cấu trúc Repository đề xuất

```
vietpay-dba-assessment/
├── README.md                          # Index tất cả deliverables
├── docs/
│   ├── adr/
│   │   └── 001-data-architecture.md   # Task 6: ADR
│   ├── er-diagram.png                 # Task 1: ER Diagram
│   └── observability.md               # Task 5: Metrics & SLOs
├── sql/
│   ├── 01-schema/
│   │   ├── 01-accounts-wallets.sql    # Task 1: DDL
│   │   ├── 02-ledger.sql
│   │   ├── 03-transactions.sql
│   │   ├── 04-idempotency.sql
│   │   └── 05-audit-trail.sql
│   ├── 02-indexes/
│   │   └── performance-indexes.sql    # Task 2: Indexes
│   └── 03-queries/
│       └── optimized-settlement.sql   # Task 2: Optimized query
├── migrations/
│   ├── V001__add_settlement_batch_id_expand.sql    # Task 3
│   ├── V002__backfill_settlement_batch_id.sql
│   ├── V003__promote_not_null_constraint.sql
│   └── rollback/
│       ├── U001__rollback_expand.sql
│       ├── U002__rollback_backfill.sql
│       └── U003__rollback_constraint.sql
├── mongodb/
│   ├── webhook-events-model.md        # Task 4a
│   └── sample-documents.json
├── neo4j/
│   ├── fraud-detection-model.md       # Task 4b
│   └── cypher-queries.cypher
└── design-notes/
    ├── integrity-guarantees.md        # Task 1: Giải thích
    ├── performance-analysis.md        # Task 2: Giải thích
    └── migration-strategy.md          # Task 3: Giải thích
```

---

## 📊 Tổng hợp Deliverables theo Task

| Task | Deliverables | Định dạng |
|---|---|---|
| **1. Relational Core** | DDL files + ER diagram + Integrity notes | `.sql`, `.png/.md`, `.md` |
| **2. Query & Perf** | Optimized query + Indexes + Performance analysis | `.sql`, `.md` |
| **3. Migration** | Migration scripts (idempotent + reversible) + Strategy notes | `.sql`, `.md` |
| **4a. MongoDB** | Document model + Justification | `.json`, `.md` |
| **4b. Neo4j** | Graph model + Cypher queries + Justification | `.cypher`, `.md` |
| **5. Observability** | Metrics, SLOs, Alerts, Thresholds | `.md` |
| **6. ADR** | Architecture Decision Record | `.md` |


---

!!! info "Nguồn gốc"
    `vietpay/requirements_analysis.md`
