---
title: 00 — Tổng quan bài demo
course: 06-high-availability
source: HA/Mysql/demo/05-orchestrator/00-overview.md
---

# 00 — Tổng quan bài demo

## Mục tiêu

Chứng minh giải pháp HA **Orchestrator** cho async/semi-sync MySQL 8.0:
1. Cài Orchestrator + Orchestrator-client trên mgmt host.
2. Tạo backend MySQL DB (orchestrator schema) trên local MySQL của mgmt.
3. Tạo user `orchestrator@<mgmt_ip>` trên 3 DB nodes với SUPER+PROCESS+REPLICATION SLAVE+RELOAD.
4. Discover topology, verify cluster đã được nhận dạng đúng.
5. Demo graceful switchover (planned, không destroy).
6. Demo force failover (halt master → auto recovery + đo PROMOTE_RTO).

## Kiến trúc

- **Orchestrator daemon (mgmt)**: Go binary, listen :3000 (HTTP API + Web UI).
- **Backend store**: MySQL DB `orchestrator` trên local mysql của mgmt host (cùng instance MySQL Demo 01 dùng mgmt làm client). Lưu metadata topology, anti-flapping state.
- **Discovery**: Orchestrator dùng `SHOW SLAVE HOSTS` + `SHOW REPLICA STATUS` để xây dựng topology tree tự động.
- **Failover**: `RecoverMasterClusterFilters=["*"]` + `ApplyMySQLPromotionAfterMasterFailover=true` → tự promote không cần can thiệp.

## Phạm vi demo

| Có | Không |
|----|-------|
| Auto-detect topology, auto-failover | Group Replication / Galera (Orchestrator chỉ async/semi-sync) |
| Web UI dragging topology | Raft HA cho chính Orchestrator (cần 3 mgmt hosts) |
| Graceful + force failover | TLS/SSL channel |
| Pre/PostFailover hooks (echo log demo) | Hooks production (Slack/PagerDuty/Consul) |

## Tiêu chí thành công

| # | Tiêu chí | Cách kiểm tra |
|---|----------|---------------|
| 1 | Demo 01 đã chạy thành công | `bash 01-precheck.sh` báo PASS |
| 2 | orchestrator service active | `systemctl is-active orchestrator` |
| 3 | Web UI :3000 trả 200 | `curl -u admin:<pwd> http://mgmt:3000/api/health` |
| 4 | Topology được discover đúng | `orchestrator-client -c topology` show 3 node với đúng quan hệ |
| 5 | Replication health = OK | `orchestrator-client -c which-cluster-instances` |
| 6 | Graceful switchover thành công (master cũ → master mới) | `which-master` đổi |
| 7 | Force failover sau halt: PROMOTE_RTO ≤ 30s | `07-force-failover-test.sh` log |
| 8 | Replica còn lại tự CHANGE SOURCE về master mới | `SHOW REPLICA STATUS\G` |

## Thời gian ước tính

| Pha | Thời gian |
|-----|-----------|
| Precheck Demo 01 | 30s |
| Install + backend setup | 2 phút |
| Discover topology | 30s |
| Verify + smoke test | 1 phút |
| Graceful failover | 1 phút |
| Force failover demo | 2 phút |
| **Tổng** | **~7–10 phút** (chưa kể Demo 01) |

## Lưu ý

- Orchestrator KHÔNG hỗ trợ Group Replication / Galera. Cluster GR phải dùng `mysqlsh` (InnoDB Cluster) hoặc tự code monitoring.
- Mặc định Orchestrator backend dùng MySQL local — production nên dùng SQLite hoặc external MySQL HA (vd Galera).
- `RecoveryPeriodBlockSeconds=300` chống flapping — script demo sẽ override khi cần test nhanh.


---

!!! info "Nguồn gốc"
    `HA/Mysql/demo/05-orchestrator/00-overview.md`
