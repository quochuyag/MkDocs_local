---
title: Runbook 00 — Overview & lựa chọn giải pháp
course: 06-high-availability
source: HA/Mysql/runbooks/00-overview.md
---

# Runbook 00 — Overview & lựa chọn giải pháp

## 1. Matrix so sánh

| Đặc tính | Async/SS | InnoDB Cluster | GR thuần | MHA | Orchestrator | Galera (PXC) | ProxySQL |
|---|---|---|---|---|---|---|---|
| Loại | Replication | GR + Router | GR | Failover manager | Failover manager | Sync multi-master | Proxy |
| Min nodes | 2 | 3 | 3 | 1 manager + 2 DB | 1 (3 raft) + ≥2 DB | 3 | 1 (≥2 cho HA) |
| Data plane | Async/Semi-sync | Group Replication | Group Replication | Async/Semi-sync | Async/Semi-sync | Sync (cert-based) | — (proxy) |
| Tự auto-failover | Không | Có | Có | Có | Có | Không cần (multi-master) | Không cần (route lại) |
| Đọc/ghi từ nhiều node | Read replica | RO via Router 6447 | Có (multi-primary) | Read replica | Read replica | Mọi node writable | R/W split |
| Có hỗ trợ Oracle | Có (official) | Có (official) | Có (official) | Không | Cộng đồng | Percona/MariaDB | Cộng đồng |
| Phù hợp WAN | Tốt | Trung bình | Trung bình | Tốt | Tốt | Kém (latency) | Tốt |
| Setup phức tạp | ★ | ★★ | ★★★ | ★★★ | ★★ | ★★ | ★★ |

## 2. Cây quyết định

```
Bạn cần HA cho MySQL?
├─ Có 1 master + N replicas, OK với failover thủ công?
│   └─ Async/Semi-sync (Runbook 01)
│
├─ Có 1 master + N replicas, cần auto-failover?
│   ├─ Stack legacy, không muốn UI → MHA (Runbook 04)
│   └─ Stack mới → Orchestrator (Runbook 05)
│
├─ Cần cluster MySQL 8.0 native, app tránh logic failover?
│   ├─ Muốn full official stack → InnoDB Cluster (Runbook 02)
│   └─ Muốn full control, dùng ProxySQL → Group Replication thuần (Runbook 03)
│
├─ Cần multi-master, mọi node writable, latency LAN thấp?
│   └─ Galera / Percona XtraDB Cluster (Runbook 06)
│
└─ Cần R/W split, connection pool, query routing?
    └─ ProxySQL — ghép phía trên một backend HA bất kỳ (Runbook 07)
```

## 3. Khuyến nghị production

| Use case | Stack đề xuất |
|---|---|
| OLTP medium scale, 1 region | InnoDB Cluster + ProxySQL (R/W split) |
| OLTP với app sẵn replication | Semi-sync + Orchestrator + ProxySQL |
| Legacy MySQL 5.7 chưa upgrade | Semi-sync + MHA + Keepalived VIP |
| Multi-DC active-active LAN | Galera (PXC) + ProxySQL |
| Multi-region DR | InnoDB ClusterSet (primary cluster + async secondary cluster) |

## 4. Chiến lược ramp

1. **Lab**: chạy theo thứ tự runbooks 01 → 02 → 06 → 07 trên VM/Docker để hiểu trade-off.
2. **Staging**: chọn 1 stack, chạy backup/restore test + chaos test (kill master, partition mạng).
3. **Pre-prod**: load test cho throughput + failover thời gian.
4. **Production**: rollout từng region, có observability (Prometheus + mysqld_exporter) + alerting.

## 5. Workflow demo (fresh lab)

Mỗi demo trong `demo/01..08` tự destroy lab cũ rồi rebuild trước khi chạy. Mục đích: tránh state leakage giữa các giải pháp HA (vd Galera ↔ MySQL community không tương thích trên cùng host).

| Demo | Bootstrap chain (default) | Env vars để skip |
|------|---------------------------|------------------|
| 01 Async/Semi-Sync | destroy → up → prep → install → master/replica setup | `KEEP_VMS=1` |
| 02 InnoDB Cluster | destroy → up → prep → install → cluster bootstrap | `KEEP_VMS=1` |
| 03 GR thuần | destroy → up → prep → install → primary/secondary setup | `KEEP_VMS=1` |
| 04 MHA | demo 01 full → MHA install + verify + VIP | `BOOTSTRAP_DEMO01=0` |
| 05 Orchestrator | demo 01 full → Orchestrator install + discover + verify | `BOOTSTRAP_DEMO01=0` |
| 06 Galera (PXC) | destroy → up → prep → install PXC → bootstrap + join | `KEEP_VMS=1` |
| 07 ProxySQL | demo 01 (default) hoặc 06 (BACKEND=galera) → ProxySQL setup | `BOOTSTRAP_BACKEND=0` |
| 08 Vagrant Lab | destroy → up → prep → ssh-trust → verify | `KEEP_VMS=1` |

> Thời gian từ scratch: ~15-20' (demo 01/03/08), ~25-30' (demo 02/06), ~30-40' (demo 04/05/07 — cộng bootstrap nền).

## 6. Observability mặc định

Mọi runbook giả định bạn sẽ thêm:
- **mysqld_exporter** (Prometheus) trên mỗi DB node.
- **proxysql_exporter** nếu dùng ProxySQL.
- Grafana dashboards: MySQL Overview (ID 7362), Galera (8627), ProxySQL (12555).
- Alert: `mysql_up == 0`, `Seconds_Behind_Source > 60`, `wsrep_local_state_comment != "Synced"`, `replication_group_member_state != "ONLINE"`.


---

!!! info "Nguồn gốc"
    `HA/Mysql/runbooks/00-overview.md`
