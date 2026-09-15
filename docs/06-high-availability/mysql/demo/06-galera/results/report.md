---
title: Báo cáo Demo 06 — Galera (Percona XtraDB Cluster 8.0)
course: 06-high-availability
source: HA/Mysql/demo/06-galera/results/report.md
---

# Báo cáo Demo 06 — Galera (Percona XtraDB Cluster 8.0)

## 1. Thông tin demo

| Item | Giá trị |
|------|---------|
| Người thực hiện | quochuyag@gmail.com |
| Ngày chạy | 2026-05-20 (B2–B7 ~17:48–17:55 host time) |
| PXC version | 8.0.x (từ `mysql --version` trên node1 — chưa extract version chính xác từ log) |
| Galera cluster name | `pxc-cluster` |

## 2. Cấu hình cluster

| Host  | IP             | Role | wsrep_node_name |
|-------|----------------|------|------------------|
| node1 | 192.168.10.11  | Bootstrap + member | pxc-node1 |
| node2 | 192.168.10.12  | Member (joined via SST) | pxc-node2 |
| node3 | 192.168.10.13  | Member (joined via SST) | pxc-node3 |

Ports: 3306 (client), 4567 (replication TCP), 4568 (IST), 4444 (SST). `innodb_autoinc_lock_mode=2` trên cả 3 node để cho phép concurrent insert.

## 3. Kết quả từng bước

| Bước | Status | Thời gian | Log |
|------|--------|-----------|-----|
| B1 vagrant-up           | PASS (idempotent) | — | (host) |
| B2 prepare-os           | PASS | <60s | [02-prepare-os.log](02-prepare-os.log) |
| B3 install-pxc          | PASS | ~300s | [03-install-pxc.log](03-install-pxc.log) |
| B4 bootstrap-node1      | PASS | <30s | [04-bootstrap-node1.log](04-bootstrap-node1.log) |
| B5 join-node2-node3     | PASS | <90s | [05-join-node2-node3.log](05-join-node2-node3.log) |
| B6 verify               | PASS | ~221s | [06-verify.log](06-verify.log) |
| B7 smoke-test           | PASS | ~162s | [07-smoke-test.log](07-smoke-test.log) |
| B8 split-brain          | NOT RUN | — | (không có log) |

## 4. Các chỉ số chính

| Metric | Giá trị thực tế | Mong đợi | Pass? |
|--------|-----------------|----------|-------|
| `wsrep_cluster_size` (mọi node) | 3 / 3 / 3 | 3 | ✓ |
| `wsrep_cluster_status` (mọi node) | Primary | Primary | ✓ |
| `wsrep_local_state_comment` (mọi node) | Synced | Synced | ✓ |
| `wsrep_ready` / `wsrep_connected` | ON / ON | ON | ✓ |
| `innodb_autoinc_lock_mode` | 2 (cả 3 node) | 2 | ✓ |
| Insert 150 rows trên node1 | 7.861s | <10s | ✓ |
| Replica node2 catch-up | 7.686s | <10s | ✓ |
| Replica node3 catch-up | 7.620s | <10s | ✓ |
| Parallel insert 3×50 rows | OK (mỗi node insert được) | OK | ✓ |
| Consistency sau parallel (total=300, mọi node) | yes (node1=200/node2=50/node3=50 split đồng nhất 3 node) | yes | ✓ |
| Split-brain block write (B8) | chưa test | yes | — |

## 5. Quan sát & nhận xét

### Điểm tốt
- Synchronous replication (certification-based) — không có lag rò rỉ; app có thể đọc-sau-ghi nhất quán mọi node.
- Multi-master writable — không cần khái niệm failover; nếu 1 node chết, các node khác vẫn nhận write (miễn quorum ≥2/3).
- Galera tự shutdown node mất quorum → tránh split-brain data divergence (kỳ vọng cho B8).
- 3 node parallel insert 50 rows mỗi node → total=300 đồng nhất trên cả 3 node, không có conflict (autoinc lock mode 2).

### Hạn chế
- WAN latency huỷ hoại throughput — certification round-trip ≥ RTT giữa nodes.
- Bắt buộc PK + InnoDB only — legacy schema phải migrate (Galera Compatibility Audit cần làm trước).
- Recovery sau full outage cần can thiệp manual: chọn node có `seqno` cao nhất, sửa `safe_to_bootstrap=1` trong `grastate.dat` rồi bootstrap. Đã encountered (memory: `bug_pxc_halt_seqno_minus_1_recovery.md`).
- Install có 5 pitfall đã fix (memory: `bug_pxc8_install_pitfalls.md`): dual-NIC, `#` in password, removed `wsrep_sst_auth`, root auth_socket, SSL certs mismatch, mysql@bootstrap vs mysql.service.
- B8 split-brain chưa chạy → chưa verify hành vi non-Primary khi mất quorum.

### Câu hỏi mở
- Tích hợp ProxySQL (demo 07 đã làm) với `mysql_galera_hostgroups` — auto-failover writer khi 1 node lag (Desynced).
- Đo write throughput so với async master/replica: degradation bao nhiêu % với sysbench OLTP RW?
- Test DDL TOI (Total Order Isolation) vs RSU (Rolling Schema Upgrade) trên bảng lớn — RSU latency thấp hơn?

## 6. Bằng chứng (từ log)

### B6 — Verify
```
[ OK ] [node1/2/3] wsrep_cluster_size=3
[ OK ] [node1/2/3] wsrep_cluster_status=Primary
[ OK ] [node1/2/3] wsrep_local_state_comment=Synced
[ OK ] [node1/2/3] wsrep_ready=ON, wsrep_connected=ON
[ OK ] [node1/2/3] innodb_autoinc_lock_mode=2
VERIFY_PASS=true
```

### B7 — Smoke test multi-master
```
Part 1: bulk insert 150 rows trên node1
  insert 150 rows xong sau 7.861s
  [node2] thấy 150 rows sau 7.686s
  [node3] thấy 150 rows sau 7.620s

Part 2: parallel insert 50 rows mỗi node
  [node1/node2/node3] đã insert 50 rows
  Sau parallel: expected = 150 + 3*50 = 300
  [node1] total=300  node1=200 node2=50 node3=50
  [node2] total=300  node1=200 node2=50 node3=50
  [node3] total=300  node1=200 node2=50 node3=50
[OK] Consistency: 3 nodes báo total=300
SMOKE_PASS=true
```

## 7. Bước tiếp theo

- [ ] **Chạy B8 split-brain test** (`08-split-brain-test.sh`) — halt 2 node, verify node còn lại non-Primary và refuse write.
- [ ] Sysbench OLTP load (read-heavy, write-heavy) — so sánh % degradation vs async stack.
- [ ] Test SST recovery: `sudo rm -rf /var/lib/mysql/* && systemctl start mysql@bootstrap` trên node2 → verify SST tự chạy từ donor.
- [ ] Test DDL TOI vs RSU (`pt-online-schema-change` so với native ALTER) trên bảng 10M rows.
- [ ] Đã ghép với ProxySQL ở demo 07 — verify behavior khi 1 backend Desynced (donor SST đang chạy).


---

!!! info "Nguồn gốc"
    `HA/Mysql/demo/06-galera/results/report.md`
