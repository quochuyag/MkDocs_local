---
title: Bước 5 — Bootstrap InnoDB Cluster trên node1, add node2 + node3
course: 06-high-availability
source: HA/Mysql/demo/02-innodb-cluster/05-cluster-bootstrap.md
---

# Bước 5 — Bootstrap InnoDB Cluster trên node1, add node2 + node3

## Mục tiêu
Trên `node1`:
1. `dba.createCluster('myCluster', ...)` — biến node1 thành seed của cluster (lúc này = 1 PRIMARY).
2. `cluster.addInstance(node2, {recoveryMethod:'clone'})` — Clone Plugin copy snapshot từ node1 sang node2.
3. `cluster.addInstance(node3, ...)` — tương tự.
4. In `cluster.status()` để verify 1 PRIMARY + 2 SECONDARY ONLINE.

## Cách chạy

```bash
bash demo/02-innodb-cluster/05-cluster-bootstrap.sh
```

## Diễn giải

Script chạy [scripts/innodb-cluster/cluster-bootstrap.sh](../../scripts/innodb-cluster/cluster-bootstrap.sh) bên trong `node1` qua `vagrant ssh`. Lệnh thực:

```javascript
// 1) Tạo cluster trên seed node1
var cluster = dba.createCluster('myCluster', {
  memberWeight: 50,
  exitStateAction: 'READ_ONLY',           // member bị expel → tự read_only chống split-brain
  consistency: 'BEFORE_ON_PRIMARY_FAILOVER' // primary mới đợi apply hết relay log trước khi accept write
});

// 2) Add node2 — Clone Plugin từ node1
var c = dba.getCluster('myCluster');
c.addInstance('clusteradmin@node2:3306', { password: '...', recoveryMethod: 'clone' });

// 3) Add node3 — Clone Plugin từ node1 hoặc node2
c.addInstance('clusteradmin@node3:3306', { password: '...', recoveryMethod: 'clone' });
```

### Tham số quan trọng

| Tham số | Giá trị | Ý nghĩa |
|---------|---------|---------|
| `memberWeight` | 50 (default 50) | Trọng số khi bầu primary. Set cao hơn ở node mạnh hơn nếu muốn ưu tiên. |
| `exitStateAction` | `READ_ONLY` | Khi node bị expel khỏi group, đặt nó về `read_only=1`. Tránh nó nhận write trong khi đang offline group → split-brain. |
| `consistency` | `BEFORE_ON_PRIMARY_FAILOVER` | Sau khi failover, primary mới đợi apply hết queued transactions trước khi cho client ghi. Đổi lấy "tail consistency" với cost RTO + ~1-2s. |
| `recoveryMethod` | `clone` | Donor node dump 1 snapshot atomic → receiver clone vào → start GR. Yêu cầu MySQL ≥ 8.0.17. Alternative: `incremental` (replay binlog) — chậm hơn nhưng nhẹ I/O. |

### Quan sát: Clone Plugin hoạt động ra sao?

```
node1 (donor)               node2 (receiver, fresh)
   │                              │
   │  ──── addInstance() ────▶    │
   │                              │   STOP all GR
   │                              │   DROP all data dirs
   │                              │   START clone (binary copy InnoDB pages)
   │  ──── transfer ~MB/s ───▶    │
   │                              │   apply remaining binlog
   │                              │   START GR → join group
   │  ◀──── GR consensus ────▶    │   state: RECOVERING → ONLINE
```

Trong khi đang Recovery, node2 sẽ ở state `RECOVERING` trong `cluster.status()`. Sau ~30s-2 phút (tuỳ data size), chuyển `ONLINE`.

## Verify

```bash
vagrant ssh node1 -c "mysqlsh --uri='clusteradmin:ChangeMe!Admin#2026@127.0.0.1:3306' \
  -e \"print(JSON.stringify(dba.getCluster('myCluster').status(),null,2));\""
```

Kỳ vọng:
```json
{
  "clusterName": "myCluster",
  "defaultReplicaSet": {
    "name": "default",
    "primary": "node1:3306",
    "ssl": "REQUIRED",
    "status": "OK",
    "statusText": "Cluster is ONLINE and can tolerate up to ONE failure.",
    "topology": {
      "node1:3306": { "address": "node1:3306", "memberRole": "PRIMARY",   "mode": "R/W", "status": "ONLINE" },
      "node2:3306": { "address": "node2:3306", "memberRole": "SECONDARY", "mode": "R/O", "status": "ONLINE" },
      "node3:3306": { "address": "node3:3306", "memberRole": "SECONDARY", "mode": "R/O", "status": "ONLINE" }
    },
    "topologyMode": "Single-Primary"
  },
  "groupInformationSourceMember": "node1:3306"
}
```

Các trường cần chú ý:
- `status: "OK"` (không phải `"OK_PARTIAL"` hay `"NO_QUORUM"`).
- 3 member đều `"ONLINE"`.
- `statusText` báo "can tolerate up to ONE failure" — tức quorum đầy đủ (3/3).
- `topologyMode: "Single-Primary"` — chỉ 1 node ghi tại 1 thời điểm.

## Lỗi thường gặp

| Lỗi | Khắc phục |
|-----|-----------|
| `ERROR: Group Replication public IP for the member not found` | `report_host` rỗng → quay lại B3 sửa cnf |
| `Recovery method 'clone' is not available` | MySQL < 8.0.17. Đổi `recoveryMethod: 'incremental'` (slower) |
| `Cannot install plugin 'clone'... unknown variable` | Plugin chưa enable. Trên donor: `INSTALL PLUGIN clone SONAME 'mysql_clone.so';` |
| `Member is in state RECOVERING` mãi không chuyển ONLINE | Xem `performance_schema.replication_group_member_stats`; thường do firewall block 33061 |
| `Last_IO_Error: 1872 Replica failed to initialize the master info structure` | Stop GR, RESET MASTER, rerun bootstrap |
| `ERROR 3092 (HY000): server is not configured as group member` | Chạy lại B4 `node-setup.sh` |

## Idempotency

- `dba.createCluster()` chạy lại sẽ báo "cluster exists" → script log warning, không bắn fail.
- `addInstance()` chạy lại với node đã ONLINE sẽ báo "instance is already part of cluster".

Nếu muốn làm lại sạch sẽ, chạy [10-rollback.sh](10-rollback.sh) trước.


---

!!! info "Nguồn gốc"
    `HA/Mysql/demo/02-innodb-cluster/05-cluster-bootstrap.md`
