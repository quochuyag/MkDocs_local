---
title: Demo & Test Task 4–6 trên Vagrant VM
course: 14-vietpay-claude
source: vietpay_cluade/vietpay_cluade/fintech-payments-db/demo/tasks-4-6/README.md
---

# Demo & Test Task 4–6 trên Vagrant VM

Bộ script tự động chạy/kiểm thử deliverable **Task 4 (polyglot)**, **Task 5
(observability)**, **Task 6 (ADR)** — theo mẫu lab Task 1–3.

👉 Tổng quan & lý do thiết kế: [`00-overview.md`](000-overview.md).

## Tô-pô

```
VM db   (192.168.56.20)  PostgreSQL 16  ──► Task 5 stack (Docker):
                                            postgres_exporter :9187
                                            node_exporter     :9100
                                            Prometheus        :9090  (nạp prometheus-rules.yml THẬT)
                                            Alertmanager      :9093
                                            Grafana           :3000
                         Task 6: lint ADR-001 chạy ké trên đây
VM poly (192.168.56.21)  MongoDB + Neo4j  ──► Task 4 (webhook firehose + fraud ring)
```

## Yêu cầu host
- Vagrant ≥ 2.3, VirtualBox ≥ 7.0
- RAM trống ≥ ~6 GB (db ~4 GB cho Postgres + stack giám sát, poly ~3 GB)
- (Windows) Git for Windows để có Git Bash

> **Quan trọng:** Task 5 cần Postgres của Task 1–3 đã có schema + dữ liệu.
> Chạy `bash demo/tasks-1-3/run-all.sh` trước nếu chưa.

## Chạy toàn bộ (1 lệnh)
```bash
bash demo/tasks-4-6/run-all.sh                 # Git Bash / WSL / macOS / Linux
```
```powershell
pwsh demo/tasks-4-6/run-all.ps1                # Windows (tự gọi Git Bash)
```

Tuỳ chọn:
```bash
bash demo/tasks-4-6/run-all.sh --from=B4       # chỉ chạy lại Task 5 trở đi
bash demo/tasks-4-6/run-all.sh --resume        # tiếp tục sau bước lỗi
VM_RAM=4096 POLY_RAM=3072 bash demo/tasks-4-6/run-all.sh
```

## Chạy từng bước
```bash
cd demo/tasks-4-6
bash 01-vm-up.sh
bash 02-prepare-os.sh
bash 03-task4-polyglot.sh       # Task 4
bash 04-task5-observability.sh  # Task 5
bash 05-task6-adr.sh            # Task 6
bash 06-verify-report.sh        # report.md
```

## Sẽ thấy gì (kết quả mong đợi)
- **Task 4 — MongoDB:** insert 2 webhook khác shape; có **TTL index** (90 ngày),
  **unique partial index** chặn trùng `idempotency_key`; query replay trả đúng.
- **Task 4 — Neo4j:** Query 1 trả device dùng chung bởi **≥3 account** (`ring_size≥3`);
  Query 2 (blast radius) trả các account trong 4 hop từ account `flagged`.
- **Task 5:** `promtool check rules` PASS trên file deliverable; `promtool test
  rules` chứng minh từng ngưỡng alert fire đúng; Prometheus nạp đủ rule
  (`/api/v1/rules`); seed bút toán PENDING quá hạn → alert **fire end-to-end**,
  xác nhận đã tới **Alertmanager** (`/api/v2/alerts`); Grafana health OK.
- **Task 6:** ADR-001 không có link nội bộ gãy; cấu trúc heading hợp lệ.

Tất cả log/report nằm trong [`results/`](results/).

## Truy cập stack từ host
- Grafana: http://192.168.56.20:3000 (admin/admin)
- Prometheus: http://192.168.56.20:9090
- Alertmanager: http://192.168.56.20:9093

## Vào VM thủ công
```bash
cd vagrant
vagrant ssh db    && sudo -u postgres psql -d fintech
vagrant ssh poly  && mongosh fintech_events
vagrant ssh poly  && cypher-shell -u neo4j -p demopass1
```

## Dọn dẹp
```bash
bash demo/tasks-4-6/09-destroy.sh            # gỡ stack giám sát + xoá VM poly
bash demo/tasks-4-6/09-destroy.sh --all -y   # + destroy VM db
bash demo/tasks-4-6/09-destroy.sh --clean -y # + xoá log trong results/
```

## Lưu ý
- Script gọi thẳng vào **file deliverable gốc** (`04-polyglot/...`,
  `05-observability/prometheus-rules.yml`, `06-adr/...`) trong `/vagrant` — test
  thật cho chính bài nộp, không phải bản sao.
- Một vài alert trong `prometheus-rules.yml` cần series chỉ có ở môi trường thật
  (vd `pg_txn_duration_seconds_bucket` cần app instrument; `pg_up{role=replica}`
  cần có replica). Trên 1 VM chúng **nạp & validate** được nhưng không có dữ liệu
  để fire — `promtool test rules` chứng minh logic ngưỡng của chúng vẫn đúng.


---

!!! info "Nguồn gốc"
    `vietpay_cluade/vietpay_cluade/fintech-payments-db/demo/tasks-4-6/README.md`
