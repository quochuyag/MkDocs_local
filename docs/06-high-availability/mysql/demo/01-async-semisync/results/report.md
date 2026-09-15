---
title: Báo cáo Demo 01 — Async / Semi-Sync Replication
course: 06-high-availability
source: HA/Mysql/demo/01-async-semisync/results/report.md
---

# Báo cáo Demo 01 — Async / Semi-Sync Replication

## 1. Thông tin demo

| Item | Giá trị |
|------|---------|
| Người thực hiện | quochuyag@gmail.com |
| Ngày chạy | 2026-05-20 (khoảng 14:03–15:46 host time) |
| Host OS / RAM | Windows 11 Pro 10.0.26200 |
| Lab | 4 VMs Vagrant + VirtualBox (Ubuntu 22.04) |
| MySQL version | 8.0.46 (community) |

## 2. Cấu hình cluster

| Host  | IP             | Role                    | server_id |
|-------|----------------|-------------------------|-----------|
| node1 | 192.168.10.11  | Master (semi-sync source) | 1 |
| node2 | 192.168.10.12  | Replica (semi-sync) | 2 |
| node3 | 192.168.10.13  | Replica (semi-sync) | 3 |

GTID `ON`, `enforce_gtid_consistency=ON`, `binlog_format=ROW`, plugin `rpl_semi_sync_source` + `rpl_semi_sync_replica` ACTIVE.

## 3. Kết quả từng bước

| Bước | Status | Thời gian | Log |
|------|--------|-----------|-----|
| B1 vagrant-up    | PASS | 319s | [01-vagrant-up.log](01-vagrant-up.log) |
| B2 prepare-os    | PASS | ~120s | [02-prepare-os.log](02-prepare-os.log) |
| B3 install-mysql | PASS | ~280s | [03-install-mysql.log](03-install-mysql.log) |
| B4 master-setup  | PASS | <60s | [04-master-setup.log](04-master-setup.log) |
| B5 replica-setup | PASS | <90s | [05-replica-setup.log](05-replica-setup.log) |
| B6 verify        | PASS | ~152s | [06-verify.log](06-verify.log) |
| B7 smoke-test    | PASS | ~76s | [07-smoke-test.log](07-smoke-test.log) |
| B8 failover      | NOT RUN | — | (không có 08-failover-test.log) |
| B9 rollback      | NOT RUN | — | (không có 09-rollback.log) |

> Lưu ý: `run-all.summary` chỉ ghi B1 vì user dừng giữa chừng; các bước B2..B7 đã chạy thủ công sau đó (có log).

## 4. Các chỉ số chính

| Metric | Giá trị thực tế | Mong đợi | Pass? |
|--------|------------------|----------|-------|
| `Rpl_semi_sync_source_status` | ON | ON | ✓ |
| `Rpl_semi_sync_source_clients` | 2 | 2 | ✓ |
| `Rpl_semi_sync_replica_status` (node2/3) | ON / ON | ON | ✓ |
| `super_read_only` (replicas) | 1 / 1 | 1 | ✓ |
| Lag idle (replicas) | 0s / 0s | <1s | ✓ |
| Insert 200 rows (node1) | 12.949s | <15s | ✓ |
| Replica catch-up node2 | 5.975s | <10s | ✓ |
| Replica catch-up node3 | 5.996s | <10s | ✓ |
| GTID đồng bộ 3 node | `1-207` mọi node | đồng bộ | ✓ |
| `Rpl_semi_sync_source_yes_tx` delta | 200 (no_tx=4 idle) | ≥200 | ✓ |

## 5. Quan sát & nhận xét

### Điểm tốt
- Semi-sync chặn commit khi không có replica ACK → đảm bảo durability tới ≥1 replica (`rpl_semi_sync_source_wait_for_replica_count` mặc định = 1).
- GTID auto-position cho replica đơn giản hoá `CHANGE REPLICATION SOURCE`.
- Lag 200 rows ~6s đủ tốt cho OLTP medium.

### Hạn chế
- Không auto-failover — cần MHA (demo 04) hoặc Orchestrator (demo 05) ghép phía trên.
- Single point of failure ở master. Nếu master crash, app cần biết để repoint hoặc dùng VIP/proxy.
- Test crash master (B8) chưa chạy → không có số đo PROMOTE_RTO/WRITE_RTO cho stack này riêng lẻ; số đo MHA (95s) và Orchestrator (263s) bên dưới đã đo trên cùng nền semi-sync.

### Câu hỏi mở
- Test `rpl_semi_sync_source_timeout` (mặc định 10s) — sau timeout fallback async, độ trễ cảm nhận?
- Đo throughput so với async thuần (sysbench OLTP RW)?

## 6. Bằng chứng (từ log)

### B6 — Verify (rút gọn)
```
[ OK ] [node1] rpl_semi_sync_source = ACTIVE
[ OK ] [node2] rpl_semi_sync_replica = ACTIVE
[ OK ] [node3] rpl_semi_sync_replica = ACTIVE
[ OK ] [node1] Rpl_semi_sync_source_status = ON
[ OK ] [node1] Rpl_semi_sync_source_clients = 2
[ OK ] [node2] IO=ON SQL=ON lag=0s super_read_only=1 semi_sync=ON
[ OK ] [node3] IO=ON SQL=ON lag=0s super_read_only=1 semi_sync=ON
VERIFY_PASS=true
```

### B7 — Smoke test
```
[node1] INSERT 200 rows xong trong 12.949s
[node2] thấy 200 rows sau 5.975s
[node3] thấy 200 rows sau 5.996s
gtid_executed: 0f949689-535e-11f1-b599-08002716ddef:1-207 (cả 3 node)
SMOKE_PASS=true
```

## 7. Bước tiếp theo

- [ ] Chạy B8 `08-failover-test.sh` để có DETECT_RTO / PROMOTE_RTO / WRITE_RTO native (không qua MHA/Orchestrator).
- [ ] Đo throughput sysbench OLTP RW với semi-sync vs async.
- [ ] Test `rpl_semi_sync_source_timeout` (giảm xuống 1s, halt 1 replica, xem fallback).
- [ ] Sau khi hoàn tất → demo 04 (MHA) hoặc demo 05 (Orchestrator) để có auto-failover.


---

!!! info "Nguồn gốc"
    `HA/Mysql/demo/01-async-semisync/results/report.md`
