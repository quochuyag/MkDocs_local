---
title: Hướng dẫn setup THỦ CÔNG — Demo 01 Async / Semi-Sync MySQL
course: 06-high-availability
source: HA/Mysql/demo/01-async-semisync/MANUAL-SETUP.md
---

# Hướng dẫn setup THỦ CÔNG — Demo 01 Async / Semi-Sync MySQL

> Tài liệu này ghi lại **TỪNG CÂU LỆNH** để dựng giải pháp 01 mà không cần `run-all.sh` / `run-all.ps1`. Copy-paste theo thứ tự từ trên xuống. Mỗi bước nêu rõ:
> - 🖥️ **Where**: chạy ở đâu (HOST / node1 / node2 / node3 / mgmt)
> - 💻 **Command**: lệnh CLI hoặc SQL
> - 📝 **File**: cấu hình cần ghi (nếu có)
> - ✅ **Verify**: cách kiểm tra step OK

## 0. Topology & biến môi trường

| Host  | IP              | Vai trò                | server_id |
|-------|-----------------|------------------------|-----------|
| node1 | 192.168.10.11   | MASTER (RW)            | 1         |
| node2 | 192.168.10.12   | REPLICA (RO)           | 2         |
| node3 | 192.168.10.13   | REPLICA (RO)           | 3         |
| mgmt  | 192.168.10.20   | mysql-client / observer| —         |

Credentials mặc định (đổi nếu muốn — xem [scripts/common/env.sh](../../scripts/common/env.sh)):

```
MYSQL_ROOT_PWD = ChangeMe!Root#2026
REPL_USER      = repl
REPL_PWD       = ChangeMe!Repl#2026
```

Ports cần mở: `22, 3306, 33060, 33061, 4567, 4568, 4444, 6446, 6447, 6032, 6033`.

---

## B0 · Prerequisites trên HOST

🖥️ **Where**: HOST (Windows / macOS / Linux)

```bash
# Linux/macOS — cài Vagrant + VirtualBox qua package manager
# Windows — tải installer:
#   https://www.virtualbox.org/wiki/Downloads     (≥ 7.0)
#   https://www.vagrantup.com/downloads           (≥ 2.3)
#   https://git-scm.com/download/win              (Git Bash)
```

✅ **Verify**:
```powershell
vagrant --version       # Vagrant 2.3+
VBoxManage --version    # 7.0+
```

---

## B1 · Bring up 4 VMs

🖥️ **Where**: HOST, ở thư mục `vagrant/`

### B1.1 — Sinh SSH key dùng chung cho cluster (chỉ 1 lần)

```bash
cd vagrant
bash provision/generate-ssh-key.sh
# tạo provision/cluster_id_rsa + .pub
```

### B1.2 — Spin up 4 VMs

```bash
export VAGRANT_DEFAULT_PROVIDER=virtualbox    # PowerShell: $env:VAGRANT_DEFAULT_PROVIDER='virtualbox'
vagrant up node1 --provider=virtualbox --no-destroy-on-error
vagrant up node2 --provider=virtualbox --no-destroy-on-error
vagrant up node3 --provider=virtualbox --no-destroy-on-error
vagrant up mgmt  --provider=virtualbox --no-destroy-on-error
```

> ⚠ Nếu lỗi `VERR_ALREADY_EXISTS` (D:\VM VirtualBox\mysql-ha-nodeX đã tồn tại):
> ```powershell
> VBoxManage list vms                                    # nếu VM "<inaccessible>" → unregister
> VBoxManage unregistervm <UUID>                          # nếu cần
> Remove-Item -Recurse -Force "D:\VM VirtualBox\mysql-ha-node1"   # xoá dir orphan
> Remove-Item -Recurse -Force "D:\VM VirtualBox\temp_clone_*"     # xoá temp clone
> ```

✅ **Verify**:
```bash
vagrant status
# Tất cả 4 VM: running (virtualbox)

# Test connectivity giữa các nodes
vagrant ssh node1 -c "ping -c1 -W2 node2 && ping -c1 -W2 node3 && ping -c1 -W2 mgmt"
```

---

## B2 · Prepare OS — chạy TRÊN MỖI 4 NODES

🖥️ **Where**: node1, node2, node3, mgmt (4 lần) — chạy với `sudo`

```bash
# SSH vào từng VM (lặp lại 4 lần)
vagrant ssh node1     # rồi node2, node3, mgmt
sudo -i               # vào root shell
```

### B2.1 — Cập nhật `/etc/hosts`

📝 **File**: `/etc/hosts` — thêm block (idempotent: marker `>>>/<<<`)

```bash
# Xoá block cũ nếu có
sed -i '/# >>> mysql-ha cluster >>>/,/# <<< mysql-ha cluster <<</d' /etc/hosts

# Append block mới
cat >>/etc/hosts <<'EOF'
# >>> mysql-ha cluster >>>
192.168.10.11  node1
192.168.10.12  node2
192.168.10.13  node3
192.168.10.20  mgmt
# <<< mysql-ha cluster <<<
EOF
```

### B2.2 — Tắt swap

```bash
swapoff -a
# Comment dòng swap trong fstab (chỉ dòng chưa bị comment)
sed -i.bak -E '/^[^#].*\sswap\s/s/^/#/' /etc/fstab
```

### B2.3 — Cài NTP (chrony)

```bash
timedatectl set-ntp true || true
DEBIAN_FRONTEND=noninteractive apt-get update
apt-get install -y chrony
systemctl enable --now chrony
```

### B2.4 — Sysctl tuning

📝 **File**: `/etc/sysctl.d/99-mysql-ha.conf`

```bash
cat >/etc/sysctl.d/99-mysql-ha.conf <<'EOF'
vm.swappiness = 1
net.core.somaxconn = 65535
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_keepalive_time = 60
net.ipv4.tcp_keepalive_intvl = 10
net.ipv4.tcp_keepalive_probes = 6
fs.aio-max-nr = 1048576
fs.file-max = 2097152
EOF
sysctl --system >/dev/null
```

### B2.5 — Ulimit cho mysql service

📝 **File**: `/etc/systemd/system/mysql.service.d/limits.conf` (và mysqld.service.d)

```bash
mkdir -p /etc/systemd/system/mysql.service.d /etc/systemd/system/mysqld.service.d
cat >/etc/systemd/system/mysql.service.d/limits.conf <<'EOF'
[Service]
LimitNOFILE=1048576
LimitNPROC=65535
EOF
cp /etc/systemd/system/mysql.service.d/limits.conf /etc/systemd/system/mysqld.service.d/limits.conf
systemctl daemon-reload || true
```

### B2.6 — Tắt AppArmor (lab)

```bash
systemctl disable --now apparmor || true
```

✅ **Verify** (vẫn trong node):
```bash
swapon --show                         # rỗng = swap OFF
sysctl vm.swappiness fs.file-max      # = 1 / 2097152
grep -A4 'mysql-ha cluster' /etc/hosts
timedatectl | grep -E 'NTP|synchron'
```

Lặp lại B2.1 → B2.6 trên **cả 4 nodes**.

---

## B3 · Cài MySQL 8.0 — chạy TRÊN 3 DB NODES (node1, node2, node3)

🖥️ **Where**: node1, node2, node3 (KHÔNG cài trên mgmt)

```bash
vagrant ssh node1     # rồi node2, node3
sudo -i
```

### B3.1 — Dọn state cũ (nếu B3 đã fail trước đó)

```bash
rm -f /etc/apt/sources.list.d/mysql.list /etc/apt/sources.list.d/mysql.list.distUpgrade
rm -f /etc/apt/trusted.gpg.d/mysql.gpg /etc/apt/keyrings/mysql.gpg
DEBIAN_FRONTEND=noninteractive apt-get update
apt-get install -y wget lsb-release gnupg ca-certificates dirmngr
```

### B3.2 — Cài mysql-apt-config (pre-seed cho MySQL 8.0)

```bash
debconf-set-selections <<'EOF'
mysql-apt-config mysql-apt-config/select-server  select mysql-8.0
mysql-apt-config mysql-apt-config/select-product select Ok
mysql-apt-config mysql-apt-config/select-tools   select Enabled
mysql-apt-config mysql-apt-config/select-preview select Disabled
mysql-apt-config mysql-apt-config/repo-distro    select ubuntu
mysql-apt-config mysql-apt-config/repo-codename  select jammy
EOF

wget -qO /tmp/mysql-apt.deb \
  "https://repo.mysql.com/mysql-apt-config_0.8.33-1_all.deb" || \
wget -qO /tmp/mysql-apt.deb \
  "https://dev.mysql.com/get/mysql-apt-config_0.8.33-1_all.deb"
DEBIAN_FRONTEND=noninteractive dpkg -i /tmp/mysql-apt.deb || true
DEBIAN_FRONTEND=noninteractive dpkg-reconfigure -f noninteractive mysql-apt-config || true
```

### B3.3 — Đảm bảo mysql.list có đủ repos (failsafe)

📝 **File**: `/etc/apt/sources.list.d/mysql.list`

```bash
if [[ ! -f /etc/apt/sources.list.d/mysql.list ]] || \
   ! grep -qE '^deb .* mysql-tools($| )' /etc/apt/sources.list.d/mysql.list; then
  CODENAME=$(lsb_release -cs 2>/dev/null || echo jammy)
  cat >/etc/apt/sources.list.d/mysql.list <<EOF
deb http://repo.mysql.com/apt/ubuntu/ ${CODENAME} mysql-apt-config
deb http://repo.mysql.com/apt/ubuntu/ ${CODENAME} mysql-8.0
deb http://repo.mysql.com/apt/ubuntu/ ${CODENAME} mysql-tools
EOF
fi
cat /etc/apt/sources.list.d/mysql.list
```

### B3.4 — Refresh GPG key MySQL (key A8D3785C có expiration cũ)

```bash
for KS in \
    hkps://keyserver.ubuntu.com:443 \
    hkps://keys.openpgp.org:443 \
    hkps://pgp.mit.edu:443 \
    hkp://keyserver.ubuntu.com:80; do
  if timeout 30 gpg --no-default-keyring \
       --keyring /etc/apt/trusted.gpg.d/mysql.gpg \
       --keyserver "${KS}" --refresh-keys 2>/dev/null; then
    echo "    refresh OK qua ${KS}"
    break
  fi
done
```

### B3.5 — Probe + fallback `[trusted=yes]` cho LAB

```bash
PROBE_LOG=$(mktemp)
apt-get update 2>&1 | tee "${PROBE_LOG}" || true
if grep -qE 'EXPKEYSIG|NO_PUBKEY|is not signed' "${PROBE_LOG}"; then
  echo "==> Key vẫn lỗi → fallback [trusted=yes] (LAB ONLY)"
  sed -i -E 's|^deb (\[[^]]+\] )?(http)|deb [trusted=yes] \2|'      /etc/apt/sources.list.d/mysql.list
  sed -i -E 's|^deb-src (\[[^]]+\] )?(http)|deb-src [trusted=yes] \2|' /etc/apt/sources.list.d/mysql.list
  apt-get update
fi
rm -f "${PROBE_LOG}"
```

### B3.6 — Cài MySQL server + shell + router

```bash
ROOT_PWD='ChangeMe!Root#2026'
echo "mysql-community-server mysql-community-server/root-pass    password ${ROOT_PWD}" | debconf-set-selections
echo "mysql-community-server mysql-community-server/re-root-pass password ${ROOT_PWD}" | debconf-set-selections
DEBIAN_FRONTEND=noninteractive apt-get install -y mysql-server mysql-shell mysql-router
```

### B3.7 — Ghi config MySQL cluster

📝 **File**: `/etc/mysql/mysql.conf.d/zz-mysql-ha.cnf`

> ⚠ `server_id` khác nhau trên mỗi node: node1=1, node2=2, node3=3

```bash
HOST=$(hostname)
case "$HOST" in
  node1) SID=1 ;;
  node2) SID=2 ;;
  node3) SID=3 ;;
  *)     SID=$(( ( RANDOM % 1000 ) + 10 )) ;;
esac

cat >/etc/mysql/mysql.conf.d/zz-mysql-ha.cnf <<EOF
[mysqld]
server_id                = ${SID}
bind-address             = 0.0.0.0
mysqlx_bind_address      = 0.0.0.0
default_authentication_plugin = mysql_native_password
log_bin                  = mysql-bin
binlog_format            = ROW
binlog_expire_logs_seconds = 604800
gtid_mode                = ON
enforce_gtid_consistency = ON
log_slave_updates        = ON
relay_log                = relay-bin
relay_log_recovery       = ON
sync_binlog              = 1
innodb_flush_log_at_trx_commit = 1
report_host              = ${HOST}
EOF

systemctl restart mysql
sleep 3
```

✅ **Verify** (trên mỗi node):
```bash
systemctl is-active mysql                            # active
ss -tlnp | grep ':3306 '                             # listening
mysql -uroot -p"${ROOT_PWD}" -e "SELECT VERSION(),@@server_id,@@gtid_mode,@@log_bin,@@binlog_format;"
# Expect: 8.0.x | 1|2|3 | ON | 1 | ROW
```

Lặp lại B3.1 → B3.7 trên **node1, node2, node3** (chỉ khác `SID` tự tính).

---

## B4 · Setup MASTER trên node1

🖥️ **Where**: node1 (chỉ chạy 1 lần)

```bash
vagrant ssh node1
sudo -i
ROOT_PWD='ChangeMe!Root#2026'
REPL_USER='repl'
REPL_PWD='ChangeMe!Repl#2026'
```

### B4.1 — Cài plugin semi-sync source (runtime, có conditional)

```bash
mysql -uroot -p"${ROOT_PWD}" <<'SQL'
SET @cnt = (SELECT COUNT(*) FROM information_schema.plugins
            WHERE plugin_name='rpl_semi_sync_source');
SET @sql = IF(@cnt=0,
              "INSTALL PLUGIN rpl_semi_sync_source SONAME 'semisync_source.so'",
              "DO 0 /* plugin already installed */");
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET GLOBAL rpl_semi_sync_source_enabled = 1;
SET GLOBAL rpl_semi_sync_source_timeout = 10000;
SQL
```

### B4.2 — Ghi config bền vững (load plugin khi mysqld restart)

📝 **File**: `/etc/mysql/mysql.conf.d/zz-semisync.cnf`

```bash
cat >/etc/mysql/mysql.conf.d/zz-semisync.cnf <<'EOF'
[mysqld]
plugin_load_add                = "semisync_source.so;semisync_replica.so"
rpl_semi_sync_source_enabled   = 1
rpl_semi_sync_source_timeout   = 10000
rpl_semi_sync_replica_enabled  = 1
EOF
```

### B4.3 — Tạo user `repl` cho replication

```bash
mysql -uroot -p"${ROOT_PWD}" <<SQL
CREATE USER IF NOT EXISTS '${REPL_USER}'@'%' IDENTIFIED WITH mysql_native_password BY '${REPL_PWD}';
ALTER USER '${REPL_USER}'@'%' IDENTIFIED WITH mysql_native_password BY '${REPL_PWD}';
GRANT REPLICATION SLAVE, REPLICATION CLIENT ON *.* TO '${REPL_USER}'@'%';
FLUSH PRIVILEGES;
SQL
```

✅ **Verify** (trên node1):
```bash
mysql -uroot -p"${ROOT_PWD}" -e "
  SELECT plugin_name,plugin_status FROM information_schema.plugins
    WHERE plugin_name LIKE 'rpl_semi_sync%';
  SHOW STATUS LIKE 'Rpl_semi_sync_source_status';
  SELECT user,host,plugin FROM mysql.user WHERE user='repl';
  SHOW MASTER STATUS\G
"
# Expect:
#   rpl_semi_sync_source = ACTIVE
#   Rpl_semi_sync_source_status = ON
#   user repl@% với mysql_native_password
#   SHOW MASTER STATUS có File / Position / Executed_Gtid_Set
```

---

## B5 · Setup REPLICAS trên node2, node3

🖥️ **Where**: node2 và node3 (chạy CÙNG LOGIC trên cả 2)

```bash
vagrant ssh node2     # rồi node3
sudo -i
ROOT_PWD='ChangeMe!Root#2026'
REPL_USER='repl'
REPL_PWD='ChangeMe!Repl#2026'
MASTER_HOST='node1'   # hostname đã có trong /etc/hosts từ B2
```

### B5.1 — Cài plugin semi-sync replica

```bash
mysql -uroot -p"${ROOT_PWD}" <<'SQL'
SET @cnt = (SELECT COUNT(*) FROM information_schema.plugins
            WHERE plugin_name='rpl_semi_sync_replica');
SET @sql = IF(@cnt=0,
              "INSTALL PLUGIN rpl_semi_sync_replica SONAME 'semisync_replica.so'",
              "DO 0 /* plugin already installed */");
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET GLOBAL rpl_semi_sync_replica_enabled = 1;
SQL
```

### B5.2 — Cấu hình replication channel (GTID auto-position)

```bash
mysql -uroot -p"${ROOT_PWD}" <<SQL
STOP REPLICA;
RESET REPLICA ALL;
CHANGE REPLICATION SOURCE TO
  SOURCE_HOST='${MASTER_HOST}',
  SOURCE_PORT=3306,
  SOURCE_USER='${REPL_USER}',
  SOURCE_PASSWORD='${REPL_PWD}',
  SOURCE_AUTO_POSITION=1,
  SOURCE_SSL=1,
  GET_SOURCE_PUBLIC_KEY=1;
START REPLICA;
SQL
sleep 2
```

### B5.3 — Set read-only (chống ghi nhầm vào replica)

```bash
mysql -uroot -p"${ROOT_PWD}" <<'SQL'
SET GLOBAL read_only = ON;
SET GLOBAL super_read_only = ON;
SQL
```

### B5.4 — Ghi config bền vững (replica plugin load)

📝 **File**: `/etc/mysql/mysql.conf.d/zz-semisync.cnf` (giống node1 — load cả 2 plugin để có thể promote sau này)

```bash
cat >/etc/mysql/mysql.conf.d/zz-semisync.cnf <<'EOF'
[mysqld]
plugin_load_add                = "semisync_source.so;semisync_replica.so"
rpl_semi_sync_source_enabled   = 0
rpl_semi_sync_replica_enabled  = 1
EOF
```

✅ **Verify** (trên mỗi replica):
```bash
mysql -uroot -p"${ROOT_PWD}" -e "SHOW REPLICA STATUS\G" | egrep \
  'Source_Host|Replica_IO_Running|Replica_SQL_Running|Seconds_Behind_Source|Last_IO_Error|Last_SQL_Error|Auto_Position'
# Expect:
#   Source_Host: node1
#   Replica_IO_Running:  Yes
#   Replica_SQL_Running: Yes
#   Seconds_Behind_Source: 0
#   Last_IO_Error / Last_SQL_Error: (rỗng)
#   Auto_Position: 1

mysql -uroot -p"${ROOT_PWD}" -e "
  SHOW STATUS LIKE 'Rpl_semi_sync_replica_status';
  SELECT @@read_only,@@super_read_only;"
# Expect:
#   Rpl_semi_sync_replica_status = ON
#   read_only = 1, super_read_only = 1
```

Lặp lại B5.1 → B5.4 trên **cả node2 và node3**.

---

## B6 · Verify toàn bộ cluster

🖥️ **Where**: HOST (chạy từ thư mục `vagrant/`), hoặc mgmt với mysql-client cài sẵn

### B6.1 — Master phải thấy 2 clients semi-sync, status ON

```bash
vagrant ssh node1 -c "
  mysql -uroot -p'ChangeMe!Root#2026' -e \"
    SHOW STATUS LIKE 'Rpl_semi_sync_source_status';
    SHOW STATUS LIKE 'Rpl_semi_sync_source_clients';
    SHOW STATUS LIKE 'Rpl_semi_sync_source_yes_tx';
    SELECT host,thread_id FROM performance_schema.replication_connection_status;\""

# Expect:
#   Rpl_semi_sync_source_status   = ON
#   Rpl_semi_sync_source_clients  = 2
#   Rpl_semi_sync_source_yes_tx   = (số tx đã ack)
```

### B6.2 — Mỗi replica phải có IO+SQL=ON, lag=0, no error

```bash
for N in node2 node3; do
  echo "=== $N ==="
  vagrant ssh "$N" -c "
    mysql -uroot -p'ChangeMe!Root#2026' -e \"
      SELECT SERVICE_STATE AS IO  FROM performance_schema.replication_connection_status;
      SELECT SERVICE_STATE AS SQL FROM performance_schema.replication_applier_status;
      SHOW STATUS LIKE 'Rpl_semi_sync_replica_status';
      SELECT @@super_read_only;\""
done

# Expect (trên mỗi replica):
#   IO  = ON
#   SQL = ON
#   Rpl_semi_sync_replica_status = ON
#   super_read_only = 1
```

### B6.3 — Baseline GTID + binlog config 3 nodes

```bash
for N in node1 node2 node3; do
  echo "=== $N ==="
  vagrant ssh "$N" -c "
    mysql -uroot -p'ChangeMe!Root#2026' -e \"
      SELECT @@hostname, @@server_id, @@gtid_mode, @@log_bin, @@binlog_format, @@enforce_gtid_consistency;\""
done
```

---

## B7 · Smoke Test — chứng minh replication chạy

🖥️ **Where**: HOST (sử dụng `vagrant ssh`) hoặc mgmt

```bash
ROOT_PWD='ChangeMe!Root#2026'
ROWS=200
```

### B7.1 — Tạo schema test trên master

```bash
vagrant ssh node1 -c "mysql -uroot -p'${ROOT_PWD}' -e \"
  DROP DATABASE IF EXISTS smoke_db;
  CREATE DATABASE smoke_db CHARACTER SET utf8mb4;
  USE smoke_db;
  CREATE TABLE t (
    id  INT PRIMARY KEY AUTO_INCREMENT,
    val VARCHAR(64) NOT NULL,
    ts  DATETIME(6) DEFAULT CURRENT_TIMESTAMP(6)
  ) ENGINE=InnoDB;\""
```

### B7.2 — Insert N rows trên master

```bash
# Tạo SQL stream và pipe vào mysql (1 connection)
SQL=""
for i in $(seq 1 $ROWS); do
  SQL+="INSERT INTO t(val) VALUES('row-${i}');"
done
echo "USE smoke_db; ${SQL}" | vagrant ssh node1 -c "mysql -uroot -p'${ROOT_PWD}'"
```

### B7.3 — Đợi replicas catch-up + đếm rows

```bash
for N in node2 node3; do
  for i in $(seq 1 60); do
    CNT=$(vagrant ssh "$N" -c "mysql -uroot -p'${ROOT_PWD}' -N -e 'SELECT COUNT(*) FROM smoke_db.t;' 2>/dev/null" | tr -d '\r')
    if [[ "$CNT" == "$ROWS" ]]; then
      echo "[$N] OK: $CNT/$ROWS rows"
      break
    fi
    sleep 0.5
  done
done
```

### B7.4 — Verify semi-sync counter đã tăng

```bash
vagrant ssh node1 -c "mysql -uroot -p'${ROOT_PWD}' -e \"
  SHOW STATUS LIKE 'Rpl_semi_sync_source_yes_tx';
  SHOW STATUS LIKE 'Rpl_semi_sync_source_no_tx';\""

# yes_tx phải tăng ≥ ROWS, no_tx ≈ 0
```

### B7.5 — So sánh GTID_executed 3 nodes (phải giống nhau)

```bash
for N in node1 node2 node3; do
  echo "=== $N ==="
  vagrant ssh "$N" -c "mysql -uroot -p'${ROOT_PWD}' -N -e 'SELECT @@global.gtid_executed;'"
done
```

---

## B8 · Failover thủ công (OPTIONAL — destructive)

🖥️ **Where**: HOST + node2 (replica chọn promote)

> ⚠ Sau B8: node1 sẽ DOWN, node2 trở thành MASTER mới, node3 trỏ về node2.
> Để chạy lại demo, làm `vagrant up node1` rồi tự reconfigure node1 làm replica.

### B8.1 — Insert sentinel row (để verify sau)

```bash
SENT="failover-sentinel-$(date +%s)"
vagrant ssh node1 -c "mysql -uroot -p'ChangeMe!Root#2026' -e \"
  INSERT INTO smoke_db.t(val) VALUES('${SENT}');\""
sleep 2    # cho replicas nhận
```

### B8.2 — HALT node1 (simulate crash)

```bash
vagrant halt --force node1
sleep 3   # cho node2/3 detect IO error
```

### B8.3 — Promote node2 thành master mới

```bash
vagrant ssh node2 << 'OUTER'
sudo -i
ROOT_PWD='ChangeMe!Root#2026'

# 1) Đợi SQL thread apply hết relay log đã có
mysql -uroot -p"${ROOT_PWD}" -e "STOP REPLICA IO_THREAD;"
until mysql -uroot -p"${ROOT_PWD}" -e "SHOW REPLICA STATUS\G" \
    | grep -E 'Seconds_Behind_Source: 0|Replica has read all relay log' >/dev/null; do
  echo "    chờ relay log apply xong..."
  sleep 2
done

# 2) Tháo replication, mở write
mysql -uroot -p"${ROOT_PWD}" <<SQL
STOP REPLICA;
RESET REPLICA ALL;
SET GLOBAL read_only = OFF;
SET GLOBAL super_read_only = OFF;
SET GLOBAL rpl_semi_sync_source_enabled = 1;
SQL
OUTER
```

### B8.4 — Trỏ node3 về master mới (node2)

```bash
NEW_MASTER_IP='192.168.10.12'
vagrant ssh node3 -c "
  mysql -uroot -p'ChangeMe!Root#2026' <<SQL
STOP REPLICA;
CHANGE REPLICATION SOURCE TO
  SOURCE_HOST='${NEW_MASTER_IP}',
  SOURCE_AUTO_POSITION=1;
START REPLICA;
SQL"
```

### B8.5 — Verify topology mới

```bash
# Write trên node2 (master mới)
vagrant ssh node2 -c "mysql -uroot -p'ChangeMe!Root#2026' -e \"
  INSERT INTO smoke_db.t(val) VALUES('post-failover-1');\""

# Check node3 nhận được
sleep 2
vagrant ssh node3 -c "mysql -uroot -p'ChangeMe!Root#2026' -e \"
  SELECT COUNT(*) FROM smoke_db.t WHERE val LIKE 'post-failover-%';\""
# Expect: 1
```

---

## B9 · Rollback (OPTIONAL)

🖥️ **Where**: HOST

### B9.1 — Soft rollback (tháo replication, giữ VMs)

```bash
ROOT_PWD='ChangeMe!Root#2026'

# Replicas trước
for N in node2 node3; do
  vagrant ssh "$N" -c "
    mysql -uroot -p'${ROOT_PWD}' -e \"
      STOP REPLICA;
      RESET REPLICA ALL;
      SET GLOBAL super_read_only=0;
      SET GLOBAL read_only=0;
      UNINSTALL PLUGIN rpl_semi_sync_replica;\" 2>/dev/null || true
    sudo rm -f /etc/mysql/mysql.conf.d/zz-semisync.cnf
  "
done

# Master
vagrant ssh node1 -c "
  mysql -uroot -p'${ROOT_PWD}' -e \"
    SET GLOBAL rpl_semi_sync_source_enabled=0;
    UNINSTALL PLUGIN rpl_semi_sync_source;
    DROP DATABASE IF EXISTS smoke_db;
    RESET MASTER;\" 2>/dev/null || true
  sudo rm -f /etc/mysql/mysql.conf.d/zz-semisync.cnf
"
```

### B9.2 — Hard rollback (destroy VMs)

```bash
cd vagrant
vagrant destroy -f
rm -f provision/cluster_id_rsa provision/cluster_id_rsa.pub
```

---

## Phụ lục A — Trouble-shooting nhanh

### A.1 Replica IO=OFF, Last_IO_Error = `Access denied for user 'repl'@...`
→ User repl chưa có trên master, hoặc password sai. Re-run B4.3.

### A.2 Replica IO=OFF, Last_IO_Error = `Could not find first log file name`
→ Master đã `PURGE BINARY LOGS` quá xa. Re-clone replica:
```sql
-- Trên replica: dùng clone plugin
INSTALL PLUGIN clone SONAME 'mysql_clone.so';
SET GLOBAL clone_valid_donor_list='node1:3306';
CLONE INSTANCE FROM 'repl'@'node1':3306 IDENTIFIED BY 'ChangeMe!Repl#2026';
```

### A.3 `Rpl_semi_sync_source_status = OFF` nhưng có 2 clients
→ Plugin loaded nhưng disabled. Chạy lại:
```sql
SET GLOBAL rpl_semi_sync_source_enabled = 1;
```

### A.4 Replica lag càng lúc càng tăng
→ Bật multi-thread applier:
```sql
STOP REPLICA SQL_THREAD;
SET GLOBAL replica_parallel_workers = 8;
SET GLOBAL replica_parallel_type = 'LOGICAL_CLOCK';
SET GLOBAL replica_preserve_commit_order = ON;
START REPLICA SQL_THREAD;
```

### A.5 `rpl_semi_sync_source_timeout` hết → fallback async
→ Bình thường (10s timeout). Khi replica live lại sẽ tự bật lại semi-sync. Theo dõi:
```sql
SHOW STATUS LIKE 'Rpl_semi_sync_source_no_tx';     -- tx không nhận ack
SHOW STATUS LIKE 'Rpl_semi_sync_source_yes_tx';    -- tx được ack
```

---

## Phụ lục B — Tóm tắt files config

Toàn bộ file ghi mới trong demo này:

| Host        | File                                                  | Mô tả                                         |
|-------------|-------------------------------------------------------|-----------------------------------------------|
| 4 nodes     | `/etc/hosts` (block `mysql-ha cluster`)               | resolve hostname → IP                          |
| 4 nodes     | `/etc/fstab` (swap dòng comment)                      | tắt swap vĩnh viễn                             |
| 4 nodes     | `/etc/sysctl.d/99-mysql-ha.conf`                      | tuning kernel cho MySQL                        |
| 4 nodes     | `/etc/systemd/system/mysql.service.d/limits.conf`     | ulimit cho mysql                                |
| 3 DB nodes  | `/etc/apt/sources.list.d/mysql.list`                  | repo MySQL 8.0 + tools                          |
| 3 DB nodes  | `/etc/mysql/mysql.conf.d/zz-mysql-ha.cnf`             | server_id, gtid, binlog, bind                  |
| 3 DB nodes  | `/etc/mysql/mysql.conf.d/zz-semisync.cnf`             | plugin_load_add + semi-sync vars               |

Toàn bộ user/privilege thay đổi trong mysql:

| User        | Tạo ở | Host pattern | Privilege                                |
|-------------|-------|--------------|-------------------------------------------|
| `root`      | sẵn   | localhost    | (đổi password = `ChangeMe!Root#2026`)    |
| `repl`      | B4.3  | `%`          | REPLICATION SLAVE, REPLICATION CLIENT     |

---

## Phụ lục C — Mapping bash scripts ↔ manual steps

Nếu bạn muốn xem script gốc:

| Script trong repo                                          | Bước trong tài liệu |
|------------------------------------------------------------|----------------------|
| `scripts/common/00-prepare-os.sh`                          | B2                   |
| `scripts/common/01-install-mysql.sh`                       | B3                   |
| `scripts/common/02-firewall.sh`                            | (không cần — Vagrant private network không block) |
| `scripts/async-semisync/master-setup.sh`                   | B4                   |
| `scripts/async-semisync/replica-setup.sh`                  | B5                   |
| `scripts/async-semisync/manual-failover.sh`                | B8                   |
| `demo/01-async-semisync/06-verify.sh`                      | B6                   |
| `demo/01-async-semisync/07-smoke-test.sh`                  | B7                   |
| `demo/01-async-semisync/09-rollback.sh`                    | B9                   |

> 💡 Tip: chạy `run-all.ps1` thực chất là wrapper gọi các script trên qua `vagrant ssh ... bash /vagrant/scripts/...`. Manual setup chỉ cần copy nội dung script vào shell của từng node — không có gì "ẩn".


---

!!! info "Nguồn gốc"
    `HA/Mysql/demo/01-async-semisync/MANUAL-SETUP.md`
