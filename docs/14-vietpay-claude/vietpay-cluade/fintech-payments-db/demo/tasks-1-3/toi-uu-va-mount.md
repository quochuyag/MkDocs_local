---
title: Tối ưu VM & Mount thư mục ngoài — Nhật ký các bước đã làm
course: 14-vietpay-claude
source: vietpay_cluade/vietpay_cluade/fintech-payments-db/demo/tasks-1-3/TOI_UU_VA_MOUNT.md
---

# Tối ưu VM & Mount thư mục ngoài — Nhật ký các bước đã làm

Tài liệu ghi lại **những gì đã thực hiện để đưa VM demo về trạng thái tối ưu** và
**mount code/log/kết quả ra thư mục ngoài repo để đọc lại từ host**, kèm lý do và
bằng chứng đã chạy thật (PostgreSQL 16 trên Vagrant/VirtualBox, Windows host).

> Liên quan: tổng quan demo [`00-overview.md`](000-overview.md), cách dùng
> [`README.md`](readme.md).

---

## 0. Bối cảnh

- Host: **16 vCPU, 63.7 GB RAM** (≈40 GB trống), VirtualBox 7.0.20, Vagrant 2.4.9.
- Mục tiêu: VM chạy nhanh nhất có thể, và mọi log/kết quả đọc được trực tiếp từ
  một thư mục trên host (không cần SSH vào VM).

---

## 1. Tự động tối ưu CPU/RAM cho VM

**Làm gì:** `vagrant/Vagrantfile` tự dò tài nguyên host (Ruby, đa nền tảng:
`Etc.nprocessors`; RAM qua PowerShell trên Windows / `/proc/meminfo` Linux /
`sysctl` macOS) rồi cấp phát:

| Tham số | Công thức | Trên máy này |
|---|---|---|
| vCPU | `clamp(host_cpu / 4, 2..6)` | **4** |
| RAM | `clamp(host_ram_mb / 16, 2048..6144)` MB | **~4078 MB** |

**Tại sao:** đủ mạnh để sinh 3M dòng + build index nhanh, nhưng không chiếm hết
host. Ghi đè khi cần: `VM_CPUS=6 VM_RAM=8192 vagrant up`.

**Bằng chứng:** `VBoxManage showvminfo fintech-pg-db` → `cpus=4`, `memory=4078`.

---

## 2. Tinh chỉnh VirtualBox (giảm overhead ảo hoá)

Thêm vào provider trong `Vagrantfile`:

| Flag | Lý do |
|---|---|
| `--paravirtprovider kvm` | giao tiếp paravirt nhanh cho Linux guest |
| `--nestedpaging on` | dùng MMU ảo hoá phần cứng (EPT/NPT) |
| `--largepages on` | giảm TLB miss |
| `--vtxvpid on`, `--vtxux on` | ít TLB flush khi context switch; unrestricted guest |
| `--audio-driver none`, `--usb off`, `--usbehci off` | bỏ thiết bị không dùng, giảm overhead |
| `linked_clone = true` | clone tức thời, tiết kiệm đĩa |

---

## 3. Tune PostgreSQL theo RAM của VM (trạng thái "tốt nhất")

**Làm gì:** `03-install-postgres.sh` ghi `conf.d/99-fintech-tuning.conf`, tính
động theo RAM VM, rồi restart.

| Tham số | Giá trị (VM 4GB) | Lý do |
|---|---|---|
| `shared_buffers` | 25% RAM (≈972 MB) | cache trang trong Postgres |
| `effective_cache_size` | ~66% RAM (≈2594 MB) | gợi ý planner về cache → chọn index hợp lý |
| `maintenance_work_mem` | RAM/8, trần 512 MB (≈486 MB) | build index / VACUUM / backfill nhanh |
| `work_mem` | 16 MB | đủ cho sort/hash thường |
| `random_page_cost` | **1.1** | phần cứng SSD/cloud (mặc định 4 = ổ quay đời cũ) |
| `effective_io_concurrency` | 200 | SSD đọc song song |
| `max_wal_size` / `min_wal_size` | 2 GB / 256 MB | ít checkpoint khi bulk-load |
| `checkpoint_completion_target` | 0.9 | trải I/O checkpoint, tránh spike |
| `wal_compression` | on | giảm WAL |
| `synchronous_commit` | **off** ⚠ | DEMO: nhanh hơn nhiều khi bulk-load; vẫn nhất quán (chỉ mất vài commit cuối nếu mất điện). PROD bật lại. |

**Tại sao `random_page_cost=1.1` là then chốt:** ở lần chạy đầu, planner chọn
Seq Scan + HashAggregate thay vì covering index. Nguyên nhân: mặc định
`random_page_cost=4` (giả định ổ đĩa quay) phạt index-scan quá nặng. Hạ về 1.1
(chuẩn SSD) → planner chọn đúng **Index Only Scan + GroupAggregate**.

---

## 4. Mount code & log ra thư mục NGOÀI repo

**Làm gì:**
- `Vagrantfile` mount thêm `EXPORT_DIR` (mặc định thư mục anh em của repo:
  `…/vietpay_cluade/fintech-demo-exports`) vào VM tại `/exports`, với
  `mount_options: ["dmode=777","fmode=777"]` để user `postgres` ghi được.
- `03-install-postgres.sh` bật `logging_collector` và đặt
  `log_directory='/exports/pg-logs'` → **log server Postgres ghi thẳng ra host**
  (kèm `log_min_duration_statement=200ms`, `log_checkpoints`, `log_lock_waits`,
  `log_autovacuum_min_duration=0`).
- `07-verify-report.sh` copy `report.md`, plan, log từng bước, và `pg-settings.txt`
  sang `EXPORT_DIR`.
- Code repo vốn đã mount sẵn tại `/vagrant` (scripts `psql -f` thẳng vào file gốc).

**Tại sao:** đọc lại kết quả/log từ host không cần SSH; tách khỏi repo nên không
lẫn vào Git.

**Cây thư mục ngoài sau khi chạy:**
```
fintech-demo-exports/
├── pg-logs/postgresql-2026-06-24.log   # log server (autovacuum, slow query, checkpoint…)
├── pg-settings.txt                     # snapshot tham số tuning
└── results/                            # report.md, explain_*_live.txt, *.log, run-all.summary
```

**Bằng chứng (pg-settings.txt, trích):**
```
random_page_cost            1.1
shared_buffers              124416 (8kB)  -> ~972MB
effective_cache_size        332032 (8kB)  -> ~2594MB
synchronous_commit          off
log_directory               /exports/pg-logs
logging_collector           on
```

---

## 5. Giữ minh hoạ "spill" deterministic

Vì server giờ đặt `work_mem=16MB`, `task2_before.sql` & `task2_after.sql` tự
`SET work_mem='4MB'` (mô phỏng server bận) để **BEFORE buộc HashAggregate spill**
còn **AFTER GroupAggregate vẫn không spill** — so sánh công bằng, lặp lại được.

---

## 6. Script destroy

Thêm `09-destroy.sh`:
- mặc định: `vagrant destroy -f` VM, **giữ box** (box dùng chung lab khác).
- `--clean`: xoá thêm log/plan trong `results/`.
- `--remove-box`: gỡ cả box (có cảnh báo).
- `--yes`: không hỏi.
`Makefile` thêm target `destroy` / `clean`.

---

## 7. Kết quả đã chạy thật (3M dòng, VM tối ưu)

`run-all.sh --fresh` → **ALL OK in ~331s**. Trích `results/report.md`:

| Task | Kết quả |
|---|---|
| **1 — Toàn vẹn** | số dư CASH 10000 / FEE 200 / ví 9800; PASS: bút toán lệch, sai currency, idempotency trùng đều bị từ chối |
| **2 — Hiệu năng** | BEFORE: HashAggregate **spill**, buffers hit≈947.905, **~1113ms** → AFTER: **Index Only Scan + GroupAggregate**, Heap Fetches 0, **không spill**, buffers hit≈4.665, **~185ms** (~6× nhanh, ~200× ít buffer), chỉ quét **1 partition** |
| **3 — Migration** | guard chặn khi còn NULL → backfill → `NOT NULL` + validate FK → rollback (U03) sạch |

---

## 8. Tóm tắt các lệnh

```bash
# Chạy đầy đủ (tự tối ưu + mount + tune)
bash demo/tasks-1-3/run-all.sh --fresh
# Chạy nhanh
DEMO_ROWS=500000 bash demo/tasks-1-3/run-all.sh
# Ghi đè tài nguyên / thư mục export
VM_CPUS=6 VM_RAM=8192 EXPORT_DIR=D:/ket-qua bash demo/tasks-1-3/run-all.sh --fresh
# Đọc lại kết quả từ host (không cần SSH)
#   <repo>/../fintech-demo-exports/{results, pg-logs, pg-settings.txt}
# Dọn dẹp
bash demo/tasks-1-3/09-destroy.sh --yes
```


---

!!! info "Nguồn gốc"
    `vietpay_cluade/vietpay_cluade/fintech-payments-db/demo/tasks-1-3/TOI_UU_VA_MOUNT.md`
