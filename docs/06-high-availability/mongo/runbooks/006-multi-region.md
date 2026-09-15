---
title: Runbook 06 — Multi-Region (Cross-DC HA / DR)
course: 06-high-availability
source: HA/mongo/runbooks/06-multi-region.md
---

# Runbook 06 — Multi-Region (Cross-DC HA / DR)

## 1. Khi nào dùng

- RPO < 1 phút và RTO < 30 phút trên scale region.
- Tuân thủ data residency (zone sharding cho EU/US/APAC).
- DR site: 1 region đứng → region B vẫn serve.

## 2. Các pattern

### Pattern A — Stretched Replica Set (1 RS, members ở nhiều DC)
```
DC-A (primary region)            DC-B (DR region)
node1:27017 PRIMARY  pri=2       node4:27017 SECONDARY pri=0, votes=0  (DR only)
node2:27017 SECONDARY pri=1
node3:27017 SECONDARY pri=1
```
- 3 voters ở DC-A → election không bị ảnh hưởng latency DC-B.
- node4 = priority=0, votes=0: chỉ replicate, không vote, không thành primary tự động.
- **DR procedure**: nếu mất toàn bộ DC-A → force-reconfig để promote node4.

### Pattern B — 5-node stretched (active-active failover)
```
DC-A: node1 (pri=2), node2 (pri=1)
DC-B: node3 (pri=1), node4 (pri=1)
DC-C (arbiter site nhỏ): node5 arbiter
```
- 5 voters → tolerate mất 1 DC.
- Latency DC-A ↔ DC-B phải < 250ms cho commit `w:majority` reasonable.

### Pattern C — Sharded Cluster + Zone sharding
```
Shard A (DC-A): chỉ chứa data với tag "US"
Shard B (DC-B): chỉ chứa data với tag "EU"
Config servers: stretched 3 nodes
mongos: deploy mỗi DC
```
- Data EU không bao giờ rời DC EU (compliance).
- Cross-region read latency = 0 trong cùng region.

## 3. Thực hiện Pattern A trong lab

Lab Vagrant chỉ có 4 VMs cùng "DC". Giả lập DC-B bằng cách dùng `mgmt` host làm DR node.

### B1. Đã có RS PSS (Runbook 01)
Verify: `bash scripts/replica-set/ops.sh status` → 3 ONLINE.

### B2. Cài MongoDB + keyFile trên mgmt
```bash
# Trên mgmt:
sudo bash /vagrant/scripts/common/01-install-mongo.sh
sudo bash /vagrant/scripts/replica-set/node-config.sh
# (script này set replSetName=rs0, restart mongod, không initiate)
```

### B3. Add mgmt như là DR member
```bash
# Trên node1 (primary):
bash /vagrant/scripts/multi-region/add-remote-secondary.sh mgmt:27017 0 false
# args: host:port priority hidden
# priority=0, votes=0 (default trong script) → DR only.
```

### B4. Verify replication tới DR
```bash
mongosh -u admin -p --host node1:27017 --eval '
rs.printSecondaryReplicationInfo()
'
# Kỳ vọng: mgmt:27017 với syncedTo ≈ now.
```

## 4. Vận hành — DR failover (manual)

Giả sử DC-A mất hoàn toàn (node1/2/3 không reachable):
```bash
# Trên mgmt (node sống duy nhất):
mongosh -u admin -p --host mgmt:27017 --eval '
var cfg = rs.conf();
// Lọc bỏ members không reachable
cfg.members = cfg.members.filter(m => m.host === "mgmt:27017");
cfg.members[0].priority = 1;
cfg.members[0].votes = 1;
rs.reconfig(cfg, {force:true});
'
# Đợi PRIMARY:
mongosh -u admin -p --host mgmt:27017 --eval 'rs.status().myState'  # == 1
```
App chuyển connection string sang `mongodb://mgmt:27017/appdb`.

## 5. Vận hành — DR failback

Khi DC-A khôi phục:
```bash
# Trên mgmt (đang là primary):
mongosh -u admin -p --eval '
rs.add({host:"node1:27017", priority:1, votes:1});
rs.add({host:"node2:27017", priority:1, votes:1});
rs.add({host:"node3:27017", priority:1, votes:1});
'
# Đợi 3 nodes này sync xong (initial sync nếu lag quá oplog window).
# Sau đó stepDown mgmt và reset priority:
mongosh -u admin -p --eval '
var cfg = rs.conf();
cfg.members.forEach(m => {
  if (m.host === "mgmt:27017") { m.priority = 0; m.votes = 0; }
  if (m.host === "node1:27017") { m.priority = 2; }
});
rs.reconfig(cfg);
rs.stepDown(60);
'
```

## 6. Zone sharding (Pattern C)

### B1. Add tags cho shards
```bash
bash /vagrant/scripts/multi-region/zone-sharding.sh shard1rs US
bash /vagrant/scripts/multi-region/zone-sharding.sh shard2rs EU
```

### B2. Thiết kế shard key có field "region"
```js
// Trong mongosh kết nối mongos:
sh.shardCollection('appdb.events', { region: 1, _id: 1 });

sh.addTagRange('appdb.events',
  { region: 'us', _id: MinKey },
  { region: 'us', _id: MaxKey },
  'US'
);
sh.addTagRange('appdb.events',
  { region: 'eu', _id: MinKey },
  { region: 'eu', _id: MaxKey },
  'EU'
);
```

### B3. Verify
```js
sh.status({verbose:true})
// kỳ vọng: chunks region='us' nằm hết trên shard1rs (tag US), region='eu' trên shard2rs.
```

## 7. Lưu ý quan trọng

- **Latency**: cross-region RTT ảnh hưởng trực tiếp tới `w:"majority"` write latency. EU↔US ~80ms → write `w:majority` mất ≥80ms.
- **Network partition**: với 5 voters stretched, mất link giữa 2 DCs → DC ít voters hơn block writes. Plan arbiter site neutral để giải.
- **Atlas managed**: có "Global Clusters" làm zone sharding tự động — đáng cân nhắc nếu không muốn tự build.
- **TLS bắt buộc** cho cross-region traffic. Dùng `common/04-tls-self-signed.sh` (lab) hoặc CA thật (prod).

## 8. Tham khảo

- https://www.mongodb.com/docs/manual/core/replica-set-architecture-geographically-distributed/
- https://www.mongodb.com/docs/manual/tutorial/manage-shard-zone/
- https://www.mongodb.com/docs/atlas/global-clusters/


---

!!! info "Nguồn gốc"
    `HA/mongo/runbooks/06-multi-region.md`
