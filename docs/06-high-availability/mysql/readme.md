---
title: MySQL High Availability — Toolkit & Runbooks
course: 06-high-availability
source: HA/Mysql/README.md
---

# MySQL High Availability — Toolkit & Runbooks

Bộ scripts + runbooks triển khai 7 giải pháp HA cho MySQL trong môi trường Linux.

## Giải pháp được bao phủ

| # | Giải pháp | Loại | Thư mục scripts | Runbook |
|---|---|---|---|---|
| 1 | Async / Semi-Sync Replication | Native, đơn giản | `scripts/async-semisync/` | `runbooks/01-async-semisync-replication.md` |
| 2 | MySQL InnoDB Cluster | GR + Router + Shell | `scripts/innodb-cluster/` | `runbooks/02-mysql-innodb-cluster.md` |
| 3 | Group Replication (thuần) | Paxos-like | `scripts/group-replication/` | `runbooks/03-group-replication.md` |
| 4 | MHA (Master HA) | Async + Manager perl | `scripts/mha/` | `runbooks/04-mha.md` |
| 5 | Orchestrator (GitHub) | Topology manager | `scripts/orchestrator/` | `runbooks/05-orchestrator.md` |
| 6 | Galera Cluster | Sync multi-master | `scripts/galera/` | `runbooks/06-galera-cluster.md` |
| 7 | ProxySQL | Connection router | `scripts/proxysql/` | `runbooks/07-proxysql.md` |
| 8 | **Vagrant lab** | 4 VMs Ubuntu để thử nghiệm | `vagrant/` | `runbooks/08-vagrant-lab.md` |

## Lab cục bộ trong 1 lệnh

```bash
cd vagrant
make full-bootstrap     # 4 VMs Ubuntu 22.04 (node1/2/3 + mgmt) với MySQL đã cài
```

Xem chi tiết: [runbooks/08-vagrant-lab.md](runbooks/008-vagrant-lab.md).

## Topology mẫu (tham chiếu cho tất cả runbooks)

```text
node1   192.168.10.11   (master / primary / writer)
node2   192.168.10.12   (replica / secondary)
node3   192.168.10.13   (replica / secondary)
mgmt    192.168.10.20   (MHA manager / Orchestrator / ProxySQL)
VIP     192.168.10.100  (failover VIP — optional)
```

- OS: Ubuntu 22.04 LTS (script cũng kèm ghi chú cho RHEL/Rocky 8/9)
- MySQL: 8.0 community (Galera dùng Percona XtraDB Cluster 8.0 hoặc MariaDB 10.11)
- User OS để chạy script: `root` (hoặc `sudo`)

## Cách dùng nhanh

```bash
# 1. Chuẩn bị OS chung trên TẤT CẢ nodes
bash scripts/common/00-prepare-os.sh
bash scripts/common/01-install-mysql.sh
bash scripts/common/02-firewall.sh

# 2. Chọn 1 giải pháp HA. Ví dụ InnoDB Cluster
#    Trên mỗi node:
bash scripts/innodb-cluster/node-setup.sh
#    Trên node1 (seed):
bash scripts/innodb-cluster/cluster-bootstrap.sh
#    Trên Router host:
bash scripts/innodb-cluster/router-setup.sh
```

Mỗi runbook trong `runbooks/` có thứ tự đầy đủ + lệnh verify + rollback.

## Quy ước biến môi trường

Tất cả script đọc biến từ `scripts/common/env.sh`. Sửa file này trước khi chạy:

```bash
export NODE1_IP=192.168.10.11
export NODE2_IP=192.168.10.12
export NODE3_IP=192.168.10.13
export MGMT_IP=192.168.10.20
export VIP=192.168.10.100
export MYSQL_ROOT_PWD='ChangeMe!Root#2026'
export REPL_USER='repl'
export REPL_PWD='ChangeMe!Repl#2026'
export ADMIN_USER='clusteradmin'
export ADMIN_PWD='ChangeMe!Admin#2026'
```

## Quy tắc workflow demo (fresh lab per demo)

Mỗi demo (`demo/01..08`) tự destroy 4 VM cũ và rebuild fresh trước khi chạy:

- **Data-plane demos** (01 async, 02 InnoDB Cluster, 03 GR, 06 Galera, 08 lab) — bước `01-vagrant-up.sh` chạy `vagrant destroy -f` rồi `vagrant up`. Lý do: mỗi giải pháp HA cần OS prep / MySQL package khác nhau, không thể share state.
- **Control-plane demos** (04 MHA, 05 Orchestrator, 07 ProxySQL) — `run-all.sh` mặc định bootstrap data-plane tương ứng trước (cũng destroy + rebuild). Demo 04/05 phụ thuộc demo 01; demo 07 phụ thuộc demo 01 hoặc 06 tuỳ `BACKEND`.

**Escape hatches** (khi cần dev/debug nhanh, không destroy):

```bash
# Re-run cùng demo không destroy VMs hiện có:
KEEP_VMS=1 bash demo/01-async-semisync/run-all.sh

# Re-run control-plane không bootstrap lại data-plane (giữ cluster MySQL sống):
BOOTSTRAP_DEMO01=0 bash demo/04-mha/run-all.sh
BOOTSTRAP_DEMO01=0 bash demo/05-orchestrator/run-all.sh
BOOTSTRAP_BACKEND=0 bash demo/07-proxysql/run-all.sh
```

**Hệ quả về thời gian**: full demo từ scratch ~15-40 phút mỗi demo (download box cached, OS prep ~2', MySQL install ~5', demo logic ~5-20'). Demo 04/05/07 cộng thêm thời gian bootstrap demo nền.

## Cảnh báo

- Script ghi đè `/etc/mysql/my.cnf` (hoặc `/etc/my.cnf` trên RHEL). **Backup trước** nếu đang chạy production.
- Mật khẩu mẫu chỉ để demo — **đổi trước khi deploy thật**.
- Một host chỉ chọn **một** giải pháp HA tại một thời điểm; không trộn InnoDB Cluster với Galera.
- `vagrant destroy -f` ở đầu mỗi demo sẽ **xoá vĩnh viễn** disk của 4 VM `mysql-ha-{node1,node2,node3,mgmt}`. Backup data quan trọng trước khi chuyển sang demo khác.


---

!!! info "Nguồn gốc"
    `HA/Mysql/README.md`
