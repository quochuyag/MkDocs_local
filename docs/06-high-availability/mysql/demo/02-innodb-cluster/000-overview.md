---
title: 00 — Tổng quan bài demo
course: 06-high-availability
source: HA/Mysql/demo/02-innodb-cluster/00-overview.md
---

# 00 — Tổng quan bài demo

## Mục tiêu

Chứng minh giải pháp HA **MySQL InnoDB Cluster** trên MySQL 8.0:
1. Dựng được cụm 3 DB node + 1 mgmt host trong môi trường ảo hoá.
2. Đưa MySQL về trạng thái sẵn sàng cho Group Replication (GTID, log_bin, clusterAdmin user).
3. Bootstrap cluster bằng `mysqlsh dba.createCluster()` + add 2 nodes còn lại bằng **Clone Plugin**.
4. Triển khai **MySQL Router** trên mgmt: expose 1 endpoint duy nhất cho ứng dụng (`:6446` RW, `:6447` RO).
5. Chứng minh **data đồng bộ** giữa 3 node qua Group Replication (smoke test).
6. Chứng minh **auto failover trong suốt với app** — halt primary, Router tự route sang primary mới.

## Kiến trúc

- **Group Replication (data plane)**: 3 node đồng thuận theo Paxos-like protocol. Mặc định **single-primary mode** — chỉ 1 node ghi, 2 node còn lại `super_read_only=ON`. Khi primary chết, group tự bầu primary mới trong vài giây.
- **MySQL Shell + `dba.*` API (control plane)**: cấu hình instance, quản lý cluster, rejoin/dissolve. Tránh phải `CHANGE REPLICATION SOURCE ...` thủ công.
- **MySQL Router (proxy)**: bootstrap từ cluster metadata, listen `:6446` cho RW (route đến primary), `:6447` cho RO (round-robin secondaries). Tự cập nhật khi topology đổi.
- **Clone Plugin**: khi add một node mới, Router/Shell yêu cầu donor copy snapshot toàn bộ database → không cần xtrabackup hay dump tay.

## Phạm vi demo

| Có | Không |
|----|-------|
| Setup cluster, smoke test, auto failover | Multi-primary mode (không khuyến nghị production) |
| Group Replication + MySQL Shell + Router | ClusterSet (replication giữa nhiều cluster) |
| Vagrant + VirtualBox + Ubuntu 22.04 | Multi-cloud / production sizing |
| Clone-based recovery | Backup/restore qua xtrabackup |
| Mock data smoke test | Benchmark hiệu năng |

## Tiêu chí thành công

| # | Tiêu chí | Cách kiểm tra |
|---|----------|---------------|
| 1 | 4 VM up, ping được nhau qua IP private | `vagrant status`, `ping node2` từ node1 |
| 2 | MySQL 8.0 chạy trên 3 DB nodes, plugin Clone + mysql-shell có sẵn | `SELECT @@version;`, `SHOW PLUGINS` |
| 3 | `gtid_mode=ON`, `enforce_gtid_consistency=ON`, `binlog_format=ROW` | `SELECT @@gtid_mode,@@enforce_gtid_consistency,@@binlog_format;` |
| 4 | Cluster có 1 PRIMARY + 2 SECONDARY, tất cả `ONLINE` | `dba.getCluster().status()` |
| 5 | MySQL Router service active, listen 6446 + 6447 | `systemctl status mysqlrouter`, `ss -tlnp` |
| 6 | App connect qua `mgmt:6446` → ra primary; `mgmt:6447` → ra secondary | `mysql -h mgmt -P 6446 -e "SELECT @@hostname"` |
| 7 | INSERT qua Router → SELECT trên cả 3 node trong < 1s | smoke test |
| 8 | Sau khi `vagrant halt <primary>`, cluster tự bầu primary mới, Router reroute, app KHÔNG cần đổi IP | failover test |

## Thời gian ước tính

| Pha | Thời gian |
|-----|-----------|
| `vagrant up` (lần đầu, tải box) | 10–15 phút |
| Prepare OS | 2 phút |
| Install MySQL (3 DB nodes) | 5–8 phút (tải gói APT) |
| Node-setup (configureInstance + restart) | 2–3 phút |
| Bootstrap cluster + add 2 instances (clone) | 3–5 phút |
| Router setup (cài + bootstrap trên mgmt) | 2 phút |
| Verify + smoke test | 1 phút |
| Failover demo | 2 phút |
| **Tổng cộng** | **~30–40 phút** |

## Sơ đồ luồng

```
Host (Vagrant)
   │
   ├── vagrant up         → 4 VMs (B1)
   ├── prepare-os         → /etc/hosts, swap off, NTP (B2)
   ├── install-mysql      → mysql-server + shell + router (B3, chỉ db nodes)
   ├── node-setup         → configureInstance trên 3 db nodes (B4)
   ├── cluster-bootstrap  → mysqlsh dba.createCluster + addInstance (B5)
   ├── router-setup       → cài + bootstrap mysql-router trên mgmt (B6)
   ├── verify             → cluster.status() = 1 PRIMARY + 2 SECONDARY ONLINE (B7)
   ├── smoke-test         → write qua Router :6446, read :6447 (B8)
   ├── failover-test      → halt primary, Router tự route lại (B9, manual)
   └── rollback           → dissolve + uninstall router (B10, manual)
```


---

!!! info "Nguồn gốc"
    `HA/Mysql/demo/02-innodb-cluster/00-overview.md`
