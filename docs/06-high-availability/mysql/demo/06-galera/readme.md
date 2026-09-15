---
title: Demo 06 — Galera Cluster (Percona XtraDB Cluster 8.0)
course: 06-high-availability
source: HA/Mysql/demo/06-galera/README.md
---

# Demo 06 — Galera Cluster (Percona XtraDB Cluster 8.0)

Bộ kịch bản end-to-end dựng cụm **Galera multi-master** trên Vagrant. Mọi node đều writable, replication đồng bộ (cert-based) — không có replication lag, không cần failover.

> Tham chiếu runbook gốc: [../../runbooks/06-galera-cluster.md](../../runbooks/006-galera-cluster.md)
> **QUAN TRỌNG**: PXC thay thế HẲN MySQL community → **KHÔNG** dùng `scripts/common/01-install-mysql.sh`. Demo này cài PXC thẳng.
> Topology: xem [../../scripts/common/env.sh](../../scripts/common/env.sh)

## Topology demo

| Host  | IP             | Vai trò                   | RAM    |
|-------|----------------|---------------------------|--------|
| node1 | 192.168.10.11  | PXC member (bootstrap)    | 2 GB   |
| node2 | 192.168.10.12  | PXC member (joiner)       | 2 GB   |
| node3 | 192.168.10.13  | PXC member (joiner)       | 2 GB   |
| mgmt  | 192.168.10.20  | mysql-client (test)       | 1 GB   |

```
            App ──▶ Bất kỳ node nào (writable)
                    │
       ┌────────────┼────────────┐
       ▼            ▼            ▼
   ┌──────┐     ┌──────┐     ┌──────┐
   │node1 │ ◀── 4567 ──▶ │node2 │ ◀── 4567 ──▶ │node3 │
   │ 3306 │      gcomm   │ 3306 │      gcomm   │ 3306 │
   └──────┘     └──────┘     └──────┘
        └──── synchronous (cert-based) replication ────┘
   Ports khác: 4444 (SST), 4568 (IST)
```

## Yêu cầu host

- Vagrant ≥ 2.3, VirtualBox ≥ 7.0
- RAM host ≥ 8 GB, disk ≥ 30 GB (PXC + xtrabackup binaries)
- Network LAN ≤ 5ms latency (Galera consensus)

## Cấu trúc demo

| Bước | Shell script | Chạy ở đâu | Vai trò |
|------|--------------|------------|---------|
| 0 | [00-overview.md](000-overview.md) | (đọc) | Mục tiêu, kiến trúc |
| 1 | [01-vagrant-up.sh](01-vagrant-up.sh) | Host | Spin up 4 VMs |
| 2 | [02-prepare-os.sh](02-prepare-os.sh) | Host → 4 VMs | hosts/swap/sysctl/NTP |
| 3 | [03-install-pxc.sh](03-install-pxc.sh) | Host → 3 DB VMs | Cài Percona XtraDB Cluster 8.0 (KHÔNG dùng install-mysql.sh!) |
| 4 | [04-bootstrap-node1.sh](04-bootstrap-node1.sh) | Host → node1 | `systemctl start mysql@bootstrap.service` |
| 5 | [05-join-node2-node3.sh](05-join-node2-node3.sh) | Host → node2,3 | `systemctl start mysql` → SST từ donor |
| 6 | [06-verify.sh](06-verify.sh) | Host | `wsrep_cluster_size=3, _comment=Synced, _status=Primary` |
| 7 | [07-smoke-test.sh](07-smoke-test.sh) | Host | Insert song song trên 3 node + verify consistency |
| 8 | [08-split-brain-test.sh](08-split-brain-test.sh) | Host | Halt 2 node → còn 1 node sẽ STOP write (non-Primary) |
| 9 | [09-rollback.sh](09-rollback.sh) | Host | Stop mysql + uninstall PXC + optional destroy VMs |

## Chạy nhanh — end-to-end

```bash
cd demo/06-galera
bash run-all.sh      # Linux/macOS/WSL/Git Bash
.\run-all.ps1        # Windows PowerShell
```

`run-all` thực hiện **B1 → B7**. **B8 (split-brain)** và **B9 (rollback)** thủ công vì destructive.

## Sự khác biệt với các demo khác

| Khía cạnh | Demo 06 (Galera) | Demo 02 (InnoDB Cluster) | Demo 01 (Async) |
|-----------|------------------|--------------------------|------------------|
| Replication | Synchronous (cert-based) | Async (GR-Paxos) | Async/Semi-sync |
| Write target | **Mọi node** | Chỉ 1 PRIMARY | Chỉ 1 master |
| Auto failover | Không cần (multi-master) | Có | Không (manual) |
| Replication lag | 0 (đồng bộ) | gần 0 (Paxos) | có thể >1s |
| Yêu cầu PK | **Bắt buộc** | Bắt buộc | Khuyến nghị |
| WAN-friendly | **Không** | Trung bình | Tốt |
| Package | percona-xtradb-cluster | mysql-server-8.0 | mysql-server-8.0 |

## Output & báo cáo

- `results/06-verify.log` — wsrep_* checkpoints
- `results/07-smoke-test.log` — write multi-node + consistency check
- `results/08-split-brain.log` — minority partition behavior
- `results/report.md` — template báo cáo

## Tham khảo
- Runbook gốc: [runbooks/06-galera-cluster.md](../../runbooks/006-galera-cluster.md)
- PXC docs: https://www.percona.com/doc/percona-xtradb-cluster/8.0/index.html
- Galera Cluster: https://galeracluster.com/library/documentation/


---

!!! info "Nguồn gốc"
    `HA/Mysql/demo/06-galera/README.md`
