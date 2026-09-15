---
title: Demo 05 — Orchestrator (openark/orchestrator)
course: 06-high-availability
source: HA/Mysql/demo/05-orchestrator/README.md
---

# Demo 05 — Orchestrator (openark/orchestrator)

Bộ kịch bản end-to-end dựng cụm **Async/Semi-sync + Orchestrator** trên Vagrant. Orchestrator (Go) là replication topology manager — phát hiện topology tự động, anti-flapping, multi-mode failure detection, Web UI port 3000.

> Tham chiếu runbook gốc: [../../runbooks/05-orchestrator.md](../../runbooks/005-orchestrator.md)
> **Tiền đề**: cần chạy [Demo 01](../01-async-semisync/) trước (semi-sync replication).
> Topology: xem [../../scripts/common/env.sh](../../scripts/common/env.sh)

## Topology demo

| Host  | IP             | Vai trò                            | RAM    |
|-------|----------------|------------------------------------|--------|
| node1 | 192.168.10.11  | MySQL Master (RW)                  | 2 GB   |
| node2 | 192.168.10.12  | MySQL Replica (RO)                 | 2 GB   |
| node3 | 192.168.10.13  | MySQL Replica (RO)                 | 2 GB   |
| mgmt  | 192.168.10.20  | Orchestrator daemon + MySQL backend (orchestrator DB) | 1.5 GB |

```
                       ┌─────────────────────────────┐
        Browser ─────▶ │  Web UI :3000 (basic auth)  │
                       │  mgmt 192.168.10.20         │
                       │  Orchestrator (Go daemon)   │
                       └──────────────┬──────────────┘
                                      │ MySQL TCP, SHOW SLAVE HOSTS, raft-style probes
       ┌──────────────────────────────┼──────────────────────────────┐
       ▼                              ▼                              ▼
   node1 (master)                node2 (replica)                node3 (replica)
       └──── async/semi-sync replication (Demo 01) ──────┘
```

## Khi master chết

1. Orchestrator phát hiện (qua `InstancePollSeconds=5s`).
2. Anti-flapping cooldown `RecoveryPeriodBlockSeconds` (default 300s).
3. PreFailover hooks chạy (vd `curl https://alerts.internal/...`).
4. Chọn replica có position cao nhất, promote.
5. ApplyMySQLPromotionAfterMasterFailover=true → `SET read_only=0; STOP REPLICA; RESET REPLICA ALL`.
6. PostFailover hooks chạy (vd move VIP, update ProxySQL writer hostgroup).

## Yêu cầu host

- Vagrant ≥ 2.3, VirtualBox ≥ 7.0
- RAM host ≥ 8 GB, disk ≥ 25 GB
- **Đã chạy Demo 01** — cụm semi-sync sẵn sàng

## Cấu trúc demo

| Bước | Shell script | Chạy ở đâu | Vai trò |
|------|--------------|------------|---------|
| 0 | [00-overview.md](000-overview.md) | (đọc) | Mục tiêu, kiến trúc |
| 1 | [01-precheck.sh](01-precheck.sh) | Host | Kiểm tra Demo 01 sẵn sàng |
| 2 | [02-orchestrator-install.sh](02-orchestrator-install.sh) | Host → mgmt | Cài binary + tạo backend DB + tạo user trên 3 DB nodes |
| 3 | [03-discover-topology.sh](03-discover-topology.sh) | Host → mgmt | `orchestrator-client -c discover` → vẽ topology |
| 4 | [04-verify.sh](04-verify.sh) | Host | API health, topology JSON, replication health |
| 5 | [05-smoke-test.sh](05-smoke-test.sh) | Host | Write trên master, đọc trên 2 replica, đo lag |
| 6 | [06-graceful-failover.sh](06-graceful-failover.sh) | Host | Planned switchover (không destroy) qua API |
| 7 | [07-force-failover-test.sh](07-force-failover-test.sh) | Host | halt master → đo PROMOTE_RTO |
| 8 | [08-rollback.sh](08-rollback.sh) | Host | Stop daemon, drop schema, optional destroy VMs |

## Chạy nhanh — end-to-end

```bash
cd demo/05-orchestrator
bash run-all.sh      # Linux/macOS/WSL/Git Bash
.\run-all.ps1        # Windows PowerShell
```

`run-all` thực hiện **B1 → B5** + **B6 (graceful)** (an toàn, không destroy). **B7 (force failover)** chạy thủ công.

## Web UI

Sau B2: http://192.168.10.20:3000 — login `admin / ChangeMe!Admin#2026` (ADMIN_PWD trong env.sh).

## Output & báo cáo

- `results/04-verify.log` — topology JSON, replication health
- `results/06-graceful-failover.log` — planned switchover trace
- `results/07-force-failover.log` — destructive failover + RTO
- `results/report.md` — template báo cáo demo

## Tham khảo
- Runbook gốc: [runbooks/05-orchestrator.md](../../runbooks/005-orchestrator.md)
- Orchestrator wiki: https://github.com/openark/orchestrator/wiki


---

!!! info "Nguồn gốc"
    `HA/Mysql/demo/05-orchestrator/README.md`
