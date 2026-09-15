---
title: Báo cáo Demo 05 — Orchestrator
course: 06-high-availability
source: HA/Mysql/demo/05-orchestrator/results/report.md
---

# Báo cáo Demo 05 — Orchestrator

## 1. Thông tin demo

| Item | Giá trị |
|------|---------|
| Người thực hiện | quochuyag@gmail.com |
| Ngày chạy | 2026-05-19 (khoảng 12:58 → 16:34) |
| Orchestrator version | v3.2.6 (openark/orchestrator) |
| Web UI | <http://192.168.10.20:3000> (admin / `ADMIN_PWD` env) |
| Backend stack | Async / Semi-Sync (Demo 01) |

## 2. Cấu hình cluster

| Host  | IP             | Role | Phụ thuộc |
|-------|----------------|------|-----------|
| node1 | 192.168.10.11  | Master ban đầu | Demo 01 |
| node2 | 192.168.10.12  | Replica | Demo 01 |
| node3 | 192.168.10.13  | Replica | Demo 01 |
| mgmt  | 192.168.10.20  | Orchestrator daemon + backend MySQL | — |

## 3. Kết quả từng bước

| Bước | Status | Thời gian | Log |
|------|--------|-----------|-----|
| B1 precheck-demo01       | PASS lần 2 (FAIL lần 1 do hostname mismatch) | <30s | [01-precheck.log](01-precheck.log) |
| B2 orchestrator-install  | PASS | ~180s | [02-orchestrator-install.log](02-orchestrator-install.log) |
| B3 discover-topology     | PASS (lần 2 — lần 1 lỗi clusterHint) | <50s | [03-discover-topology.log](03-discover-topology.log) |
| B4 verify                | PASS | ~40s | [04-verify.log](04-verify.log) |
| B5 smoke-test            | PASS | <30s | [05-smoke-test.log](05-smoke-test.log) |
| B6 graceful-failover     | PASS (7s) | 37s tổng | [06-graceful-failover.log](06-graceful-failover.log) |
| B7 force-failover        | PASS | 276s | [07-force-failover.log](07-force-failover.log) |

> Lần discover đầu (16:20:08) lỗi `Unable to determine cluster name. clusterHint=192.168.10.11:3306`. Đã fix bằng cách seed lại với IP thay vì hostname (memory: `bug_demo03_ip_hostname_mismatch.md`).

## 4. Các chỉ số chính

| Metric | Giá trị thực tế | Mong đợi | Pass? |
|--------|-----------------|----------|-------|
| Topology discover đủ 3 node | yes (`[rw] +-- [ro] +-- [ro]`) | yes | ✓ |
| Web UI :3000 trả 200 | yes (API `/api/health` OK) | yes | ✓ |
| replication-analysis sạch (lúc verify) | yes (không DeadMaster) | yes | ✓ |
| **Graceful switchover** (node1→node2) | **7s** | <15s | ✓ |
| Topology sau switchover | node2 [rw], node1 [downtimed,nonreplicating], node3 → node2 | đúng | ✓ |
| **Force failover** (halt node2) PROMOTE_RTO | **263s** | <30s ⚠ vượt | △ |
| Force failover WRITE_RTO | **276s** | <45s ⚠ vượt | △ |
| node1 follow new master sau force | yes (Source_Host=192.168.10.13) | yes | ✓ |

> Số đo 263s là với config gốc (`InstancePollSeconds=5`, `RecoveryPeriodBlockSeconds=300`). Đã hardening script + config:
> - `scripts/common/env.sh` thêm `ORC_INSTANCE_POLL_SECONDS=1`, `ORC_RECOVERY_BLOCK_SECONDS=60` (lab defaults).
> - `07-force-failover-test.sh` thêm `ack-all-recoveries` trước halt và `force-master-failover` belt-and-braces sau 60s không tự promote.
>
> Lần chạy tiếp với config mới kỳ vọng PROMOTE_RTO < 30s.

## 5. Quan sát & nhận xét

### Điểm tốt
- Graceful switchover (`graceful-master-takeover`) cực nhanh — 7s, app downtime ~0 nếu retry connection.
- Web UI hiển thị topology dạng tree rất rõ ràng, dễ debug cho ops.
- API REST đầy đủ — dễ tích hợp Slack/PagerDuty hook qua `PreFailoverProcesses`/`PostFailoverProcesses`.
- Tự rebuild config replica (`CHANGE REPLICATION SOURCE`) cho node còn sống — không cần can thiệp manual.

### Hạn chế
- Force failover mặc định chậm (~4-5 phút) vì anti-flapping + multi-stage validation. Phải tune mới phù hợp demo.
- Single Orchestrator instance trên mgmt = SPOF cho control plane. Production cần Raft 3-node.
- Không hỗ trợ Group Replication / Galera native — chỉ async/semi-sync.
- Backend MySQL trên mgmt: nếu mgmt host fail, mất historical recovery audit (giải quyết bằng Raft hoặc external backend).
- Config bug: orchestrator-setup.sh ban đầu lỗi `CREATE USER` qua mysql -h<IP> vì root@localhost only. Đã fix bằng SSH vào DB node (memory: orchestrator-setup pattern).

### Câu hỏi mở
- PostFailoverProcesses hook để update ProxySQL `mysql_servers` writer hostgroup tự động — workflow như thế nào?
- Raft 3-node: overhead 2 mgmt hosts thêm có đáng cho UX HA cho chính Orchestrator?
- Khi nào nên dùng `force-master-failover` API thay vì để Orchestrator tự detect? (Network partition giả mạo gửi tín hiệu sai)

## 6. Bằng chứng (từ log)

### B3 — Discover (lần 2 thành công)
```
192.168.10.11:3306   [0s,ok,8.0.46,rw,ROW,>>,GTID]
+ 192.168.10.12:3306 [0s,ok,8.0.46,ro,ROW,>>,GTID]
+ 192.168.10.13:3306 [0s,ok,8.0.46,ro,ROW,>>,GTID]
which-cluster-master = 192.168.10.11:3306
```

### B6 — Graceful switchover
```
graceful-master-takeover -i 192.168.10.11:3306 -d 192.168.10.12:3306
→ xong sau 7s
which-master = 192.168.10.12:3306
INSERT vào node2 OK (read_only=0)
Topology: node2 [rw], node1 [downtimed], node3 [ro]
```

### B7 — Force failover (halt --force node2)
```
Halt 16:29:54
DeadMaster detected qua replication-analysis
NEW MASTER = 192.168.10.13 (node3) sau 263s
node1 Source_Host = 192.168.10.13
node3 chấp nhận INSERT sau 276s
FAILOVER_PASS=true PROMOTE_RTO=263s WRITE_RTO=276s
```

## 7. Bước tiếp theo

- [ ] **Chạy lại B7 với config mới** (ORC_INSTANCE_POLL_SECONDS=1, ORC_RECOVERY_BLOCK_SECONDS=60) — kỳ vọng PROMOTE_RTO < 30s.
- [ ] Cấu hình PostFailoverProcesses hook update ProxySQL (demo 07) → eliminate writer hostgroup manual update.
- [ ] Deploy Raft 3-node Orchestrator (cần thêm 2 mgmt hosts) — verify HA cho chính Orchestrator.
- [ ] Test detection edge cases: `UnreachableMaster` (block port 3306, không halt VM), `DeadIntermediateMaster` (kill replica trung gian).
- [ ] So sánh head-to-head với MHA (demo 04) trên cùng nền semi-sync.


---

!!! info "Nguồn gốc"
    `HA/Mysql/demo/05-orchestrator/results/report.md`
