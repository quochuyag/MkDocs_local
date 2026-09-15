---
title: Báo cáo Demo 04 — MHA (Master High Availability)
course: 06-high-availability
source: HA/Mysql/demo/04-mha/results/report.md
---

# Báo cáo Demo 04 — MHA (Master High Availability)

## 1. Thông tin demo

| Item | Giá trị |
|------|---------|
| Người thực hiện | quochuyag@gmail.com |
| Ngày chạy | 2026-05-19 (B5–B7 ~08:26–14:28 UTC) |
| MHA version | v0.58 |
| Cluster name | myCluster |
| Backend stack | Async / Semi-Sync (Demo 01) |

## 2. Cấu hình cluster

| Host  | IP             | Role | Phụ thuộc |
|-------|----------------|------|-----------|
| node1 | 192.168.10.11  | Master ban đầu + mha-node | Demo 01 |
| node2 | 192.168.10.12  | Replica + mha-node (candidate_master=1) | Demo 01 |
| node3 | 192.168.10.13  | Replica + mha-node | Demo 01 |
| mgmt  | 192.168.10.20  | MHA Manager (Perl daemon) | — |
| VIP   | 192.168.10.100 | Floating IP gắn vào master | hook `master_ip_failover.sh` |

## 3. Kết quả từng bước

| Bước | Status | Thời gian | Log |
|------|--------|-----------|-----|
| B1 precheck-demo01     | PASS | <5s | [01-precheck.log](01-precheck.log) |
| B2 ssh-trust           | PASS | <30s | [02-ssh-trust.log](02-ssh-trust.log) |
| B3 mha-node-install    | PASS | ~180s | [03-mha-node-install.log](03-mha-node-install.log) |
| B4 mha-manager-install | PASS | ~120s | [04-mha-manager-install.log](04-mha-manager-install.log) |
| B5 verify              | PASS | ~20s | [05-verify.log](05-verify.log) |
| B6 vip-bind            | PASS | ~14s | [06-vip-bind.log](06-vip-bind.log) |
| B7 failover            | PASS | 95s | [07-failover.log](07-failover.log) |
| B8 rebuild-old-master  | PASS | ~60s | [08-rebuild-old-master.log](08-rebuild-old-master.log) |

## 4. Các chỉ số chính

| Metric | Giá trị thực tế | Mong đợi | Pass? |
|--------|-----------------|----------|-------|
| `masterha_check_ssh` exit | 0 (All SSH connection tests passed) | 0 | ✓ |
| `masterha_check_repl` | MySQL Replication Health is OK | OK | ✓ |
| `masterha_check_status` | PING_OK, master:192.168.10.11 | PING_OK | ✓ |
| VIP gắn trên node1 ban đầu | yes (192.168.10.100/24 eth1) | yes | ✓ |
| Ping VIP từ mgmt | 0.347ms avg, 0% loss | OK | ✓ |
| **PROMOTE_RTO** (halt → master mới chấp nhận INSERT) | **95s** | <30s ⚠ vượt mục tiêu | △ |
| VIP move sang master mới | yes (eth1 trên node2) | yes | ✓ |
| Replica còn lại CHANGE SOURCE | yes (node3 → 192.168.10.12) | yes | ✓ |
| Manager tự exit sau failover | yes (cần `--ignore_last_failover` re-run) | yes | ✓ |
| `[server1]` removed khỏi config | yes (--remove_dead_master_conf) | yes | ✓ |
| Data loss (sentinel insert) | none (semi-sync ACK trước commit) | none | ✓ |

> PROMOTE_RTO 95s = ping_interval=3s × 3 vòng + secondary_check + binlog copy + relay apply + VIP move. Có thể giảm bằng `ping_interval=1`, nhưng đánh đổi false-positive cao hơn.

## 5. Quan sát & nhận xét

### Điểm tốt
- MHA tự copy binlog còn sót trên master (qua SSH) → giảm data loss khi master crash đột ngột.
- VIP move qua `master_ip_failover.sh` → app không cần đổi connection string.
- Hỗ trợ GTID auto-pos → bypass nhiều bước SSH/check trong recovery.

### Hạn chế
- Manager là single instance trên mgmt — nếu mgmt host chết, không có failover backup.
- Project ở maintenance mode (yoshinorim/mha4mysql-manager 2018) — không nhận update; Orchestrator là khuyến nghị mới.
- Hook `master_ip_failover.sh` dùng `ip addr add` thô + `arping -U` — production cần Keepalived/Pacemaker để: (a) detect mgmt host alive, (b) automatic re-bind VIP nếu master tự khôi phục.
- Cảnh báo `arping: command not found` lần đầu — đã có ở lần 2 (iputils-arping cần cài cùng `iproute2`).
- Test ban đầu `mysql -uroot -h${VIP}` luôn FAIL vì `root@localhost` only → đã fix script `06-vip-bind.sh` dùng `repl@'%'`.

### Câu hỏi mở
- Tích hợp với ProxySQL (demo 07) thay vì VIP có hợp lý hơn? (mgmt-side connection routing thay vì L2 VIP move.)
- So sánh với Orchestrator (demo 05) — Web UI, Raft 3-node HA cho manager, anti-flapping rõ ràng.
- `masterha_master_switch --master_state=alive` (planned switchover) — không cần halt, có dùng được làm rolling upgrade không?

## 6. Bằng chứng (từ log)

### B5 — masterha_check_*
```
masterha_check_ssh: All SSH connection tests passed successfully.
masterha_check_repl:
  192.168.10.11(current master)
   +--192.168.10.12 (candidate_master=1)
   +--192.168.10.13
  MySQL Replication Health is OK.
masterha_check_status: myCluster (pid:5087) is running(0:PING_OK), master:192.168.10.11
```

### B7 — Failover output
```
HALT_TS              = 2026-05-19 14:26:52
FAILOVER_COMPLETE_TS = 2026-05-19 14:28:27
PROMOTE_RTO          = 95s
OLD_MASTER           = node1 (192.168.10.11)
NEW_MASTER           = node2 (192.168.10.12)
VIP-on-new-master    = OK (192.168.10.100/24 secondary on eth1 of node2)
Slave-follows-new    = OK (node3 → 192.168.10.12, IO=Yes SQL=Yes)
Manager-self-stopped = OK (exits after successful failover)
Server1-removed      = OK (--remove_dead_master_conf)
FAILOVER_PASS=true
```

## 7. Bước tiếp theo

- [ ] Test `masterha_master_switch` (planned switchover) — đo RTO khi master còn sống.
- [ ] Thay VIP hook bằng Keepalived script với health probe tới `:3306`.
- [ ] Tích hợp với ProxySQL: PostFailover hook update `mysql_servers` writer hostgroup (eliminate VIP).
- [ ] So sánh head-to-head với Orchestrator (demo 05) trên cùng nền semi-sync — RTO, UX, robustness.
- [ ] Đặt MHA manager thành systemd service (hiện dùng `masterha_manager &` thủ công sau failover).


---

!!! info "Nguồn gốc"
    `HA/Mysql/demo/04-mha/results/report.md`
