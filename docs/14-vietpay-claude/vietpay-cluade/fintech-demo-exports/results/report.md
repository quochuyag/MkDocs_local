---
title: 'Báo cáo demo Task 4–6 (Vagrant: VM db + VM poly)'
course: 14-vietpay-claude
source: vietpay_cluade/vietpay_cluade/fintech-demo-exports/results/report.md
---

# Báo cáo demo Task 4–6 (Vagrant: VM db + VM poly)

- Thời điểm: 2026-06-25 11:56:57
- VM db (Postgres 16, DB `fintech`): 192.168.56.20 — Task 5 + Task 6
- VM poly (MongoDB + Neo4j): 192.168.56.21 — Task 4

## Task 4 — Polyglot (MongoDB + Neo4j)
### MongoDB — webhook firehose
- ✅ Ingest 2 webhook khác shape
- ✅ TTL index (tự hết hạn payload 90 ngày)
- ✅ Unique partial index dedupe idempotency_key
- ✅ Index nested field không cần cột cứng
- ✅ Insert trùng idempotency_key bị từ chối
### Neo4j — fraud-ring
- ✅ Ring: device chia sẻ bởi ≥3 account
- ✅ Blast radius từ account flagged (≤4 hop)
- ✅ Ràng buộc uniqueness (định danh node)

## Task 5 — Observability (full stack)
- promtool: xem `results/promtool-check.txt` & `promtool-test.txt`
- ✅ promtool test rules: mọi alert fire đúng ngưỡng
- ✅ Prometheus NẠP file rule deliverable (rule thật active)
- ✅ Exporter phát metric settlement THẬT từ ledger
- ✅ Alert fire trong Prometheus sau khi seed PENDING quá hạn
- ✅ End-to-end: alert tới Alertmanager (/api/v2/alerts)
- ✅ Grafana provisioned & health OK

> Dashboard: http://192.168.56.20:3000 (Grafana), 192.168.56.20:9090 (Prometheus), 192.168.56.20:9093 (Alertmanager).
> Bằng chứng e2e: `results/alert-e2e.txt`.

## Task 6 — ADR-001
- ✅ ADR tồn tại & không rỗng
- ✅ Cấu trúc heading hợp lệ
- ✅ Link nội bộ không gãy



---

!!! info "Nguồn gốc"
    `vietpay_cluade/vietpay_cluade/fintech-demo-exports/results/report.md`
