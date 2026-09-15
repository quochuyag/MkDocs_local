---
title: Runbook 07 — ProxySQL
course: 06-high-availability
source: HA/Mysql/runbooks/07-proxysql.md
---

# Runbook 07 — ProxySQL

ProxySQL là **L7 proxy** chuyên cho MySQL: connection pooling, R/W split, query routing/rewriting, query cache, mirror, multi-tenant. Không phải HA solution độc lập — luôn ghép với 1 trong các giải pháp HA backend ở trên.

## 1. Các kịch bản tích hợp

| Backend | ProxySQL config |
|---|---|
| Async/Semi-sync + Orchestrator/MHA | `mysql_replication_hostgroups(writer=10, reader=20)` — ProxySQL tự phát hiện `read_only` flag để phân nhóm |
| Galera | `mysql_galera_hostgroups(writer=10, backup=11, reader=20, offline=30)` — kiểm tra `wsrep_local_state=4` |
| InnoDB Cluster | `mysql_group_replication_hostgroups(...)` — kiểm tra `MEMBER_STATE=ONLINE` và `MEMBER_ROLE=PRIMARY` |

## 2. Cài đặt + cấu hình cho async/semi-sync

```bash
bash scripts/proxysql/proxysql-setup.sh
```
Sau khi chạy:
- ProxySQL admin: `mysql -uadmin -padmin -h127.0.0.1 -P6032`
- ProxySQL SQL: `mysql -uappuser -p<APP_PWD> -h<mgmt> -P6033`
- writer_hostgroup=10, reader_hostgroup=20
- Rule: `SELECT.*FOR UPDATE` → HG10, `^SELECT` → HG20.

## 3. Add config cho Galera backend

```bash
bash scripts/proxysql/proxysql-galera.sh
```
ProxySQL sẽ:
- Đặt 1 node duy nhất ở HG10 (writer) — tránh write conflict do certification.
- Các node Synced khác ở HG11 (backup writers) — auto-promote khi HG10 down.
- Tất cả Synced node ở HG20 (readers).
- Node ở `Donor/Desynced` → HG30 (offline), không nhận traffic.

## 4. Vận hành

### 4.1 Thêm/bớt server runtime
```sql
-- vào admin (6032)
INSERT INTO mysql_servers(hostgroup_id, hostname, port) VALUES (10, '192.168.10.14', 3306);
LOAD MYSQL SERVERS TO RUNTIME; SAVE MYSQL SERVERS TO DISK;
```

### 4.2 Xem trạng thái + healthcheck
```sql
SELECT hostgroup_id, hostname, port, status, weight FROM runtime_mysql_servers ORDER BY hostgroup_id;
SELECT * FROM mysql_server_connect_log ORDER BY time_start_us DESC LIMIT 10;
SELECT * FROM mysql_server_ping_log    ORDER BY time_start_us DESC LIMIT 10;
SELECT hostgroup, srv_host, status, ConnFree, ConnUsed, Queries FROM stats_mysql_connection_pool;
```

### 4.3 Top queries
```sql
SELECT digest, count_star, sum_time, sum_time/count_star AS avg_us, schemaname, digest_text
FROM stats_mysql_query_digest ORDER BY sum_time DESC LIMIT 20;
```

### 4.4 Query rewrite ví dụ
```sql
INSERT INTO mysql_query_rules
  (rule_id, active, match_pattern, replace_pattern, apply)
VALUES
  (100, 1, '^SELECT \* FROM big_table WHERE id=(\d+)$',
            'SELECT id, name FROM big_table WHERE id=\1', 1);
LOAD MYSQL QUERY RULES TO RUNTIME; SAVE MYSQL QUERY RULES TO DISK;
```

### 4.5 Kill long-running query
```sql
SELECT thread_id, info, time_ms FROM stats_mysql_processlist WHERE time_ms > 5000;
KILL CONNECTION <thread_id>;
```

## 5. ProxySQL HA (chính nó)

ProxySQL stateless về data plane → có thể chạy nhiều instance, dùng:
- Keepalived/VIP trước nhiều ProxySQL node, hoặc
- ProxySQL native cluster: thêm `cluster_*` variables trỏ tới các peer khác — config tự đồng bộ.

```sql
UPDATE global_variables SET variable_value='admin:<password>' WHERE variable_name='admin-cluster_username';
INSERT INTO proxysql_servers (hostname, port, weight, comment) VALUES
  ('proxysql1', 6032, 1, 'peer'),
  ('proxysql2', 6032, 1, 'peer');
LOAD PROXYSQL SERVERS TO RUNTIME; SAVE PROXYSQL SERVERS TO DISK;
```

## 6. Lưu ý

- ProxySQL **không** terminate transaction giữa các backend — `transaction_persistent=1` để giữ connection trong cùng HG cho đến COMMIT.
- Password hash trong `mysql_users` mặc định plaintext; bật `admin-hash_passwords=1` để hash sha1.
- ProxySQL không hỗ trợ `caching_sha2_password` (mặc định MySQL 8). Tạo app user với `mysql_native_password` hoặc upgrade ProxySQL ≥ 2.5 + bật `mysql-have_ssl=1`.
- Đừng dùng `STRICT_TRANS_TABLES` khác giữa các backend — query route tới reader có thể fail khác kiểu so với writer.

## 7. Rollback / tháo
```bash
systemctl stop proxysql && systemctl disable proxysql
apt-get remove --purge proxysql
rm -rf /var/lib/proxysql
```

## 8. Tham khảo
- https://proxysql.com/documentation/


---

!!! info "Nguồn gốc"
    `HA/Mysql/runbooks/07-proxysql.md`
