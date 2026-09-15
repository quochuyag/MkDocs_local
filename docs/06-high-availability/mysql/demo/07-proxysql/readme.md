---
title: Demo 07 — ProxySQL (R/W split + connection pool)
course: 06-high-availability
source: HA/Mysql/demo/07-proxysql/README.md
---

# Demo 07 — ProxySQL (R/W split + connection pool)

Bộ kịch bản end-to-end cài **ProxySQL 2.6** trên mgmt và ghép với một backend HA. ProxySQL là L7 proxy — connection pooling, R/W split, query routing, query cache. **Không** phải HA solution độc lập — luôn cần 1 backend HA (Demo 01/02/03/06).

> Tham chiếu runbook gốc: [../../runbooks/07-proxysql.md](../../runbooks/007-proxysql.md)
> **Tiền đề**: phải có 1 trong các backend đã chạy thành công:
>   - **Demo 01** (async/semi-sync) — script default mode `BACKEND=async-semisync`
>   - **Demo 06** (Galera/PXC) — chạy với `BACKEND=galera`
>
> Topology: xem [../../scripts/common/env.sh](../../scripts/common/env.sh)

## Topology demo

| Host  | IP             | Vai trò                                       | RAM    |
|-------|----------------|-----------------------------------------------|--------|
| node1 | 192.168.10.11  | MySQL backend (master / PXC writer)           | 2 GB   |
| node2 | 192.168.10.12  | MySQL backend (replica / PXC member)          | 2 GB   |
| node3 | 192.168.10.13  | MySQL backend (replica / PXC member)          | 2 GB   |
| mgmt  | 192.168.10.20  | ProxySQL daemon (admin:6032 / SQL:6033)       | 1.5 GB |

```
                       App
                        │
              ┌─────────▼──────────┐
              │   ProxySQL :6033   │ (R/W split via query rules)
              │   admin :6032      │
              └────┬──────────┬────┘
       writer HG10 │          │ reader HG20 (round-robin)
                   ▼          ▼
            ┌─────────┐   ┌──────────┐
            │  node1  │   │  node2/3 │
            └─────────┘   └──────────┘
```

## Cấu trúc demo

| Bước | Shell script | Chạy ở đâu | Vai trò |
|------|--------------|------------|---------|
| 0 | [00-overview.md](000-overview.md) | (đọc) | Mục tiêu, kiến trúc |
| 1 | [01-precheck.sh](01-precheck.sh) | Host | Kiểm tra backend (async/galera) đã chạy |
| 2 | [02-install-proxysql.sh](02-install-proxysql.sh) | Host → mgmt | Cài ProxySQL + monitor user + app user trên 3 DB |
| 3 | [03-configure-galera.sh](03-configure-galera.sh) | Host → mgmt | (chỉ khi BACKEND=galera) Setup `mysql_galera_hostgroups` |
| 4 | [04-verify.sh](04-verify.sh) | Host | runtime_mysql_servers status, connect test :6033 |
| 5 | [05-smoke-test.sh](05-smoke-test.sh) | Host | Insert/Select qua :6033, verify R/W split |
| 6 | [06-failover-demo.sh](06-failover-demo.sh) | Host | Halt 1 backend → ProxySQL tự re-route |
| 7 | [07-rollback.sh](07-rollback.sh) | Host | Stop daemon, drop config |

## Chạy nhanh — end-to-end

```bash
# Mặc định backend là Demo 01 (async/semi-sync)
cd demo/07-proxysql
bash run-all.sh

# Hoặc với Galera backend (Demo 06)
BACKEND=galera bash run-all.sh
```

## Output & báo cáo

- `results/04-verify.log` — ProxySQL admin queries, status
- `results/05-smoke-test.log` — R/W split verification
- `results/06-failover.log` — backend failover behaviour
- `results/report.md` — template báo cáo

## Tham khảo
- Runbook gốc: [runbooks/07-proxysql.md](../../runbooks/007-proxysql.md)
- ProxySQL docs: https://proxysql.com/documentation/


---

!!! info "Nguồn gốc"
    `HA/Mysql/demo/07-proxysql/README.md`
