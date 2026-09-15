---
title: 00 — Tổng quan bài demo
course: 06-high-availability
source: HA/Mysql/demo/03-group-replication/00-overview.md
---

# 00 — Tổng quan bài demo

## Mục tiêu

Chứng minh giải pháp HA **Group Replication thuần** (không qua `mysqlsh dba.*`) cho MySQL 8.0:
1. Dựng cụm 3 node + 1 mgmt host trên Vagrant.
2. Bootstrap group trên node1, join node2/node3 bằng SQL trực tiếp.
3. Chứng minh **3 ONLINE member + 1 PRIMARY + GTID đồng bộ**.
4. Chứng minh **data đồng bộ** trên cả 3 node (smoke test).
5. Chứng minh **auto-failover** (halt primary → secondaries tự bầu primary mới).

## Kiến trúc

- **Group Replication (Paxos-like consensus)**: mọi node là member, nhưng chỉ 1 ở `MEMBER_ROLE=PRIMARY` trong single-primary mode (mặc định).
- **Group_replication_recovery channel**: dùng `repl@%` user (mysql_native_password) để recovery khi node mới join.
- **GTID auto-position**: bắt buộc.
- **GR_GROUP_UUID**: cố định (định danh group) — `aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa`.
- **ip_allowlist**: chỉ cho phép 3 IP node nói chuyện với nhau qua port 33061.

## Phạm vi demo

| Có | Không |
|----|-------|
| Setup cluster, smoke test, failover tự động | Multi-primary mode (mặc định single-primary) |
| ProxySQL hoặc Router | Không có proxy mặc định — app dùng connection retry hoặc tự sniff primary |
| Clone Plugin có sẵn cho recovery khi tụt nhiều | Không demo recovery deep — xem runbook |

## Tiêu chí thành công

| # | Tiêu chí | Cách kiểm tra |
|---|----------|---------------|
| 1 | 4 VM up, ping được nhau | `vagrant status` + ping nội bộ |
| 2 | MySQL 8.0 chạy trên 3 DB nodes, plugin `group_replication` ACTIVE | `SELECT plugin_status FROM IS.plugins WHERE plugin_name='group_replication';` |
| 3 | 3 ONLINE members, 1 PRIMARY | `SELECT * FROM performance_schema.replication_group_members;` |
| 4 | GTID `gtid_executed` đồng bộ 3 node | `SELECT @@global.gtid_executed;` |
| 5 | INSERT trên PRIMARY → SELECT trên 2 SECONDARY < 1s | smoke test |
| 6 | `vagrant halt` primary → secondaries bầu primary mới trong ≤ 15s | failover test |
| 7 | Secondary cũ tự ở `super_read_only=1` | `SELECT @@super_read_only;` |

## Thời gian ước tính

| Pha | Thời gian |
|-----|-----------|
| `vagrant up` lần đầu | 10–15 phút |
| Prepare OS | 2 phút |
| Install MySQL | 5–8 phút |
| primary-setup + secondary-setup | 1–2 phút |
| Verify + smoke test | 1 phút |
| Failover demo | 2 phút |
| **Tổng** | **~25–30 phút** |


---

!!! info "Nguồn gốc"
    `HA/Mysql/demo/03-group-replication/00-overview.md`
