---
title: Demo & Test toàn bộ bài (Task 1–6) trên Vagrant
course: 14-vietpay-claude
source: vietpay_cluade/vietpay_cluade/fintech-payments-db/demo/README.md
---

# Demo & Test toàn bộ bài (Task 1–6) trên Vagrant

Bộ lab tự động **dựng VM + chạy & kiểm thử thật** mọi deliverable của bài fintech
payments DB. Một lệnh để bàn giao — người dùng tự chạy và tự kiểm chứng.

## Tô-pô VM (2 máy, 1 Vagrantfile trong `vagrant/`)

```
db   (192.168.56.20)  PostgreSQL 16     ← Task 1,2,3 và Task 5 (+ Task 6 chạy ké)
                       + Docker stack giám sát (Task 5):
                         postgres_exporter:9187  node_exporter:9100
                         Prometheus:9090  Alertmanager:9093  Grafana:3000
poly (192.168.56.21)  MongoDB + Neo4j   ← Task 4 (polyglot)
```

## Yêu cầu host
- Vagrant ≥ 2.3, VirtualBox ≥ 7.0
- RAM trống ≥ ~6 GB, đĩa ~10 GB
- (Windows) Git for Windows (Git Bash)

## Chạy TẤT CẢ bằng 1 lệnh
```bash
bash demo/run-all.sh                 # Git Bash / WSL / macOS / Linux
```
```powershell
pwsh demo/run-all.ps1                # Windows (tự gọi Git Bash)
```
Thứ tự: **Phase 1 = Task 1–3** (PostgreSQL) → **Phase 2 = Task 4–6**. Bắt buộc
theo thứ tự vì Task 5 đọc ledger do Task 1–3 tạo.

### Tuỳ chọn hữu ích
```bash
KEEP_VM=1 bash demo/run-all.sh           # giữ VM hiện có, KHÔNG destroy (iterate nhanh)
DEMO_ROWS=500000 bash demo/run-all.sh    # ít dữ liệu Task 2 -> nhanh hơn
bash demo/run-all.sh --skip-1-3          # chỉ chạy Phase 2 (Task 1–3 đã chạy trước)
bash demo/run-all.sh --skip-4-6          # chỉ chạy Phase 1
```
> Mặc định (clean-room) Phase 1 sẽ `vagrant destroy` rồi dựng lại VM `db` từ đầu.
> Dùng `KEEP_VM=1` nếu muốn giữ VM đang chạy.

## Kết quả mong đợi (tất cả ✅)
- **Task 1** ledger: số dư đúng; 3 test toàn vẹn (lệch/sai-ccy/idempotency) bị DB từ chối.
- **Task 2** hiệu năng: plan AFTER = Index Only Scan, Heap Fetches 0, không spill, 1 partition.
- **Task 3** migration: guard chặn → backfill → promote NOT NULL → rollback sạch.
- **Task 4** polyglot: Mongo (TTL + unique-partial index, dedupe); Neo4j (ring ≥3, blast-radius).
- **Task 5** observability: `promtool` test rules PASS; Prometheus nạp **đúng file**
  `prometheus-rules.yml`; exporter phát SLI settlement **thật** từ ledger; **alert
  fire end-to-end tới Alertmanager**; Grafana provisioned.
- **Task 6** ADR-001: cấu trúc + link nội bộ hợp lệ.

Báo cáo: `demo/tasks-1-3/results/report.md` và `demo/tasks-4-6/results/report.md`.
Dashboard Grafana sau khi chạy: http://192.168.56.20:3000 (admin/admin).

## Chạy lẻ từng phase
```bash
bash demo/tasks-1-3/run-all.sh    # B1..B7  (PostgreSQL)
bash demo/tasks-4-6/run-all.sh    # B1..B6  (polyglot + observability + ADR)
```

## Dọn dẹp
```bash
bash demo/destroy-all.sh             # destroy cả db + poly (hỏi xác nhận)
bash demo/destroy-all.sh --halt -y   # chỉ TẮT máy (đảo ngược được), giải phóng RAM
bash demo/destroy-all.sh --clean -y  # destroy + xoá log results/ của cả hai bộ
```

## Khắc phục sự cố
- **`VBoxManage ... VERR_ALREADY_EXISTS` khi `vagrant up`** (Windows): VirtualBox
  đôi khi để sót folder VM cũ sau `destroy`. `run-all.sh` và `destroy-all.sh` đã
  **tự dọn** folder mồ côi (`fintech-db`/`fintech-poly`) khi VM không còn đăng ký.
  Nếu vẫn gặp, xoá thủ công `"<Default machine folder>\fintech-db"` rồi chạy lại.
- **Cổng 3000/9090/9093 bận**: đổi qua `GRAFANA_PORT`/`PROM_PORT`/`ALERT_PORT`.
- **Task 5 báo thiếu schema**: chạy Phase 1 trước (`bash demo/run-all.sh` hoặc
  `bash demo/tasks-1-3/run-all.sh`) để tạo ledger.

## Ghi chú thiết kế
- Scripts gọi `psql -f` / `mongosh` / `cypher-shell` / Prometheus **thẳng vào file
  deliverable gốc** trong `/vagrant/...` (synced folder = repo) — test thật cho
  chính bài nộp, không phải bản sao.
- Mọi bước idempotent; mỗi phase có `--resume`/`--from=`. Log: `*/results/`.
- Chi tiết & lý do thiết kế: `demo/tasks-1-3/00-overview.md`, `demo/tasks-4-6/00-overview.md`.


---

!!! info "Nguồn gốc"
    `vietpay_cluade/vietpay_cluade/fintech-payments-db/demo/README.md`
