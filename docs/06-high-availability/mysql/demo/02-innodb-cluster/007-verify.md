---
title: Bước 7 — Verify toàn cluster
course: 06-high-availability
source: HA/Mysql/demo/02-innodb-cluster/07-verify.md
---

# Bước 7 — Verify toàn cluster

## Mục tiêu
Tổng hợp tất cả checkpoint vào 1 báo cáo `results/07-verify.log`. Read-only — an toàn rerun nhiều lần.

## Cách chạy

```bash
bash demo/02-innodb-cluster/07-verify.sh
```

## Checkpoints

| # | Item | Câu lệnh | Pass khi |
|---|------|----------|----------|
| 1 | Service mysql active trên node1/2/3 | `systemctl is-active mysql` | `active` |
| 2 | Port 3306 + 33061 listen 0.0.0.0 | `ss -tlnp` | có cả 2 dòng |
| 3 | GTID + enforce_gtid + binlog_format | `SELECT @@gtid_mode,@@enforce_gtid_consistency,@@binlog_format;` | `ON / 1 / ROW` |
| 4 | Plugin `group_replication` ACTIVE trên 3 node | `SELECT plugin_status FROM IS.plugins WHERE plugin_name='group_replication';` | `ACTIVE` |
| 5 | `replication_group_members`: 3 dòng, all ONLINE | `SELECT MEMBER_HOST,MEMBER_STATE,MEMBER_ROLE FROM PS.replication_group_members;` | 3 rows, all `ONLINE`, có 1 `PRIMARY` |
| 6 | `cluster.status()` trả `"OK"` | `dba.getCluster().status()` | `status="OK"` |
| 7 | mgmt: mysqlrouter service active | `systemctl is-active mysqlrouter` | `active` |
| 8 | mgmt: Router lắng nghe 6446 + 6447 | `ss -tlnp` | cả 2 port |
| 9 | Connect qua Router :6446 (RW) → ra primary | `SELECT @@hostname` qua `:6446` | trả hostname = current primary |
| 10 | Connect qua Router :6447 (RO) → 2 secondaries round-robin | `SELECT @@hostname` qua `:6447` × 4 lần | xuất hiện cả 2 secondary |
| 11 | Secondary có `super_read_only=1` | `SELECT @@super_read_only` trên node2/3 | `1` |
| 12 | gtid_executed đồng bộ 3 node (cuối, không tính read flux) | `SELECT @@global.gtid_executed` × 3 | bằng nhau |

## Output

Toàn bộ output lưu tại [results/07-verify.log](results/07-verify.log). Cuối log có dòng `VERIFY_PASS=true/false` để gate B8.

## Đọc kết quả

- Nếu `VERIFY_PASS=true` → an toàn chạy `08-smoke-test.sh`.
- Nếu `false` → grep log tìm dòng `[FAIL]` để xác định checkpoint nào fail.

## Diễn giải checkpoint đặc biệt

### #5 — `replication_group_members`
```
+--------------------------------------+-------------+-------------+--------------+-------------+
| MEMBER_ID                            | MEMBER_HOST | MEMBER_PORT | MEMBER_STATE | MEMBER_ROLE |
+--------------------------------------+-------------+-------------+--------------+-------------+
| 11111111-1111-1111-1111-111111111111 | node1       |        3306 | ONLINE       | PRIMARY     |
| 22222222-...                         | node2       |        3306 | ONLINE       | SECONDARY   |
| 33333333-...                         | node3       |        3306 | ONLINE       | SECONDARY   |
+--------------------------------------+-------------+-------------+--------------+-------------+
```

Các state khác cần biết:
- `RECOVERING`: đang join cluster, copy data từ donor.
- `OFFLINE`: GR chưa start hoặc đã stop.
- `ERROR`: failed → group sẽ tự expel sau timeout.
- `UNREACHABLE`: bị mất quorum hoặc network partition.

### #6 — `cluster.status()` status text
- `"OK"`: 3/3 ONLINE, có thể chịu lỗi 1 node.
- `"OK_PARTIAL"`: 2/3 ONLINE, vẫn chấp nhận write nhưng không còn redundancy → bù gấp.
- `"OK_NO_TOLERANCE"`: chỉ còn 1 node ONLINE, write vẫn chạy nhưng node này chết → cluster chết.
- `"NO_QUORUM"`: mất quorum, group block write. Cần `forceQuorumUsingPartitionOf()`.

### #9, #10 — Router routing
- `:6446` luôn ra duy nhất 1 node (PRIMARY hiện tại). Khi failover → đổi.
- `:6447` round-robin các SECONDARY (default policy). Có thể đổi sang `first-available` qua config.

## Lưu ý

Script này read-only — không thay đổi state DB/cluster.


---

!!! info "Nguồn gốc"
    `HA/Mysql/demo/02-innodb-cluster/07-verify.md`
