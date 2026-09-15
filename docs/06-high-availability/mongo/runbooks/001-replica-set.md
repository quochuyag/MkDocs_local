---
title: Runbook 01 — Replica Set (PSS — Primary + Secondary + Secondary)
course: 06-high-availability
source: HA/mongo/runbooks/01-replica-set.md
---

# Runbook 01 — Replica Set (PSS — Primary + Secondary + Secondary)

Replica set 3 nodes là **giải pháp HA mặc định** cho MongoDB. Mọi runbook sau (PITR, hidden, multi-region) build trên top này.

## 1. Khi nào dùng

- OLTP dataset < ~1 TB.
- 1 data center hoặc 2 DCs LAN (latency < 5ms).
- App có thể connect string list 3 hosts (MongoDB driver tự discover topology).

## 2. Kiến trúc & ports

```
              ┌─────────────────────────────┐
       App ──▶│  Driver (replicaSet=rs0)    │
              │  read pref / write concern  │
              └──────────┬──────────────────┘
                         │
        ┌────────────────┼────────────────┐
        ▼                ▼                ▼
   node1:27017     node2:27017     node3:27017
   PRIMARY  ◀── oplog tailing ──▶ SECONDARY (RO)
```

- Port: 27017 (mongod).
- Election: ~10s khi primary mất; majority = 2/3 → tolerate 1 fault.

## 3. Tiền đề

- 3 nodes đã chạy `common/00-prepare-os.sh`, `01-install-mongo.sh`, `02-firewall.sh`.
- Hostname/IP resolve được giữa 3 nodes (`getent hosts node2`).
- Cùng 1 keyFile trên cả 3 nodes (chạy `common/03-keyfile.sh` trên 1 node + scp sang 2 nodes còn lại; hoặc trong lab Vagrant: `make keyfile` đã làm).

## 4. Các bước

### B1. Config mongod cho replication (trên CẢ 3 nodes)
```bash
bash /vagrant/scripts/replica-set/node-config.sh
```
Script ghi `/etc/mongod.conf` với `replication.replSetName: rs0`, `security.keyFile`, `security.authorization: enabled`, restart mongod.

### B2. Initiate replica set (CHỈ trên node1)
```bash
bash /vagrant/scripts/replica-set/initiate.sh
```
Script gọi `rs.initiate({...})` với 3 members (node1 priority=2, node2/node3 priority=1), đợi primary, sau đó tạo:
- `admin` (root role)
- `clusteradmin` (clusterAdmin + clusterManager + clusterMonitor)
- `backupuser` (backup + restore)
- `appuser` trên DB `appdb` (readWrite)

### B3. Verify
```bash
bash /vagrant/scripts/replica-set/ops.sh status
# Kỳ vọng: 1 PRIMARY, 2 SECONDARY, health=1 với mọi node.

bash /vagrant/scripts/replica-set/ops.sh lag    # secondary replication lag
bash /vagrant/scripts/replica-set/ops.sh oplog  # oplog window (cần ≥ 24h)
```

App connection string:
```
mongodb://appuser:<pwd>@node1:27017,node2:27017,node3:27017/appdb?replicaSet=rs0&readPreference=primaryPreferred&w=majority
```

## 5. Vận hành (ops.sh)

| Tác vụ | Lệnh |
|---|---|
| Trạng thái | `bash scripts/replica-set/ops.sh status` |
| Stepdown primary | `bash scripts/replica-set/ops.sh stepdown 60` |
| Freeze 1 node | `bash scripts/replica-set/ops.sh freeze 300` |
| Thêm member | `bash scripts/replica-set/ops.sh add node4:27017 1` |
| Xoá member | `bash scripts/replica-set/ops.sh remove node3:27017` |
| Lag | `bash scripts/replica-set/ops.sh lag` |
| Oplog window | `bash scripts/replica-set/ops.sh oplog` |

### 5.1 Tự động failover
Khi primary mất:
1. Heartbeat fail trong ~10s → SECONDARY trigger election.
2. SECONDARY nào có optime mới nhất → ứng cử.
3. Đa số voters (≥2 trong 3) chấp nhận → PRIMARY mới.
4. Driver phía app phát hiện qua topology stream → reconnect (driver hỗ trợ sẵn, không cần config app).

### 5.2 Failover manual (planned)
```bash
bash scripts/replica-set/ops.sh stepdown 60     # primary trở thành secondary trong 60s
bash scripts/replica-set/ops.sh status          # verify primary mới
```

### 5.3 Khi mất quorum (chỉ còn 1 node sống)
Cluster tự block writes. Khắc phục bằng `force-reconfig`:
```bash
# Trên node còn sống, tạo file my-cfg.json:
mongosh -u admin -p ... --eval 'JSON.stringify(rs.conf(), null, 2)' > /tmp/cfg.json
# Sửa: chỉ giữ members còn sống.
bash scripts/replica-set/ops.sh force-reconfig /tmp/cfg.json
```

## 6. Write concern khuyến nghị

| Mục đích | Setting |
|---|---|
| Tốc độ cao, chấp nhận mất tối đa vài giây dữ liệu | `w:1` |
| OLTP tài chính | `w:"majority", j:true` |
| Audit/log | `w:"majority", wtimeout:5000` |

Read concern song hành: `readConcern:"majority"` cho consistency, `readConcern:"local"` mặc định.

## 7. Rollback / tháo replica set

```bash
# Trên mỗi node (LƯU Ý: xoá local DB sẽ xoá luôn lịch sử oplog, không quay đầu):
systemctl stop mongod
rm -rf /var/lib/mongodb/local
# Khôi phục /etc/mongod.conf về standalone (xoá block replication).
systemctl start mongod
```

## 8. Lưu ý quan trọng

- **Số members phải lẻ** (3, 5, 7) — chẵn dễ tie-break thất bại. Nếu buộc dùng 2, thêm 1 arbiter (Runbook 02).
- Mọi member phải mở port 27017 cho nhau (firewall đã làm bởi script).
- Cùng 1 keyFile **bắt buộc** trên 3 nodes — sai → secondary refuse join.
- Oplog window ≥ 24h (nếu lag > oplog window → phải resync từ đầu). Mặc định script set `oplogSizeMB: 2048`. Production: 5-10 GB tuỳ throughput.
- WiredTiger cache mặc định 50% RAM. Lab set 1 GB.

## 9. Tham khảo

- https://www.mongodb.com/docs/manual/replication/
- https://www.mongodb.com/docs/manual/reference/replica-configuration/


---

!!! info "Nguồn gốc"
    `HA/mongo/runbooks/01-replica-set.md`
