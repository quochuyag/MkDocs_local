---
title: Hướng dẫn setup THỦ CÔNG — Demo 07 ProxySQL (R/W split + connection pool)
course: 06-high-availability
source: HA/Mysql/demo/07-proxysql/MANUAL-SETUP.md
---

# Hướng dẫn setup THỦ CÔNG — Demo 07 ProxySQL (R/W split + connection pool)

> Tài liệu này ghi lại **TỪNG CÂU LỆNH** để dựng ProxySQL ghép vào backend HA (Galera hoặc async/semi-sync) mà không cần `run-all.sh`. Copy-paste theo thứ tự từ trên xuống. Mỗi bước nêu rõ:
> - 🖥️ **Where**: chạy ở đâu (HOST / node1 / node2 / node3 / mgmt)
> - 💻 **Command**: lệnh CLI hoặc SQL
> - 📝 **File**: cấu hình cần ghi (nếu có)
> - ✅ **Verify**: cách kiểm tra step OK

## 0. Topology & biến môi trường

| Host  | IP              | Vai trò                                       | RAM    |
|-------|-----------------|-----------------------------------------------|--------|
| node1 | 192.168.10.11   | MySQL backend (writer/PXC member)             | 2 GB   |
| node2 | 192.168.10.12   | MySQL backend (replica/PXC member)            | 2 GB   |
| node3 | 192.168.10.13   | MySQL backend (replica/PXC member)            | 2 GB   |
| mgmt  | 192.168.10.20   | ProxySQL daemon (admin:6032 / SQL:6033)       | 1.5 GB |

```
                       App
                        │
              ┌─────────▼──────────┐
              │   ProxySQL :6033   │ ← R/W split via mysql_query_rules
              │   admin :6032      │ ← config qua mysql client
              └────┬──────────┬────┘
       writer HG10 │          │ reader HG20 (round-robin)
                   ▼          ▼
            ┌─────────┐   ┌──────────┐
            │  node3  │   │  node1/2 │   (HG ID phụ thuộc backend + writer hiện tại)
            └─────────┘   └──────────┘
```

Credentials mặc định (xem [scripts/common/env.sh](../../scripts/common/env.sh)):

```
MYSQL_ROOT_PWD = ChangeMe!Root#2026
ADMIN_PWD      = ChangeMe!Admin#2026     # dùng cho monitor user
APP_USER       = appuser
APP_PWD        = ChangeMe!App#2026
PROXYSQL_ADMIN_PORT = 6032
PROXYSQL_MYSQL_PORT = 6033
```

Hostgroup convention:

| HG  | Vai trò              | Async/semi-sync (mysql_replication_hostgroups) | Galera (mysql_galera_hostgroups)   |
|-----|----------------------|-----------------------------------------------|------------------------------------|
| 10  | writer               | server có `read_only=0`                       | server có `wsrep_local_state=4` được chọn |
| 11  | backup writer        | —                                             | các member còn lại (failover candidates) |
| 20  | reader               | server có `read_only=1`                       | tất cả member (round-robin)        |
| 30  | offline              | —                                             | server bị shun ra khỏi cluster     |

---

## B0 · Prerequisites — Backend HA đã chạy

🖥️ **Where**: HOST

Demo 07 KHÔNG phải HA solution độc lập — phải có 1 backend đã được dựng:

| Backend         | Demo gốc | Lệnh dựng                            |
|-----------------|----------|--------------------------------------|
| async/semi-sync | Demo 01  | `cd demo/01-async-semisync && bash run-all.sh` |
| Galera (PXC)    | Demo 06  | `cd demo/06-galera && bash run-all.sh`         |

Trong tài liệu này:
- Lệnh áp dụng **cho cả 2 backend** → không đánh dấu thêm.
- Lệnh chỉ cho **Galera** → 🟢 đánh dấu.
- Lệnh chỉ cho **async/semi-sync** → 🟡 đánh dấu.

✅ **Verify** (chọn theo backend):

```bash
cd vagrant

# Tất cả 4 VM phải running
vagrant status
# node1/node2/node3/mgmt = running (virtualbox)

# Backend: Galera 🟢
for N in node1 node2 node3; do
  vagrant ssh "$N" -c "mysql -uroot -p'ChangeMe!Root#2026' -N -B -e \"
    SHOW STATUS LIKE 'wsrep_cluster_status';
    SHOW STATUS LIKE 'wsrep_local_state_comment';\" 2>/dev/null"
done
# Kỳ vọng: wsrep_cluster_status=Primary, wsrep_local_state_comment=Synced trên cả 3

# Backend: async/semi-sync 🟡
vagrant ssh node1 -c "mysql -uroot -p'ChangeMe!Root#2026' -e \"SHOW STATUS LIKE 'Rpl_semi_sync_source_status';\""
# Kỳ vọng: ON
```

---

## B1 · Pre-check tự động (idempotent)

🖥️ **Where**: HOST

Script tự động kiểm tra topology + backend ready trước khi cài ProxySQL:

```bash
cd demo/07-proxysql

# Default: async/semi-sync 🟡
bash 01-precheck.sh

# Galera 🟢
BACKEND=galera bash 01-precheck.sh
```

Output kỳ vọng (Galera):
```
[ OK ] [node1] running
[ OK ] [node1] mysql active
[ OK ] [node1] cluster=Primary local=Synced
...
PRECHECK_PASS=true — sẵn sàng cài ProxySQL (BACKEND=galera)
```

---

## B2 · Cài ProxySQL trên mgmt + tạo monitor/app user trên 3 DB

🖥️ **Where**: HOST (orchestrate qua `vagrant ssh`)

### B2.1 — Tạo monitor + appuser TRÊN TỪNG DB NODE (socket local)

> ⚠ **Lưu ý quan trọng**: với Galera/PXC, sau `install-pxc.sh` chỉ tồn tại `root@localhost` (không có root@'%'). Nếu cố `mysql -uroot -h<NODE_IP>` từ mgmt sẽ fail với `ERROR 1130: Host 'mgmt' is not allowed`. Phải tạo user qua **socket local** trên từng node.
>
> Trên Galera, DDL được auto-replicate qua wsrep → về lý thuyết chỉ cần chạy 1 node. Nhưng chạy cả 3 cho an toàn (idempotent).

```bash
ROOT_PWD='ChangeMe!Root#2026'
ADMIN_PWD='ChangeMe!Admin#2026'
APP_USER='appuser'
APP_PWD='ChangeMe!App#2026'

SQL_USERS="CREATE USER IF NOT EXISTS 'monitor'@'%' IDENTIFIED BY '${ADMIN_PWD}';
GRANT USAGE, REPLICATION CLIENT ON *.* TO 'monitor'@'%';
CREATE USER IF NOT EXISTS '${APP_USER}'@'%' IDENTIFIED WITH mysql_native_password BY '${APP_PWD}';
GRANT ALL ON appdb.* TO '${APP_USER}'@'%';
FLUSH PRIVILEGES;"

for N in node1 node2 node3; do
  echo "--- [$N] tạo users qua socket ---"
  vagrant ssh "$N" -c "mysql -uroot -p'${ROOT_PWD}' -e \"${SQL_USERS}\""
done
```

> 📌 `IDENTIFIED WITH mysql_native_password` quan trọng: ProxySQL 2.6 chỉ hỗ trợ native plugin cho frontend auth. Nếu dùng `caching_sha2_password` (mặc định MySQL 8) thì appuser sẽ không connect được qua :6033.

✅ **Verify**:
```bash
vagrant ssh node1 -c "mysql -uroot -p'${ROOT_PWD}' -e \"
  SELECT user, host, plugin FROM mysql.user WHERE user IN ('monitor','appuser');\""
# Kỳ vọng:
#   appuser   %  mysql_native_password
#   monitor   %  caching_sha2_password (hoặc tương đương — không quan trọng cho ProxySQL probe)
```

### B2.2 — Cài ProxySQL 2.6 trên mgmt

🖥️ **Where**: mgmt (qua `vagrant ssh mgmt`)

```bash
vagrant ssh mgmt
sudo -i
```

📝 **File**: `/etc/apt/sources.list.d/proxysql.list`

```bash
# Add repo key (apt-key deprecated nhưng vẫn work trên jammy)
wget -qO- 'https://repo.proxysql.com/ProxySQL/repo_pub_key' | apt-key add -

cat >/etc/apt/sources.list.d/proxysql.list <<'EOF'
deb https://repo.proxysql.com/ProxySQL/proxysql-2.6.x/jammy/ ./
EOF

apt-get update
apt-get install -y proxysql mysql-client
systemctl enable --now proxysql
```

> Với RHEL/Rocky: dùng `/etc/yum.repos.d/proxysql.repo` với baseurl `https://repo.proxysql.com/ProxySQL/proxysql-2.6.x/centos/$releasever`, rồi `yum install -y proxysql mysql`.

✅ **Verify**:
```bash
systemctl is-active proxysql                  # active
ss -tlnp | egrep ':6032|:6033'                 # 2 listener ports
```

---

## B3 · Cấu hình routing — chọn theo backend

🖥️ **Where**: mgmt (vẫn trong shell sudo)

### B3.1 — Common: monitor credentials + app user + query rules

```bash
ADMIN_PWD='ChangeMe!Admin#2026'
APP_USER='appuser'
APP_PWD='ChangeMe!App#2026'

mysql -uadmin -padmin -h127.0.0.1 -P6032 <<SQL
-- 1. Monitor credentials (ProxySQL probe các DB node bằng user này)
UPDATE global_variables SET variable_value='monitor'    WHERE variable_name='mysql-monitor_username';
UPDATE global_variables SET variable_value='${ADMIN_PWD}' WHERE variable_name='mysql-monitor_password';

-- 2. App user (frontend :6033) — default_hostgroup=10, transaction_persistent=1
DELETE FROM mysql_users;
INSERT INTO mysql_users (username, password, default_hostgroup, transaction_persistent)
  VALUES ('${APP_USER}', '${APP_PWD}', 10, 1);

-- 3. Query routing rules:
--    rule 1: SELECT ... FOR UPDATE → writer HG10 (giữ row-lock đúng nguồn)
--    rule 2: ^SELECT                → reader HG20 (round-robin)
DELETE FROM mysql_query_rules;
INSERT INTO mysql_query_rules (rule_id, active, match_digest, destination_hostgroup, apply) VALUES
  (1, 1, '^SELECT.*FOR UPDATE', 10, 1),
  (2, 1, '^SELECT',              20, 1);

LOAD MYSQL VARIABLES   TO RUNTIME; SAVE MYSQL VARIABLES   TO DISK;
LOAD MYSQL USERS       TO RUNTIME; SAVE MYSQL USERS       TO DISK;
LOAD MYSQL QUERY RULES TO RUNTIME; SAVE MYSQL QUERY RULES TO DISK;
SQL
```

### B3.2 — Khai báo mysql_servers + hostgroup mapping

#### 🟡 Async/semi-sync — `mysql_replication_hostgroups`

ProxySQL theo dõi `read_only=1/0` của từng server → tự đẩy writer (RO=0) vào HG10 và readers (RO=1) vào HG20.

```bash
NODE1_IP=192.168.10.11
NODE2_IP=192.168.10.12
NODE3_IP=192.168.10.13

mysql -uadmin -padmin -h127.0.0.1 -P6032 <<SQL
DELETE FROM mysql_replication_hostgroups;
INSERT INTO mysql_replication_hostgroups (writer_hostgroup, reader_hostgroup, comment)
  VALUES (10, 20, 'async-cluster');

DELETE FROM mysql_servers;
INSERT INTO mysql_servers (hostgroup_id, hostname, port, max_connections) VALUES
  (10, '${NODE1_IP}', 3306, 200),
  (10, '${NODE2_IP}', 3306, 200),
  (10, '${NODE3_IP}', 3306, 200);

LOAD MYSQL SERVERS TO RUNTIME; SAVE MYSQL SERVERS TO DISK;
SELECT hostgroup_id, hostname, status FROM runtime_mysql_servers ORDER BY hostgroup_id, hostname;
SQL
```

Sau vài giây probe đầu tiên, ProxySQL sẽ tự move 2 replica xuống HG20.

#### 🟢 Galera — `mysql_galera_hostgroups`

ProxySQL theo dõi `wsrep_local_state=4` (Synced) + `read_only` + `wsrep_desync`. Layout 4-hostgroup (writer=10, backup=11, reader=20, offline=30):

```bash
NODE1_IP=192.168.10.11
NODE2_IP=192.168.10.12
NODE3_IP=192.168.10.13

mysql -uadmin -padmin -h127.0.0.1 -P6032 <<SQL
DELETE FROM mysql_galera_hostgroups WHERE writer_hostgroup=10;
INSERT INTO mysql_galera_hostgroups
  (writer_hostgroup, backup_writer_hostgroup, reader_hostgroup, offline_hostgroup,
   active, max_writers, writer_is_also_reader, max_transactions_behind)
  VALUES (10, 11, 20, 30, 1, 1, 2, 100);

DELETE FROM mysql_servers WHERE hostgroup_id IN (10, 11, 20, 30);
INSERT INTO mysql_servers (hostgroup_id, hostname, port) VALUES
  (10, '${NODE1_IP}', 3306),
  (10, '${NODE2_IP}', 3306),
  (10, '${NODE3_IP}', 3306);

LOAD MYSQL SERVERS TO RUNTIME; SAVE MYSQL SERVERS TO DISK;
SELECT hostgroup_id, hostname, port, status FROM runtime_mysql_servers ORDER BY hostgroup_id, hostname;
SQL
```

> 🔑 **Tham số quan trọng** trong `mysql_galera_hostgroups`:
> - `max_writers=1` → single-writer mode (tránh write conflict do certification). PXC vẫn cho multi-writer nhưng best practice là 1.
> - `writer_is_also_reader=2` → writer KHÔNG nhận read traffic; reads chỉ vào backup writers (`=0`: writer cũng đọc; `=1`: writer đọc nếu chỉ có 1 node; `=2`: writer không đọc).
> - `max_transactions_behind=100` → nếu một reader `wsrep_local_recv_queue` > 100 thì SHUNNED tạm.

Kỳ vọng sau load:
```
hostgroup_id  hostname        port  status
10            192.168.10.11   3306  SHUNNED      ← 2 nodes "shunned out" khỏi writer pool
10            192.168.10.12   3306  SHUNNED
10            192.168.10.13   3306  ONLINE       ← 1 node được elect làm writer
11            192.168.10.11   3306  ONLINE       ← các backup writer
11            192.168.10.12   3306  ONLINE
20            192.168.10.11   3306  ONLINE       ← reader pool
20            192.168.10.12   3306  ONLINE
```

> 📌 Trạng thái `SHUNNED` trong HG10 ở đây **không phải lỗi** — đó là cách ProxySQL giữ 2 server còn lại như candidate cho writer election khi node hiện tại fail; traffic write thực tế chỉ ra node có status=ONLINE trong HG10.

---

## B4 · Verify

🖥️ **Where**: HOST hoặc mgmt

### B4.1 — Service + ports

```bash
vagrant ssh mgmt -c "
  systemctl is-active proxysql
  sudo ss -tlnp | egrep ':6032 |:6033 '
"
```

### B4.2 — Servers ONLINE + monitor probe alive

```bash
vagrant ssh mgmt -c "
  mysql -uadmin -padmin -h127.0.0.1 -P6032 -e \"
    SELECT hostgroup_id, hostname, status FROM runtime_mysql_servers ORDER BY hostgroup_id, hostname;
  \"
"
```

Probe history (ProxySQL admin SQLite **KHÔNG có hàm `UNIX_TIMESTAMP()`** → inject từ shell):

```bash
SINCE_US=$(( ($(date +%s) - 60) * 1000000 ))
vagrant ssh mgmt -c "
  mysql -uadmin -padmin -h127.0.0.1 -P6032 -e \"
    SELECT COUNT(*) AS recent_ok FROM mysql_server_ping_log
    WHERE time_start_us > ${SINCE_US} AND ping_error IS NULL;
  \"
"
# Kỳ vọng ≥ 3 (3 server × probe mỗi 10s = 18 trong 60s)
```

### B4.3 — App connect qua :6033

```bash
APP_USER='appuser'
APP_PWD='ChangeMe!App#2026'

vagrant ssh mgmt -c "
  mysql -u${APP_USER} -p'${APP_PWD}' -h127.0.0.1 -P6033 -e 'SELECT @@hostname;'
"
# Kỳ vọng output 1 hostname trong số node1/node2/node3 (reader pool)
```

### B4.4 — Active query rules

```bash
vagrant ssh mgmt -c "
  mysql -uadmin -padmin -h127.0.0.1 -P6032 -e \"
    SELECT rule_id, active, match_digest, destination_hostgroup, apply
    FROM runtime_mysql_query_rules ORDER BY rule_id;
  \"
"
# Kỳ vọng 2 rule active=1
```

---

## B5 · Smoke test — R/W split

🖥️ **Where**: HOST

### B5.1 — Schema setup qua :6033

```bash
APP_USER='appuser'
APP_PWD='ChangeMe!App#2026'

vagrant ssh mgmt -c "
  mysql -u${APP_USER} -p'${APP_PWD}' -h127.0.0.1 -P6033 <<SQL
    CREATE DATABASE IF NOT EXISTS appdb;
    DROP TABLE IF EXISTS appdb.t;
    CREATE TABLE appdb.t(
      id BIGINT PRIMARY KEY AUTO_INCREMENT,
      val VARCHAR(64) NOT NULL,
      ts DATETIME(6) DEFAULT CURRENT_TIMESTAMP(6)
    ) ENGINE=InnoDB;
SQL
"
```

### B5.2 — INSERT 100 rows (kỳ vọng vào HG10 = writer)

```bash
SQL='USE appdb;'
for i in $(seq 1 100); do SQL+="INSERT INTO t(val) VALUES('row-$i');"; done

vagrant ssh mgmt -c "
  mysql -u${APP_USER} -p'${APP_PWD}' -h127.0.0.1 -P6033 -e \"${SQL}\"
"
```

### B5.3 — 8 SELECT (kỳ vọng round-robin trong HG20)

```bash
for i in 1 2 3 4 5 6 7 8; do
  vagrant ssh mgmt -c "mysql -u${APP_USER} -p'${APP_PWD}' -h127.0.0.1 -P6033 -N -B -e 'SELECT @@hostname;'"
done
# Kỳ vọng 2 hostname khác nhau (node1, node2 chẳng hạn) — KHÔNG bao giờ ra writer
```

### B5.4 — Verify R/W split qua stats

```bash
vagrant ssh mgmt -c "
  mysql -uadmin -padmin -h127.0.0.1 -P6032 -e \"
    SELECT hostgroup, srv_host, status, ConnFree, ConnUsed, Queries
    FROM stats_mysql_connection_pool ORDER BY hostgroup, srv_host;
  \"
"
```

Kỳ vọng:
```
hostgroup  srv_host        status   Queries
10         192.168.10.13   ONLINE   103     ← INSERT (100 + 3 setup) vào writer
11         192.168.10.11   ONLINE   0
20         192.168.10.11   ONLINE   5       ← SELECT round-robin
20         192.168.10.12   ONLINE   3
```

### B5.5 — Top query digest

> ⚠ **ProxySQL admin SQLite KHÔNG có hàm `LEFT(s, n)`** — phải dùng `SUBSTR(s, 1, n)`.

```bash
vagrant ssh mgmt -c "
  mysql -uadmin -padmin -h127.0.0.1 -P6032 -e \"
    SELECT digest, count_star, sum_time, schemaname, hostgroup,
           SUBSTR(digest_text, 1, 80) AS query
    FROM stats_mysql_query_digest
    ORDER BY sum_time DESC LIMIT 5;
  \"
"
```

Output mẫu:
```
0x3A1E... 200 911544 appdb               10  INSERT INTO t(val) VALUES(?)
0x0DEE... 2    48176 information_schema  10  CREATE TABLE appdb.t(id BIGINT ...)
0xA802... 17   19974 information_schema  20  SELECT @@hostname
```

### B5.6 — Sanity count

```bash
APP_USER='appuser'
APP_PWD='ChangeMe!App#2026'
vagrant ssh mgmt -c "mysql -u${APP_USER} -p'${APP_PWD}' -h127.0.0.1 -P6033 -N -B -e 'SELECT COUNT(*) FROM appdb.t;'"
# Kỳ vọng: 100
```

---

## B6 · Failover demo — halt 1 backend

🖥️ **Where**: HOST. ⚠ DESTRUCTIVE: 1 VM bị halt cứng.

### B6.1 — Snapshot trạng thái trước halt

```bash
vagrant ssh mgmt -c "
  mysql -uadmin -padmin -h127.0.0.1 -P6032 -e \"
    SELECT hostgroup_id, hostname, port, status FROM runtime_mysql_servers
    ORDER BY hostgroup_id, hostname;\"
"
```

Giả sử node3 là writer hiện tại (HG10 ONLINE).

### B6.2 — Halt cứng node3

```bash
HALT_TS=$(date +%s)
vagrant halt --force node3
```

### B6.3 — Poll ProxySQL detection (timeout 60s)

```bash
TARGET_IP='192.168.10.13'
for i in $(seq 1 60); do
  ST=$(vagrant ssh mgmt -c "mysql -uadmin -padmin -h127.0.0.1 -P6032 -N -B -e \"
    SELECT status FROM runtime_mysql_servers WHERE hostname='${TARGET_IP}' ORDER BY hostgroup_id LIMIT 1;\"" | tr -d '\r')
  case "$ST" in
    SHUNNED|OFFLINE_HARD)
      echo "Detected ${TARGET_IP} = $ST sau $(( $(date +%s) - HALT_TS ))s"
      break
      ;;
  esac
  sleep 1
done
```

Kỳ vọng: detect trong 10–60s (tuỳ `mysql-monitor_connect_interval`, `monitor_ping_interval`).

### B6.4 — Verify traffic re-route

```bash
for i in 1 2 3 4 5 6; do
  vagrant ssh mgmt -c "mysql -uappuser -p'ChangeMe!App#2026' -h127.0.0.1 -P6033 -N -B -e 'SELECT @@hostname;'"
done
# Tất cả phải đi vào node1 / node2 — KHÔNG hit node3
```

### B6.5 — Trạng thái cuối

```bash
vagrant ssh mgmt -c "
  mysql -uadmin -padmin -h127.0.0.1 -P6032 -e \"
    SELECT hostgroup_id, hostname, port, status FROM runtime_mysql_servers
    ORDER BY hostgroup_id, hostname;\"
"
```

Kỳ vọng (sau halt node3):
```
10  192.168.10.11   SHUNNED
10  192.168.10.12   ONLINE    ← node2 được promote làm writer
11  192.168.10.11   ONLINE
20  192.168.10.11   ONLINE
30  192.168.10.13   SHUNNED   ← node3 vào offline hostgroup
```

---

## B7 · Recovery — bring back node3

🖥️ **Where**: HOST, sau khi B6 đã halt node3.

### B7.1 — `vagrant up`

```bash
cd vagrant
vagrant up node3
```

### B7.2 — Khắc phục `grastate.dat seqno=-1` (chỉ với Galera 🟢)

Sau halt cứng, PXC ghi `seqno=-1` vào grastate.dat → systemd guard **chặn auto-start**. Cần phục hồi seqno từ binlog/InnoDB redo:

```bash
vagrant ssh node3
sudo -i

cat /var/lib/mysql/grastate.dat
# seqno: -1
# safe_to_bootstrap: 0

# 1) Recover position từ InnoDB redo (chạy as mysql user)
sudo -u mysql bash -c 'mysqld --wsrep-recover' 2>/dev/null
grep -i 'WSREP: Recovered position' /var/log/mysql/error.log | tail -1
# Output: ... [WSREP] Recovered position: <UUID>:<SEQNO>
#         vd: 88327264-...:533

# 2) Ghi seqno đó vào grastate.dat
sed -i 's/seqno: .*/seqno: 533/' /var/lib/mysql/grastate.dat

# 3) Start mysql — sẽ IST/SST từ donor (node1 hoặc node2)
systemctl start mysql

# 4) Wait Synced
for i in {1..60}; do
  STATE=$(mysql -uroot -p'ChangeMe!Root#2026' -NB -e "SHOW STATUS LIKE 'wsrep_local_state_comment'" 2>/dev/null | awk '{print $2}')
  echo "wsrep_local_state_comment=$STATE"
  [[ "$STATE" == "Synced" ]] && break
  sleep 5
done
```

> 💡 Nếu không cần biết seqno chính xác, có thể set `seqno: 0` để buộc full SST. Risk: SST tốn thời gian + bandwidth.
> Cách khác: xóa grastate.dat → PXC sẽ tự bootstrap với seqno=-1 và xin SST.

### B7.3 — ProxySQL tự re-include

```bash
vagrant ssh mgmt -c "
  mysql -uadmin -padmin -h127.0.0.1 -P6032 -e \"
    SELECT hostgroup_id, hostname, port, status FROM runtime_mysql_servers
    ORDER BY hostgroup_id, hostname;\"
"
# Sau 10-30s, node3 quay lại HG10/11/20 với status=ONLINE.
# ProxySQL có thể promote lại node3 làm writer (do max_writers=1 chọn theo weight + status).
```

---

## B8 · Operations cheat-sheet

🖥️ **Where**: mgmt

| Thao tác                                         | Lệnh ProxySQL admin (:6032)                                                          |
|--------------------------------------------------|--------------------------------------------------------------------------------------|
| Reload servers (sau khi sửa weight)              | `LOAD MYSQL SERVERS TO RUNTIME; SAVE MYSQL SERVERS TO DISK;`                          |
| Reload query rules                               | `LOAD MYSQL QUERY RULES TO RUNTIME; SAVE MYSQL QUERY RULES TO DISK;`                  |
| Reload users                                     | `LOAD MYSQL USERS TO RUNTIME; SAVE MYSQL USERS TO DISK;`                              |
| Đặt server OFFLINE_SOFT (drain)                  | `UPDATE mysql_servers SET status='OFFLINE_SOFT' WHERE hostname='192.168.10.13';`<br>`LOAD MYSQL SERVERS TO RUNTIME;` |
| Bật server lại ONLINE                            | `UPDATE mysql_servers SET status='ONLINE' WHERE hostname='192.168.10.13';`<br>`LOAD MYSQL SERVERS TO RUNTIME;` |
| Reset query cache                                | `PROXYSQL FLUSH QUERY CACHE NOW;`                                                     |
| Reset stats counters                             | `SELECT * FROM stats_mysql_connection_pool_reset;`                                    |
| Xem connection pool                              | `SELECT * FROM stats_mysql_connection_pool;`                                          |
| Xem global error log                             | `SELECT * FROM stats_mysql_global ORDER BY Variable_Name;`                            |
| Restart ProxySQL graceful                        | `PROXYSQL RESTART;` (giữ runtime, reload từ disk)                                     |
| Backup config                                    | `SAVE MYSQL SERVERS TO DISK; SAVE MYSQL USERS TO DISK; SAVE MYSQL QUERY RULES TO DISK; SAVE MYSQL VARIABLES TO DISK;` |

---

## B9 · Rollback

🖥️ **Where**: HOST

### B9.1 — Soft rollback (gỡ ProxySQL, giữ backend + dữ liệu)

```bash
ROOT_PWD='ChangeMe!Root#2026'

# Stop + purge ProxySQL trên mgmt
vagrant ssh mgmt -c "
  sudo bash -c '
    systemctl stop proxysql 2>/dev/null || true
    systemctl disable proxysql 2>/dev/null || true
    apt-get remove --purge -y proxysql 2>/dev/null || true
    rm -rf /var/lib/proxysql
  '
"

# Drop monitor + appuser + appdb (đủ 1 node với Galera; 3 node với async)
vagrant ssh node1 -c "
  mysql -uroot -p'${ROOT_PWD}' -e \"
    DROP USER IF EXISTS 'appuser'@'%';
    DROP USER IF EXISTS 'monitor'@'%';
    DROP DATABASE IF EXISTS appdb;
    FLUSH PRIVILEGES;\"
"
```

### B9.2 — Hard rollback (destroy mọi thứ)

```bash
cd vagrant
vagrant destroy -f
rm -f provision/cluster_id_rsa provision/cluster_id_rsa.pub
```

---

## Phụ lục A — Trouble-shooting nhanh

### A.1 `ERROR 1130 (HY000): Host 'mgmt' is not allowed to connect to this MySQL server`

→ Root chỉ có ở `root@localhost` (mặc định MySQL/PXC sau install). KHÔNG thể tạo monitor user qua `mysql -h<NODE_IP>` từ mgmt. **Fix**: chạy CREATE USER qua **socket local** trên từng node (xem B2.1).

### A.2 `ProxySQL Admin Error: no such function: UNIX_TIMESTAMP` / `LEFT`

→ ProxySQL admin parser là SQLite-style, **KHÔNG có** `UNIX_TIMESTAMP()`, `LEFT()`, `NOW()`, `DATE_FORMAT()`. Workaround:
- `UNIX_TIMESTAMP()` → tính từ shell: `SINCE_US=$(( $(date +%s) * 1000000 ))`.
- `LEFT(s, n)` → `SUBSTR(s, 1, n)`.
- `NOW()` → dùng `STRFTIME('%s','now')`.

### A.3 `ERROR 1045 (28000): ProxySQL Error: Access denied for user 'appuser'@'mgmt'`

→ Frontend auth fail. Kiểm tra:
1. `appuser` được tạo `IDENTIFIED WITH mysql_native_password` trên DB (ProxySQL 2.6 không hỗ trợ caching_sha2 frontend).
2. `mysql_users` trong ProxySQL: `SELECT * FROM runtime_mysql_users WHERE username='appuser';`.
3. Password trong `mysql_users.password` khớp với password trên DB.

### A.4 Sau halt node, server status mãi `SHUNNED` (không `ONLINE_HARD`)

→ `SHUNNED` là tạm thời (probe đang fail). Chuyển sang `OFFLINE_HARD` chỉ khi `mysql-shun_on_failures` (mặc định 5) probe liên tiếp fail. Tăng tốc detect:
```sql
UPDATE global_variables SET variable_value=2  WHERE variable_name='mysql-shun_on_failures';
UPDATE global_variables SET variable_value=1000 WHERE variable_name='mysql-monitor_ping_interval';  -- ms
LOAD MYSQL VARIABLES TO RUNTIME; SAVE MYSQL VARIABLES TO DISK;
```

### A.5 Galera: 2/3 server SHUNNED trong HG10 nhưng cluster healthy

→ Đúng — đó là behavior của `mysql_galera_hostgroups` với `max_writers=1`. Chỉ 1 server ONLINE trong HG10 cùng lúc; 2 server còn lại "shunned out of writer" nhưng vẫn ONLINE trong HG11 (backup writer) + HG20 (reader). Verify bằng:
```sql
SELECT hostgroup_id, hostname, status FROM runtime_mysql_servers ORDER BY hostgroup_id;
```
Phải thấy mỗi node xuất hiện ở 3 hostgroup (10/11/20).

### A.6 INSERT route vào reader (HG20) thay vì writer (HG10)

→ Query rule match wrong. Kiểm tra `match_digest` regex:
```sql
SELECT rule_id, active, match_digest, destination_hostgroup FROM runtime_mysql_query_rules ORDER BY rule_id;
```
Default order: `^SELECT.*FOR UPDATE → 10`, `^SELECT → 20`. Mọi câu **không** bắt đầu bằng `SELECT` đều đi vào `default_hostgroup=10` của user (writer).

### A.7 PXC node sau halt: `mysql service has not been started automatically`

→ `grastate.dat` có `seqno=-1`. Xem B7.2 — phải recover seqno bằng `mysqld --wsrep-recover` rồi ghi lại file.

---

## Phụ lục B — Tóm tắt files / users sau demo

### Files tạo mới

| Host  | File                                             | Mô tả                                |
|-------|--------------------------------------------------|--------------------------------------|
| mgmt  | `/etc/apt/sources.list.d/proxysql.list`          | repo ProxySQL 2.6.x                  |
| mgmt  | `/var/lib/proxysql/proxysql.db`                  | runtime config persistence (SQLite)  |
| mgmt  | `/var/lib/proxysql/proxysql.log`                 | proxysql daemon log                  |
| mgmt  | `/etc/proxysql.cnf`                              | bootstrap config (admin port, etc.)  |

### Users tạo mới trong MySQL

| User              | Host  | Plugin                  | Privilege                             |
|-------------------|-------|-------------------------|---------------------------------------|
| `monitor`         | `%`   | (default)               | USAGE, REPLICATION CLIENT             |
| `appuser`         | `%`   | `mysql_native_password` | ALL ON `appdb.*`                      |

### Schema tạo mới

| Database | Table | Tạo ở B  | Engine |
|----------|-------|----------|--------|
| `appdb`  | `t`   | B5.1     | InnoDB |

### ProxySQL admin tables đã chỉnh sửa

- `global_variables` (monitor_username, monitor_password)
- `mysql_users` (appuser)
- `mysql_query_rules` (rule 1 + 2)
- `mysql_servers` (3 backend)
- `mysql_replication_hostgroups` 🟡 *hoặc* `mysql_galera_hostgroups` 🟢

---

## Phụ lục C — Mapping bash scripts ↔ manual steps

| Script trong repo                                           | Bước trong tài liệu     |
|-------------------------------------------------------------|--------------------------|
| `demo/07-proxysql/01-precheck.sh`                           | B0 + B1                  |
| `scripts/proxysql/proxysql-setup.sh` (`BOOTSTRAP_USERS=false`) | B2.2 + B3.1 + B3.2 (🟡) |
| `scripts/proxysql/proxysql-galera.sh`                       | B3.2 (🟢)                |
| `demo/07-proxysql/02-install-proxysql.sh`                   | B2 toàn bộ               |
| `demo/07-proxysql/03-configure-galera.sh`                   | B3.2 (🟢)                |
| `demo/07-proxysql/04-verify.sh`                             | B4                       |
| `demo/07-proxysql/05-smoke-test.sh`                         | B5                       |
| `demo/07-proxysql/06-failover-demo.sh`                      | B6                       |
| `demo/07-proxysql/07-rollback.sh`                           | B9                       |

> 💡 Tip: `run-all.sh` chạy B1 → B5 tự động. B6 (destructive halt) và B7 (recovery) phải chạy thủ công. B9 chỉ chạy khi muốn tháo demo.

---

## Phụ lục D — Tunings nâng cao (optional)

### D.1 Query cache (ProxySQL-native)

```sql
INSERT INTO mysql_query_rules (rule_id, active, match_digest, destination_hostgroup, cache_ttl, apply)
  VALUES (3, 1, '^SELECT.*FROM appdb\\.config', 20, 60000, 1);   -- cache 60s
LOAD MYSQL QUERY RULES TO RUNTIME; SAVE MYSQL QUERY RULES TO DISK;

-- Monitor cache hit rate
SELECT Variable_Name, Variable_Value FROM stats_mysql_global
WHERE Variable_Name LIKE 'Query_Cache%';
```

### D.2 Connection multiplexing

```sql
-- Bật cho user (cần transaction_persistent=1 để giữ transaction không bị split)
UPDATE mysql_users SET fast_forward=0, transaction_persistent=1 WHERE username='appuser';

-- Tăng connection pool size per backend
UPDATE mysql_servers SET max_connections=500 WHERE hostgroup_id IN (10, 20);

LOAD MYSQL USERS TO RUNTIME; LOAD MYSQL SERVERS TO RUNTIME;
SAVE MYSQL USERS TO DISK;    SAVE MYSQL SERVERS TO DISK;
```

### D.3 Connection limits per app user

```sql
UPDATE mysql_users
SET max_connections=200, default_schema='appdb'
WHERE username='appuser';
LOAD MYSQL USERS TO RUNTIME; SAVE MYSQL USERS TO DISK;
```

### D.4 ProxySQL Cluster (multi-instance HA)

ProxySQL daemon đơn lẻ là SPOF. Production setup: deploy ≥ 2 instance, config qua `proxysql_servers` table với shared `cluster_username/password`. Xem [docs](https://proxysql.com/documentation/proxysql-cluster/).

---

## Tham khảo

- Runbook gốc: [runbooks/07-proxysql.md](../../runbooks/007-proxysql.md)
- ProxySQL documentation: https://proxysql.com/documentation/
- Galera hostgroups: https://proxysql.com/documentation/galera-configuration/
- Native MySQL replication hostgroups: https://proxysql.com/documentation/mysql-replication/


---

!!! info "Nguồn gốc"
    `HA/Mysql/demo/07-proxysql/MANUAL-SETUP.md`
