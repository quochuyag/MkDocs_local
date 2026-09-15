---
title: Runbook 02 — PSA Topology (Primary + Secondary + Arbiter)
course: 06-high-availability
source: HA/mongo/runbooks/02-psa-topology.md
---

# Runbook 02 — PSA Topology (Primary + Secondary + Arbiter)

## 1. Khi nào dùng (và khi nào KHÔNG)

PSA = 2 data nodes (P, S) + 1 arbiter (chỉ vote, không lưu data). Tiết kiệm 1 host disk.

✅ **Dùng được**:
- Chỉ có 2 host data + 1 host rẻ (mgmt/jump box).
- Workload có thể chấp nhận **write concern w:1** hoặc thỉnh thoảng block ngắn với `w:"majority"`.

❌ **KHÔNG nên dùng**:
- App yêu cầu `w:"majority", j:true` 100% thời gian → khi 1 data node down, write majority **block** vì còn 1 data + 1 arbiter (arbiter không thoả `j:true` vì không persist).
- Cluster có data > vài trăm GB — arbiter không thể trở thành donor recovery cho secondary mới.
- Production critical — MongoDB khuyến nghị PSS, không PSA.

> **Cảnh báo MongoDB 5.0+**: với PSA và `w:"majority"`, nếu secondary mất, primary tiếp tục accept writes nhưng **không thể commit majority** → cache bloat. Đặt `disableSplitHorizonIPCheck` hoặc dùng `readConcern:"available"` không giải được vấn đề này.

## 2. Kiến trúc

```
   node1:27017 (PRIMARY)    node2:27017 (SECONDARY)
        ▲                          ▲
        └── oplog ──────────┬──────┘
                            │
                  node3:27020 (ARBITER — vote only)
```

## 3. Tiền đề

- 2 nodes cài MongoDB (`common/00-prepare-os.sh`, `01-install-mongo.sh`).
- 1 node arbiter (có thể là mgmt) — cài MongoDB nhưng KHÔNG cần disk lớn.
- KeyFile chung trên cả 3.

## 4. Các bước

### B1. Config 2 data nodes
```bash
# Trên node1 và node2:
NODE_ROLE=data bash /vagrant/scripts/psa/node-config.sh data
```
Script ghi `/etc/mongod-data.conf` + systemd unit `mongod-data.service` (port 27017, replSet=`rspsa`).

### B2. Config arbiter
```bash
# Trên node3 (hoặc mgmt):
NODE_ROLE=arbiter bash /vagrant/scripts/psa/node-config.sh arbiter
```
Cài đặt cùng mongod nhưng port 27020, dataDir riêng, sẽ chỉ giữ metadata vote.

### B3. Initiate PSA replica set (trên node1)
```bash
bash /vagrant/scripts/psa/initiate-psa.sh
```
Script:
- `rs.initiate({...})` với 2 members data + 1 arbiterOnly:true.
- Tạo `admin` (root), `clusteradmin`.

### B4. Verify
```bash
mongosh --host node1 -u admin -p --eval 'rs.status().members.forEach(m => print(m.name + " " + m.stateStr))'
# Kỳ vọng: PRIMARY, SECONDARY, ARBITER
```

## 5. Vận hành

| Tác vụ | Lệnh / Lưu ý |
|---|---|
| Trạng thái | `mongosh --eval 'rs.status()'` |
| Stepdown | `rs.stepDown(60)` — node2 trở thành primary trong 60s |
| Chuyển sang PSS | Add node thứ 4 data, `rs.remove(arbiter)`. Reconfig. |

### 5.1 Khi 1 data node down
- `rs.status()` thấy data node `state="(not reachable)"`.
- Arbiter + 1 data còn lại = 2/3 majority → primary mới được bầu (hoặc giữ nguyên).
- **Writes với `w:"majority"` BLOCK** vì cần 2 data ack. Workaround tạm: chuyển sang `w:1`.

### 5.2 Khi arbiter down
- 2 data + 0 arbiter = 2/2 majority → cluster vẫn writable bình thường.
- Restart arbiter là xong, không cần resync (no data).

### 5.3 Cảnh báo về primary catchup
PSA có thể rơi vào case: secondary lag rồi mất → primary tiếp tục accept writes, nhưng oplog không thể commit majority → cluster tích luỹ "unindexed history" → restart primary có thể rollback writes. Theo dõi alert:
```
mongodb_mongod_replset_member_replication_lag{state="SECONDARY"} > 60
mongodb_mongod_replset_member_health{state="SECONDARY"} == 0
```

## 6. Rollback

```bash
# Trên mỗi node:
systemctl stop mongod-data || systemctl stop mongod-arbiter
systemctl disable mongod-data mongod-arbiter
rm -rf /var/lib/mongodb-arbiter /var/lib/mongodb
rm /etc/mongod-data.conf /etc/mongod-arbiter.conf
rm /etc/systemd/system/mongod-data.service /etc/systemd/system/mongod-arbiter.service
systemctl daemon-reload
```

## 7. Tham khảo

- https://www.mongodb.com/docs/manual/core/replica-set-arbiter/
- https://www.mongodb.com/docs/manual/reference/write-concern/#mongodb-writeconcern-writeconcern.-majority-


---

!!! info "Nguồn gốc"
    `HA/mongo/runbooks/02-psa-topology.md`
