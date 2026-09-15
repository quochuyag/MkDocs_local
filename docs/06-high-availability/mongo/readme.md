---
title: MongoDB High Availability — Toolkit & Runbooks
course: 06-high-availability
source: HA/mongo/README.md
---

# MongoDB High Availability — Toolkit & Runbooks

Bộ scripts + runbooks triển khai các giải pháp HA cho MongoDB trong môi trường Linux. Đi kèm Vagrant lab 4 VMs Ubuntu 22.04 để thử nghiệm cục bộ.

> 📖 **Đọc bản HTML chi tiết** (architecture diagrams, runbook step-by-step, có mục lục): [docs/mongo-ha-guide.html](docs/mongo-ha-guide.html) — mở trực tiếp bằng trình duyệt.

## Giải pháp được bao phủ

| # | Giải pháp | Loại | Thư mục scripts | Runbook |
|---|---|---|---|---|
| 1 | Replica Set (PSS) | Native replication, default | [scripts/replica-set/](scripts/replica-set/) | [runbooks/01-replica-set.md](runbooks/001-replica-set.md) |
| 2 | PSA (Primary + Secondary + Arbiter) | 2 data + 1 vote-only | [scripts/psa/](scripts/psa/) | [runbooks/02-psa-topology.md](runbooks/002-psa-topology.md) |
| 3 | Sharded Cluster | Horizontal scale + RS-per-shard | [scripts/sharded-cluster/](scripts/sharded-cluster/) | [runbooks/03-sharded-cluster.md](runbooks/003-sharded-cluster.md) |
| 4 | Hidden + Delayed member | Anti-mistake / dedicated backup host | [scripts/hidden-delayed/](scripts/hidden-delayed/) | [runbooks/04-hidden-delayed.md](runbooks/004-hidden-delayed.md) |
| 5 | Backup + PITR | mongodump + LVM snapshot + oplog tail | [scripts/backup-pitr/](scripts/backup-pitr/) | [runbooks/05-backup-and-pitr.md](runbooks/005-backup-and-pitr.md) |
| 6 | Multi-region / Zone sharding | Geo DR | [scripts/multi-region/](scripts/multi-region/) · [demo/multi-region/](demo/multi-region/) | [runbooks/06-multi-region.md](runbooks/006-multi-region.md) |
| 7 | Atlas (managed) | Cloud managed reference | — | [runbooks/07-atlas-managed.md](runbooks/007-atlas-managed.md) |
| 8 | **Vagrant lab** | 4 VMs để thử nghiệm | [vagrant/](vagrant/) | [runbooks/08-vagrant-lab.md](runbooks/008-vagrant-lab.md) |

Bắt đầu chọn giải pháp: [runbooks/00-overview.md](runbooks/000-overview.md).

## Lab cục bộ trong 1 lệnh

```bash
cd vagrant
make full-bootstrap     # 4 VMs Ubuntu 22.04 (node1/2/3 + mgmt) với MongoDB 7.0 đã cài
```

Chi tiết: [runbooks/08-vagrant-lab.md](runbooks/008-vagrant-lab.md).

## Topology mẫu (tham chiếu cho tất cả runbooks)

```text
node1   192.168.20.11   (primary thường, priority=2 trong RS)
node2   192.168.20.12   (secondary)
node3   192.168.20.13   (secondary / hoặc arbiter trong PSA)
mgmt    192.168.20.20   (mongos / DR secondary / backup tooling)
```

- OS: Ubuntu 22.04 LTS (script kèm nhánh `dnf` cho RHEL/Rocky 8/9)
- MongoDB: 7.0 Community (override `MONGO_MAJOR=8.0` trong env.sh nếu muốn)
- User OS chạy script: `root` (hoặc `sudo`)

## Mapping port theo giải pháp

| Port | Vai trò | Dùng trong |
|---|---|---|
| 27017 | mongod (RS member) / mongos | Runbook 01, 02, 03 (mongos), 06 |
| 27018 | mongod shard member | Runbook 03 |
| 27019 | mongod config server member | Runbook 03 |
| 27020 | mongod arbiter | Runbook 02 |

## Cách dùng nhanh (Replica Set PSS — default)

```bash
# 1. Chuẩn bị OS chung trên TẤT CẢ nodes
bash scripts/common/00-prepare-os.sh
bash scripts/common/01-install-mongo.sh
bash scripts/common/02-firewall.sh

# 2. KeyFile: sinh trên 1 node, scp sang các node khác
bash scripts/common/03-keyfile.sh
# scp /etc/mongodb/keyfile root@node2:/etc/mongodb/keyfile
# scp /etc/mongodb/keyfile root@node3:/etc/mongodb/keyfile

# 3. Bật replication trên CẢ 3 nodes
bash scripts/replica-set/node-config.sh

# 4. Initiate RS + tạo users (chỉ trên node1)
bash scripts/replica-set/initiate.sh

# 5. Verify
bash scripts/replica-set/ops.sh status
```

## Quy ước biến môi trường

Tất cả script đọc biến từ [scripts/common/env.sh](scripts/common/env.sh). Sửa file này trước khi chạy:

```bash
export NODE1_IP=192.168.20.11
export NODE2_IP=192.168.20.12
export NODE3_IP=192.168.20.13
export MGMT_IP=192.168.20.20
export RS_NAME=rs0
export MONGO_ADMIN_PWD='ChangeMe!Admin#2026'
export CLUSTER_ADMIN_PWD='ChangeMe!Cluster#2026'
export BACKUP_PWD='ChangeMe!Backup#2026'
export APP_PWD='ChangeMe!App#2026'
export MONGO_MAJOR=7.0    # hoặc 8.0
```

## Cảnh báo

- Script ghi đè `/etc/mongod.conf`. **Backup trước** nếu đang chạy production.
- Mật khẩu mẫu chỉ để demo — **đổi trước khi deploy thật**.
- KeyFile phải giống nhau trên TẤT CẢ members của cùng 1 RS/cluster — sai → secondary refuse join.
- Một host trong lab có thể chạy nhiều mongod (RS member, shard member, config server) trên port khác nhau cho Runbook 03; production tách host riêng.


---

!!! info "Nguồn gốc"
    `HA/mongo/README.md`
