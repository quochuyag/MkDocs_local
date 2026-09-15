---
title: HƯỚNG DẪN CHI TIẾT — VietPay Database Assessment
course: 14-vietpay-claude
source: vietpay_cluade/HUONG_DAN.md
---

# HƯỚNG DẪN CHI TIẾT — VietPay Database Assessment

> Tài liệu tiếng Việt giải thích **đã làm gì, làm theo các bước nào, và TẠI SAO
> làm như vậy** cho từng task, kèm cách chạy/kiểm tra và cách đưa vào máy bạn.
> Toàn bộ phần SQL (Task 1–3) đã được chạy thật trên PostgreSQL 16 — xem
> `KET_QUA_KIEM_TRA.md`.

## Mục lục
1. [Cấu trúc thư mục](#1-cấu-trúc-thư-mục)
2. [Task 1 — Mô hình ledger quan hệ](#2-task-1--mô-hình-ledger-quan-hệ)
3. [Task 2 — Tối ưu truy vấn & hiệu năng](#3-task-2--tối-ưu-truy-vấn--hiệu-năng)
4. [Task 3 — Migration zero-downtime](#4-task-3--migration-zero-downtime)
5. [Task 4 — Polyglot (MongoDB + Neo4j)](#5-task-4--polyglot-mongodb--neo4j)
6. [Task 5 — Observability](#6-task-5--observability)
7. [Task 6 — ADR](#7-task-6--adr)
8. [Cách chạy & kiểm tra trên Windows](#8-cách-chạy--kiểm-tra-trên-windows)
9. [Cách nộp bài (đẩy lên GitHub)](#9-cách-nộp-bài-đẩy-lên-github)

---

## 1. Cấu trúc thư mục

```
vietpay_cluade/                         (thư mục đích trên máy bạn: D:\Dba_project\vietpay_cluade)
└── fintech-payments-db/                Repo Git hoàn chỉnh (đã có sẵn lịch sử commit)
    │
    ├── README.md                       Bản tóm tắt + chỉ mục deliverable (tiếng Anh, để nộp)
    ├── HUONG_DAN.md                    ◀ TÀI LIỆU NÀY (giải thích chi tiết, tiếng Việt)
    ├── KET_QUA_KIEM_TRA.md             Bằng chứng các test đã chạy đậu
    ├── run_all.sh                      Script chạy lại schema + in số dư kiểm chứng
    ├── .gitignore
    │
    ├── 01-relational-core/             ── TASK 1: ledger lõi ──
    │   ├── schema/
    │   │   ├── 00_extensions_and_types.sql   ENUM + extension
    │   │   ├── 01_accounts_wallets.sql       Khách hàng, ví, hệ thống tài khoản
    │   │   ├── 02_idempotency.sql            Chống post trùng
    │   │   ├── 03_ledger.sql                 Bút toán kép + trigger cân sổ
    │   │   ├── 04_audit_trail.sql            Nhật ký chỉ-ghi-thêm (append-only)
    │   │   └── 05_seed_and_worked_example.sql Dữ liệu mẫu + ví dụ nạp tiền chạy được
    │   ├── er-diagram.md               Sơ đồ ER (Mermaid)
    │   └── integrity-notes.md          Giải thích đảm bảo toàn vẹn + chiến lược index
    │
    ├── 02-query-performance/           ── TASK 2: hiệu năng ──
    │   ├── 00_transactions_unpartitioned.sql  Bảng cũ (trạng thái TRƯỚC)
    │   ├── 01_optimized_partitioned.sql       Partition theo tháng + covering index
    │   ├── 02_optimized_query.sql             Truy vấn báo cáo đã tối ưu
    │   ├── 03_rollup_alternative.sql          Bảng tổng hợp (giải pháp khi báo cáo chạy liên tục)
    │   ├── explain_before.txt / explain_after.txt   Query plan đo thật
    │   └── performance-notes.md               Phân tích + số liệu đo
    │
    ├── 03-migration/                   ── TASK 3: migration ──
    │   ├── flyway/   V...01 expand, V...02 backfill, V...03 contract
    │   ├── undo/     U...01..03 (rollback từng phase)
    │   ├── migration-notes.md          Giải thích từng phase + khi nào app đọc shape cũ/mới
    │   └── runbook.md                  Các lệnh vận hành theo thứ tự
    │
    ├── 04-polyglot/                    ── TASK 4 ──
    │   ├── mongodb/webhook_events.js   Mô hình event firehose
    │   ├── neo4j/fraud_ring.cypher     Mô hình + truy vấn phát hiện gian lận
    │   └── polyglot-notes.md           Lý giải vì sao chọn từng loại DB
    │
    ├── 05-observability/               ── TASK 5 ──
    │   ├── observability.md            Metrics, SLO, cảnh báo
    │   └── prometheus-rules.yml        File rule cảnh báo Prometheus
    │
    └── 06-adr/
        └── ADR-001-data-architecture.md  ── TASK 6: bản ghi quyết định kiến trúc ──
```

**Quy ước đặt tên:** thư mục đánh số `01..06` theo đúng thứ tự 6 task trong đề;
mỗi task có file SQL/code + một file `*-notes.md` giải thích. Cứ mở file `.md`
trong mỗi thư mục là hiểu phần đó.

---

## 2. Task 1 — Mô hình ledger quan hệ

**Mục tiêu của đề:** thiết kế schema PostgreSQL chuẩn hoá cho ví/thanh toán gồm
tài khoản/ví, **sổ kế toán kép (double-entry)**, giao dịch, idempotency key, và
audit trail. Giải thích: sổ luôn cân, request trùng không post 2 lần, và chiến
lược index.

### Đã làm gì
Tạo 6 file SQL trong `01-relational-core/schema/`. Các bảng chính: `currencies`,
`customers`, `accounts` (gồm cả ví khách và tài khoản hệ thống), `journal_entries`
(đầu bút toán), `ledger_postings` (các vế nợ/có), `account_balances` (số dư duy
trì sẵn), `idempotency_keys`, `audit_log`.

### Các bước & LÝ DO từng quyết định
1. **Tiền lưu bằng `BIGINT` đơn vị nhỏ nhất (cent), KHÔNG dùng float.**
   *Lý do:* số thực nhị phân không biểu diễn chính xác `0.1`; trong sổ tiền điều
   này gây lệch khi đối soát. Mỗi loại tiền có `minor_unit` (USD=2, VND=0).
2. **Kế toán kép:** mỗi sự kiện = 1 `journal_entry` + ≥2 `ledger_postings`,
   tổng Nợ = tổng Có. Dấu nằm ở cột `direction` (DEBIT/CREDIT), `amount` luôn > 0.
   *Lý do:* không thể "cân giả" bằng số âm; mọi dòng tiền luôn có đủ 2 vế.
3. **Trigger cân sổ kiểu DEFERRED (kiểm tra lúc COMMIT).**
   *Lý do:* cho phép insert đầu bút toán và N vế theo thứ tự bất kỳ trong 1
   transaction; chỉ cần cân khi transaction kết thúc. Nếu lệch → từ chối commit.
4. **Trigger khớp loại tiền** (vế phải cùng currency với tài khoản).
   *Lý do:* tránh ghi nhầm USD vào ví VND.
5. **`account_balances` cập nhật ngay trong cùng transaction** (qua trigger),
   theo "normal balance": ASSET/EXPENSE tăng khi DEBIT, còn lại tăng khi CREDIT.
   *Lý do:* số dư và các vế gốc không bao giờ lệch nhau.
6. **Idempotency:** `UNIQUE(idem_key, request_path)`. Handler INSERT key trong
   **cùng transaction** tạo bút toán. Request trùng đụng unique → đọc kết quả đã
   lưu, **không post lại**. `request_hash` bắt trường hợp dùng lại key với body
   khác. *Lý do:* đây chính là "khóa" chống post 2 lần khi client retry.
7. **Audit trail append-only:** trigger ghi ảnh JSONB cũ/mới; chặn UPDATE/DELETE
   trên `audit_log` bằng RULE. *Lý do:* nhật ký không thể bị sửa → tin cậy để đối soát.

### Kết quả kiểm chứng
Ví dụ nạp $100 phí $2 → CASH 10000 / FEE 200 / ví 9800 (cân). Bút toán lệch và
sai currency đều bị từ chối; request trùng không post gì. (Xem `integrity-notes.md`.)

---

## 3. Task 2 — Tối ưu truy vấn & hiệu năng

**Mục tiêu:** tăng tốc truy vấn báo cáo settlement trên bảng 50 triệu dòng:
```sql
SELECT wallet_id,currency,SUM(amount) FROM transactions
WHERE status='SETTLED' AND created_at>=:m_start AND created_at<:m_end
GROUP BY wallet_id,currency;
```

### Đã làm gì & LÝ DO
1. **Partition `transactions` theo tháng (RANGE trên `created_at`).**
   *Lý do:* truy vấn luôn giới hạn trong 1 tháng → planner "prune" chỉ quét **1
   partition** thay vì cả 50M dòng. Bonus: xoá/lưu trữ tháng cũ chỉ là thao tác
   metadata (DETACH/DROP), không phải DELETE hàng triệu dòng.
2. **Partial covering index:**
   `(wallet_id, currency) INCLUDE (amount, created_at) WHERE status='SETTLED'`.
   - `WHERE status='SETTLED'` (partial): index chỉ chứa dòng báo cáo cần →
     nhỏ & rẻ; insert PENDING/FAILED không đụng index.
   - khoá `(wallet_id, currency)`: khớp `GROUP BY` → gộp bằng **GroupAggregate
     không cần sort, không spill ra đĩa**.
   - `INCLUDE (amount, created_at)`: index **bao phủ** → `SUM(amount)` và điều
     kiện ngày lấy thẳng từ index → **Index Only Scan, Heap Fetches: 0**.
3. **Giải pháp khi báo cáo chạy liên tục:** bảng tổng hợp
   `settlement_monthly_rollup` cập nhật tăng dần → báo cáo biến thành tra cứu
   điểm (dưới 1ms). Bảng partition vẫn là nguồn sự thật.

### Cách xác minh cải thiện (đọc query plan)
Chạy `EXPLAIN (ANALYZE, BUFFERS)` và kiểm tra: (1) chỉ 1 partition xuất hiện
(pruning); (2) **Index Only Scan, Heap Fetches: 0**; (3) GroupAggregate không
spill; (4) **Buffers giảm khoảng 1 bậc**.

### Kết quả đo thật (2M dòng)
Buffers 22.294 → **3.289** (~6.8× ít hơn); HashAggregate spill 15MB → GroupAggregate
không spill; Bitmap Heap Scan → Index Only Scan. (Plan đầy đủ ở `explain_*.txt`.)

### Chi phí của index
~30 MB/tháng cho phần SETTLED; chỉ chịu write-amplification trên dòng SETTLED
(nhờ partial). Đổi lại giảm ~7× I/O đọc — đáng cho workload báo cáo đọc nhiều.

---

## 4. Task 3 — Migration zero-downtime

**Mục tiêu:** thêm cột `settlement_batch_id NOT NULL` vào bảng 50M dòng đang
chạy production, **không downtime, không khóa lâu, rollback ở mọi bước**.

### Vì sao cách "ngây thơ" gây sập
`ADD COLUMN ... NOT NULL DEFAULT ...` có thể rewrite toàn bộ 50M dòng dưới khóa
`ACCESS EXCLUSIVE` → khóa đọc/ghi vài phút. Nên ta tách "thêm cột" khỏi "bắt buộc".

### Mẫu Expand → Migrate → Contract (các phase)
| Phase | Việc làm | Khóa | App đọc |
|---|---|---|---|
| 1. Expand | thêm cột **nullable** + FK `NOT VALID` | metadata, tức thời | **shape CŨ** |
| 2. Dual-write | deploy app ghi cột cho mọi insert mới | không | **shape CŨ** |
| 3. Backfill | procedure cập nhật dòng cũ **theo batch** | ngắn từng batch | **shape CŨ** |
| 4. Contract | `CHECK NOT VALID`→`VALIDATE`→`SET NOT NULL` | nhẹ, không rewrite | **shape MỚI** |
| 5. Cleanup | deploy app bỏ nhánh code cũ | không | **shape MỚI** |

### LÝ DO các kỹ thuật then chốt
- **FK `NOT VALID`:** thêm tức thì, ép đúng cho dòng mới, không quét 50M dòng cũ.
- **Backfill có `COMMIT` từng batch + `FOR UPDATE SKIP LOCKED` + `pg_sleep`:**
  giải phóng khóa, giới hạn bloat, không tranh chấp với ghi production, có thể
  bóp ga. **Idempotent** (`WHERE ... IS NULL`) → ngắt giữa chừng chạy lại được.
- **Guard clause:** nếu còn dòng NULL, V3 báo lỗi và dừng → không có trạng thái
  nửa vời.
- **`CHECK NOT VALID` rồi `VALIDATE` rồi `SET NOT NULL`:** PG12+ tái dùng CHECK
  đã validate để **bỏ qua quét toàn bảng** khi set NOT NULL → nhanh, khóa nhẹ.
- **App đọc shape cũ đến hết phase 3**, chỉ phụ thuộc cột sau phase 4 → rollback
  bất kỳ lúc nào trước đó chỉ là redeploy, không đụng dữ liệu.

### Kết quả kiểm chứng (2M dòng)
Guard chặn đúng khi chưa backfill; sau backfill cột thành `NOT NULL`, FK được
validate; script undo đảo ngược sạch; chạy lại forward là no-op (idempotent).

---

## 5. Task 4 — Polyglot (MongoDB + Neo4j)

**MongoDB — kho event webhook thô.** Mỗi nhà cung cấp (Stripe, Adyen…) gửi payload
hình dạng khác nhau, ghi rất nhiều, append-only, có vòng đời lưu trữ riêng.
*Vì sao hơn cột JSONB của Postgres:* shape không đồng nhất, ghi nặng & shard theo
`{provider, received_at}`, **TTL index** tự xoá sau 90 ngày, index trực tiếp field
lồng nhau. *Ranh giới trung thực:* nếu volume nhỏ và hay JOIN với ledger thì JSONB
lại đơn giản hơn.

**Neo4j — phát hiện vòng gian lận.** Các tài khoản nối nhau qua thiết bị/thẻ/IP
chung. *Vì sao đúng là bài toán graph:* câu hỏi về **độ sâu thay đổi** ("trong 4
hop có những tài khoản nào liên quan?") — SQL phải self-join đệ quy rối rắm, còn
Cypher dùng `-[:USED_DEVICE|USED_CARD*1..4]-` và *index-free adjacency* nên chi
phí theo kích thước vùng lân cận chứ không phải toàn bảng. *Ranh giới:* nếu chỉ
hỏi 1-hop ("ai dùng thẻ X") thì index quan hệ là đủ.

Chi tiết + 2 truy vấn Cypher: `04-polyglot/`.

---

## 6. Task 5 — Observability

Hai tầng: **sức khỏe hạ tầng** và **SLI nghiệp vụ** (tiền có settle đúng hạn?).
Định nghĩa metric/SLO cho: latency (p99 ghi < 50ms), throughput, **replication
lag** (<10s), **lock contention/deadlock**, **settlement lag** (99% trong 15
phút), capacity (connection, đĩa, **txid wraparound** — sát thủ thầm lặng của
Postgres).

Cảnh báo: chỉ **page** (gọi dậy) cho thứ ảnh hưởng người dùng hoặc nguy cấp (lag,
backlog, wraparound, cạn connection/đĩa); còn lại là **warn** để on-call không bị
nhiễu. File rule: `05-observability/prometheus-rules.yml`.

---

## 7. Task 6 — ADR (bản ghi quyết định kiến trúc)

Gồm: chuẩn mô hình hoá (tiền là số nguyên, toàn vẹn ở schema, key BIGINT nội bộ +
UUID đối ngoại, thời gian UTC `timestamptz`, không xoá cứng), lựa chọn **mạnh vs
eventual consistency** (ledger mạnh; báo cáo/replica/event/graph eventual; ghi
chéo service dùng **outbox pattern**), và **data contract** giữa microservice
(không share bảng, event versioned + schema registry, expand-contract cho cả
contract, consumer-driven contract test). Xem `06-adr/ADR-001-data-architecture.md`.

---

## 8. Cách chạy & kiểm tra trên Windows

### 8.1 Đặt project vào đúng thư mục
1. Giải nén `fintech-payments-db.zip`. Bên trong có thư mục `fintech-payments-db`.
2. Tạo thư mục đích và chép vào:
   ```
   D:\Dba_project\vietpay_cluade\fintech-payments-db\
   ```
   (Trong file zip đã kèm sẵn thư mục `.git` với lịch sử commit — giữ nguyên.)

### 8.2 Cài PostgreSQL & chạy thử (PowerShell)
1. Cài PostgreSQL 16 (https://www.postgresql.org/download/windows/).
2. Mở PowerShell tại thư mục project:
   ```powershell
   cd D:\Dba_project\vietpay_cluade\fintech-payments-db
   $env:PGPASSWORD="<mật khẩu postgres của bạn>"
   createdb -U postgres fintech
   psql -U postgres -d fintech -f 01-relational-core/schema/00_extensions_and_types.sql
   psql -U postgres -d fintech -f 01-relational-core/schema/01_accounts_wallets.sql
   psql -U postgres -d fintech -f 01-relational-core/schema/02_idempotency.sql
   psql -U postgres -d fintech -f 01-relational-core/schema/03_ledger.sql
   psql -U postgres -d fintech -f 01-relational-core/schema/04_audit_trail.sql
   psql -U postgres -d fintech -f 01-relational-core/schema/05_seed_and_worked_example.sql
   ```
3. Kiểm tra số dư (phải là CASH 10000 / FEE 200 / ví 9800):
   ```powershell
   psql -U postgres -d fintech -c "SELECT COALESCE(a.system_code,'wallet:'||a.owner_customer_id) acct,b.balance,b.currency FROM account_balances b JOIN accounts a ON a.id=b.account_id ORDER BY a.id;"
   ```
> Mẹo: nếu có Git Bash/WSL, có thể chạy thẳng `./run_all.sh` thay cho các lệnh trên.

### 8.3 Task 2/3 (tùy chọn, cần dữ liệu)
- Task 2: chạy `00_...`, `01_...` rồi nạp dữ liệu mẫu và dùng `EXPLAIN (ANALYZE,
  BUFFERS)` với truy vấn trong `02_optimized_query.sql` để tự thấy plan đổi.
- Task 3: chạy lần lượt `flyway/V...01`, `V...02`, `CALL backfill_settlement_batch_id(10000,50);`,
  rồi `V...03`. Muốn rollback thì chạy file trong `undo/`.

---

## 9. Cách nộp bài (đẩy lên GitHub)

```powershell
cd D:\Dba_project\vietpay_cluade\fintech-payments-db
git config user.name "Tên của bạn"
git config user.email "email@cua.ban"
# Tạo repo public rỗng trên GitHub trước, rồi:
git remote add origin https://github.com/<tài-khoản>/<repo>.git
git branch -M main
git push -u origin main
```
Sau đó reply vào email assessment kèm link repo. README.md (tiếng Anh) đã là chỉ
mục deliverable cho người chấm.

> ⚠️ Lưu ý nhỏ: tên file migration và ngày commit đang để **2026-06-23**. Nếu cần,
> chỉnh lại cho khớp thời điểm thực của bạn trước khi push.


---

!!! info "Nguồn gốc"
    `vietpay_cluade/HUONG_DAN.md`
