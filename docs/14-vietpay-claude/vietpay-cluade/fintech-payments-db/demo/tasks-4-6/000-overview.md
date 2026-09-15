---
title: Demo Task 4–6 trên máy ảo Vagrant — Tổng quan
course: 14-vietpay-claude
source: vietpay_cluade/vietpay_cluade/fintech-payments-db/demo/tasks-4-6/00-overview.md
---

# Demo Task 4–6 trên máy ảo Vagrant — Tổng quan

Mục tiêu: **chạy & test thật** deliverable Task 4–6, theo đúng phong cách lab
Task 1–3 (Vagrant + scripts đánh số + `run-all` + thư mục `results/`).

## Kiến trúc VM (quyết định & lý do)

| Quyết định | Lý do |
|---|---|
| **Task 5/6 dùng LẠI VM `db`** (Postgres của Task 1–3) | Task 5 cần một PostgreSQL THẬT làm target cho exporter; dựng lại là lãng phí. Task 6 chỉ là kiểm tra tài liệu → chạy ké luôn. |
| **Task 4 tách ra VM `poly` riêng** | MongoDB + Neo4j độc lập hoàn toàn với ledger. JVM của Neo4j không nên tranh RAM với Postgres. Đúng tinh thần "right tool, right store". |
| **1 Vagrantfile, 2 máy (multi-machine)** | `vagrant status` thấy cả hai; `poly` đặt `autostart:false` nên luồng Task 1–3 (`vagrant up db`) không đổi. |
| **Task 5 = full stack qua Docker Compose** | postgres_exporter + node_exporter + Prometheus + Alertmanager + Grafana. Prometheus nạp **chính file deliverable** `05-observability/prometheus-rules.yml` → chứng minh rule thật parse & active. |
| **Settlement SLI lấy từ bảng THẬT** `journal_entries.status='PENDING'` | `pg_settlement_oldest_pending_seconds` / `_backlog_count` suy ra từ ledger thật, không phải số bịa. |

## Các bước (mỗi bước 1 script, chạy tuần tự)

| Step | Script | Làm gì |
|---|---|---|
| B1 | `01-vm-up.sh` | Đảm bảo VM `db` chạy (Task 1–3 đã cài) + boot VM `poly` |
| B2 | `02-prepare-os.sh` | Cài Docker trên `db`; cập nhật OS + tiện ích trên `poly` |
| B3 | `03-task4-polyglot.sh` | Cài MongoDB + Neo4j trên `poly`, **chạy file deliverable** rồi assert (TTL/unique index, ring_size≥3, blast-radius) |
| B4 | `04-task5-observability.sh` | `promtool` validate + unit-test rules → dựng stack → **bắn 1 alert end-to-end thật** (Prometheus→Alertmanager) |
| B5 | `05-task6-adr.sh` | Lint markdown + kiểm tra link nội bộ của ADR-001 |
| B6 | `06-verify-report.sh` | Tổng hợp `results/report.md` |

## Yêu cầu trên VM `db` cho Task 5

Task 5 dựng stack giám sát, **cần Postgres của Task 1–3 đã có schema + dữ liệu**.
Nếu chưa chạy Task 1–3, hãy chạy trước:
```bash
bash demo/tasks-1-3/run-all.sh        # tạo DB fintech + schema + dữ liệu
```
Sau đó mới chạy demo Task 4–6.

## Chạy

```bash
# Git Bash / WSL / macOS / Linux (từ thư mục repo)
bash demo/tasks-4-6/run-all.sh
```
```powershell
pwsh demo/tasks-4-6/run-all.ps1
```

Kết quả & log: `demo/tasks-4-6/results/`.
Sau khi xong, mở dashboard từ host: `http://192.168.56.20:3000` (Grafana,
admin/admin), `:9090` (Prometheus), `:9093` (Alertmanager).

## Dọn dẹp

```bash
bash demo/tasks-4-6/09-destroy.sh           # gỡ stack Task 5 + xoá VM poly (hỏi xác nhận)
bash demo/tasks-4-6/09-destroy.sh --all -y  # đồng thời destroy luôn VM db
```


---

!!! info "Nguồn gốc"
    `vietpay_cluade/vietpay_cluade/fintech-payments-db/demo/tasks-4-6/00-overview.md`
