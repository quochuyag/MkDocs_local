---
title: Demo 01 — Async / Semi-Synchronous Replication (Vagrant Lab)
course: 06-high-availability
source: HA/Mysql/demo/01-async-semisync/README.md
---

# Demo 01 — Async / Semi-Synchronous Replication (Vagrant Lab)

Bộ kịch bản end-to-end để dựng lab 3 node MySQL 8.0 trên Vagrant + VirtualBox và triển khai giải pháp HA **Async / Semi-Sync Replication** (1 master + 2 replicas, GTID auto-position, semi-sync plugin).

> Tham chiếu runbook gốc: [../../runbooks/01-async-semisync-replication.md](../../runbooks/001-async-semisync-replication.md)
> Topology: xem [../../scripts/common/env.sh](../../scripts/common/env.sh)

## Topology demo

| Host  | IP             | Vai trò              | RAM    | server_id |
|-------|----------------|----------------------|--------|-----------|
| node1 | 192.168.10.11  | **Master (RW)**      | 2 GB   | 1         |
| node2 | 192.168.10.12  | Replica (RO)         | 2 GB   | 2         |
| node3 | 192.168.10.13  | Replica (RO)         | 2 GB   | 3         |
| mgmt  | 192.168.10.20  | Client / observer    | 1 GB   | —         |

```
        ┌────────────────────────────────────────────────────────┐
        │                  semi-sync replication                  │
        │                                                         │
        │   ┌──────────┐   bin-log   ┌──────────┐                 │
        │   │  node1   │ ──────────▶ │  node2   │ (RO)            │
        │   │  master  │             └──────────┘                 │
        │   │   (RW)   │ ──────────▶ ┌──────────┐                 │
        │   └──────────┘             │  node3   │ (RO)            │
        │        ▲                   └──────────┘                 │
        │        │ ACK (≥1 replica)                               │
        │        └─────────────────── semi-sync ack ──────────────┘
        └────────────────────────────────────────────────────────
                              ▲
                              │ mysql client
                         ┌────────┐
                         │  mgmt  │  (192.168.10.20)
                         └────────┘
```

## Yêu cầu host

- Windows 10/11 + PowerShell 5+ **hoặc** macOS / Linux + bash
- [Vagrant ≥ 2.3](https://www.vagrantup.com/downloads)
- [VirtualBox ≥ 7.0](https://www.virtualbox.org/wiki/Downloads)
- RAM host ≥ 8 GB (4 VMs)
- Disk trống ≥ 25 GB

## Cấu trúc demo

| Bước | Markdown                              | Shell script                          | Chạy ở đâu     |
|------|---------------------------------------|---------------------------------------|----------------|
| 0    | [00-overview.md](000-overview.md)      | —                                     | (đọc)          |
| 1    | [01-vagrant-up.md](001-vagrant-up.md)  | [01-vagrant-up.sh](01-vagrant-up.sh)  | Host           |
| 2    | [02-prepare-os.md](002-prepare-os.md)  | [02-prepare-os.sh](02-prepare-os.sh)  | Host → 4 VMs   |
| 3    | [03-install-mysql.md](003-install-mysql.md) | [03-install-mysql.sh](03-install-mysql.sh) | Host → 3 DB VMs |
| 4    | [04-master-setup.md](004-master-setup.md) | [04-master-setup.sh](04-master-setup.sh) | Host → node1 |
| 5    | [05-replica-setup.md](005-replica-setup.md) | [05-replica-setup.sh](05-replica-setup.sh) | Host → node2,3 |
| 6    | [06-verify.md](006-verify.md)          | [06-verify.sh](06-verify.sh)          | Host           |
| 7    | [07-smoke-test.md](007-smoke-test.md)  | [07-smoke-test.sh](07-smoke-test.sh)  | Host           |
| 8    | [08-failover-test.md](008-failover-test.md) | [08-failover-test.sh](08-failover-test.sh) | Host         |
| 9    | [09-rollback.md](009-rollback.md)      | [09-rollback.sh](09-rollback.sh)      | Host           |

## Chạy nhanh — end-to-end

### Trên Linux / macOS / WSL / Git Bash:
```bash
cd demo/01-async-semisync
bash run-all.sh
```

### Trên PowerShell (Windows + VirtualBox):
```powershell
cd demo\01-async-semisync
.\run-all.ps1
```

> ⚠ **Yêu cầu Git Bash** (cài kèm "Git for Windows"). Script tự tìm Git Bash tại `C:\Program Files\Git\bin\bash.exe`.
> **KHÔNG dùng** `bash.exe` của WSL ở `C:\Windows\System32\` — WSL2 cần "Virtual Machine Platform"/Hyper-V, sẽ xung đột với VirtualBox.
> Script tự `export VAGRANT_DEFAULT_PROVIDER=virtualbox` để ép Vagrant dùng VirtualBox.

`run-all` thực hiện tuần tự **B1 → B7** và ghi log vào `results/`. Bước **B8 (failover)** và **B9 (rollback)** phải chạy thủ công vì có tính phá huỷ.

### Chạy thủ công không cần bash (Windows native, PowerShell)
Nếu không có Git Bash, có thể boot lab thủ công:
```powershell
$env:VAGRANT_DEFAULT_PROVIDER = 'virtualbox'
cd ..\..\vagrant
bash provision\generate-ssh-key.sh   # cần bash 1 lần để tạo SSH key (hoặc tạo bằng ssh-keygen.exe của Git)
vagrant up
vagrant provision node1 --provision-with common-prep
vagrant provision node2 --provision-with common-prep
vagrant provision node3 --provision-with common-prep
vagrant provision mgmt  --provision-with common-prep
vagrant provision node1 --provision-with install-mysql
vagrant provision node2 --provision-with install-mysql
vagrant provision node3 --provision-with install-mysql
vagrant ssh node1 -c "sudo bash /vagrant/scripts/async-semisync/master-setup.sh"
vagrant ssh node2 -c "sudo bash /vagrant/scripts/async-semisync/replica-setup.sh"
vagrant ssh node3 -c "sudo bash /vagrant/scripts/async-semisync/replica-setup.sh"
```

## Output & báo cáo

Tất cả output verify/smoke/failover được ghi vào [results/](results/):

- `results/06-verify.log` — trạng thái plugin + replica
- `results/07-smoke-test.log` — INSERT/SELECT đồng bộ giữa các node
- `results/08-failover.log` — log promote node2, reconfigure node3
- `results/report.md` — template báo cáo demo, tự điền sau khi chạy

## Dọn dẹp sau khi demo xong

Có 2 mức:

| Mức | Khi nào dùng | Lệnh |
|-----|--------------|------|
| Trong-demo soft rollback (giữ VMs, chỉ tháo replication) | Demo lại nhiều lần | `bash 09-rollback.sh` |
| Soft rollback hard (destroy VMs của demo này) | Hết phiên demo | `MODE=hard bash 09-rollback.sh` |
| **Cleanup TỔNG** (VMs + orphan VBox + SSH keys + .vagrant/) | Xong hẳn workshop | `bash ../../vagrant/cleanup.sh` |
| **Cleanup TỔNG + box + logs** (giải phóng ~700MB disk) | Hết hẳn, đổi máy | `bash ../../vagrant/cleanup.sh --all --yes` |

Trên PowerShell (Windows):
```powershell
..\..\vagrant\cleanup.ps1            # interactive
..\..\vagrant\cleanup.ps1 -All -Yes  # xoá tất bao gồm box + logs, không hỏi
..\..\vagrant\cleanup.ps1 -DryRun    # xem những gì sẽ làm
```

## Tham khảo
- Runbook gốc: [runbooks/01-async-semisync-replication.md](../../runbooks/001-async-semisync-replication.md)
- Vagrant lab: [runbooks/08-vagrant-lab.md](../../runbooks/008-vagrant-lab.md)
- MySQL docs: https://dev.mysql.com/doc/refman/8.0/en/replication-semisync.html


---

!!! info "Nguồn gốc"
    `HA/Mysql/demo/01-async-semisync/README.md`
