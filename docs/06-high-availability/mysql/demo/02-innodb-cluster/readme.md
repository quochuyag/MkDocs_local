---
title: Demo 02 — MySQL InnoDB Cluster (Vagrant Lab)
course: 06-high-availability
source: HA/Mysql/demo/02-innodb-cluster/README.md
---

# Demo 02 — MySQL InnoDB Cluster (Vagrant Lab)

Bộ kịch bản end-to-end để dựng lab 3 DB node + 1 mgmt host trên Vagrant + VirtualBox và triển khai giải pháp HA **InnoDB Cluster** = Group Replication (data plane) + MySQL Shell (control plane) + MySQL Router (proxy 6446 RW / 6447 RO).

> Tham chiếu runbook gốc: [../../runbooks/02-mysql-innodb-cluster.md](../../runbooks/002-mysql-innodb-cluster.md)
> Topology: xem [../../scripts/common/env.sh](../../scripts/common/env.sh)

## Topology demo

| Host  | IP             | Vai trò                       | RAM    | server_id |
|-------|----------------|-------------------------------|--------|-----------|
| node1 | 192.168.10.11  | GR member — Primary ban đầu   | 2 GB   | 1         |
| node2 | 192.168.10.12  | GR member — Secondary         | 2 GB   | 2         |
| node3 | 192.168.10.13  | GR member — Secondary         | 2 GB   | 3         |
| mgmt  | 192.168.10.20  | MySQL Router (RW 6446/RO 6447) + client | 1.5 GB | — |

```
                      ┌─────────────────────────┐
              App ──▶ │ mgmt 192.168.10.20      │
                      │  MySQL Router :6446 RW──┼──▶ Primary
                      │  MySQL Router :6447 RO──┼──▶ Secondaries (round-robin)
                      └────────────┬────────────┘
                                   │
              ┌────────────────────┼────────────────────┐
              ▼                    ▼                    ▼
        ┌──────────┐         ┌──────────┐         ┌──────────┐
        │  node1   │ ◀──33061──▶ node2   │ ◀──33061──▶ node3  │
        │   3306   │         │   3306   │         │   3306   │
        └──────────┘         └──────────┘         └──────────┘
            └──── Group Replication (Paxos-like consensus) ────┘
```

## Yêu cầu host

- Windows 10/11 + PowerShell 5+ **hoặc** macOS / Linux + bash
- [Vagrant ≥ 2.3](https://www.vagrantup.com/downloads)
- [VirtualBox ≥ 7.0](https://www.virtualbox.org/wiki/Downloads)
- RAM host ≥ 8 GB (4 VMs), disk trống ≥ 25 GB
- MySQL ≥ 8.0.17 (lab dùng 8.0 community — Clone Plugin có sẵn)

## Cấu trúc demo

| Bước | Markdown                                          | Shell script                                  | Chạy ở đâu       |
|------|---------------------------------------------------|-----------------------------------------------|------------------|
| 0    | [00-overview.md](000-overview.md)                  | —                                             | (đọc)            |
| 1    | [01-vagrant-up.md](001-vagrant-up.md)              | [01-vagrant-up.sh](01-vagrant-up.sh)          | Host             |
| 2    | [02-prepare-os.md](002-prepare-os.md)              | [02-prepare-os.sh](02-prepare-os.sh)          | Host → 4 VMs     |
| 3    | [03-install-mysql.md](003-install-mysql.md)        | [03-install-mysql.sh](03-install-mysql.sh)    | Host → 3 DB VMs  |
| 4    | [04-node-setup.md](004-node-setup.md)              | [04-node-setup.sh](04-node-setup.sh)          | Host → 3 DB VMs  |
| 5    | [05-cluster-bootstrap.md](005-cluster-bootstrap.md)| [05-cluster-bootstrap.sh](05-cluster-bootstrap.sh) | Host → node1 |
| 6    | [06-router-setup.md](006-router-setup.md)          | [06-router-setup.sh](06-router-setup.sh)      | Host → mgmt      |
| 7    | [07-verify.md](007-verify.md)                      | [07-verify.sh](07-verify.sh)                  | Host             |
| 8    | [08-smoke-test.md](008-smoke-test.md)              | [08-smoke-test.sh](08-smoke-test.sh)          | Host             |
| 9    | [09-failover-test.md](009-failover-test.md)        | [09-failover-test.sh](09-failover-test.sh)    | Host             |
| 10   | [10-rollback.md](010-rollback.md)                  | [10-rollback.sh](10-rollback.sh)              | Host             |

## Chạy nhanh — end-to-end

### Trên Linux / macOS / WSL / Git Bash:
```bash
cd demo/02-innodb-cluster
bash run-all.sh
```

### Trên PowerShell (Windows + VirtualBox):
```powershell
cd demo\02-innodb-cluster
.\run-all.ps1
```

> ⚠ **Yêu cầu Git Bash** trên Windows. Script tự tìm Git Bash tại `C:\Program Files\Git\bin\bash.exe`. KHÔNG dùng WSL `bash.exe` vì xung đột Hyper-V/VirtualBox.

`run-all` thực hiện tuần tự **B1 → B8** và ghi log vào `results/`. **B9 (failover)** và **B10 (rollback)** phải chạy thủ công vì có tính phá huỷ.

### Chạy thủ công không cần bash (Windows native, PowerShell)

Nếu không có Git Bash, có thể boot lab và provision thủ công. Mỗi block tương ứng 1 bước trong bảng "Cấu trúc demo" ở trên.

> 📖 **Hướng dẫn copy/paste chi tiết — từng câu lệnh CLI + SQL + JS + nội dung file config**: [MANUAL-SETUP.md](manual-setup.md). Tài liệu đó liệt kê tất cả lệnh cần chạy, các pitfall (`#` trong URI, `report_host=hostname`, AppArmor profile, SysV vs systemd unit), và lý do của từng option.

```powershell
$env:VAGRANT_DEFAULT_PROVIDER = 'virtualbox'
cd ..\..\vagrant

# B1 — sinh SSH key (1 lần) + boot 4 VMs
bash provision\generate-ssh-key.sh    # cần bash 1 lần; hoặc thay bằng ssh-keygen.exe của Git
vagrant up

# B2 — common prepare-os cho cả 4 nodes (hostname, NTP, swap, sysctl, AppArmor)
vagrant provision node1 --provision-with common-prep
vagrant provision node2 --provision-with common-prep
vagrant provision node3 --provision-with common-prep
vagrant provision mgmt  --provision-with common-prep

# B3 — cài MySQL 8.0 + Shell + Router trên 3 DB nodes (firewall ports cũng mở luôn)
vagrant provision node1 --provision-with install-mysql
vagrant provision node2 --provision-with install-mysql
vagrant provision node3 --provision-with install-mysql

# B4 — configureInstance() trên cả 3 nodes (tự fix my.cnf + restart MySQL nếu cần)
vagrant ssh node1 -c "sudo bash /vagrant/scripts/innodb-cluster/node-setup.sh"
vagrant ssh node2 -c "sudo bash /vagrant/scripts/innodb-cluster/node-setup.sh"
vagrant ssh node3 -c "sudo bash /vagrant/scripts/innodb-cluster/node-setup.sh"

# B5 — tạo cluster trên node1 + add node2, node3 qua Clone Plugin
vagrant ssh node1 -c "sudo bash /vagrant/scripts/innodb-cluster/cluster-bootstrap.sh"

# B6 — cài MySQL Shell + Router trên mgmt (tools-only profile, KHÔNG cài server),
#       sau đó bootstrap Router từ cluster, mở firewall, expose :6446 RW + :6447 RO
vagrant ssh mgmt -c "sudo INSTALL_PROFILE=tools-only bash /vagrant/scripts/common/01-install-mysql.sh"
vagrant ssh mgmt -c "sudo bash /vagrant/scripts/innodb-cluster/router-setup.sh"

# B7 — verify cluster.status() (1 PRIMARY + 2 SECONDARY, all ONLINE)
vagrant ssh node1 -c "sudo bash /vagrant/scripts/innodb-cluster/cluster-ops.sh status"

# Smoke test routing từ node1 (mgmt không có mysql client trong tools-only profile):
vagrant ssh node1 -c "mysql -uclusteradmin -p'ChangeMe!Admin#2026' -h192.168.10.20 -P6446 -N -e 'SELECT @@report_host'"
vagrant ssh node1 -c "mysql -uclusteradmin -p'ChangeMe!Admin#2026' -h192.168.10.20 -P6447 -N -e 'SELECT @@report_host'"
```

> ⚠ Trong PowerShell, password chứa `#` — luôn quote bằng **single quote** (`'ChangeMe!Admin#2026'`); double quote sẽ làm PS interpret `#` là comment.
> Mật khẩu mặc định: `MYSQL_ROOT_PWD=ChangeMe!Root#2026`, `ADMIN_PWD=ChangeMe!Admin#2026` (xem [scripts/common/env.sh](../../scripts/common/env.sh)).

## Sự khác biệt so với demo 01

| Khía cạnh | Demo 01 (Async/Semi-sync) | Demo 02 (InnoDB Cluster) |
|-----------|---------------------------|--------------------------|
| Replication | 1 master → 2 replicas (1-way) | Multi-writer-capable, single-primary mặc định |
| Control plane | SQL thủ công | `mysqlsh dba.*` JavaScript API |
| Endpoint cho app | Đổi IP khi failover | Router :6446 không đổi — failover trong suốt |
| Failover | Thủ công (`08-failover-test.sh`) | **Tự động** — GR election (~5-10s) |
| Data sync khi rejoin | Phải dump/restore tay | **Clone Plugin** tự copy |
| Yêu cầu mạng | LAN tốt | LAN ≤ 5ms latency (consensus protocol) |
| Số node tối thiểu | 2 (1 master + 1 replica) | 3 (cần quorum) |

## Output & báo cáo

Tất cả output verify/smoke/failover được ghi vào [results/](results/):

- `results/07-verify.log` — cluster.status() JSON + checkpoint
- `results/08-smoke-test.log` — write qua :6446, read qua :6447
- `results/09-failover.log` — halt primary → election → router reroute
- `results/report.md` — template báo cáo demo, tự điền sau khi chạy

## Tham khảo
- Runbook gốc: [runbooks/02-mysql-innodb-cluster.md](../../runbooks/002-mysql-innodb-cluster.md)
- Vagrant lab: [runbooks/08-vagrant-lab.md](../../runbooks/008-vagrant-lab.md)
- MySQL InnoDB Cluster: https://dev.mysql.com/doc/mysql-shell/8.0/en/mysql-innodb-cluster.html
- Group Replication: https://dev.mysql.com/doc/refman/8.0/en/group-replication.html
- MySQL Router: https://dev.mysql.com/doc/mysql-router/8.0/en/


---

!!! info "Nguồn gốc"
    `HA/Mysql/demo/02-innodb-cluster/README.md`
