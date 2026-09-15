---
title: 00 — Tổng quan bài demo
course: 06-high-availability
source: HA/Mysql/demo/07-proxysql/00-overview.md
---

# 00 — Tổng quan bài demo

## Mục tiêu

Chứng minh giải pháp **ProxySQL** ghép trên một backend HA:
1. Cài ProxySQL 2.6 trên mgmt host.
2. Tạo `monitor`@'%' (cho ProxySQL probe) và `appuser`@'%' (cho app) trên 3 DB nodes.
3. Cấu hình routing:
   - `mysql_replication_hostgroups (writer=10, reader=20)` cho async/semi-sync, hoặc
   - `mysql_galera_hostgroups (10, 11, 20, 30)` cho Galera.
4. Cấu hình query rules: `SELECT … FOR UPDATE` → writer; `^SELECT` → reader.
5. Smoke test qua :6033: insert routed đến writer, select routed đến reader (round-robin).
6. Demo backend failover: halt 1 node → ProxySQL detect, đẩy ra OFFLINE_HARD, re-route traffic.

## Kiến trúc

- **ProxySQL admin (:6032)**: dùng `mysql -uadmin -padmin -P6032` để config runtime.
  - `mysql_servers` — backend list.
  - `mysql_users` — credential ProxySQL "biết" để forward.
  - `mysql_query_rules` — pattern → hostgroup.
  - `mysql_replication_hostgroups` — auto-detect `read_only=1/0` chuyển server giữa HG.
- **ProxySQL SQL (:6033)**: app connect như MySQL server bình thường.

## Phạm vi demo

| Có | Không |
|----|-------|
| R/W split bằng regex query rule | Query rewrite phức tạp |
| Monitor user + ping/connect probes | TLS frontend (mysql-have_ssl) |
| Backend failover detection | ProxySQL cluster (multiple ProxySQL instances sync) |
| Galera + async/semi-sync backends | InnoDB Cluster backend (cần `mysql_group_replication_hostgroups`) |

## Tiêu chí thành công

| # | Tiêu chí | Cách kiểm tra |
|---|----------|---------------|
| 1 | Backend ready (Demo 01 hoặc 06) | `bash 01-precheck.sh` |
| 2 | proxysql service active | `systemctl is-active proxysql` |
| 3 | Admin :6032 + SQL :6033 listen | `ss -tlnp` |
| 4 | `runtime_mysql_servers` có 3 backends, status ONLINE | admin query |
| 5 | App connect `mysql -uappuser -p... -P6033` thành công | `SELECT @@hostname` qua :6033 |
| 6 | INSERT qua :6033 luôn ra writer (HG10) | smoke test |
| 7 | SELECT qua :6033 ra reader (HG20) round-robin | smoke test |
| 8 | Halt 1 backend → ProxySQL chuyển sang OFFLINE_HARD trong ≤ 10s | failover demo |

## Thời gian ước tính

| Pha | Thời gian |
|-----|-----------|
| Precheck | 30s |
| Install ProxySQL + user creation | 2 phút |
| Configure (async hoặc galera) | 30s |
| Verify | 30s |
| Smoke test | 1 phút |
| Failover demo | 2 phút |
| **Tổng** | **~6–8 phút** (chưa kể backend demo) |

## Lưu ý

- ProxySQL chỉ hỗ trợ `mysql_native_password` mặc định — `appuser` được tạo với plugin native trong upstream script.
- Khi backend là Galera, phải dùng `mysql_galera_hostgroups` thay vì `mysql_replication_hostgroups` để ProxySQL biết check `wsrep_local_state=4` (Synced).
- ProxySQL không terminate transaction — đảm bảo `transaction_persistent=1` để toàn bộ transaction stay ở 1 hostgroup.


---

!!! info "Nguồn gốc"
    `HA/Mysql/demo/07-proxysql/00-overview.md`
