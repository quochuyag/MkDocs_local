---
title: Báo cáo demo Task 1–3 (PostgreSQL trên Vagrant VM)
course: 14-vietpay-claude
source: vietpay_cluade/vietpay_cluade/fintech-payments-db/demo/tasks-1-3/results/report.md
---

# Báo cáo demo Task 1–3 (PostgreSQL trên Vagrant VM)

- Thời điểm: 2026-06-25 11:50:24
- VM: db (192.168.56.20), PostgreSQL 16, DB `fintech`
- Dataset Task 2: 3000000 dòng

## Task 1 — Toàn vẹn ledger
- ✅ Bút toán lệch bị từ chối
- ✅ Sai currency bị từ chối
- ✅ Idempotency key trùng bị chặn

## Task 2 — Hiệu năng (BEFORE vs AFTER)

| Chỉ số | BEFORE | AFTER |
|---|---|---|
| Kiểu quét | Index Scan using ix_legacy_created on transactions | Index Only Scan using transactions_part_2026_02_wallet_id_currency_amount_created_idx on transactions_part_2026_02 transactions_part |
| Aggregate | HashAggregate | GroupAggregate |
| Spill đĩa | CÓ spill | không spill |
| Heap Fetches | n/a | Heap Fetches: 0 |
| Buffers (top) | Buffers: shared hit=947905, temp read=1520 written=3016 | Buffers: shared hit=633881 |

- Exec time BEFORE: Execution Time: 1250.599 ms
- Exec time AFTER : Execution Time: 404.546 ms

> Plan đầy đủ: `results/explain_before_live.txt`, `results/explain_after_live.txt`.
> Điều cần thấy: AFTER chỉ quét **1 partition** + **Index Only Scan, Heap Fetches: 0** + **GroupAggregate không spill**; BEFORE quét rộng + HashAggregate spill.

## Task 3 — Migration zero-downtime
- ✅ Guard chặn promote khi chưa backfill
- ✅ Promote thành NOT NULL + validate FK
- ✅ Rollback (U03) đảo ngược sạch



---

!!! info "Nguồn gốc"
    `vietpay_cluade/vietpay_cluade/fintech-payments-db/demo/tasks-1-3/results/report.md`
