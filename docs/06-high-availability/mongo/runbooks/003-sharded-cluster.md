---
title: Runbook 03 — Sharded Cluster
course: 06-high-availability
source: HA/mongo/runbooks/03-sharded-cluster.md
---

# Runbook 03 — Sharded Cluster

## 1. Khi nào dùng

- Dataset > ~1 TB hoặc working set vượt RAM 1 node.
- Write throughput vượt khả năng 1 primary (~50k+ writes/sec).
- Cần horizontal scale theo tenant/region (kết hợp [zone sharding][06]).

[06]: 06-multi-region.md

❌ KHÔNG cần shard nếu:
- Dataset < 500 GB và write < 10k/sec → Replica Set đủ.
- Read-heavy → tăng RAM + secondary là đủ.

## 2. Kiến trúc

```
                    ┌────────────────────────────┐
       App ───────▶ │  mongos (router) :27017    │ ◀── nhiều mongos để HA
                    │  stateless, không có data  │
                    └──────────┬─────────────────┘
                               │
        ┌──────────────────────┼──────────────────────┐
        ▼                      ▼                      ▼
   Config Server RS      Shard 1 RS              Shard 2 RS
   (cfgrs)               (shard1rs)              (shard2rs)
   node1:27019           node1:27018             node4:27018
   node2:27019           node2:27018             node5:27018
   node3:27019           node3:27018             node6:27018
```

- **Config servers**: lưu metadata (chunk → shard mapping). Phải là replica set 3 nodes.
- **Shard RS**: replica set 3 nodes mỗi shard (HA cho từng shard).
- **mongos**: stateless router. Deploy ≥2 cho HA. App connect vào mongos, không bao giờ connect trực tiếp shard.

### Lab port mapping (4 VMs)

Để chạy trên 4 VMs Vagrant, **chỉ 1 shard**, dùng port khác nhau:
- node1/2/3 :27019 → config server RS (`cfgrs`)
- node1/2/3 :27018 → shard 1 RS (`shard1rs`)
- mgmt   :27017 → mongos

Thêm shard 2 trong lab: thay đổi `SHARD_PORT=27028 SHARD_RS_NAME=shard2rs` rồi lặp lại trên 3 nodes (port khác).

## 3. Tiền đề

- 3 nodes đã chạy `common/00..02`.
- KeyFile chung trên tất cả nodes + mgmt.
- mongos host (mgmt) cài `mongodb-org-mongos` + `mongodb-mongosh`.

## 4. Các bước

### B1. Config Server Replica Set
```bash
# Trên node1, node2, node3 (KHÔNG --init):
bash /vagrant/scripts/sharded-cluster/config-server-setup.sh

# Trên node1 (init RS + tạo admin user):
bash /vagrant/scripts/sharded-cluster/config-server-setup.sh --init
```

### B2. Shard Replica Set
```bash
# Trên node1, node2, node3:
bash /vagrant/scripts/sharded-cluster/shard-setup.sh

# Trên node1:
bash /vagrant/scripts/sharded-cluster/shard-setup.sh --init
```

### B3. mongos (trên mgmt)
```bash
bash /vagrant/scripts/sharded-cluster/mongos-setup.sh
```
mongos đọc topology từ `cfgrs/node1:27019,node2:27019,node3:27019` (đã ghi trong `/etc/mongos.conf`).

### B4. Add shard + tạo users + enable sharding
```bash
# Trên mgmt (chạy qua mongos):
bash /vagrant/scripts/sharded-cluster/add-shard.sh
```
Script:
- `sh.addShard('shard1rs/node1:27018,...')`
- Tạo `clusteradmin`, `backupuser`, `appuser`
- `sh.enableSharding('appdb')`
- `sh.shardCollection('appdb.events', {userId:'hashed'})` (collection mẫu)

### B5. Verify
```bash
mongosh "mongodb://admin:<pwd>@mgmt:27017/admin" --eval 'sh.status({verbose:false})'
```
Kỳ vọng:
- Sharding version có.
- `shards`: shard1rs.
- `databases`: `appdb` với `partitioned: true`.
- `events` shard key `{userId:hashed}`, chunks chia đều.

App connect string:
```
mongodb://appuser:<pwd>@mgmt:27017/appdb
# CHÚ Ý: không có replicaSet param — driver tự nhận diện là mongos cluster.
# Nếu có nhiều mongos: mongos1,mongos2,mongos3:27017
```

## 5. Vận hành (balancer-ops.sh)

| Tác vụ | Lệnh |
|---|---|
| sh.status() | `bash scripts/sharded-cluster/balancer-ops.sh status` |
| Balancer state | `bash scripts/sharded-cluster/balancer-ops.sh balancer` |
| Stop balancer | `bash scripts/sharded-cluster/balancer-ops.sh stop` |
| Đặt window | `bash scripts/sharded-cluster/balancer-ops.sh window 02:00 06:00` |
| Phân bố chunks | `bash scripts/sharded-cluster/balancer-ops.sh chunks appdb.events` |

### 5.1 Thêm shard
```bash
# Trên 3 nodes mới (node4/5/6) hoặc dùng port khác trên 3 nodes hiện tại:
SHARD_PORT=27028 SHARD_RS_NAME=shard2rs bash scripts/sharded-cluster/shard-setup.sh
SHARD_PORT=27028 SHARD_RS_NAME=shard2rs bash scripts/sharded-cluster/shard-setup.sh --init
SHARD_PORT=27028 SHARD_RS_NAME=shard2rs bash scripts/sharded-cluster/add-shard.sh
# Balancer tự động chia chunks sang shard mới (~30 phút - vài giờ tuỳ data).
```

### 5.2 Loại shard ra (drain)
```bash
mongosh "mongodb://admin:<pwd>@mgmt:27017/admin" --eval "
db.adminCommand({ removeShard: 'shard2rs' });
"
# Lặp lại lệnh trên cho đến khi state == 'completed'.
```

### 5.3 Failover trong shard
Mỗi shard là 1 RS — election tự động như Runbook 01. mongos phát hiện qua heartbeat tới shard và route lại trong ~10s.

### 5.4 Config server quorum loss
Mất quorum config server → cluster **READ-ONLY** (không thay đổi được metadata). Restore:
- Khôi phục node config từ backup hoặc resync từ remaining members.
- Hoặc force-reconfig nếu 1 member sống.

## 6. Backup sharded cluster

Backup phức tạp hơn replica set: cần **đồng thời stop balancer + snapshot mọi shard + config server**.
```bash
# 1. Stop balancer
bash scripts/sharded-cluster/balancer-ops.sh stop

# 2. Snapshot từng shard + config server (xem Runbook 05)
# Mỗi shard: bash scripts/backup-pitr/mongodump.sh node1:27018
# Config:    bash scripts/backup-pitr/mongodump.sh node1:27019

# 3. Restart balancer
bash scripts/sharded-cluster/balancer-ops.sh start
```
Production: dùng Percona Backup for MongoDB (PBM) — coordinator backup nhất quán cho sharded cluster, hoặc Ops Manager.

## 7. Rollback

```bash
# Trên mọi node:
systemctl stop mongod-cfg mongod-shard1rs mongos || true
systemctl disable mongod-cfg mongod-shard1rs mongos
rm -rf /var/lib/mongodb-cfg /var/lib/mongodb-shard1rs
rm /etc/mongod-cfg.conf /etc/mongod-shard1rs.conf /etc/mongos.conf
```

## 8. Lưu ý quan trọng

- **Shard key chọn sai = pain cho life of cluster** (chunks không split, hot shard). Test trên staging với dữ liệu thật trước.
- Hashed key chia đều nhưng làm range query inefficient. Compound key {tenant:1, ts:1} cho time-series.
- Mọi collection sharded **phải có index trên shard key prefix**.
- Mỗi mongos lưu local cache routing — sau big topology change, restart mongos để clear stale cache.
- WiredTiger cache trên shard mongod: tuning giống replica set.

## 9. Tham khảo

- https://www.mongodb.com/docs/manual/sharding/
- https://www.mongodb.com/docs/manual/core/sharding-shard-key/
- https://docs.percona.com/percona-backup-mongodb/


---

!!! info "Nguồn gốc"
    `HA/mongo/runbooks/03-sharded-cluster.md`
