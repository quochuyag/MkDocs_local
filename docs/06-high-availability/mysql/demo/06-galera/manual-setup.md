---
title: Hướng dẫn setup THỦ CÔNG — Demo 06 Galera Cluster (Percona XtraDB Cluster 8.0)
course: 06-high-availability
source: HA/Mysql/demo/06-galera/MANUAL-SETUP.md
---

# Hướng dẫn setup THỦ CÔNG — Demo 06 Galera Cluster (Percona XtraDB Cluster 8.0)

> Tài liệu này ghi lại **TỪNG CÂU LỆNH** để dựng giải pháp 06 mà không cần `run-all.sh` / `run-all.ps1`. Copy-paste theo thứ tự từ trên xuống. Mỗi bước nêu rõ:
> - 🖥️ **Where**: chạy ở đâu (HOST / node1 / node2 / node3 / mgmt)
> - 💻 **Command**: lệnh CLI hoặc SQL
> - 📝 **File**: cấu hình cần ghi (nếu có)
> - ✅ **Verify**: cách kiểm tra step OK
>
> ⚠ **QUAN TRỌNG**: PXC thay thế HẲN `mysql-server` community. **KHÔNG** chạy `scripts/common/01-install-mysql.sh` trên 3 DB nodes. Nếu host đã cài MySQL community, phải PURGE trước (xem B3.0).

## 0. Topology & biến môi trường

| Host  | IP              | Vai trò                                | Ports listen                  |
|-------|-----------------|----------------------------------------|-------------------------------|
| node1 | 192.168.10.11   | PXC member (bootstrap node)            | 3306, 4567, 4568, 4444        |
| node2 | 192.168.10.12   | PXC member (joiner)                    | 3306, 4567, 4568, 4444        |
| node3 | 192.168.10.13   | PXC member (joiner)                    | 3306, 4567, 4568, 4444        |
| mgmt  | 192.168.10.20   | mysql-client / observer                | —                             |

Credentials mặc định (đổi nếu muốn — xem [scripts/common/env.sh](../../scripts/common/env.sh)):

```
MYSQL_ROOT_PWD       = ChangeMe!Root#2026
GALERA_CLUSTER_NAME  = pxc-cluster
```

Cổng Galera cần thông giữa 3 DB nodes:

| Port  | Mục đích                                              |
|-------|-------------------------------------------------------|
| 3306  | Client MySQL (như bình thường — mọi node WRITABLE)    |
| 4567  | Galera replication (group communication, gcomm)       |
| 4568  | IST — Incremental State Transfer (replay missed txns) |
| 4444  | SST — State Snapshot Transfer (full copy via xtrabackup) |

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

✅ **Verify**:
```bash
vagrant status
# Tất cả 4 VM: running (virtualbox)

# Test connectivity giữa các nodes (đặc biệt port 4567 sau này — không kiểm tra ở đây vì PXC chưa chạy)
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

### B2.1 — `/etc/hosts` (4 nodes giống nhau)

📝 **File**: `/etc/hosts` — append block:
```
# >>> mysql-ha cluster >>>
192.168.10.11  node1
192.168.10.12  node2
192.168.10.13  node3
192.168.10.20  mgmt
# <<< mysql-ha cluster <<<
```

### B2.2 — Tắt swap, NTP, sysctl, ulimit

```bash
# Tắt swap (PXC khuyến nghị)
swapoff -a
sed -i.bak -E '/^[^#].*\sswap\s/s/^/#/' /etc/fstab

# NTP — clock skew giữa nodes phá hỏng cert-based replication
timedatectl set-ntp true
DEBIAN_FRONTEND=noninteractive apt-get update
apt-get install -y chrony && systemctl enable --now chrony

# sysctl
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
sysctl --system

# ulimit
mkdir -p /etc/systemd/system/mysql.service.d
cat >/etc/systemd/system/mysql.service.d/limits.conf <<'EOF'
[Service]
LimitNOFILE=1048576
LimitNPROC=65535
EOF
systemctl daemon-reload

# AppArmor: disable (Galera bind 4567/4568/4444 mà default profile chặn)
systemctl disable --now apparmor 2>/dev/null || true
```

✅ **Verify**: trên mỗi node:
```bash
grep -A4 'mysql-ha cluster' /etc/hosts    # 4 dòng IP
swapon --show                              # rỗng (swap OFF)
timedatectl | grep -i synchron             # "System clock synchronized: yes"
sysctl vm.swappiness                       # = 1
```

---

## B3 · Cài Percona XtraDB Cluster 8.0 — chạy TRÊN 3 DB NODES

🖥️ **Where**: node1, node2, node3 (KHÔNG cài trên mgmt)

> ⚠ **Bỏ qua bước này** nếu host vẫn còn package `mysql-server` (MySQL community) từ demo khác. Trước hết PURGE — xem B3.0.

### B3.0 — Purge MySQL community nếu đã cài (one-time)

🖥️ **Where**: node1, node2, node3

```bash
# Kiểm tra
dpkg -l | grep -E '^ii  mysql-server-8\.|^ii  mysql-server-core' | head -n3

# Nếu thấy package mysql-server* → purge
sudo systemctl stop mysql 2>/dev/null || true
sudo systemctl stop mysql@bootstrap.service 2>/dev/null || true
sudo DEBIAN_FRONTEND=noninteractive apt-get remove --purge -y \
  'mysql-server*' 'mysql-client*' 'mysql-common*' 'mysql-community*' 'libmysqlclient*'
sudo rm -rf /var/lib/mysql /etc/mysql /var/log/mysql
sudo apt-get autoremove -y
```

✅ **Verify** không còn `mysql-server-*`:
```bash
dpkg -l | grep -E 'mysql-server|percona-xtradb' || echo "OK - clean"
ls /var/lib/mysql /etc/mysql 2>&1 | grep -i 'no such'  # đều "No such file"
```

### B3.1 — Add Percona repo + preseed root password

🖥️ **Where**: node1, node2, node3 (cùng câu lệnh)

```bash
# Add Percona repo
wget -qO /tmp/percona.deb https://repo.percona.com/apt/percona-release_latest.generic_all.deb
sudo dpkg -i /tmp/percona.deb
sudo percona-release setup pxc-80
sudo apt-get update

# Preseed root password TRƯỚC khi cài — nếu không, PXC mặc định set root@localhost
# với plugin auth_socket (không có password), khiến mọi tool TCP+password fail.
sudo debconf-set-selections <<'EOF'
percona-xtradb-cluster-server percona-xtradb-cluster-server/root-pass password ChangeMe!Root#2026
percona-xtradb-cluster-server percona-xtradb-cluster-server/re-root-pass password ChangeMe!Root#2026
EOF
```

### B3.2 — Cài PXC

```bash
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y percona-xtradb-cluster
# Package ~250 MB, mất 1-3 phút
```

Postinst của Percona thường tự start `mysql.service` ngay — STOP nó trước khi config:

```bash
sudo systemctl stop mysql || sudo systemctl stop mysqld || true
```

### B3.3 — Ghi config Galera (mỗi node 1 file, khác nhau ở `wsrep_node_name` + `wsrep_node_address`)

📝 **File**: `/etc/mysql/mysql.conf.d/zz-pxc.cnf`

> 🚨 **Quan trọng — đa NIC**: Vagrant gắn 2 interface cho mỗi VM: `eth0` (NAT 10.0.2.15 — DÙNG CHUNG cho cả 3 VMs) và `eth1` (host-only 192.168.10.x — IP unique). Galera dùng `wsrep_node_address` để tự nhận diện. NẾU dùng NAT IP (10.0.2.15), 3 node đều khai báo cùng IP → cluster broken. **PHẢI** pin IP host-only.

Bash one-liner pick IP host-only:
```bash
LOCAL_IP=$(hostname -I | tr ' ' '\n' | grep -E '^192\.168\.10\.[0-9]+$' | head -n1)
echo "LOCAL_IP=$LOCAL_IP"   # phải là 192.168.10.11/12/13 theo node
```

Set NODE_NAME theo hostname:
```bash
case "$(hostname)" in
  node1) NODE_NAME=pxc-node1 ;;
  node2) NODE_NAME=pxc-node2 ;;
  node3) NODE_NAME=pxc-node3 ;;
esac
echo "NODE_NAME=$NODE_NAME"
```

Ghi config:
```bash
sudo tee /etc/mysql/mysql.conf.d/zz-pxc.cnf >/dev/null <<EOF
[mysqld]
wsrep_provider                = /usr/lib/galera4/libgalera_smm.so
wsrep_cluster_address         = gcomm://192.168.10.11,192.168.10.12,192.168.10.13
wsrep_cluster_name            = pxc-cluster
wsrep_node_name               = ${NODE_NAME}
wsrep_node_address            = ${LOCAL_IP}

binlog_format                 = ROW
default_storage_engine        = InnoDB
innodb_autoinc_lock_mode      = 2

wsrep_sst_method              = xtrabackup-v2
# wsrep_sst_auth REMOVED in PXC 8.0 — SST nay dùng internal user
# mysql.pxc.sst.user.<rand> tự sinh bởi mysqld; KHÔNG khai báo ở đây.

# Tắt SSL cho LAB — PXC 8.0 mặc định pxc-encrypt-cluster-traffic=ON,
# mỗi node sinh cert riêng → handshake fail. Production phải bật + đồng bộ certs.
pxc-encrypt-cluster-traffic    = OFF

pxc_strict_mode               = ENFORCING
EOF
```

✅ **Verify** trên cả 3 node:
```bash
dpkg -l | grep percona-xtradb-cluster | head -n3
# percona-xtradb-cluster                 1:8.0.45-36-1.jammy
# percona-xtradb-cluster-client          1:8.0.45-36-1.jammy
# percona-xtradb-cluster-common          1:8.0.45-36-1.jammy

sudo grep -E '^wsrep_node_(name|address)' /etc/mysql/mysql.conf.d/zz-pxc.cnf
# wsrep_node_name = pxc-nodeN
# wsrep_node_address = 192.168.10.1N    ← KHÔNG được là 10.0.2.15

sudo systemctl is-active mysql
# inactive  ← OK, mỗi node sẽ start riêng ở B4/B5
```

---

## B4 · Bootstrap cluster trên node1

🖥️ **Where**: node1

> ⚠ Bước này CHỈ chạy 1 lần khi tạo cluster MỚI. Nếu cluster đã tồn tại, dùng `systemctl start mysql` thường (như B5).

### B4.1 — Start mysql ở chế độ bootstrap

```bash
sudo systemctl reset-failed mysql@bootstrap.service 2>/dev/null || true
sudo systemctl start mysql@bootstrap.service
# Đợi 10s để PXC init datadir
sleep 10

# Verify service đang active
sudo systemctl is-active mysql@bootstrap.service     # active
```

`mysql@bootstrap.service` được tạo bởi PXC, đọc thêm `/etc/default/mysql.bootstrap` để override `wsrep_cluster_address=gcomm://` (rỗng = "tạo cluster mới"). Sau khi cluster đã có thành viên, ta sẽ chuyển sang `mysql.service` ở B5.

### B4.2 — Đảm bảo root có password native

Nếu B3.1 preseed thành công thì root@localhost đã có password. Nhưng nếu trước đó cài qua đường khác (vagrant snapshot, install-mysql.sh), root có thể đang dùng `auth_socket`. Set lại (idempotent):

```bash
# Thử login với password trước
mysql -uroot -p'ChangeMe!Root#2026' -h127.0.0.1 -e "SELECT 1" 2>/dev/null \
  || sudo mysql -uroot -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY 'ChangeMe!Root#2026'; FLUSH PRIVILEGES;"
```

### B4.3 — Verify cluster size = 1, Primary

```bash
mysql -uroot -p'ChangeMe!Root#2026' -e "
SHOW STATUS WHERE Variable_name IN
 ('wsrep_cluster_size','wsrep_cluster_status','wsrep_local_state_comment','wsrep_ready');"
```

Kỳ vọng:
```
wsrep_cluster_size           1
wsrep_cluster_status         Primary
wsrep_local_state_comment    Synced
wsrep_ready                  ON
```

---

## B5 · Join node2 + node3 + Promote node1

### B5.1 — Start mysql.service trên node2

🖥️ **Where**: node2

```bash
sudo systemctl start mysql
# Mất 1-3 phút: PXC sẽ chọn donor (node1), thực hiện SST qua xtrabackup-v2
# (stream backup full /var/lib/mysql sang node2).

# Đợi sync xong
for i in {1..60}; do
  STATE=$(mysql -uroot -p'ChangeMe!Root#2026' -NB -e "SHOW STATUS LIKE 'wsrep_local_state_comment'" 2>/dev/null | awk '{print $2}')
  echo "   wsrep_local_state_comment=$STATE"
  [ "$STATE" = "Synced" ] && break
  sleep 5
done
```

### B5.2 — Start mysql.service trên node3 (giống node2)

🖥️ **Where**: node3

```bash
sudo systemctl start mysql
for i in {1..60}; do
  STATE=$(mysql -uroot -p'ChangeMe!Root#2026' -NB -e "SHOW STATUS LIKE 'wsrep_local_state_comment'" 2>/dev/null | awk '{print $2}')
  echo "   wsrep_local_state_comment=$STATE"
  [ "$STATE" = "Synced" ] && break
  sleep 5
done
```

### B5.3 — Promote node1 từ bootstrap-mode → regular member

🖥️ **Where**: node1

Sau khi cluster đã có ≥ 2 thành viên (node2, node3), `mysql@bootstrap.service` trên node1 không còn cần thiết (cluster đã có quorum, không cần ai khai báo `gcomm://` rỗng nữa). Switch sang `mysql.service` để:
- `systemctl is-active mysql` trả về `active` → verify pass.
- Sau này restart node1 (sửa config, OS update...) không phải nhớ "node1 dùng @bootstrap, node2/3 dùng mysql".

```bash
sudo systemctl stop mysql@bootstrap.service
sudo systemctl reset-failed mysql@bootstrap.service 2>/dev/null || true
sudo systemctl start mysql

# Đợi node1 rejoin cluster (IST nhẹ vì datadir vẫn cùng UUID)
for i in {1..30}; do
  STATE=$(mysql -uroot -p'ChangeMe!Root#2026' -NB -e "SHOW STATUS LIKE 'wsrep_local_state_comment'" 2>/dev/null | awk '{print $2}')
  echo "   node1 state=$STATE"
  [ "$STATE" = "Synced" ] && break
  sleep 2
done
```

✅ **Verify** trên cả 3 node:
```bash
# Trên HOST
for N in node1 node2 node3; do
  echo "--- $N ---"
  vagrant ssh $N -c "mysql -uroot -p'ChangeMe!Root#2026' -e \"
    SHOW STATUS WHERE Variable_name IN
     ('wsrep_cluster_size','wsrep_cluster_status','wsrep_local_state_comment','wsrep_ready','wsrep_connected');\""
done
```

Kỳ vọng MỖI node hiển thị:
```
wsrep_cluster_size           3
wsrep_cluster_status         Primary
wsrep_local_state_comment    Synced
wsrep_ready                  ON
wsrep_connected              ON
```

---

## B6 · Verify đầy đủ

🖥️ **Where**: HOST

### B6.1 — Service + port

```bash
for N in node1 node2 node3; do
  echo "--- $N ---"
  vagrant ssh $N -c "
    sudo systemctl is-active mysql
    sudo ss -tlnp 2>/dev/null | grep -E ':(3306|4567) ' | head -n2
  "
done
```

Kỳ vọng: mọi node `active`, listen 3306 + 4567.

### B6.2 — wsrep status (đã làm ở B5.3) + Galera config

```bash
for N in node1 node2 node3; do
  echo "--- $N ---"
  vagrant ssh $N -c "mysql -uroot -p'ChangeMe!Root#2026' -e \"
    SELECT @@innodb_autoinc_lock_mode AS aim,
           @@wsrep_cluster_name AS cluster,
           @@wsrep_node_name AS node;\""
done
```

Kỳ vọng `aim=2`, `cluster=pxc-cluster`, `node=pxc-nodeN`.

---

## B7 · Smoke test — Multi-master write + Consistency

🖥️ **Where**: HOST

### B7.1 — Tạo schema (nhớ: Galera bắt buộc PK + InnoDB)

```bash
vagrant ssh node1 -c "mysql -uroot -p'ChangeMe!Root#2026' -e \"
DROP DATABASE IF EXISTS smoke_db;
CREATE DATABASE smoke_db CHARACTER SET utf8mb4;
USE smoke_db;
CREATE TABLE t(
  id  BIGINT PRIMARY KEY AUTO_INCREMENT,
  src VARCHAR(16) NOT NULL,
  val VARCHAR(64) NOT NULL,
  ts  DATETIME(6) DEFAULT CURRENT_TIMESTAMP(6)
) ENGINE=InnoDB;\""
```

### B7.2 — Part 1: Insert tuần tự trên node1, check sync trên node2/3

```bash
# Insert 150 rows trên node1
SQL="USE smoke_db;"
for i in $(seq 1 150); do SQL+="INSERT INTO t(src,val) VALUES('node1','seq-${i}');"; done
vagrant ssh node1 -c "mysql -uroot -p'ChangeMe!Root#2026' -e \"$SQL\""

# Check count trên cả 3 node
for N in node1 node2 node3; do
  C=$(vagrant ssh $N -c "mysql -uroot -p'ChangeMe!Root#2026' -NB -e 'SELECT COUNT(*) FROM smoke_db.t'" | tr -d '\r')
  echo "$N count=$C"   # Tất cả phải = 150
done
```

### B7.3 — Part 2: Insert SONG SONG 50 rows trên mỗi node (test multi-master + certification)

```bash
for N in node1 node2 node3; do
  (
    SQL="USE smoke_db;"
    for i in $(seq 1 50); do
      SQL+="INSERT INTO t(src,val) VALUES('${N}','par-${i}-$$');"
    done
    vagrant ssh "$N" -c "mysql -uroot -p'ChangeMe!Root#2026' -e \"$SQL\""
    echo "[$N] done 50 rows"
  ) &
done
wait
sleep 2   # đợi cert-replication settle

# Verify consistency
for N in node1 node2 node3; do
  C=$(vagrant ssh $N -c "mysql -uroot -p'ChangeMe!Root#2026' -NB -e 'SELECT COUNT(*) FROM smoke_db.t'" | tr -d '\r')
  echo "$N total=$C"   # Tất cả phải = 300 (150 + 3*50)
done
```

✅ **Verify**: 3 node báo total **giống nhau** (= 300). Nếu lệch — có race condition trong test, hoặc network partition giữa các node.

---

## B8 · Test Split-Brain (DESTRUCTIVE — sẽ halt 2 VM)

🖥️ **Where**: HOST

> ⚠ Phá tạm cluster để demo behaviour minority partition. Sau test → B8.4 để recovery.

### B8.1 — Halt node2 + node3

```bash
vagrant halt --force node2
vagrant halt --force node3
sleep 15   # đợi node1 detect (gmcast.peer_timeout ~3s default, nhưng cộng failure detection thì ~10s)
```

### B8.2 — Verify node1 chuyển sang non-Primary

```bash
vagrant ssh node1 -c "mysql -uroot -p'ChangeMe!Root#2026' -e \"
SHOW STATUS WHERE Variable_name IN
 ('wsrep_cluster_size','wsrep_cluster_status','wsrep_local_state_comment','wsrep_ready');\""
```

Kỳ vọng:
```
wsrep_cluster_size           1
wsrep_cluster_status         non-Primary     ← KEY
wsrep_local_state_comment    Initialized
wsrep_ready                  OFF
```

### B8.3 — Verify node1 REFUSE write

```bash
vagrant ssh node1 -c "mysql -uroot -p'ChangeMe!Root#2026' -e \"
INSERT INTO smoke_db.t(src,val) VALUES('node1','split-brain-probe');\""
```

Kỳ vọng error:
```
ERROR 1047 (08S01): WSREP has not yet prepared node for application use
```

### B8.4 — Recovery: power-on lại node2 + node3

```bash
vagrant up node2 node3
# 2 node sẽ tự rejoin cluster:
#  - IST nếu data delta nhỏ (nhanh, vài giây)
#  - SST nếu donor đã purge log → mất 1-3 phút như B5

# Đợi và verify
sleep 30
for N in node1 node2 node3; do
  vagrant ssh $N -c "mysql -uroot -p'ChangeMe!Root#2026' -NB -e \"
    SHOW STATUS WHERE Variable_name IN
     ('wsrep_cluster_size','wsrep_cluster_status','wsrep_local_state_comment');\""
done
```

### B8.5 — Force quorum khi thật sự chỉ còn 1 node (CẨN THẬN)

Nếu trong production node2+node3 thực sự MẤT vĩnh viễn (disk failure), bạn cần ép node1 thành Primary để write tiếp:

```sql
SET GLOBAL wsrep_provider_options='pc.bootstrap=true';
```

⚠ **RỦI RO split-brain**: nếu node2/node3 thực ra vẫn sống và đang hoạt động ở phía khác → bạn vừa tạo 2 cluster đồng thời chấp nhận write. Chỉ làm khi chắc chắn 2 node kia DEAD.

---

## B9 · Rollback (OPTIONAL)

🖥️ **Where**: HOST

### B9.1 — Soft rollback (uninstall PXC, giữ VMs)

```bash
for N in node1 node2 node3; do
  vagrant ssh "$N" -c "sudo bash -c '
    systemctl stop mysql 2>/dev/null || true
    systemctl stop mysql@bootstrap.service 2>/dev/null || true
    apt-get remove --purge -y \"percona-xtradb-cluster*\" 2>/dev/null || true
    rm -rf /var/lib/mysql /etc/mysql/mysql.conf.d/zz-pxc.cnf
  '"
done
```

### B9.2 — Hard rollback (destroy VMs)

```bash
cd vagrant
vagrant destroy -f
rm -f provision/cluster_id_rsa provision/cluster_id_rsa.pub
```

---

## Phụ lục A — Trouble-shooting nhanh

### A.1 `ERROR 1698 (28000): Access denied for user 'root'@'localhost'`
→ PXC apt install chạy với `DEBIAN_FRONTEND=noninteractive` mà KHÔNG preseed → root@localhost dùng `auth_socket` (login qua unix socket, không password). Fix:
```bash
sudo mysql -uroot -e "
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY 'ChangeMe!Root#2026';
FLUSH PRIVILEGES;"
```
Hoặc xem B3.1 — preseed TRƯỚC khi cài.

### A.2 Error log: `unknown variable 'wsrep_sst_auth=...'`
→ `wsrep_sst_auth` đã bị **REMOVED** ở PXC 8.0. PXC giờ dùng internal user `mysql.pxc.sst.user.<rand>` tự sinh. Xóa dòng `wsrep_sst_auth = ...` khỏi `zz-pxc.cnf`.

### A.3 Error log: `Failed to establish connection: invalid padding: certificate signature failure`
→ PXC 8.0 mặc định `pxc-encrypt-cluster-traffic=ON`. Mỗi node sinh SSL cert riêng tại first start, không match nhau → handshake fail trên port 4567. Fix:
- LAB: thêm `pxc-encrypt-cluster-traffic = OFF` vào `zz-pxc.cnf` (đã làm ở B3.3).
- PROD: bật ON và copy `/var/lib/mysql/{ca,server-cert,server-key}.pem` từ node1 sang node2/3 TRƯỚC khi `systemctl start mysql`.

### A.4 Cluster bootstrap được nhưng node2/3 không join — error `Connection refused` rồi `Connection timed out`
→ Thường do `wsrep_node_address` trỏ về NAT IP shared (10.0.2.15) thay vì host-only IP. Kiểm tra:
```bash
sudo grep wsrep_node_address /etc/mysql/mysql.conf.d/zz-pxc.cnf
# Phải là 192.168.10.11/12/13, KHÔNG được 10.0.2.15
```
Nếu sai → sửa file + `sudo systemctl restart mysql`.

### A.5 `unknown variable 'pxc-encrypt-cluster-traffic=...'`
→ Sai key name. PXC 8.0 dùng dấu **gạch** (`pxc-encrypt-cluster-traffic`), KHÔNG phải underscore. Cùng giá trị ON/OFF.

### A.6 Bootstrap fail: `mysql@bootstrap.service: Failed with result 'signal'`
→ Đọc `/var/log/mysql/error.log` 50 dòng cuối. Thường vì:
- Config `zz-pxc.cnf` sai syntax (xem A.2, A.3, A.5).
- Datadir cũ corrupt → backup `/var/lib/mysql.bak` và `sudo rm -rf /var/lib/mysql && sudo mysqld --initialize-insecure`.
- AppArmor block port 4567 → `sudo systemctl disable --now apparmor`.

### A.7 node2 SST fail giữa chừng → datadir partial
```bash
sudo systemctl stop mysql
sudo rm -rf /var/lib/mysql/*       # CẨN THẬN: chỉ làm trên joiner, không phải donor
sudo systemctl start mysql         # SST chạy lại từ đầu
```

### A.8 `pxc_strict_mode=ENFORCING` báo lỗi khi `CREATE TABLE` không có PK
→ Đúng kỳ vọng. Galera bắt buộc PK cho mọi bảng có write. Add PK rồi retry.

### A.9 `ER_LOCK_DEADLOCK (1213)` khi parallel write
→ Đó là Galera certification fail (write-set conflict). App phải retry transaction. Galera dùng "first-commit-wins" — node nào commit local trước thắng, node sau bị abort. Bình thường khi 2 node update cùng row.

---

## Phụ lục B — Tóm tắt files config

Toàn bộ file ghi mới trong demo này:

| Host        | File                                                  | Mô tả                                         |
|-------------|-------------------------------------------------------|-----------------------------------------------|
| 4 nodes     | `/etc/hosts` (block `mysql-ha cluster`)               | resolve hostname → IP                          |
| 4 nodes     | `/etc/fstab` (swap dòng comment)                      | tắt swap vĩnh viễn                             |
| 4 nodes     | `/etc/sysctl.d/99-mysql-ha.conf`                      | tuning kernel cho MySQL                        |
| 4 nodes     | `/etc/systemd/system/mysql.service.d/limits.conf`     | ulimit cho mysql                               |
| 3 DB nodes  | `/etc/apt/sources.list.d/percona-*.list`              | repo Percona PXC 8.0                           |
| 3 DB nodes  | `/etc/mysql/mysql.conf.d/zz-pxc.cnf`                  | wsrep_*, pxc_strict_mode, SSL OFF              |
| 3 DB nodes  | `/etc/default/mysql.bootstrap`                        | (PXC sinh sẵn — chỉ relevant cho mysql@bootstrap) |

Toàn bộ user/privilege thay đổi trong mysql:

| User                            | Tạo ở    | Host pattern | Privilege                                     |
|---------------------------------|----------|--------------|-----------------------------------------------|
| `root`                          | install  | localhost    | password = `ChangeMe!Root#2026` (mysql_native_password) |
| `mysql.pxc.sst.user.<rand>`     | tự sinh  | localhost    | (PXC quản lý, no need to touch) — dùng cho SST |
| `mysql.pxc.internal.session`    | tự sinh  | localhost    | (PXC quản lý) — DML internal cho replication   |

> 💡 **Không cần tạo `sstuser` thủ công** như PXC 5.7. PXC 8.0 đã tự động hoá toàn bộ SST credential.

---

## Phụ lục C — Mapping bash scripts ↔ manual steps

Nếu bạn muốn xem script gốc:

| Script trong repo                                              | Bước trong tài liệu |
|----------------------------------------------------------------|----------------------|
| `vagrant/Vagrantfile`                                          | B1                   |
| `vagrant/provision/generate-ssh-key.sh`                        | B1.1                 |
| `scripts/common/00-prepare-os.sh`                              | B2                   |
| `scripts/galera/install-pxc.sh`                                | B3.1 – B3.3          |
| `scripts/galera/bootstrap-node.sh`                             | B4                   |
| `scripts/galera/join-node.sh`                                  | B5.1, B5.2           |
| `scripts/galera/recover-split-brain.sh`                        | B8.5                 |
| `demo/06-galera/04-bootstrap-node1.sh`                         | B4                   |
| `demo/06-galera/05-join-node2-node3.sh`                        | B5                   |
| `demo/06-galera/06-verify.sh`                                  | B6                   |
| `demo/06-galera/07-smoke-test.sh`                              | B7                   |
| `demo/06-galera/08-split-brain-test.sh`                        | B8                   |
| `demo/06-galera/09-rollback.sh`                                | B9                   |

---

## Phụ lục D — Khác biệt với các demo HA khác

| Khía cạnh             | Demo 06 (Galera)         | Demo 02 (InnoDB Cluster)   | Demo 03 (Group Replication)  | Demo 01 (Async)              |
|-----------------------|--------------------------|----------------------------|------------------------------|------------------------------|
| Replication mode      | Synchronous (cert-based) | Async + Paxos consensus    | Async + Paxos consensus      | Async / Semi-sync            |
| Where can write?      | **MỌI node**             | Chỉ 1 PRIMARY              | Chỉ 1 PRIMARY (single-primary) | Chỉ master                   |
| Auto failover         | Không cần (multi-master) | Có (Router auto re-route)  | Có (Paxos election)          | Không (manual)               |
| Replication lag       | 0 (đồng bộ)              | gần 0 (Paxos)              | gần 0 (Paxos)                | có thể > 1s                  |
| Yêu cầu PK            | **Bắt buộc**             | Bắt buộc                   | Bắt buộc                     | Khuyến nghị                  |
| WAN-friendly          | **Không** (consensus delay) | Trung bình              | Trung bình                   | Tốt                          |
| Conflict resolution   | First-commit-wins (cert abort) | Single primary chỉ 1 writer | Single primary           | Master-only writes           |
| Package required      | `percona-xtradb-cluster` | `mysql-server-8.0`         | `mysql-server-8.0`           | `mysql-server-8.0`           |
| Đụng MySQL community? | **CÓ — phải purge trước** | Không                     | Không                        | Không                        |

---

## Phụ lục E — Lỗi đã gặp khi tự động hoá demo này (lessons learned)

Demo run đầu tiên gặp 6 bug — tất cả đã fix vào upstream `scripts/`:

| # | Triệu chứng                                                    | Nguyên nhân                                                | Fix file & dòng                             |
|---|----------------------------------------------------------------|------------------------------------------------------------|---------------------------------------------|
| 1 | Bootstrap pass nhưng node2/3 không thấy node1 qua Galera       | `wsrep_node_address = 10.0.2.15` (NAT shared) trên cả 3 node | `install-pxc.sh:31` — pick `192.168.10.x`   |
| 2 | `unknown variable 'wsrep_sst_auth=...'` aborted server         | `#` trong password bị MySQL parser coi là comment-start    | `install-pxc.sh:60-61` — biến đã bị remove ở PXC 8.0 |
| 3 | Bootstrap fail vẫn với cùng error sau khi quote `"..."`        | `wsrep_sst_auth` REMOVED hoàn toàn ở PXC 8.0               | `install-pxc.sh` — xóa hẳn dòng             |
| 4 | `Access denied for user 'root'@'localhost'`                    | Không preseed root pwd → auth_socket plugin                | `install-pxc.sh:17-20` — debconf preseed    |
| 5 | `invalid padding: certificate signature failure` trên port 4567 | SSL cluster ON, mỗi node sinh cert riêng                  | `install-pxc.sh:63-65` — `pxc-encrypt-cluster-traffic = OFF` |
| 6 | `06-verify.sh` báo `[FAIL] [node1] mysql=inactive`             | node1 còn dùng `mysql@bootstrap.service`, không phải `mysql.service` | `demo/06-galera/05-join-node2-node3.sh` — promote step |

Lưu ý: lần chạy đầu (sau khi đã có MySQL community từ demo trước) còn cần B3.0 purge mysql-server thủ công vì script `03-install-pxc.sh` chỉ DETECT (rồi exit 1), không tự purge — để tránh xoá nhầm data demo khác.


---

!!! info "Nguồn gốc"
    `HA/Mysql/demo/06-galera/MANUAL-SETUP.md`
