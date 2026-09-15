---
title: Demo & Test Task 1–3 trên Vagrant VM (PostgreSQL 16)
course: 14-vietpay-claude
source: vietpay_cluade/vietpay_cluade/fintech-payments-db/demo/tasks-1-3/README.md
---

# Demo & Test Task 1–3 trên Vagrant VM (PostgreSQL 16)

Bộ script tự động **dựng 1 VM Ubuntu 22.04 + PostgreSQL 16** rồi chạy/kiểm thử
toàn bộ deliverable Task 1–3 ngay trên đó. Theo mẫu lab `D:\Dba_project\HA\Mysql`.

👉 Tổng quan & lý do thiết kế: [`00-overview.md`](000-overview.md).
👉 Nhật ký tối ưu VM + mount thư mục ngoài: [`TOI_UU_VA_MOUNT.md`](toi-uu-va-mount.md).

## Yêu cầu host
- [Vagrant](https://developer.hashicorp.com/vagrant/downloads) ≥ 2.3
- [VirtualBox](https://www.virtualbox.org/) ≥ 7.0
- RAM trống ≥ 3 GB; ~3 GB đĩa cho VM
- (Windows) [Git for Windows](https://git-scm.com/download/win) để có Git Bash

## Chạy toàn bộ (1 lệnh)
```bash
bash demo/tasks-1-3/run-all.sh          # Git Bash / WSL / macOS / Linux
```
```powershell
pwsh demo/tasks-1-3/run-all.ps1         # Windows PowerShell (tự gọi Git Bash)
```

Tuỳ chọn hữu ích:
```bash
DEMO_ROWS=500000 bash demo/tasks-1-3/run-all.sh   # ít dữ liệu → nhanh
bash demo/tasks-1-3/run-all.sh --from=B5          # chỉ chạy lại Task 2 trở đi
bash demo/tasks-1-3/run-all.sh --resume           # tiếp tục sau bước lỗi
KEEP_VM=1 bash demo/tasks-1-3/run-all.sh          # giữ VM cũ, không destroy
```

## Chạy từng bước (nếu muốn quan sát kỹ)
```bash
cd demo/tasks-1-3
bash 01-vagrant-up.sh
bash 02-prepare-os.sh
bash 03-install-postgres.sh
bash 04-task1-schema-integrity.sh   # Task 1
bash 05-task2-performance.sh        # Task 2
bash 06-task3-migration.sh          # Task 3
bash 07-verify-report.sh            # report.md
```

## Sẽ thấy gì (kết quả mong đợi)
- **Task 1:** số dư CASH 10000 / FEE 200 / ví 9800; 3 dòng `PASS` (bút toán lệch,
  sai currency, idempotency trùng đều bị DB từ chối); đối soát mỗi currency = 0.
- **Task 2:** plan **BEFORE** = Bitmap/Seq + HashAggregate (có thể spill);
  plan **AFTER** = **Index Only Scan, Heap Fetches: 0, GroupAggregate** + buffers
  giảm mạnh, chỉ quét **1 partition**.
- **Task 3:** guard chặn promote khi chưa backfill → backfill về 0 NULL →
  promote thành `NOT NULL` + validate FK → rollback (U03) đưa lại nullable.

Tất cả log/plan/report nằm trong [`results/`](results/).

## Vào VM thủ công
```bash
cd vagrant && vagrant ssh db
sudo -u postgres psql -d fintech     # truy vấn trực tiếp
```

## Tài nguyên VM (tự tối ưu)
Vagrantfile **tự dò CPU/RAM host** và cấp phát: vCPU = clamp(host/4, 2..6),
RAM = clamp(host_ram/16, 2048..6144) MB. Ghi đè thủ công:
```bash
VM_CPUS=6 VM_RAM=8192 bash demo/tasks-1-3/run-all.sh --fresh
```
PostgreSQL được tune theo RAM của VM (shared_buffers 25%, effective_cache_size
~66%, `random_page_cost=1.1` cho SSD, maintenance_work_mem 256MB…) trong
`/etc/postgresql/16/main/conf.d/99-fintech-tuning.conf`.

## Dọn dẹp (destroy)
```bash
bash demo/tasks-1-3/09-destroy.sh            # xoá VM (hỏi xác nhận), giữ box
bash demo/tasks-1-3/09-destroy.sh --clean -y # xoá VM + log/plan, không hỏi
bash demo/tasks-1-3/09-destroy.sh --remove-box -y  # ⚠ gỡ cả box (dùng chung lab khác)
# hoặc: make -C vagrant destroy   |   cd vagrant && vagrant destroy -f
```

## Lưu ý
- Con số buffers/thời gian **tuỳ máy**; điều cần chứng minh là **hình dạng plan đổi**
  (Index Only Scan + Heap Fetches: 0 + không spill) và **migration an toàn/đảo ngược được**.
- Script gọi `psql -f` thẳng vào **file deliverable gốc** (`01-…/`, `02-…/`,
  `03-…/`) — đây là test thật cho chính bài nộp, không phải bản sao.


---

!!! info "Nguồn gốc"
    `vietpay_cluade/vietpay_cluade/fintech-payments-db/demo/tasks-1-3/README.md`
