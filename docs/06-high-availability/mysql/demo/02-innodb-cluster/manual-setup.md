---
title: Hướng dẫn setup THỦ CÔNG — Demo 02 MySQL InnoDB Cluster
course: 06-high-availability
source: HA/Mysql/demo/02-innodb-cluster/MANUAL-SETUP.md
---

# Hướng dẫn setup THỦ CÔNG — Demo 02 MySQL InnoDB Cluster

> Tài liệu này ghi lại **TỪNG CÂU LỆNH** để dựng giải pháp 02 (InnoDB Cluster = Group Replication + MySQL Shell + Router) mà không cần `run-all.sh` / `run-all.ps1`. Copy-paste theo thứ tự từ trên xuống. Mỗi bước nêu rõ:
> - 🖥️ **Where**: chạy ở đâu (HOST / node1 / node2 / node3 / mgmt)
> - 💻 **Command**: lệnh CLI hoặc JS/SQL
> - 📝 **File**: cấu hình cần ghi (nếu có)
> - ✅ **Verify**: cách kiểm tra step OK

## 0. Topology & biến môi trường

| Host  | IP              | Vai trò                                  | server_id |
|-------|-----------------|------------------------------------------|-----------|
| node1 | 192.168.10.11   | GR member — Primary ban đầu               | 1         |
| node2 | 192.168.10.12   | GR member — Secondary                     | 2         |
| node3 | 192.168.10.13   | GR member — Secondary                     | 3         |
| mgmt  | 192.168.10.20   | MySQL Router (`:6446` RW / `:6447` RO)    | —         |

Credentials mặc định (đổi nếu muốn — xem [scripts/common/env.sh](../../scripts/common/env.sh)):

```
MYSQL_ROOT_PWD = ChangeMe!Root#2026
ADMIN_USER     = clusteradmin              # dùng cho dba.* APIs + Router
ADMIN_PWD      = ChangeMe!Admin#2026
APP_USER       = appuser                    # client test qua Router
APP_PWD        = ChangeMe!App#2026
CLUSTER_NAME   = myCluster
```

Ports: `22, 3306, 33060 (X-protocol), 33061 (Group Replication), 6446 (Router RW), 6447 (Router RO)`.

> ⚠ Password chứa `#`. Khi nhét vào URI của `mysqlsh`/`mysqlrouter --bootstrap` thì PHẢI **URL-encode** (`#` → `%23`), nếu không sẽ bị parse fail với lỗi `Invalid URI: Illegal character [#] found at position N`. Encoded:
> ```
> ChangeMe!Admin#2026   →   ChangeMe!Admin%232026
> ChangeMe!Root#2026    →   ChangeMe!Root%232026
> ```
> Khi truyền vào `mysql` client CLI (`-pPWD`) thì KHÔNG cần encode.
> Khi truyền vào JS heredoc options (`{password:'…'}`) cũng KHÔNG encode — đó là JS string literal.

> 💡 **Workflow fresh-lab**: `run-all.sh` của demo 02 mặc định **destroy 4 VMs cũ** rồi rebuild (xem `KEEP_VMS=1` để bypass). Manual setup dưới đây giả định bắt đầu với VMs sạch — nếu lab đang chạy demo khác (Galera, Async, GR), chạy `cd vagrant && vagrant destroy -f` trước B1.

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

> ⚠ Ubuntu vagrant cloud-init thêm dòng `127.0.2.1 <hostname>` → `getent hosts node1` có thể trả về `127.0.2.1` (loopback). Đó là lý do **B3.7** phải set `report_host = <IP private>` (KHÔNG dùng hostname), nếu không Group Replication sẽ từ chối join với lỗi *"resolves to an IP address (127.0.2.1) that does not match a real network interface"*.

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

> ⚠ Lệnh này chỉ **disable systemd unit**. Sau khi cài `mysql-router` ở B6, package postinst sẽ nạp lại profile `/etc/apparmor.d/usr.bin.mysqlrouter` vào kernel — phải **unload profile riêng** trong B6.1 nếu không Router bootstrap sẽ fail với "Cannot create directory /var/lib/mysqlrouter".

✅ **Verify** (vẫn trong node):
```bash
swapon --show                         # rỗng = swap OFF
sysctl vm.swappiness fs.file-max      # = 1 / 2097152
grep -A4 'mysql-ha cluster' /etc/hosts
timedatectl | grep -E 'NTP|synchron'
```

Lặp lại B2.1 → B2.6 trên **cả 4 nodes**.

---

## B3 · Cài MySQL 8.0 SERVER — chạy TRÊN 3 DB NODES (node1, node2, node3)

🖥️ **Where**: node1, node2, node3 (KHÔNG cài server trên mgmt — mgmt sẽ cài tools-only ở B6)

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

### B3.4 — Refresh GPG key MySQL (key `B7B3B788A8D3785C` đã expire 2024)

> ⚠ Mọi version `mysql-apt-config` (kể cả 0.8.33-1 mới nhất tại thời điểm doc này) đều ship cùng key đã hết hạn. Triệu chứng nếu skip step này: `apt-get update` báo `EXPKEYSIG B7B3B788A8D3785C ... is not signed`. Phải refresh metadata expiration từ keyserver TRƯỚC khi `apt update`. Lab fallback `[trusted=yes]` ở B3.5 nếu refresh fail.

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

> ⚠ `server_id` và `report_host` khác nhau trên mỗi node. **`report_host` PHẢI là IP private** (không phải hostname) — vì Ubuntu cloud-init khiến `node1` resolve về `127.0.2.1` → GR refuse.

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

✅ **Verify** (trên mỗi node):
```bash
systemctl is-active mysql                            # active
ss -tlnp | grep ':3306 '                             # listening
mysql -uroot -p"${ROOT_PWD}" -e "
  SELECT @@hostname,@@server_id,@@report_host,@@gtid_mode,@@log_bin,@@binlog_format;
  SELECT plugin_name,plugin_status FROM information_schema.plugins WHERE plugin_name='clone';"
# Expect:
#   server_id   = 1|2|3 đúng theo node
#   report_host = 192.168.10.{11,12,13} (KHÔNG phải hostname)
#   gtid_mode   = ON / log_bin = 1 / binlog_format = ROW
#   clone plugin = ACTIVE
```

Lặp lại B3.1 → B3.7 trên **cả node1, node2, node3**.

---

## B4 · Configure instance cho InnoDB Cluster — chạy TRÊN 3 DB NODES

🖥️ **Where**: node1, node2, node3 (3 lần) — chạy với `sudo`

```bash
vagrant ssh node1     # rồi node2, node3
sudo -i
ROOT_PWD='ChangeMe!Root#2026'
ADMIN_USER='clusteradmin'
ADMIN_PWD='ChangeMe!Admin#2026'
ADMIN_PWD_ENC='ChangeMe!Admin%232026'    # URL-encoded (# → %23) cho URI
```

### B4.1 — Tạo user `clusteradmin` cho dba.* APIs

```bash
mysql -uroot -p"${ROOT_PWD}" <<SQL
CREATE USER IF NOT EXISTS '${ADMIN_USER}'@'%' IDENTIFIED BY '${ADMIN_PWD}';
GRANT ALL PRIVILEGES ON *.* TO '${ADMIN_USER}'@'%' WITH GRANT OPTION;
FLUSH PRIVILEGES;
SQL
```

### B4.2 — Chạy `dba.configureInstance()` — MySQL Shell tự fix config + restart

> ⚠ **DÙNG JS HEREDOC**, không dùng CLI form `mysqlsh -- dba configureInstance '{...}'`. CLI parse JSON như connection-options sẽ fail: `Invalid values in connection options: clusterAdmin, clusterAdminPassword, interactive, restart`.
>
> ⚠ **KHÔNG** truyền `clusterAdmin`/`clusterAdminPassword` vì user đã tạo ở B4.1 → MySQL Shell sẽ throw `ArgumentError: account already exists, clusterAdminPassword is not allowed`.

```bash
mysqlsh --uri="${ADMIN_USER}:${ADMIN_PWD_ENC}@127.0.0.1:3306" <<'JS'
dba.configureInstance(null, {
  interactive: false,
  restart: true
});
JS
```

MySQL Shell sẽ:
- Detect các config cần sửa (vd `binlog_transaction_dependency_tracking=COMMIT_ORDER` → `WRITESET`)
- Áp dụng via `SET PERSIST` (lưu vào `mysqld-auto.cnf`)
- Restart server nếu cần
- Sau restart MySQL có thể mất 5-10s mới ping được:

```bash
for i in {1..30}; do
  if mysqladmin -uroot -p"${ROOT_PWD}" ping &>/dev/null; then echo "MySQL up"; break; fi
  sleep 2
done
```

### B4.3 — Verify instance ready

```bash
mysqlsh --uri="${ADMIN_USER}:${ADMIN_PWD_ENC}@127.0.0.1:3306" <<JS
dba.checkInstanceConfiguration({
  user: '${ADMIN_USER}',
  password: '${ADMIN_PWD}',
  host: '127.0.0.1',
  port: 3306
});
JS

# Expect output:
#   "Instance configuration is compatible with InnoDB cluster"
#   "The instance '192.168.10.1X:3306' is valid to be used in an InnoDB cluster."
```

Lặp lại B4.1 → B4.3 trên **cả node1, node2, node3**.

---

## B5 · Bootstrap cluster trên node1 + add node2, node3

🖥️ **Where**: node1 (chỉ chạy 1 lần)

```bash
vagrant ssh node1
sudo -i
ADMIN_USER='clusteradmin'
ADMIN_PWD='ChangeMe!Admin#2026'
ADMIN_PWD_ENC='ChangeMe!Admin%232026'
NODE1_IP=192.168.10.11
NODE2_IP=192.168.10.12
NODE3_IP=192.168.10.13
CLUSTER_NAME='myCluster'
```

### B5.1 — Tạo cluster (seed = node1)

```bash
mysqlsh --uri="${ADMIN_USER}:${ADMIN_PWD_ENC}@${NODE1_IP}:3306" <<JS
var cluster = dba.createCluster('${CLUSTER_NAME}', {
  memberWeight: 50,
  exitStateAction: 'READ_ONLY',
  consistency: 'BEFORE_ON_PRIMARY_FAILOVER'
});
print("Cluster created.\n");
JS
```

Giải thích options:
- `memberWeight: 50` — trọng số khi bầu primary (mặc định 50, đặt cao hơn cho node mạnh hơn)
- `exitStateAction: 'READ_ONLY'` — node mất quorum sẽ thành read-only (an toàn hơn `ABORT_SERVER`)
- `consistency: 'BEFORE_ON_PRIMARY_FAILOVER'` — read trên primary mới phải đợi xử lý hết backlog

### B5.2 — Add node2 (Clone Plugin sẽ copy data từ node1)

```bash
mysqlsh --uri="${ADMIN_USER}:${ADMIN_PWD_ENC}@${NODE1_IP}:3306" <<JS
var c = dba.getCluster('${CLUSTER_NAME}');
c.addInstance('${ADMIN_USER}@${NODE2_IP}:3306', {
  password: '${ADMIN_PWD}',
  recoveryMethod: 'clone'
});
JS
```

> 💡 `recoveryMethod: 'clone'` dùng **Clone Plugin** — copy InnoDB tablespace + binlog từ donor (node1). Quá trình: DROP DATA → FILE COPY → PAGE COPY → REDO COPY → RESTART. Mất ~1-3 phút cho lab nhỏ.
>
> Cảnh báo *"contains transactions that do not originate from the cluster"* là bình thường — Clone Plugin sẽ ghi đè state.

### B5.3 — Add node3

```bash
mysqlsh --uri="${ADMIN_USER}:${ADMIN_PWD_ENC}@${NODE1_IP}:3306" <<JS
var c = dba.getCluster('${CLUSTER_NAME}');
c.addInstance('${ADMIN_USER}@${NODE3_IP}:3306', {
  password: '${ADMIN_PWD}',
  recoveryMethod: 'clone'
});
JS
```

### B5.4 — Verify cluster

```bash
mysqlsh --uri="${ADMIN_USER}:${ADMIN_PWD_ENC}@${NODE1_IP}:3306" \
  -e "var c=dba.getCluster('${CLUSTER_NAME}'); print(JSON.stringify(c.status(),null,2));"

# Expect (rút gọn):
#   "primary": "192.168.10.11:3306"
#   "status":  "OK"
#   "statusText": "Cluster is ONLINE and can tolerate up to ONE failure."
#   3 members:
#     192.168.10.11 — PRIMARY  / R/W / ONLINE
#     192.168.10.12 — SECONDARY/ R/O / ONLINE
#     192.168.10.13 — SECONDARY/ R/O / ONLINE
```

Cross-check qua performance_schema:
```bash
mysql -uroot -p"${ROOT_PWD:-ChangeMe!Root#2026}" -e "
  SELECT MEMBER_ID, MEMBER_HOST, MEMBER_PORT, MEMBER_STATE, MEMBER_ROLE
  FROM performance_schema.replication_group_members;"
# Expect: 3 row, MEMBER_STATE = ONLINE, 1 PRIMARY + 2 SECONDARY
```

---

## B6 · Cài MySQL Router trên mgmt + bootstrap từ cluster

🖥️ **Where**: mgmt

```bash
vagrant ssh mgmt
sudo -i
ROOT_PWD='ChangeMe!Root#2026'
ADMIN_USER='clusteradmin'
ADMIN_PWD='ChangeMe!Admin#2026'
ADMIN_PWD_ENC='ChangeMe!Admin%232026'
NODE1_IP=192.168.10.11
RUNTIME_DIR=/var/lib/mysqlrouter
```

### B6.1 — Cài MySQL Shell + Router + Client (tools-only, KHÔNG cài server)

**Shortcut**: dùng common installer đã có GPG key handling đầy đủ (4-layer fallback):

```bash
sudo INSTALL_PROFILE=tools-only bash /vagrant/scripts/common/01-install-mysql.sh
mysqlsh --version
mysqlrouter --version
mysql --version
```

Common installer tự lo: pre-seed `mysql-apt-config 0.8.33-1` → refresh GPG key từ 4 keyserver → probe `apt-get update` → fallback `[trusted=yes]` nếu fail → install `mysql-shell + mysql-router + mysql-community-client`.

**Manual** (nếu không muốn dùng common installer): lặp lại B3.1 → B3.5 trên mgmt rồi:

```bash
DEBIAN_FRONTEND=noninteractive apt-get install -y mysql-shell mysql-router mysql-community-client
```

> 💡 Không cài `mysql-server` vì mgmt chỉ làm Router. Cài `mysql-community-client` (CLI `mysql`) để test routing :6446/:6447 từ mgmt ở B8.

### B6.1bis — UFW: ALLOW SSH (22/tcp) **TRƯỚC** khi enable

> ⚠ **CRITICAL BUG**: Nếu enable UFW mà chưa pre-allow port 22, các kết nối SSH MỚI (vagrant ssh -c) sẽ bị block → mgmt VM "running" nhưng SSH chết → toàn bộ B6/B7/B8 sau đó fail với exit 255, 0 dòng output. UFW rule persist sau reboot, không tự khôi phục bằng restart VM.
>
> Cùng họ bug với `bug_ufw_blocks_ssh.md` (đã fix cho DB nodes trong `common/02-firewall.sh` nhưng wrapper demo có instance UFW riêng nên không inherit).

```bash
# Allow SSH TRƯỚC tiên — không skip step này!
ufw allow OpenSSH || ufw allow 22/tcp
ufw allow 6446/tcp
ufw allow 6447/tcp
ufw --force enable
ufw status
# Expect: Status: active, 22/tcp ALLOW IN, 6446/tcp ALLOW IN, 6447/tcp ALLOW IN
```

**Recovery nếu lỡ SSH lock**:
```powershell
# Từ HOST — chạy lệnh qua VirtualBox guestcontrol (bypass SSH)
VBoxManage guestcontrol mysql-ha-mgmt run --username vagrant --password vagrant `
  --exe /usr/bin/sudo -- /usr/bin/sudo ufw allow 22/tcp
```

### B6.2 — Unload AppArmor profile của mysqlrouter

> ⚠ Package install nạp `/etc/apparmor.d/usr.bin.mysqlrouter` SAU khi B2.6 đã disable apparmor service. Kernel vẫn enforce profile → bootstrap fail *"Cannot create directory '/var/lib/mysqlrouter': Permission denied... This may be caused by AppArmor settings"*.

```bash
if [[ -f /etc/apparmor.d/usr.bin.mysqlrouter ]] && command -v apparmor_parser >/dev/null; then
  apparmor_parser -R /etc/apparmor.d/usr.bin.mysqlrouter 2>/dev/null || true
  mkdir -p /etc/apparmor.d/disable
  ln -sf /etc/apparmor.d/usr.bin.mysqlrouter /etc/apparmor.d/disable/usr.bin.mysqlrouter
fi
```

### B6.3 — Dọn runtime dir cũ rồi bootstrap

> ⚠ Nếu `/var/lib/mysqlrouter` đã tồn tại (do package install pre-tạo), `mysqlrouter --bootstrap --user mysqlrouter --force` báo *"Can't set ownership of file '/var/lib/mysqlrouter' to the user 'mysqlrouter'. error: Permission denied"*. Xoá dir để Router tự tạo fresh với owner đúng.

```bash
id mysqlrouter >/dev/null 2>&1 || useradd -r -s /usr/sbin/nologin mysqlrouter
rm -rf "${RUNTIME_DIR}"

mysqlrouter --bootstrap "${ADMIN_USER}:${ADMIN_PWD_ENC}@${NODE1_IP}:3306" \
            --directory "${RUNTIME_DIR}" \
            --conf-use-sockets \
            --conf-bind-address 0.0.0.0 \
            --user mysqlrouter \
            --force
```

Output sẽ ghi `/var/lib/mysqlrouter/mysqlrouter.conf` với metadata cluster + listen 6446 (RW), 6447 (RO), 6448/6449 (X-protocol).

### B6.4 — Dọn SysV init.d mysqlrouter, cài systemd unit mới

> ⚠ Package mysql-router ship `/etc/init.d/mysqlrouter` + auto-start trỏ tới config mặc định `/etc/mysqlrouter/mysqlrouter.conf` (KHÔNG có cluster info → không listen 6446/6447). Phải tắt nó trước khi enable systemd unit mới.

```bash
systemctl stop  mysqlrouter 2>/dev/null || true
systemctl disable mysqlrouter 2>/dev/null || true
command -v update-rc.d >/dev/null && update-rc.d -f mysqlrouter disable 2>/dev/null || true
pkill -f "mysqlrouter -c /etc/mysqlrouter" 2>/dev/null || true
```

📝 **File**: `/etc/systemd/system/mysqlrouter.service`

> ⚠ ExecStart phải **gọi mysqlrouter foreground**. KHÔNG dùng `/var/lib/mysqlrouter/start.sh` (script generated) — script đó fork mysqlrouter rồi exit ⇒ `Type=simple` coi service đã chết, status=inactive.

```bash
cat >/etc/systemd/system/mysqlrouter.service <<EOF
[Unit]
Description=MySQL Router (InnoDB Cluster bootstrap)
After=network.target

[Service]
Type=simple
User=mysqlrouter
ExecStart=/usr/bin/mysqlrouter -c ${RUNTIME_DIR}/mysqlrouter.conf
Restart=on-failure
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now mysqlrouter
sleep 3
```

✅ **Verify** (trên mgmt):
```bash
systemctl is-active mysqlrouter                    # active
ss -tlnp | egrep '6446|6447'
# Expect 2 dòng LISTEN:
#   0.0.0.0:6446 mysqlrouter
#   0.0.0.0:6447 mysqlrouter
```

---

## B7 · Verify toàn bộ cluster

🖥️ **Where**: HOST hoặc node1

### B7.1 — `cluster.status()` JSON đầy đủ

```bash
vagrant ssh node1 -c "
  mysqlsh --uri='clusteradmin:ChangeMe!Admin%232026@192.168.10.11:3306' \
    -e \"print(JSON.stringify(dba.getCluster('myCluster').status(),null,2));\""

# Kiểm tra:
#   defaultReplicaSet.status     = OK
#   defaultReplicaSet.statusText = "Cluster is ONLINE and can tolerate up to ONE failure."
#   3 topology members:
#     192.168.10.11:3306 → memberRole PRIMARY,   mode R/W, status ONLINE
#     192.168.10.12:3306 → memberRole SECONDARY, mode R/O, status ONLINE
#     192.168.10.13:3306 → memberRole SECONDARY, mode R/O, status ONLINE
```

### B7.2 — Trên mỗi node — `replication_group_members`

```bash
for N in node1 node2 node3; do
  echo "=== $N ==="
  vagrant ssh "$N" -c "
    mysql -uroot -p'ChangeMe!Root#2026' -e \"
      SELECT MEMBER_HOST, MEMBER_PORT, MEMBER_STATE, MEMBER_ROLE
      FROM performance_schema.replication_group_members;\""
done
```

> ⚠ **MEMBER_HOST trả IP** (do `report_host = 192.168.10.X` ở B3.7), **không phải hostname** (`node1`). Khi compare với `@@hostname` (trả tên VM) phải map IP↔name. Pattern dùng trong [demo/02-innodb-cluster/07-verify.sh](07-verify.sh):
> ```bash
> ip_to_name() {
>   case "$1" in
>     "${NODE1_IP}") echo "${NODE1_HOST}" ;;
>     "${NODE2_IP}") echo "${NODE2_HOST}" ;;
>     "${NODE3_IP}") echo "${NODE3_HOST}" ;;
>     *) echo "$1" ;;
>   esac
> }
> PRIMARY_IP=$(mysql -N -e "SELECT MEMBER_HOST FROM performance_schema.replication_group_members WHERE MEMBER_ROLE='PRIMARY';")
> PRIMARY_NAME=$(ip_to_name "${PRIMARY_IP}")
> ```

### B7.2bis — Verify GR replication port listening

> ⚠ **Default GR port = `mysqld_port + 10000` = 13306**, KHÔNG phải 33061 (như tên biến `GR_PORT=33061` trong env.sh có thể gây hiểu lầm). MySQL Shell auto-compute `group_replication_local_address = report_host:mysqld_port+10000` khi không truyền `localAddress` option vào `dba.createCluster`/`addInstance`.

```bash
for N in node1 node2 node3; do
  echo "=== $N ==="
  vagrant ssh "$N" -c "
    GR_ADDR=\$(mysql -uroot -p'ChangeMe!Root#2026' -N -e 'SELECT @@group_replication_local_address;')
    GR_PORT=\$(echo \"\$GR_ADDR\" | awk -F: '{print \$NF}')
    echo \"GR local_address = \$GR_ADDR (port \$GR_PORT)\"
    sudo ss -tlnp | grep \":\$GR_PORT \" || echo \"NOT LISTENING\"
  "
done
# Expect mỗi node: GR local_address = 192.168.10.1X:13306 + ss listening row
```

### B7.3 — Router listening + cluster metadata

```bash
vagrant ssh mgmt -c "
  sudo ss -tlnp | egrep '6446|6447'
  echo '---'
  cat /var/lib/mysqlrouter/data/state.json | head -30"
```

---

## B8 · Smoke Test — write qua RW, read qua RO

🖥️ **Where**: HOST → node1 (vì mgmt tools-only profile KHÔNG có `mysql` client)

```bash
ADMIN_PWD='ChangeMe!Admin#2026'    # CLI -p không cần encode
MGMT_IP=192.168.10.20
```

### B8.1 — Tạo `appuser` + schema test (qua RW port của Router)

```bash
vagrant ssh node1 -c "mysql -uclusteradmin -p'${ADMIN_PWD}' -h${MGMT_IP} -P6446 <<'SQL'
CREATE USER IF NOT EXISTS 'appuser'@'%' IDENTIFIED BY 'ChangeMe!App#2026';
GRANT ALL PRIVILEGES ON *.* TO 'appuser'@'%';
FLUSH PRIVILEGES;

DROP DATABASE IF EXISTS smoke_db;
CREATE DATABASE smoke_db CHARACTER SET utf8mb4;
USE smoke_db;
CREATE TABLE t (
  id  INT PRIMARY KEY AUTO_INCREMENT,
  val VARCHAR(64) NOT NULL,
  ts  DATETIME(6) DEFAULT CURRENT_TIMESTAMP(6)
) ENGINE=InnoDB;

INSERT INTO t(val) VALUES ('hello-from-router-rw');
SQL"
```

### B8.2 — Test RW (6446) — luôn ra primary node1

```bash
for i in 1 2 3; do
  vagrant ssh node1 -c "
    mysql -uappuser -p'ChangeMe!App#2026' -h${MGMT_IP} -P6446 -N -B \
      -e 'SELECT @@report_host, @@server_id'"
done
# Expect 3 dòng giống nhau: 192.168.10.11   1
```

### B8.3 — Test RO (6447) — round-robin secondaries

```bash
for i in 1 2 3 4 5 6; do
  vagrant ssh node1 -c "
    mysql -uappuser -p'ChangeMe!App#2026' -h${MGMT_IP} -P6447 -N -B \
      -e 'SELECT @@report_host, @@server_id'"
done
# Expect xen kẽ 192.168.10.12 / 192.168.10.13
```

### B8.4 — Đọc row vừa insert trên cả 3 nodes (cluster đã sync)

```bash
for N in node1 node2 node3; do
  echo "=== $N ==="
  vagrant ssh "$N" -c "
    mysql -uroot -p'ChangeMe!Root#2026' -N -e \
      'SELECT COUNT(*) FROM smoke_db.t WHERE val=\"hello-from-router-rw\";'"
done
# Expect: 1 trên cả 3 nodes
```

---

## B9 · Failover test (OPTIONAL — destructive)

🖥️ **Where**: HOST

> ⚠ Sau B9: node1 sẽ DOWN; cluster sẽ tự bầu PRIMARY mới giữa node2/node3.
> Router sẽ tự reroute (≤10s) — app KHÔNG cần đổi IP.

### B9.1 — Insert sentinel rồi halt primary

```bash
vagrant ssh node1 -c "mysql -uclusteradmin -p'ChangeMe!Admin#2026' -h192.168.10.20 -P6446 -e \"
  USE smoke_db; INSERT INTO t(val) VALUES('pre-failover-sentinel');\""

vagrant halt --force node1
sleep 10    # cho group detect failure + election
```

### B9.2 — Verify cluster đã elect primary mới

```bash
# Connect qua node2 hoặc node3 (node1 đã chết)
vagrant ssh node2 -c "
  mysqlsh --uri='clusteradmin:ChangeMe!Admin%232026@192.168.10.12:3306' \
    -e \"print(JSON.stringify(dba.getCluster('myCluster').status(),null,2));\""

# Expect:
#   primary thành 192.168.10.12 hoặc 192.168.10.13 (KHÔNG còn node1)
#   192.168.10.11:3306 status = "(MISSING)"
#   statusText: "Cluster is NOT tolerant to any failures."
```

### B9.3 — Test app vẫn write được qua Router (IP không đổi)

```bash
vagrant ssh node2 -c "mysql -uappuser -p'ChangeMe!App#2026' -h192.168.10.20 -P6446 -e \"
  USE smoke_db;
  INSERT INTO t(val) VALUES('post-failover-from-app');
  SELECT @@report_host AS routed_to, @@server_id;\""

# Expect: routed_to = 192.168.10.12 hoặc .13 (primary mới)
```

### B9.4 — Rejoin node1 sau khi nó back online

```bash
vagrant up node1
sleep 30    # cho mysql service start

vagrant ssh node2 -c "
  mysqlsh --uri='clusteradmin:ChangeMe!Admin%232026@192.168.10.12:3306' \
    -e \"dba.getCluster('myCluster').rejoinInstance('clusteradmin@192.168.10.11:3306', {password:'ChangeMe!Admin#2026'});\""
```

Verify lại bằng `cluster.status()` — kỳ vọng quay về 3 ONLINE.

---

## B10 · Rollback (OPTIONAL)

🖥️ **Where**: HOST

### B10.1 — Soft rollback — dissolve cluster, giữ VMs

```bash
vagrant ssh node1 -c "
  mysqlsh --uri='clusteradmin:ChangeMe!Admin%232026@192.168.10.11:3306' \
    -e \"dba.getCluster('myCluster').dissolve({force:true});\""

vagrant ssh mgmt -c "
  sudo systemctl stop mysqlrouter
  sudo systemctl disable mysqlrouter
  sudo rm -f /etc/systemd/system/mysqlrouter.service
  sudo rm -rf /var/lib/mysqlrouter
"

# Dọn data trên 3 nodes
for N in node1 node2 node3; do
  vagrant ssh "$N" -c "
    mysql -uroot -p'ChangeMe!Root#2026' -e \"
      DROP DATABASE IF EXISTS smoke_db;
      DROP USER IF EXISTS 'appuser'@'%';\""
done
```

### B10.2 — Hard rollback — destroy VMs

```bash
cd vagrant
vagrant destroy -f
rm -f provision/cluster_id_rsa provision/cluster_id_rsa.pub
```

Hoặc dùng `cleanup.sh` để dọn cả orphan VBox + .vagrant/:
```bash
bash ../../vagrant/cleanup.sh --all --yes
```

---

## Phụ lục A — Trouble-shooting nhanh

### A.1 `Invalid URI: Illegal character [#] found at position N`

→ Password chứa `#` chưa URL-encode khi truyền vào `mysqlsh --uri=...` hoặc `mysqlrouter --bootstrap`. Encode: `#` → `%23`.

### A.2 `Invalid values in connection options: clusterAdmin, clusterAdminPassword, interactive, restart`

→ Dùng CLI form `mysqlsh -- dba configureInstance '{json}'`. CLI parse JSON như connection-options. **Fix**: dùng JS heredoc (xem B4.2).

### A.3 `The 'clusteradmin'@'%' account already exists, clusterAdminPassword is not allowed`

→ User đã được SQL tạo ở B4.1. Bỏ `clusterAdmin`/`clusterAdminPassword` ra khỏi options của `dba.configureInstance()`.

### A.4 `Cannot use host 'nodeN' for instance 'nodeN:3306' because it resolves to an IP address (127.0.2.1) that does not match a real network interface`

→ `report_host` đang là hostname (Ubuntu cloud-init thêm dòng `127.0.2.1 nodeN`). **Fix**: set `report_host = <IP private>` (xem B3.7), restart MySQL.

### A.5 Router bootstrap: `Cannot create directory '/var/lib/mysqlrouter': Permission denied`

→ AppArmor profile của mysqlrouter chưa unload. **Fix**: B6.2.

### A.6 Router bootstrap: `Can't set ownership of file '/var/lib/mysqlrouter' to the user 'mysqlrouter'`

→ Dir đã tồn tại do package install. **Fix**: `rm -rf /var/lib/mysqlrouter` trước bootstrap (B6.3).

### A.7 `systemctl is-active mysqlrouter` = active nhưng `ss -tlnp` không thấy 6446/6447

→ SysV init.d đang chạy với config mặc định `/etc/mysqlrouter/mysqlrouter.conf` (không có cluster info). **Fix**: B6.4 (stop SysV + cài systemd unit mới).

### A.8 systemd unit start xong rồi mysqlrouter chết ngay

→ ExecStart đang trỏ `/var/lib/mysqlrouter/start.sh` — script này fork rồi exit. **Fix**: ExecStart gọi `mysqlrouter -c <conf>` foreground (xem B6.4).

### A.9 Cluster status: `Cluster has no quorum`

→ Quá nửa số node down. Khi còn ít nhất 1 node sống:
```js
// trong mysqlsh trên node còn sống
dba.getCluster('myCluster').forceQuorumUsingPartitionOf('clusteradmin@192.168.10.11:3306');
```

### A.10 Cluster bị "completely outage" (tất cả node down)

→ Sau khi VMs back online:
```js
dba.rebootClusterFromCompleteOutage('myCluster');
```

### A.11 mgmt VM "running" nhưng `vagrant ssh mgmt -c "..."` exit 255, 0 output

→ UFW enable mà chưa pre-allow port 22. SSH session đang chạy survive nhưng kết nối mới bị block. UFW persist sau reboot. **Fix**:
```powershell
# Từ HOST — bypass SSH qua VirtualBox guestcontrol
VBoxManage guestcontrol mysql-ha-mgmt run --username vagrant --password vagrant `
  --exe /usr/bin/sudo -- /usr/bin/sudo ufw allow 22/tcp
```
**Phòng ngừa**: luôn `ufw allow OpenSSH` TRƯỚC `ufw --force enable` — xem B6.1bis.

### A.12 `port 33061 not listening` (verify FAIL nhưng GR đang chạy bình thường)

→ Default GR port là `mysqld_port + 10000 = 13306`, KHÔNG phải 33061. Tên biến `GR_PORT=33061` trong `scripts/common/env.sh` chỉ là placeholder không reflect default thực tế. **Fix**: query động:
```bash
mysql -N -e "SELECT @@group_replication_local_address;"
# → 192.168.10.11:13306
```
Sau đó kiểm tra ss listening trên port đó (xem B7.2bis).

### A.13 `Dba.checkInstanceConfiguration: Access denied for user 'clusteradmin'@'localhost'` + prompt password

→ `dba.checkInstanceConfiguration('user@host:port')` (URI string không có password) mở connection MỚI đến target instance → prompt vì arg không có password. **Fix**: pass options dict thứ 2:
```js
dba.checkInstanceConfiguration('clusteradmin@127.0.0.1:3306',
                               {password:'ChangeMe!Admin#2026', interactive:false})
```
Hoặc dùng connection dict form như B4.3 đã làm.

### A.14 B7 verify báo `[FAIL] :6446 không nhất quán: node1 node1 node1` (hits hostname vs PRIMARY_HOST IP)

→ `MEMBER_HOST` trả IP (do `report_host=NODE_IP`); `SELECT @@hostname` trả tên VM. Compare luôn fail. **Fix**: thêm `ip_to_name()` mapper, dùng `PRIMARY_NAME` (hostname) khi compare với hits. Đã fix trong [07-verify.sh](07-verify.sh) — xem B7.2.

### A.15 B7 verify báo `[FAIL] [node1] super_read_only=0` (primary đúng phải =0!)

→ Loop check super_read_only=1 cho TẤT CẢ nodes, không phân biệt PRIMARY (=0) vs SECONDARY (=1). Đã fix trong 07-verify.sh — verify cả primary có SRO=0 lẫn secondaries có SRO=1.

### A.16 B7 verify báo `[FAIL] baseline=ON ON ROW` (giá trị đúng!)

→ Bug regex check `*"ON"*"1"*"ROW"*` — `@@enforce_gtid_consistency` trả `ON` không phải `1`. Đã fix → `*"ON"*"ON"*"ROW"*`.

---

## Phụ lục B — Tóm tắt files config

Toàn bộ file ghi mới trong demo này:

| Host        | File                                                  | Mô tả                                          |
|-------------|-------------------------------------------------------|-----------------------------------------------|
| 4 nodes     | `/etc/hosts` (block `mysql-ha cluster`)               | resolve hostname → IP                          |
| 4 nodes     | `/etc/fstab` (swap dòng comment)                      | tắt swap vĩnh viễn                             |
| 4 nodes     | `/etc/sysctl.d/99-mysql-ha.conf`                      | tuning kernel cho MySQL                        |
| 4 nodes     | `/etc/systemd/system/mysql.service.d/limits.conf`     | ulimit cho mysql                                |
| 3 DB nodes  | `/etc/apt/sources.list.d/mysql.list`                  | repo MySQL 8.0 + tools                          |
| 3 DB nodes  | `/etc/mysql/mysql.conf.d/zz-mysql-ha.cnf`             | server_id, gtid, binlog, **report_host=IP**    |
| 3 DB nodes  | `/var/lib/mysql/mysqld-auto.cnf` (auto bởi configureInstance) | GR-required vars (writeset, etc.) |
| mgmt        | `/etc/apt/sources.list.d/mysql.list`                  | repo cho mysql-shell + mysql-router            |
| mgmt        | `/etc/apparmor.d/disable/usr.bin.mysqlrouter` (symlink)| disable AppArmor profile của Router            |
| mgmt        | `/var/lib/mysqlrouter/mysqlrouter.conf` (auto bootstrap)| cluster metadata + listen 6446/6447           |
| mgmt        | `/etc/systemd/system/mysqlrouter.service`             | systemd unit thay SysV init.d                  |

Toàn bộ user trong mysql sau khi setup:

| User             | Tạo ở | Host pattern | Privilege                          | Dùng cho                       |
|------------------|-------|--------------|------------------------------------|--------------------------------|
| `root`           | sẵn   | `localhost`  | (đổi password = `ChangeMe!Root#2026`) | DBA local                    |
| `clusteradmin`   | B4.1  | `%`          | ALL + GRANT OPTION                  | `dba.*` APIs + Router metadata |
| `mysql_router1_*`| auto bởi `mysqlrouter --bootstrap` | `%` | Router-internal grants | Router → cluster              |
| `mysql_innodb_cluster_*` | auto bởi `dba.configureInstance` | nhiều | GR-internal | Group Replication recovery   |
| `appuser`        | B8.1  | `%`          | ALL                                 | Test app connect qua Router    |

---

## Phụ lục C — Mapping bash scripts ↔ manual steps

| Script trong repo                                                       | Bước trong tài liệu       |
|-------------------------------------------------------------------------|---------------------------|
| `demo/02-innodb-cluster/01-vagrant-up.sh` (auto `vagrant destroy -f` đầu)| B1 (fresh-lab workflow)   |
| `scripts/common/00-prepare-os.sh`                                       | B2                        |
| `scripts/common/01-install-mysql.sh` (default profile `server`)         | B3                        |
| `scripts/common/01-install-mysql.sh` (`INSTALL_PROFILE=tools-only`, đã include GPG key handling 4 lớp + mysql-community-client) | B6.1 |
| `scripts/common/02-firewall.sh` (DB nodes; mgmt UFW handle riêng ở B6.1bis) | B6.1bis (mgmt)         |
| `scripts/innodb-cluster/node-setup.sh` (URL-encoded URI + clusterAdmin SQL trước) | B4               |
| `scripts/innodb-cluster/cluster-bootstrap.sh` (URL-encoded URI cho 3 mysqlsh blocks) | B5            |
| `scripts/innodb-cluster/router-setup.sh` (AppArmor unload + clean RUNTIME_DIR + systemd unit) | B6.2 → B6.4 |
| `scripts/innodb-cluster/cluster-ops.sh status`                          | B7.1                      |
| `demo/02-innodb-cluster/04-node-setup.sh` (urlenc shell + `{password,interactive}` options) | B4 wrapper |
| `demo/02-innodb-cluster/06-router-setup.sh` (call common installer, UFW pre-allow OpenSSH) | B6 wrapper |
| `demo/02-innodb-cluster/07-verify.sh` (`ip_to_name()` + dynamic GR port + baseline regex fix) | B7      |
| `demo/02-innodb-cluster/08-smoke-test.sh`                               | B8                        |
| `demo/02-innodb-cluster/09-failover-test.sh`                            | B9                        |
| `demo/02-innodb-cluster/10-rollback.sh`                                 | B10                       |

> 💡 Tip: `run-all.sh`/`run-all.ps1` chỉ là wrapper gọi các script trên qua `vagrant ssh ... bash /vagrant/scripts/...`. Manual setup là copy/paste nội dung script vào shell của từng node — không có gì "ẩn".

---

## Phụ lục D — Vì sao password lại phải URL-encode?

`mysqlsh --uri=user:password@host:port` parse string theo cú pháp URI (RFC 3986). Trong RFC 3986, `#` là **gen-delim** (fragment separator) → không hợp lệ trong `userinfo` nếu chưa percent-encode. Tương tự với `@`, `:`, `/`, `?`.

Helper `urlenc` trong [scripts/common/env.sh](../../scripts/common/env.sh):

```bash
urlenc() {
  local s="${1:-}"
  s="${s//%/%25}"   # % phải escape trước
  s="${s//:/%3A}"
  s="${s//@/%40}"
  s="${s//\//%2F}"
  s="${s//#/%23}"
  s="${s//\?/%3F}"
  printf '%s' "$s"
}
# Usage:
ADMIN_PWD_ENC="$(urlenc "${ADMIN_PWD}")"
mysqlsh --uri="${ADMIN_USER}:${ADMIN_PWD_ENC}@${HOST}:${PORT}"
```

Trong các JS heredoc, **không** encode — `dba.configureInstance(null, {password: '...'})` truyền JS string nguyên văn, JS không parse URI. Chỉ phần `--uri="..."` của shell là cần encode.

`mysql` client CLI (`mysql -u... -p...`) cũng KHÔNG cần encode, vì `-p` là arg riêng — không nằm trong URI.

---

## Tham khảo

- Runbook gốc: [runbooks/02-mysql-innodb-cluster.md](../../runbooks/002-mysql-innodb-cluster.md)
- Vagrant lab: [runbooks/08-vagrant-lab.md](../../runbooks/008-vagrant-lab.md)
- MySQL InnoDB Cluster: https://dev.mysql.com/doc/mysql-shell/8.0/en/mysql-innodb-cluster.html
- Group Replication: https://dev.mysql.com/doc/refman/8.0/en/group-replication.html
- MySQL Router: https://dev.mysql.com/doc/mysql-router/8.0/en/


---

!!! info "Nguồn gốc"
    `HA/Mysql/demo/02-innodb-cluster/MANUAL-SETUP.md`
