---
title: Demo Task 1–3 trên máy ảo Vagrant — Tổng quan
course: 14-vietpay-claude
source: vietpay_cluade/vietpay_cluade/fintech-payments-db/demo/tasks-1-3/00-overview.md
---

# Demo Task 1–3 trên máy ảo Vagrant — Tổng quan

Mục tiêu: **chạy & test thật** các deliverable Task 1–3 trong một VM PostgreSQL
sạch, bằng scripts tự động — theo đúng phong cách lab `D:\Dba_project\HA\Mysql`
(Vagrant + scripts đánh số + `run-all` + thư mục `results/`).

## Vì sao thiết kế thế này

| Quyết định | Lý do |
|---|---|
| **1 VM** (không phải 4 như lab MySQL HA) | Task 1–3 chạy trên **một** PostgreSQL đơn (ledger, tối ưu query, migration). Không có replication/cluster → không cần nhiều node. |
| **Ubuntu 22.04 + PostgreSQL 16 (PGDG)** | Khớp stack ghi trong README repo; PGDG cho bản 16 chính chủ. |
| **Synced folder repo → `/vagrant`** | Script `psql -f` thẳng vào **chính các file deliverable** (`01-…/schema`, `02-…`, `03-…/flyway`) → chứng minh file gốc chạy được, không phải bản sao. |
| **`env.sh` single source of truth** | Tên VM/DB/IP/số dòng khai báo 1 chỗ; script con chỉ tham chiếu `${VAR}`. |
| **Mọi step idempotent + `run-all --resume`** | Lab hay bị ngắt giữa chừng (RAM/IO); chạy lại không hại, resume được. |
| **Dữ liệu Task 2 sinh DETERMINISTIC** | Theo `generate_series` (không random thuần) → số liệu tái lập giữa các lần chạy. |

## Các bước (mỗi bước 1 script, chạy tuần tự)

| Step | Script | Làm gì |
|---|---|---|
| B1 | `01-vagrant-up.sh` | Boot VM Ubuntu 22.04, kiểm tra `/vagrant` |
| B2 | `02-prepare-os.sh` | Cập nhật OS + tiện ích |
| B3 | `03-install-postgres.sh` | Cài PostgreSQL 16 + tạo DB `fintech` |
| B4 | `04-task1-schema-integrity.sh` | Apply schema ledger + **test toàn vẹn** (lệch/sai-ccy/trùng-idem/đối soát) |
| B5 | `05-task2-performance.sh` | Sinh dữ liệu + capture **plan BEFORE/AFTER** |
| B6 | `06-task3-migration.sh` | Chạy **expand-contract** thật: guard chặn → backfill → promote → rollback |
| B7 | `07-verify-report.sh` | Tổng hợp `results/report.md` |

## Chạy

```bash
# Git Bash / WSL / macOS / Linux (từ thư mục repo)
bash demo/tasks-1-3/run-all.sh
# Chạy nhanh (ít dữ liệu hơn):
DEMO_ROWS=500000 bash demo/tasks-1-3/run-all.sh
```
```powershell
# PowerShell (Windows) — wrapper tự tìm Git Bash
pwsh demo/tasks-1-3/run-all.ps1
```

Kết quả & log: `demo/tasks-1-3/results/` (`report.md`, `explain_*_live.txt`, `*.log`).

## Dọn dẹp

```bash
cd vagrant && vagrant destroy -f      # xoá VM
# hoặc: make -C vagrant destroy
```


---

!!! info "Nguồn gốc"
    `vietpay_cluade/vietpay_cluade/fintech-payments-db/demo/tasks-1-3/00-overview.md`
