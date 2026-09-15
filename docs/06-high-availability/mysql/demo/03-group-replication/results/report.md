---
title: Báo cáo Demo 03 — Group Replication thuần
course: 06-high-availability
source: HA/Mysql/demo/03-group-replication/results/report.md
---

# Báo cáo Demo 03 — Group Replication thuần

## 1. Thông tin demo

| Item | Giá trị |
|------|---------|
| Người thực hiện | quochuyag@gmail.com |
| Ngày chạy | 2026-05-20 (khoảng 09:49–09:56 host time) |
| Host OS / RAM | Windows 11 Pro 10.0.26200 |
| MySQL version | 8.0.46 (community) |
| GR group UUID | `aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa` |

## 2. Cấu hình cluster

| Host  | IP             | Role | server_id |
|-------|----------------|------|-----------|
| node1 | 192.168.10.11  | GR member — PRIMARY ban đầu | 1 |
| node2 | 192.168.10.12  | GR member — SECONDARY | 2 |
| node3 | 192.168.10.13  | GR member — SECONDARY | 3 |
| mgmt  | 192.168.10.20  | mysql client | — |

GTID `ON`, `enforce_gtid_consistency=ON`, `binlog_format=ROW`, plugin `group_replication` ACTIVE, port 33061 GR-internal.

## 3. Kết quả từng bước

| Bước | Status | Thời gian | Log |
|------|--------|-----------|-----|
| B1 vagrant-up        | PASS | (host idempotent) | [01-vagrant-up.log](01-vagrant-up.log) |
| B2 prepare-os        | PASS | <60s | [02-prepare-os.log](02-prepare-os.log) |
| B3 install-mysql     | PASS | <300s | [03-install-mysql.log](03-install-mysql.log) |
| B4 primary-setup     | PASS | <60s | [04-primary-setup.log](04-primary-setup.log) |
| B5 secondary-setup   | PASS | <90s | [05-secondary-setup.log](05-secondary-setup.log) |
| B6 verify            | PASS | ~140s | [06-verify.log](06-verify.log) |
| B7 smoke-test        | PASS | ~57s | [07-smoke-test.log](07-smoke-test.log) |
| B8 failover          | PASS | ~83s | [08-failover.log](08-failover.log) |
| B9 rollback          | PASS | <5s | [09-rollback.log](09-rollback.log) |

## 4. Các chỉ số chính

| Metric | Giá trị thực tế | Mong đợi | Pass? |
|--------|-----------------|----------|-------|
| Số member ONLINE | 3 | 3 | ✓ |
| Số PRIMARY | 1 (192.168.10.11) | 1 | ✓ |
| `super_read_only` đúng vai trò | PRIMARY=0, SECONDARY=1/1 | đúng | ✓ |
| GTID đồng bộ 3 node (sau smoke) | `1-208` mọi node | đồng bộ | ✓ |
| Insert 200 rows trên PRIMARY | 12.259s | <15s | ✓ |
| Lag node1/2/3 (catch-up) | 5.443 / 5.774 / 5.743s | <10s | ✓ |
| **PROMOTE_RTO** (halt → primary mới) | **27s** | <30s | ✓ |
| **WRITE_RTO** (halt → INSERT OK) | **32s** | <45s | ✓ |
| Sentinel row giữ sau failover | yes | yes | ✓ |
| Replica còn sống tự catch-up | yes (node3: 252/252) | yes | ✓ |

## 5. Quan sát & nhận xét

### Điểm tốt
- Failover hoàn toàn tự động — không cần manager bên ngoài, không cần Shell/Router.
- PROMOTE_RTO=27s rất nhanh so với MHA (95s) và Orchestrator force (263s).
- Toàn bộ config thuần SQL → dễ tự động hoá bằng Ansible/Pulumi.
- Sentinel row (id=201) giữ nguyên sau halt → consistency tốt với default settings.

### Hạn chế
- Không có Router → app phải tự sniff PRIMARY (`SELECT MEMBER_HOST FROM performance_schema.replication_group_members WHERE MEMBER_ROLE='PRIMARY'`) hoặc dùng ProxySQL (demo 07) với `mysql_group_replication_hostgroups`.
- GR yêu cầu mọi bảng có PK + InnoDB → legacy schema phải migrate.
- Demo dùng dual-NIC; cần `loose-group_replication_local_address` trỏ đúng IP hostonly (không phải NAT 10.0.2.15) — bug đã fix trong `primary/secondary-setup.sh` (memory: bug_gr_vagrant_dual_nic).

### Câu hỏi mở
- Switch sang multi-primary mode (`group_replication_switch_to_multi_primary_mode()`) — phù hợp use case nào?
- Test split brain: drop network giữa node1 và (node2,node3) → minority partition fence?
- Số đo dùng ProxySQL trước GR thay vì sniff thủ công?

## 6. Bằng chứng (từ log)

### B6 — Verify
```
MEMBER_HOST       MEMBER_STATE    MEMBER_ROLE
192.168.10.11     ONLINE          PRIMARY
192.168.10.12     ONLINE          SECONDARY
192.168.10.13     ONLINE          SECONDARY
[ OK ] 3 members ONLINE, exactly 1 PRIMARY
[ OK ] [node1] super_read_only=0  [node2] =1  [node3] =1
gtid_executed đồng bộ: 1-5 / 1-5 / 1-5
VERIFY_PASS=true
```

### B7 — Smoke
```
insert 200 rows xong sau 12.259s
[node1] thấy 200 rows sau 5.443s
[node2] thấy 200 rows sau 5.774s
[node3] thấy 200 rows sau 5.743s
gtid_executed: aaaaaaaa-...:1-208 (cả 3 node)
SMOKE_PASS=true
```

### B8 — Failover (halt --force node1)
```
Primary trước halt: node1
Insert sentinel id=201, replicas thấy ngay
Halt 09:55:37 → poll từ node2
FOUND new PRIMARY = 192.168.10.12 sau 16s
NEW PRIMARY = node2 sau 27s
node2 chấp nhận INSERT sau 32s
post-failover insert 50 rows xong 5.499s
[node3] OK 252/252
FAILOVER_PASS=true PROMOTE_RTO=27s WRITE_RTO=32s old=node1 new=node2
```

## 7. Bước tiếp theo

- [ ] Demo 07 (ProxySQL) ghép trên GR này để có R/W split + failover trong suốt cho app.
- [ ] Test multi-primary: `SELECT group_replication_switch_to_multi_primary_mode();` rồi insert song song 3 node.
- [ ] Test split brain: `iptables -A INPUT -s node2,node3 -j DROP` trên node1 → quan sát node1 chuyển ERROR và bị evict.
- [ ] So sánh với demo 02 (InnoDB Cluster) — Router 6446 vs sniff thủ công.


---

!!! info "Nguồn gốc"
    `HA/Mysql/demo/03-group-replication/results/report.md`
