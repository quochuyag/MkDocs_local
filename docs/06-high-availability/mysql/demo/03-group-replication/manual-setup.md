---
title: Hướng dẫn setup THỦ CÔNG — Demo 03 MySQL Group Replication thuần
course: 06-high-availability
source: HA/Mysql/demo/03-group-replication/MANUAL-SETUP.md
---

# Hướng dẫn setup THỦ CÔNG — Demo 03 MySQL Group Replication thuần

> Tài liệu này ghi lại **TỪNG CÂU LỆNH** để dựng giải pháp 03 (**Group Replication "thuần"** — KHÔNG qua `mysqlsh dba.*`, KHÔNG có MySQL Router) mà không cần `run-all.sh` / `run-all.ps1`. Copy-paste theo thứ tự từ trên xuống. Mỗi bước nêu rõ:
> - 🖥️ **Where**: chạy ở đâu (HOST / node1 / node2 / node3 / mgmt)
> - 💻 **Command**: lệnh CLI hoặc SQL
> - 📝 **File**: cấu hình cần ghi (nếu có)
> - ✅ **Verify**: cách kiểm tra step OK + output kỳ vọng

## 0. Topology & biến môi trường

| Host  | IP              | Vai trò                                   | server_id |
|-------|-----------------|-------------------------------------------|-----------|
| node1 | 192.168.10.11   | GR member — PRIMARY ban đầu (bootstrap)   | 1         |
| node2 | 192.168.10.12   | GR member — SECONDARY                     | 2         |
| node3 | 192.168.10.13   | GR member — SECONDARY                     | 3         |
| mgmt  | 192.168.10.20   | Client/observer (KHÔNG có MySQL server)   | —         |

Credentials mặc định (đổi nếu muốn — xem [scripts/common/env.sh](../../scripts/common/env.sh)):

```
MYSQL_ROOT_PWD = ChangeMe!Root#2026
REPL_USER      = repl                       # user của group_replication_recovery channel
REPL_PWD       = ChangeMe!Repl#2026
GR_GROUP_UUID  = aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa   # ID cố định của group
```

Ports: `22, 3306, 33060 (X-protocol), 33061 (Group Replication / XCom)`.

> ⚠ Demo này **KHÔNG dùng mysqlsh dba.* APIs** (đó là Demo 02 / InnoDB Cluster). Tất cả thao tác qua `mysql` client + SQL trực tiếp. Vì vậy KHÔNG cần URL-encode password — `mysql -p<pwd>` truyền raw.

---

## B0 · Prerequisites trên HOST

🖥️ **Where**: HOST (Windows / macOS / Linux)

```bash
# Linux/macOS — cài Vagrant + VirtualBox qua package manager
# Windows — tải installer:
#   https://www.virtualbox.org/wiki/Downloads     (≥ 7.0)
#   https://www.vagrantup.com/downloads           (≥ 2.3)
#   https://git-scm.com/download/win              (Git Bash, để có ssh-keygen)
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

> ⚠ Nếu lỗi `VERR_INTNET_FLT_IF_NOT_FOUND` (Host-Only Adapter "ghost-bind"), chạy fix-script (administrator):
> ```powershell
> demo\01-async-semisync\fix-vbox-hostonly.ps1
> ```

✅ **Verify**:
```bash
vagrant status
# Tất cả 4 VM: running (virtualbox)

vagrant ssh node1 -c "ping -c1 -W2 node2 && ping -c1 -W2 node3 && ping -c1 -W2 mgmt"
```

> 💡 **Lưu ý 2 NIC**: mỗi VM có eth0=NAT (`10.0.2.15`, dùng chung 4 VMs) + eth1=hostonly (`192.168.10.x`, unique). XCom của Group Replication phải gắn vào IP private (`192.168.10.x`), nếu không 3 node sẽ trùng identity `10.0.2.15:33061` → GR báo *"Old incarnation found"*. Lưu ý này quan trọng cho B4/B5.

---

## B2 · Prepare OS — chạy TRÊN MỖI 4 NODES

🖥️ **Where**: node1, node2, node3, mgmt (4 lần) — chạy với `sudo`

```bash
vagrant ssh node1     # rồi node2, node3, mgmt
sudo -i
```

### B2.1 — Cập nhật `/etc/hosts`

📝 **File**: `/etc/hosts` — thêm block (idempotent: marker `>>>/<<<`)

```bash
sed -i '/# >>> mysql-ha cluster >>>/,/# <<< mysql-ha cluster <<</d' /etc/hosts
cat >>/etc/hosts <<'EOF'
# >>> mysql-ha cluster >>>
192.168.10.11  node1
192.168.10.12  node2
192.168.10.13  node3
192.168.10.20  mgmt
# <<< mysql-ha cluster <<<
EOF
```

> ⚠ Ubuntu vagrant cloud-init thêm dòng `127.0.2.1 <hostname>` → `getent hosts node1` có thể trả về `127.0.2.1` (loopback). Đó là lý do **B3.7** phải set `report_host = <IP private>` (KHÔNG dùng hostname), nếu không Group Replication sẽ từ chối join.

### B2.2 — Tắt swap

```bash
swapoff -a
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

📝 **File**: `/etc/systemd/system/mysql.service.d/limits.conf`

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

Lặp lại B2.1 → B2.6 trên **cả 4 nodes** (node1, node2, node3, mgmt).

---

## B3 · Cài MySQL 8.0 SERVER — chạy TRÊN 3 DB NODES (node1, node2, node3)

🖥️ **Where**: node1, node2, node3 (KHÔNG cài server trên mgmt — mgmt chỉ làm client/observer)

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
```

### B3.4 — Refresh GPG key MySQL

```bash
for KS in \
    hkps://keyserver.ubuntu.com:443 \
    hkps://keys.openpgp.org:443 \
    hkps://pgp.mit.edu:443 \
    hkp://keyserver.ubuntu.com:80; do
  if timeout 30 gpg --no-default-keyring \
       --keyring /etc/apt/trusted.gpg.d/mysql.gpg \
       --keyserver "${KS}" --refresh-keys 2>/dev/null; then
    break
  fi
done
```

### B3.5 — Probe + fallback `[trusted=yes]` cho LAB

```bash
PROBE_LOG=$(mktemp)
apt-get update 2>&1 | tee "${PROBE_LOG}" || true
if grep -qE 'EXPKEYSIG|NO_PUBKEY|is not signed' "${PROBE_LOG}"; then
  sed -i -E 's|^deb (\[[^]]+\] )?(http)|deb [trusted=yes] \2|'      /etc/apt/sources.list.d/mysql.list
  sed -i -E 's|^deb-src (\[[^]]+\] )?(http)|deb-src [trusted=yes] \2|' /etc/apt/sources.list.d/mysql.list
  apt-get update
fi
rm -f "${PROBE_LOG}"
```

### B3.6 — Cài MySQL server (KHÔNG cài shell/router cho demo 03)

```bash
ROOT_PWD='ChangeMe!Root#2026'
echo "mysql-community-server mysql-community-server/root-pass    password ${ROOT_PWD}" | debconf-set-selections
echo "mysql-community-server mysql-community-server/re-root-pass password ${ROOT_PWD}" | debconf-set-selections
DEBIAN_FRONTEND=noninteractive apt-get install -y mysql-server
```

> 💡 Demo 03 KHÔNG cần `mysql-shell` (vì không dùng `dba.*`) và KHÔNG cần `mysql-router` (vì không có proxy ở data plane mặc định). Nếu muốn ghép ProxySQL sau, xem Demo 07.

### B3.7 — Ghi config MySQL baseline (gtid + binlog + report_host=IP)

📝 **File**: `/etc/mysql/mysql.conf.d/zz-mysql-ha.cnf`

> ⚠ `server_id` và `report_host` khác nhau trên mỗi node. **`report_host` PHẢI là IP private 192.168.10.x** (KHÔNG phải hostname) — vì Ubuntu cloud-init khiến `node1` resolve về `127.0.2.1` → GR refuse hoặc các IP advertised sai.

```bash
HOST=$(hostname)
case "$HOST" in
  node1) SID=1; REPORT_HOST=192.168.10.11 ;;
  node2) SID=2; REPORT_HOST=192.168.10.12 ;;
  node3) SID=3; REPORT_HOST=192.168.10.13 ;;
  *)     SID=$(( ( RANDOM % 1000 ) + 10 )); REPORT_HOST=$(hostname -I | awk '{print $1}') ;;
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
report_host              = ${REPORT_HOST}
EOF

systemctl restart mysql
sleep 3
```

### B3.8 — Mở firewall (UFW)

```bash
ufw allow OpenSSH || ufw allow 22/tcp
ufw allow 3306/tcp     # MySQL client
ufw allow 33060/tcp    # X-protocol
ufw allow 33061/tcp    # ⚡ GR XCom — quan trọng cho Group Replication
ufw --force enable
```

> ⚠ Phải `ufw allow 22/tcp` (hoặc `OpenSSH`) **TRƯỚC** khi `ufw enable`. Nếu enable trước, default policy `deny incoming` sẽ chặn SSH → vagrant không vào lại được, chỉ recover bằng `vagrant destroy`.

✅ **Verify** (trên mỗi node):
```bash
systemctl is-active mysql                            # active
ss -tlnp | grep ':3306 '                             # listening
mysql -uroot -p"${ROOT_PWD}" -e "
  SELECT @@hostname,@@server_id,@@report_host,@@gtid_mode,@@log_bin,@@binlog_format;"
# Expect:
#   server_id   = 1|2|3 đúng theo node
#   report_host = 192.168.10.{11,12,13} (KHÔNG phải hostname)
#   gtid_mode   = ON / log_bin = 1 / binlog_format = ROW
```

Lặp lại B3.1 → B3.8 trên **cả node1, node2, node3**.

---

## B4 · Bootstrap Group Replication trên node1 (CHỈ NODE1, CHỈ 1 LẦN)

🖥️ **Where**: node1

```bash
vagrant ssh node1
sudo -i
ROOT_PWD='ChangeMe!Root#2026'
REPL_USER='repl'
REPL_PWD='ChangeMe!Repl#2026'
GR_GROUP_UUID='aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
NODE1_IP=192.168.10.11
NODE2_IP=192.168.10.12
NODE3_IP=192.168.10.13
```

### B4.1 — Ghi config Group Replication

📝 **File**: `/etc/mysql/mysql.conf.d/zz-group-replication.cnf`

> ⚠ **`ip_allowlist` PHẢI bao gồm cả NAT subnet `10.0.2.0/24`**. Vagrant box có 2 NIC: eth0=NAT (10.0.2.15, **dùng chung 4 VMs**) và eth1=hostonly (192.168.10.x). Khi GR/XCom self-check, kernel có thể chọn 10.0.2.15 làm source IP cho self-connection (vì default route đi qua eth0) → bị reject nếu ip_allowlist chỉ có 192.168.10.x → lỗi *"Connection attempt from IP address ::ffff:10.0.2.15 refused"*.
>
> ⚠ **`local_address` PHẢI là IP hostonly `192.168.10.11`** (không phải `10.0.2.15`). Nếu set sai, node1 advertise identity `10.0.2.15:33061` ra group → khi node2/node3 join cũng dùng `10.0.2.15` → GR thấy 3 node trùng identity → *"Old incarnation found"*.

```bash
cat >/etc/mysql/mysql.conf.d/zz-group-replication.cnf <<EOF
[mysqld]
plugin_load_add                       = "group_replication.so"
transaction_write_set_extraction      = XXHASH64
binlog_checksum                       = NONE
loose-group_replication_group_name    = "${GR_GROUP_UUID}"
loose-group_replication_start_on_boot = OFF
loose-group_replication_local_address = "${NODE1_IP}:33061"
loose-group_replication_group_seeds   = "${NODE1_IP}:33061,${NODE2_IP}:33061,${NODE3_IP}:33061"
loose-group_replication_bootstrap_group           = OFF
loose-group_replication_single_primary_mode       = ON
loose-group_replication_enforce_update_everywhere_checks = OFF
loose-group_replication_ip_allowlist  = "${NODE1_IP},${NODE2_IP},${NODE3_IP},10.0.2.0/24,127.0.0.1/32"
EOF

systemctl restart mysql
sleep 5
```

### B4.2 — Tạo user `repl@%` cho recovery channel

> 💡 `mysql_native_password` được dùng (không phải `caching_sha2_password`) vì recovery channel kết nối từ donor → joiner qua raw TCP — `caching_sha2` cần TLS hoặc RSA key trao đổi, phức tạp hơn cho lab.

```bash
mysql -uroot -p"${ROOT_PWD}" <<SQL
SET SQL_LOG_BIN=0;
CREATE USER IF NOT EXISTS '${REPL_USER}'@'%' IDENTIFIED WITH mysql_native_password BY '${REPL_PWD}';
GRANT REPLICATION SLAVE, CONNECTION_ADMIN, BACKUP_ADMIN, GROUP_REPLICATION_STREAM ON *.* TO '${REPL_USER}'@'%';
SET SQL_LOG_BIN=1;
CHANGE REPLICATION SOURCE TO
  SOURCE_USER='${REPL_USER}',
  SOURCE_PASSWORD='${REPL_PWD}'
FOR CHANNEL 'group_replication_recovery';
SQL
```

### B4.3 — Bootstrap group (chỉ chạy LẦN ĐẦU TIÊN trên node1)

```bash
mysql -uroot -p"${ROOT_PWD}" <<SQL
SET GLOBAL group_replication_bootstrap_group = ON;
START GROUP_REPLICATION;
SET GLOBAL group_replication_bootstrap_group = OFF;
SQL
```

> ⚠ Nếu phải bootstrap LẠI (vd sau khi B5 fail và bạn đã sửa config rồi muốn start sạch), trước khi chạy SQL trên cần `STOP GROUP_REPLICATION;` + `systemctl restart mysql` để clear XCom in-memory state. Nếu không, node1 nhớ "Old incarnation" của node2 cũ → reject join.

### B4.4 — Verify node1 ONLINE + PRIMARY

```bash
mysql -uroot -p"${ROOT_PWD}" -e "
  SELECT MEMBER_ID, MEMBER_HOST, MEMBER_PORT, MEMBER_STATE, MEMBER_ROLE
  FROM performance_schema.replication_group_members;"

# Expect:
# MEMBER_HOST    MEMBER_STATE   MEMBER_ROLE
# 192.168.10.11  ONLINE         PRIMARY
```

---

## B5 · Join node2 và node3 vào group

🖥️ **Where**: node2 và node3 — chạy **lần lượt**, cùng pattern

```bash
vagrant ssh node2    # rồi node3
sudo -i
ROOT_PWD='ChangeMe!Root#2026'
REPL_USER='repl'
REPL_PWD='ChangeMe!Repl#2026'
GR_GROUP_UUID='aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
NODE1_IP=192.168.10.11
NODE2_IP=192.168.10.12
NODE3_IP=192.168.10.13
```

### B5.1 — Phát hiện local IP — phải pick **HOSTONLY**, không phải NAT

> ⚠ `hostname -I` trả về cả `10.0.2.15 192.168.10.12` (NAT trước, hostonly sau). Nếu lấy `awk '{print $1}'` sẽ ra NAT IP → GR fail (xem cảnh báo B4.1). Phải filter cụ thể cho subnet 192.168.10.0/24:

```bash
LOCAL_IP=$(hostname -I | tr ' ' '\n' | grep -E "^(${NODE1_IP}|${NODE2_IP}|${NODE3_IP})$" | head -n1)
echo "LOCAL_IP=${LOCAL_IP}"     # node2 → 192.168.10.12, node3 → 192.168.10.13
```

### B5.2 — Ghi config Group Replication

📝 **File**: `/etc/mysql/mysql.conf.d/zz-group-replication.cnf`

```bash
cat >/etc/mysql/mysql.conf.d/zz-group-replication.cnf <<EOF
[mysqld]
plugin_load_add                       = "group_replication.so"
transaction_write_set_extraction      = XXHASH64
binlog_checksum                       = NONE
loose-group_replication_group_name    = "${GR_GROUP_UUID}"
loose-group_replication_start_on_boot = OFF
loose-group_replication_local_address = "${LOCAL_IP}:33061"
loose-group_replication_group_seeds   = "${NODE1_IP}:33061,${NODE2_IP}:33061,${NODE3_IP}:33061"
loose-group_replication_bootstrap_group           = OFF
loose-group_replication_single_primary_mode       = ON
loose-group_replication_ip_allowlist  = "${NODE1_IP},${NODE2_IP},${NODE3_IP},10.0.2.0/24,127.0.0.1/32"
EOF

systemctl restart mysql
sleep 5
```

### B5.3 — Tạo user repl (idempotent) + cấu hình recovery channel + START GR

```bash
mysql -uroot -p"${ROOT_PWD}" <<SQL
SET SQL_LOG_BIN=0;
CREATE USER IF NOT EXISTS '${REPL_USER}'@'%' IDENTIFIED WITH mysql_native_password BY '${REPL_PWD}';
GRANT REPLICATION SLAVE, CONNECTION_ADMIN, BACKUP_ADMIN, GROUP_REPLICATION_STREAM ON *.* TO '${REPL_USER}'@'%';
SET SQL_LOG_BIN=1;

CHANGE REPLICATION SOURCE TO
  SOURCE_USER='${REPL_USER}',
  SOURCE_PASSWORD='${REPL_PWD}'
FOR CHANNEL 'group_replication_recovery';

START GROUP_REPLICATION;
SQL
```

> 💡 **KHÔNG** `SET GLOBAL group_replication_bootstrap_group = ON` trên secondary — chỉ node1 bootstrap. Secondary join vào group đã tồn tại qua seeds.
>
> 💡 GR_GROUP_UUID giống hệt node1 → node2/3 biết được join vào đúng group.

### B5.4 — Verify node2 (hoặc node3) đã ONLINE

```bash
sleep 5
mysql -uroot -p"${ROOT_PWD}" -e "
  SELECT MEMBER_HOST, MEMBER_STATE, MEMBER_ROLE
  FROM performance_schema.replication_group_members
  ORDER BY MEMBER_HOST;"

# Sau node2 join:
# 192.168.10.11  ONLINE  PRIMARY
# 192.168.10.12  ONLINE  SECONDARY

# Sau node3 join:
# 192.168.10.11  ONLINE  PRIMARY
# 192.168.10.12  ONLINE  SECONDARY
# 192.168.10.13  ONLINE  SECONDARY
```

Lặp lại B5.1 → B5.4 trên **node3**.

---

## B6 · Verify toàn bộ cluster

🖥️ **Where**: HOST (qua `vagrant ssh`)

### B6.1 — Service + ports listen + GR plugin trên 3 nodes

```bash
for N in node1 node2 node3; do
  echo "=== $N ==="
  vagrant ssh "$N" -c "
    sudo systemctl is-active mysql
    sudo ss -tlnp | grep -E ':3306 |:33061 '
    mysql -uroot -p'ChangeMe!Root#2026' -N -e \"
      SELECT @@gtid_mode,@@enforce_gtid_consistency,@@binlog_format;
      SELECT plugin_status FROM information_schema.plugins WHERE plugin_name='group_replication';\""
done
# Expect mỗi node:
#   mysql active
#   ports 3306 + 33061 listening
#   gtid_mode=ON, enforce_gtid=ON, binlog=ROW
#   plugin_status=ACTIVE
```

### B6.2 — Group state + super_read_only

```bash
vagrant ssh node1 -c "
  mysql -uroot -p'ChangeMe!Root#2026' -e \"
    SELECT MEMBER_HOST, MEMBER_STATE, MEMBER_ROLE
    FROM performance_schema.replication_group_members
    ORDER BY MEMBER_HOST;
    -- Lưu ý: super_read_only=0 trên PRIMARY, =1 trên SECONDARY
    SELECT @@hostname AS host, @@super_read_only AS sro;\""

# Cross-check trên 2 nodes còn lại
for N in node2 node3; do
  vagrant ssh "$N" -c "
    mysql -uroot -p'ChangeMe!Root#2026' -N -e \"
      SELECT '$N' AS node, @@super_read_only;\""
done
# Expect: PRIMARY (node1) → 0,  SECONDARY (node2,3) → 1
```

### B6.3 — GTID đồng bộ 3 node

```bash
for N in node1 node2 node3; do
  vagrant ssh "$N" -c "
    mysql -uroot -p'ChangeMe!Root#2026' -N -e \"
      SELECT '$N' AS node, @@global.gtid_executed;\""
done
# Expect: cả 3 node trả về cùng GTID range
#   aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa:1-5
```

---

## B7 · Smoke test — INSERT qua PRIMARY, đo lag đồng bộ trên 2 SECONDARY

🖥️ **Where**: HOST

> 💡 Khác Demo 02 (qua Router 6446/6447), demo này connect **trực tiếp** tới PRIMARY (`node1:3306`). Khi PRIMARY thay đổi sau failover, app phải tự sniff member mới (qua `replication_group_members`) hoặc dùng proxy ngoài (xem Demo 07).

### B7.1 — Tìm PRIMARY hiện tại + map IP → hostname

```bash
# performance_schema trả về MEMBER_HOST = IP (192.168.10.x), vagrant ssh cần hostname
PRIMARY_IP=$(vagrant ssh node1 -c "
  mysql -uroot -p'ChangeMe!Root#2026' -N -B -e \"
    SELECT MEMBER_HOST FROM performance_schema.replication_group_members
    WHERE MEMBER_ROLE='PRIMARY';\" 2>/dev/null" | tr -d '\r')
case "${PRIMARY_IP}" in
  192.168.10.11) PRIMARY=node1 ;;
  192.168.10.12) PRIMARY=node2 ;;
  192.168.10.13) PRIMARY=node3 ;;
esac
echo "PRIMARY = ${PRIMARY} (${PRIMARY_IP})"
```

### B7.2 — CREATE schema + table

```bash
vagrant ssh "${PRIMARY}" -c "mysql -uroot -p'ChangeMe!Root#2026' <<'SQL'
DROP DATABASE IF EXISTS smoke_db;
CREATE DATABASE smoke_db CHARACTER SET utf8mb4;
USE smoke_db;
CREATE TABLE t (
  id  INT PRIMARY KEY AUTO_INCREMENT,
  val VARCHAR(64) NOT NULL,
  ts  DATETIME(6) DEFAULT CURRENT_TIMESTAMP(6)
) ENGINE=InnoDB;
SQL"
```

### B7.3 — Bulk INSERT 200 rows qua PRIMARY

```bash
ROWS=200
INSERT_SQL="USE smoke_db;"
for i in $(seq 1 ${ROWS}); do
  INSERT_SQL+="INSERT INTO t(val) VALUES('row-${i}');"
done

printf '%s' "${INSERT_SQL}" | vagrant ssh "${PRIMARY}" -c \
  "mysql -uroot -p'ChangeMe!Root#2026'" >/dev/null
```

### B7.4 — Đếm row trên 3 nodes (đợi sync < 1s)

```bash
sleep 1
for N in node1 node2 node3; do
  vagrant ssh "$N" -c "
    mysql -uroot -p'ChangeMe!Root#2026' -N -e \"
      SELECT '$N' AS node, COUNT(*) AS rows_seen FROM smoke_db.t;\""
done
# Expect: cả 3 node = 200 rows. GTID range tăng từ :1-5 → :1-205
```

✅ **Smoke pass** = 3 node cùng count + cùng GTID range.

---

## B8 · Failover test — halt PRIMARY, đo PROMOTE_RTO + WRITE_RTO (OPTIONAL — destructive)

🖥️ **Where**: HOST

> ⚠ Bước này **HALT** primary. Cluster sẽ tự bầu primary mới giữa 2 secondary trong ≤30s. Sau bước này, node1 sẽ DOWN — phải `vagrant up node1` rồi `START GROUP_REPLICATION` để rejoin.

### B8.1 — Insert sentinel + halt PRIMARY

```bash
# Tìm PRIMARY (xem B7.1)
PRIMARY=node1   # giả sử
SENT_VAL="failover-sentinel-$(date +%s)"

vagrant ssh "${PRIMARY}" -c "
  mysql -uroot -p'ChangeMe!Root#2026' -e \"
    INSERT INTO smoke_db.t(val) VALUES('${SENT_VAL}');\""

HALT_TS=$(date +%s)
vagrant halt --force "${PRIMARY}"
```

### B8.2 — Poll secondary đến khi thấy PRIMARY mới

```bash
QUERY_NODE=node2    # secondary còn sống bất kỳ
NEW_PRIMARY=""
for i in $(seq 1 60); do
  NP_IP=$(vagrant ssh "${QUERY_NODE}" -c "
    mysql -uroot -p'ChangeMe!Root#2026' -N -B -e \"
      SELECT MEMBER_HOST FROM performance_schema.replication_group_members
      WHERE MEMBER_ROLE='PRIMARY' AND MEMBER_STATE='ONLINE'
      LIMIT 1;\" 2>/dev/null" 2>/dev/null | tr -d '\r' | tr -d '[:space:]')
  if [[ -n "${NP_IP}" && "${NP_IP}" != "192.168.10.11" ]]; then
    PROMOTE_RTO=$(( $(date +%s) - HALT_TS ))
    case "${NP_IP}" in
      192.168.10.12) NEW_PRIMARY=node2 ;;
      192.168.10.13) NEW_PRIMARY=node3 ;;
    esac
    echo "NEW PRIMARY = ${NEW_PRIMARY} (${NP_IP}) sau ${PROMOTE_RTO}s"
    break
  fi
  sleep 1
done
```

### B8.3 — Đo WRITE_RTO: thử INSERT vào NEW_PRIMARY

```bash
for i in $(seq 1 60); do
  if vagrant ssh "${NEW_PRIMARY}" -c "
      mysql -uroot -p'ChangeMe!Root#2026' smoke_db \
        -e 'INSERT INTO t(val) VALUES(\"post-failover-probe\");'" >/dev/null 2>&1; then
    WRITE_RTO=$(( $(date +%s) - HALT_TS ))
    echo "WRITE_RTO = ${WRITE_RTO}s (${NEW_PRIMARY} accepts writes)"
    break
  fi
  sleep 1
done
```

### B8.4 — Confirm group state trên 2 node sống

```bash
vagrant ssh "${NEW_PRIMARY}" -c "
  mysql -uroot -p'ChangeMe!Root#2026' -e \"
    SELECT MEMBER_HOST, MEMBER_STATE, MEMBER_ROLE
    FROM performance_schema.replication_group_members
    ORDER BY MEMBER_HOST;\""

# Expect:
#   192.168.10.11  UNREACHABLE   <NULL>      (node bị halt)
#   192.168.10.12  ONLINE        PRIMARY   ← (hoặc node3, tuỳ bầu)
#   192.168.10.13  ONLINE        SECONDARY
```

### B8.5 — Rejoin node1

```bash
vagrant up node1
sleep 20

vagrant ssh node1 -c "
  mysql -uroot -p'ChangeMe!Root#2026' -e 'START GROUP_REPLICATION;'"

sleep 5
vagrant ssh "${NEW_PRIMARY}" -c "
  mysql -uroot -p'ChangeMe!Root#2026' -e \"
    SELECT MEMBER_HOST, MEMBER_STATE, MEMBER_ROLE
    FROM performance_schema.replication_group_members;\""
# Expect: 3 ONLINE — node1 đã thành SECONDARY (primary mới giữ ngôi)
```

> 💡 Nếu node1 tụt GTID quá nhiều (data đã đè trên primary mới), `START GROUP_REPLICATION` sẽ fail. Khi đó dùng Clone Plugin:
> ```sql
> -- trên node1
> SET GLOBAL clone_valid_donor_list='192.168.10.12:3306';
> CLONE INSTANCE FROM 'repl'@'192.168.10.12':3306 IDENTIFIED BY 'ChangeMe!Repl#2026';
> -- MySQL sẽ restart sau khi clone xong, tự rejoin
> ```

---

## B9 · Rollback (OPTIONAL)

🖥️ **Where**: HOST

### B9.1 — Soft rollback — stop GR, drop smoke_db, giữ VMs

```bash
for N in node1 node2 node3; do
  vagrant ssh "$N" -c "
    mysql -uroot -p'ChangeMe!Root#2026' -e \"
      STOP GROUP_REPLICATION;
      RESET REPLICA ALL FOR CHANNEL 'group_replication_recovery';
      DROP DATABASE IF EXISTS smoke_db;
      SET GLOBAL super_read_only=0;
      SET GLOBAL read_only=0;\" 2>/dev/null || true
    sudo rm -f /etc/mysql/mysql.conf.d/zz-group-replication.cnf
    sudo systemctl restart mysql"
done
```

### B9.2 — Hard rollback — destroy VMs

```bash
cd vagrant
vagrant destroy -f
rm -f provision/cluster_id_rsa provision/cluster_id_rsa.pub
```

---

## Phụ lục A — Trouble-shooting nhanh (lessons learned trong session test thực tế)

### A.1 `ERROR 3092: The server is not configured properly to be an active member of the group` (trên secondary)

→ Có nhiều nguyên nhân, check error log `/var/log/mysql/error.log` xem chính xác:

- **A.1a** *"Connection attempt from IP address ::ffff:10.0.2.15 refused. Address is not in the IP allowlist"*: `ip_allowlist` thiếu NAT subnet. **Fix**: thêm `10.0.2.0/24` vào `loose-group_replication_ip_allowlist` (xem B4.1 / B5.2).

- **A.1b** *"Old incarnation found while trying to add node 10.0.2.15:33061"*: `local_address` đang là `10.0.2.15:33061` (NAT IP, dùng chung 4 VM nên trùng identity). **Fix**: secondary phải set `local_address = <hostonly IP>:33061`. Trong script `secondary-setup.sh`, đổi `hostname -I | awk '{print $1}'` thành `hostname -I | tr ' ' '\n' | grep -E '^192\.168\.10\.(11|12|13)$'` (xem B5.1).

- **A.1c** *"Timeout while waiting for the group communication engine to be ready!"*: thường node1 (đã bootstrap trước với local_address sai) còn cache "Old incarnation" trong XCom in-memory state. **Fix**: trên node1 chạy `STOP GROUP_REPLICATION;` + `systemctl restart mysql` + re-bootstrap (B4.3).

### A.2 `Verify` script báo `[FAIL] baseline=ON ON ROW`

→ Code so sánh `[[ "${BASELINE}" == *"ON"*"1"*"ROW"* ]]` sai. `@@enforce_gtid_consistency` trả về `ON` (chuỗi), không phải `1`. **Fix**: tách 3 cột riêng bằng awk rồi so sánh từng cột (đã apply vào `demo/03-group-replication/06-verify.sh`).

### A.3 `Verify` báo `[FAIL] [node1] super_read_only=0` mặc dù node1 đang là PRIMARY

→ `PRIMARY_HOST` từ `performance_schema.replication_group_members` trả về **IP** (`192.168.10.11`, do `report_host=IP`), nhưng loop var `$N` là **hostname** (`node1`) → so sánh `[[ "$N" == "$PRIMARY_HOST" ]]` luôn false. **Fix**: thêm hàm `ip_to_name()` map IP → hostname trước khi compare (đã apply vào `06-verify.sh`, `07-smoke-test.sh`, `08-failover-test.sh`).

### A.4 `vagrant ssh '192.168.10.11' ...` báo *"machine with the name was not found"*

→ Tương tự A.3 — `PRIMARY_HOST` là IP nhưng `vagrant ssh` cần hostname. **Fix**: dùng `ip_to_name()` (xem A.3).

### A.5 UFW chặn SSH sau reboot

→ Nếu `02-firewall.sh` (cũ) `ufw enable` trước khi `ufw allow 22/tcp`, default policy `deny incoming` chặn cả SSH. **Recovery**: chỉ có `vagrant destroy -f` rồi `vagrant up` lại; không sửa được trong-place vì SSH đã đứt.

### A.6 `VERR_INTNET_FLT_IF_NOT_FOUND` khi `vagrant up`

→ VirtualBox Host-Only Adapter NDIS driver bị "ghost-bind" sau Windows update. Chạy `demo\01-async-semisync\fix-vbox-hostonly.ps1` với quyền administrator.

### A.7 GR node join mà gtid_executed tụt nhiều → fail recovery

→ Recovery channel pull qua binlog không thể chạy nếu binlog đã purge. **Fix**: dùng Clone Plugin (xem B8.5):
```sql
SET GLOBAL clone_valid_donor_list='192.168.10.11:3306';
CLONE INSTANCE FROM 'repl'@'192.168.10.11':3306 IDENTIFIED BY 'ChangeMe!Repl#2026';
```

---

## Phụ lục B — Tóm tắt files config

| Host        | File                                                  | Mô tả                                          |
|-------------|-------------------------------------------------------|------------------------------------------------|
| 4 nodes     | `/etc/hosts` (block `mysql-ha cluster`)               | resolve hostname → IP                          |
| 4 nodes     | `/etc/fstab` (swap dòng comment)                      | tắt swap vĩnh viễn                             |
| 4 nodes     | `/etc/sysctl.d/99-mysql-ha.conf`                      | tuning kernel cho MySQL                        |
| 4 nodes     | `/etc/systemd/system/mysql.service.d/limits.conf`     | ulimit cho mysql                                |
| 3 DB nodes  | `/etc/apt/sources.list.d/mysql.list`                  | repo MySQL 8.0                                  |
| 3 DB nodes  | `/etc/mysql/mysql.conf.d/zz-mysql-ha.cnf`             | server_id, gtid, binlog, **report_host=IP**    |
| 3 DB nodes  | `/etc/mysql/mysql.conf.d/zz-group-replication.cnf`    | local_address, seeds, ip_allowlist, GR plugin  |

MySQL users sau khi setup:

| User      | Tạo ở | Host pattern | Privilege                                                       | Dùng cho                       |
|-----------|-------|--------------|-----------------------------------------------------------------|--------------------------------|
| `root`    | sẵn   | `localhost`  | (đổi password = `ChangeMe!Root#2026`)                            | DBA local                      |
| `repl`    | B4.2  | `%`          | REPLICATION SLAVE, CONNECTION_ADMIN, BACKUP_ADMIN, GROUP_REPLICATION_STREAM | `group_replication_recovery` channel + Clone donor |

> 💡 Khác Demo 02: KHÔNG có `clusteradmin` / `mysql_innodb_cluster_*` / `mysql_router1_*` vì không dùng `dba.*` APIs và không có Router.

---

## Phụ lục C — Mapping bash scripts ↔ manual steps

| Script trong repo                                                       | Bước trong tài liệu       |
|-------------------------------------------------------------------------|---------------------------|
| `scripts/common/00-prepare-os.sh`                                       | B2                        |
| `scripts/common/01-install-mysql.sh` (default profile `server`)         | B3                        |
| `scripts/common/02-firewall.sh`                                         | B3.8 (đã include khi B3 trên Vagrantfile) |
| `scripts/group-replication/primary-setup.sh`                            | B4                        |
| `scripts/group-replication/secondary-setup.sh`                          | B5 (chạy trên node2 + node3) |
| `demo/03-group-replication/06-verify.sh`                                | B6                        |
| `demo/03-group-replication/07-smoke-test.sh`                            | B7                        |
| `demo/03-group-replication/08-failover-test.sh`                         | B8                        |
| `demo/03-group-replication/09-rollback.sh`                              | B9                        |

> 💡 Tip: `run-all.sh`/`run-all.ps1` chỉ là wrapper gọi các script trên qua `vagrant ssh ... bash /vagrant/scripts/...`. Manual setup là copy/paste nội dung script vào shell của từng node — không có gì "ẩn".

---

## Phụ lục D — Vì sao Vagrant + GR cần `10.0.2.0/24` trong ip_allowlist?

Vagrant box mặc định có **2 NIC**:

```
eth0  10.0.2.15/24    (NAT, mỗi VM cùng IP, NAT'd tới host port 2222/2200/2201/2202)
eth1  192.168.10.X/24 (hostonly, unique IP cho từng VM)
```

Default route trên Ubuntu vagrant:

```
default via 10.0.2.2 dev eth0     ← eth0 (NAT) là default
192.168.10.0/24 dev eth1
```

Khi MySQL XCom (group communication engine) cần làm self-test (open một TCP connection từ chính nó tới `local_address`), kernel routing có thể chọn **source IP = 10.0.2.15** (eth0) ngay cả khi destination là `192.168.10.12` (eth1). Đặc biệt với các connection cục bộ / self-loopback.

Vì vậy ip_allowlist chỉ `192.168.10.11,12,13` → GR rejecting `10.0.2.15` source → join fail.

Hai fix bổ trợ nhau (manual áp dụng cả hai):

1. **`local_address = <IP hostonly>`** (192.168.10.X) — đảm bảo identity advertised ra group là UNIQUE per node (KHÔNG dùng 10.0.2.15 dùng chung 4 VM).
2. **`ip_allowlist += 10.0.2.0/24`** — chấp nhận self-test connection xảy ra qua NAT source.

Một giải pháp thay thế là **chỉnh default route** để 192.168.10.0/24 traffic luôn source qua eth1, nhưng dễ vỡ và làm Vagrant SSH (port 2222 qua NAT) bị ảnh hưởng → cách đơn giản nhất cho lab là mở rộng allowlist như trên.

> Trong production thật (1 NIC, không dùng Vagrant), config chuẩn vẫn là `ip_allowlist = "<list IP các member>"` không cần NAT subnet.

---

## Tham khảo

- Runbook gốc: [runbooks/03-group-replication.md](../../runbooks/003-group-replication.md)
- Vagrant lab: [runbooks/08-vagrant-lab.md](../../runbooks/008-vagrant-lab.md)
- MySQL Group Replication: https://dev.mysql.com/doc/refman/8.0/en/group-replication.html
- GR FAQ — XCom + ip_allowlist: https://dev.mysql.com/doc/refman/8.0/en/group-replication-ip-address-permissions.html
- Clone Plugin (recovery): https://dev.mysql.com/doc/refman/8.0/en/clone-plugin.html


---

!!! info "Nguồn gốc"
    `HA/Mysql/demo/03-group-replication/MANUAL-SETUP.md`
