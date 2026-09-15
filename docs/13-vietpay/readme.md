---
title: 🏦 VietPay — Enterprise Database Architecture Assessment
course: 13-vietpay
source: vietpay/README.md
---

# 🏦 VietPay — Enterprise Database Architecture Assessment
## Take Home Assessment (Database) — Enterprise Database Architect

---

## 📋 Tổng quan

Repository này chứa thiết kế lớp dữ liệu cốt lõi cho nền tảng thanh toán fintech VietPay, bao gồm:
- PostgreSQL schema chuẩn hóa với double-entry ledger
- Tối ưu hiệu suất truy vấn cho bảng 50M+ rows
- Zero-downtime migration scripts
- Polyglot data modelling (MongoDB + Neo4j)
- Observability & SLO specification
- Architecture Decision Record (ADR)

> 📖 **Đọc [`HUONG-DAN-CHI-TIET.md`](huong-dan-chi-tiet.md) để xem hướng dẫn chi tiết từng task, lý do thiết kế, và kết quả review.**

---

## 📁 Cấu trúc Repository

```
vietpay/
├── README.md                              ← Bạn đang ở đây
├── HUONG-DAN-CHI-TIET.md                  ← Hướng dẫn chi tiết + lý do + review
├── requirements_analysis.md               ← Phân tích yêu cầu từ đề bài
│
├── sql/                                   ← Task 1 & 2
│   ├── 01-schema/                         ← DDL files
│   │   ├── 01-accounts-wallets.sql        ── Accounts & Wallets tables
│   │   ├── 02-ledger.sql                  ── Double-entry ledger
│   │   ├── 03-transactions.sql            ── Transactions table
│   │   ├── 04-idempotency.sql             ── Idempotency keys mechanism
│   │   └── 05-audit-trail.sql             ── Audit trail + triggers
│   ├── 02-indexes/
│   │   └── performance-indexes.sql        ── Covering indexes + partitioning
│   └── 03-queries/
│       └── optimized-settlement.sql       ── Optimized settlement query + materialized view
│
├── migrations/                            ← Task 3
│   ├── V001__add_settlement_batch_id_expand.sql    ── Phase 1: Expand
│   ├── V002__backfill_settlement_batch_id.sql      ── Phase 2: Backfill
│   ├── V003__promote_not_null_constraint.sql       ── Phase 3: Contract
│   └── rollback/
│       ├── U001__rollback_expand.sql               ── Rollback Phase 1
│       ├── U002__rollback_backfill.sql              ── Rollback Phase 2
│       └── U003__rollback_constraint.sql            ── Rollback Phase 3
│
├── mongodb/                               ← Task 4a
│   ├── webhook-events-model.md            ── MongoDB design document
│   └── sample-documents.js                ── Sample documents + aggregation pipelines
│
├── neo4j/                                 ← Task 4b
│   ├── fraud-detection-model.md           ── Neo4j design document
│   └── cypher-queries.cypher              ── Graph schema + Cypher queries
│
├── docs/                                  ← Task 5 & 6
│   ├── er-diagram.md                      ── ER Diagram (Mermaid)
│   ├── observability.md                   ── Grafana dashboard + SLOs + alerts
│   └── adr/
│       └── 001-data-architecture.md       ── Architecture Decision Record
│
└── design-notes/                          ← Detailed explanations
    ├── integrity-guarantees.md            ── Double-entry, idempotency, indexing
    ├── performance-analysis.md            ── Query plan analysis, trade-offs
    └── migration-strategy.md              ── Zero-downtime migration strategy
```

---

## 🎯 Index theo Task

### Task 1: Relational Core Model
| Deliverable | File | Mô tả |
|---|---|---|
| DDL — Accounts & Wallets | [`01-accounts-wallets.sql`](sql/01-schema/01-accounts-wallets.sql) | Tables `accounts`, `wallets` với UUID PKs, CHECK constraints |
| DDL — Ledger | [`02-ledger.sql`](sql/01-schema/02-ledger.sql) | `ledger_entries` append-only, zero-sum enforcement trigger |
| DDL — Transactions | [`03-transactions.sql`](sql/01-schema/03-transactions.sql) | `transactions` table, status state machine trigger |
| DDL — Idempotency | [`04-idempotency.sql`](sql/01-schema/04-idempotency.sql) | `idempotency_keys` với UNIQUE constraint, TTL cleanup |
| DDL — Audit Trail | [`05-audit-trail.sql`](sql/01-schema/05-audit-trail.sql) | `audit_log` append-only, generic trigger function |
| ER Diagram | [`er-diagram.md`](docs/er-diagram.md) | Mermaid ER diagram toàn bộ schema |
| Design Notes | [`integrity-guarantees.md`](design-notes/integrity-guarantees.md) | Giải thích chi tiết integrity guarantees |

### Task 2: Query & Performance
| Deliverable | File | Mô tả |
|---|---|---|
| Indexes + Partitioning | [`performance-indexes.sql`](sql/02-indexes/performance-indexes.sql) | Covering partial index, composite indexes, monthly partitioning |
| Optimized Query | [`optimized-settlement.sql`](sql/03-queries/optimized-settlement.sql) | 3 approaches: direct + materialized view + hybrid |
| Performance Analysis | [`performance-analysis.md`](design-notes/performance-analysis.md) | EXPLAIN plan analysis, trade-offs, benchmarks |

### Task 3: Zero-Downtime Migration
| Deliverable | File | Mô tả |
|---|---|---|
| Phase 1 — Expand | [`V001__*.sql`](migrations/v001-add-settlement-batch-id-expand.sql) | Add nullable column + FK + indexes CONCURRENTLY |
| Phase 2 — Backfill | [`V002__*.sql`](migrations/v002-backfill-settlement-batch-id.sql) | Batch update 50M rows, advisory lock, progress tracking |
| Phase 3 — Contract | [`V003__*.sql`](migrations/v003-promote-not-null-constraint.sql) | NOT VALID CHECK + VALIDATE + SET NOT NULL |
| Rollback Scripts | [`rollback/`](migrations/rollback/) | Reversible rollback for each phase |
| Migration Strategy | [`migration-strategy.md`](design-notes/migration-strategy.md) | Comprehensive strategy with risk assessment |

### Task 4: Polyglot Modelling
| Deliverable | File | Mô tả |
|---|---|---|
| MongoDB Model | [`webhook-events-model.md`](mongodb/webhook-events-model.md) | Webhook event store, justification vs JSONB |
| MongoDB Samples | [`sample-documents.js`](mongodb/sample-documents.js) | Sample documents, indexes, aggregation pipelines |
| Neo4j Model | [`fraud-detection-model.md`](neo4j/fraud-detection-model.md) | Fraud ring detection graph model |
| Cypher Queries | [`cypher-queries.cypher`](neo4j/cypher-queries.cypher) | Graph schema + fraud detection queries |

### Task 5: Observability
| Deliverable | File | Mô tả |
|---|---|---|
| Dashboard + SLOs | [`observability.md`](docs/observability.md) | 11 metrics, PromQL, SLO targets, 11 alert rules |

### Task 6: Design Write-up (ADR)
| Deliverable | File | Mô tả |
|---|---|---|
| ADR | [`001-data-architecture.md`](docs/adr/001-data-architecture.md) | Modelling standards, consistency, data contracts |

---

## 🔑 Key Design Decisions

### 1. Fintech Data Correctness
- **Double-entry ledger** với DEFERRABLE constraint trigger — mỗi transaction phải có entries sum = 0
- **Immutable financial records** — ledger + audit log không thể UPDATE/DELETE
- **Idempotency keys** — UNIQUE constraint ngăn duplicate posting
- **Defense in depth**: constraints → triggers → app logic → periodic verification

### 2. Performance
- **Covering partial index** cho settlement query: `WHERE status = 'SETTLED'` → Index-Only Scan
- **Range partitioning** theo `created_at` (monthly) → Partition pruning, parallel query
- **Materialized view** cho historical reports → Pre-aggregated, < 10ms query time
- **Settlement query improvement**: 45s → 850ms (Index) → 230ms (Partition) → 10ms (MV)

### 3. Safe Change
- **Expand-contract pattern** — add nullable → backfill → dual-write → promote NOT NULL
- **NOT VALID + VALIDATE** — chỉ cần ShareUpdateExclusiveLock, không block DML
- **Batch backfill** — 10K rows/batch, pg_sleep between batches, advisory lock
- **Rollback at every phase** — idempotent rollback scripts

### 4. Right Tool for the Job
- **PostgreSQL** — OLTP core (wallets, ledger, transactions) — ACID guarantees
- **MongoDB** — Webhook event ingestion — schema-less, sharding, TTL
- **Neo4j** — Fraud ring detection — multi-hop graph traversal, pattern matching

### 5. Data Contracts
- **Schema Registry** (Confluent, Avro) — versioned event schemas
- **BACKWARD compatibility** — consumers xử lý old + new format
- **Contract testing** (Pact) — CI/CD fails before breaking changes reach production

---

## 🛠 Technology Stack

| Area | Tool | Version |
|---|---|---|
| Relational DB | PostgreSQL | 15+ |
| Document DB | MongoDB | 7.0+ |
| Graph DB | Neo4j | 5.x |
| Migrations | Flyway | 10.x |
| Metrics | Prometheus + postgres_exporter | latest |
| Dashboards | Grafana | 10.x |
| Schema Registry | Confluent Schema Registry | 7.x |
| CDC | Debezium | 2.x |

---

## 📐 Recommended Tools

| Lĩnh vực | Công cụ đã sử dụng |
|---|---|
| Relational | PostgreSQL ✅ |
| Document | MongoDB ✅ |
| Graph | Neo4j (Cypher) ✅ |
| Migrations | Flyway ✅ |
| Observability | Grafana + Prometheus ✅ |


---

!!! info "Nguồn gốc"
    `vietpay/README.md`
