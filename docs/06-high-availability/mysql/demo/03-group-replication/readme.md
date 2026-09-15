---
title: Demo 03 — Group Replication thuần (Vagrant Lab)
course: 06-high-availability
source: HA/Mysql/demo/03-group-replication/README.md
---

# Demo 03 — Group Replication thuần (Vagrant Lab)

Bộ kịch bản end-to-end dựng cụm **Group Replication (GR) cấu hình thuần** — không qua `mysqlsh dba.*` wrapper, không dùng MySQL Router. Bạn tự `START GROUP_REPLICATION` bằng SQL, tự chọn proxy (ProxySQL/HAProxy hoặc app tự retry).

> Tham chiếu runbook gốc: [../../runbooks/03-group-replication.md](../../runbooks/003-group-replication.md)
> Topology: xem [../../scripts/common/env.sh](../../scripts/common/env.sh)

## Khi nào chọn demo này thay vì Demo 02 (InnoDB Cluster)

| Tiêu chí | Demo 03 (GR thuần) | Demo 02 (InnoDB Cluster) |
|---|---|---|
| Control plane | SQL trực tiếp | `mysqlsh dba.*` JS API |
| Tự sinh user `clusteradmin` | Phải tạo tay | Wrapper tự sinh |
| Metadata schema | Không | `mysql_innodb_cluster_metadata` |
| Proxy mặc định | Tự chọn (ProxySQL ở Demo 07) | MySQL Router |
| Phù hợp tự động hoá | Ansible/Puppet/Terraform | Tools fluent với mysqlsh |

## Topology demo

| Host  | IP             | Vai trò                       | RAM    | server_id |
|-------|----------------|-------------------------------|--------|-----------|
| node1 | 192.168.10.11  | GR member — Primary (bootstrap) | 2 GB | 1         |
| node2 | 192.168.10.12  | GR member — Secondary         | 2 GB   | 2         |
| node3 | 192.168.10.13  | GR member — Secondary         | 2 GB   | 3         |
| mgmt  | 192.168.10.20  | Client / observer (chưa cài proxy) | 1 GB | — |

```
                                ┌─────────┐
                       App ────▶│  mgmt   │ mysql client (test trực tiếp)
                                └─────────┘
                                     │
                ┌────────────────────┼────────────────────┐
                ▼                    ▼                    ▼
          ┌──────────┐         ┌──────────┐         ┌──────────┐
          │  node1   │ ◀─33061─▶  node2   │ ◀─33061─▶  node3   │
          │   3306   │         │   3306   │         │   3306   │
          └──────────┘         └──────────┘         └──────────┘
              └──── Group Replication (Paxos consensus) ────┘
```

## Yêu cầu host

- Windows 10/11 + PowerShell 5+ **hoặc** macOS / Linux + bash
- [Vagrant ≥ 2.3](https://www.vagrantup.com/downloads), [VirtualBox ≥ 7.0](https://www.virtualbox.org/wiki/Downloads)
- RAM host ≥ 8 GB (4 VMs), disk trống ≥ 25 GB

## Cấu trúc demo

| Bước | Shell script | Chạy ở đâu | Vai trò |
|------|--------------|------------|---------|
| 0 | [00-overview.md](000-overview.md) | (đọc) | Mục tiêu, kiến trúc |
| 1 | [01-vagrant-up.sh](01-vagrant-up.sh) | Host | Spin up 4 VMs |
| 2 | [02-prepare-os.sh](02-prepare-os.sh) | Host → 4 VMs | hosts/swap/sysctl/NTP |
| 3 | [03-install-mysql.sh](03-install-mysql.sh) | Host → 3 DB VMs | MySQL 8.0 community |
| 4 | [04-primary-setup.sh](04-primary-setup.sh) | Host → node1 | Bootstrap group trên node1 |
| 5 | [05-secondary-setup.sh](05-secondary-setup.sh) | Host → node2,3 | Join 2 node còn lại |
| 6 | [06-verify.sh](06-verify.sh) | Host | replication_group_members, GTID |
| 7 | [07-smoke-test.sh](07-smoke-test.sh) | Host | INSERT primary, SELECT 3 node |
| 8 | [08-failover-test.sh](08-failover-test.sh) | Host | halt primary → auto election |
| 9 | [09-rollback.sh](09-rollback.sh) | Host | STOP GR + xoá config |

## Chạy nhanh — end-to-end

```bash
cd demo/03-group-replication
bash run-all.sh      # Linux/macOS/WSL/Git Bash
# hoặc
.\run-all.ps1        # Windows PowerShell
```

`run-all` thực hiện **B1 → B7**. **B8 (failover)** và **B9 (rollback)** chạy thủ công vì destructive.

## Chạy thủ công (copy/paste từng câu lệnh)

Nếu không thể chạy `run-all` (không có Git Bash, muốn hiểu rõ từng bước, hoặc demo trên máy không có Vagrant), đọc **[MANUAL-SETUP.md](manual-setup.md)** — ghi lại từng lệnh CLI/SQL + nội dung file config + verify cụ thể, kèm phụ lục trouble-shooting các lỗi đã gặp trong test thực tế (Vagrant 2-NIC, ip_allowlist, IP-vs-hostname mismatch).

## Sự khác biệt so với Demo 02

| Khía cạnh | Demo 02 (InnoDB Cluster) | Demo 03 (GR thuần) |
|-----------|--------------------------|---------------------|
| Setup node | `dba.configureInstance()` auto fix my.cnf | Phải tự ghi `zz-group-replication.cnf` |
| Bootstrap | `dba.createCluster()` | `SET group_replication_bootstrap_group=ON; START GROUP_REPLICATION;` |
| Add node | `cluster.addInstance({recoveryMethod:'clone'})` | `START GROUP_REPLICATION` + GTID auto-position (recovery channel) |
| Status | `cluster.status()` JSON | `SELECT * FROM performance_schema.replication_group_members;` |
| Proxy | MySQL Router 6446/6447 | Tự chọn ProxySQL (Demo 07) hoặc HAProxy |
| Failover endpoint | Tự động qua Router | App phải nhận biết primary mới (qua proxy hoặc connection retry) |

## Output & báo cáo

- `results/06-verify.log` — replication_group_members + GTID sync
- `results/07-smoke-test.log` — write trên primary, đọc trên secondaries
- `results/08-failover.log` — halt primary, đợi election, đo PROMOTE_RTO
- `results/report.md` — template báo cáo demo

## Tham khảo
- Runbook gốc: [runbooks/03-group-replication.md](../../runbooks/003-group-replication.md)
- MySQL Group Replication: https://dev.mysql.com/doc/refman/8.0/en/group-replication.html


---

!!! info "Nguồn gốc"
    `HA/Mysql/demo/03-group-replication/README.md`
