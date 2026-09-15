---
title: Hướng dẫn setup THỦ CÔNG — Demo 04 MHA (Master High Availability Manager)
course: 06-high-availability
source: HA/Mysql/demo/04-mha/MANUAL-SETUP.md
---

# Hướng dẫn setup THỦ CÔNG — Demo 04 MHA (Master High Availability Manager)

> Tài liệu này ghi lại **TỪNG CÂU LỆNH** để dựng giải pháp 04 (MHA) mà không cần `run-all.sh` / `run-all.ps1`. Copy-paste theo thứ tự từ trên xuống. Mỗi bước nêu rõ:
> - 🖥️ **Where**: chạy ở đâu (HOST / node1 / node2 / node3 / mgmt)
> - 💻 **Command**: lệnh CLI hoặc SQL
> - 📝 **File**: cấu hình cần ghi (nếu có)
> - ✅ **Verify**: cách kiểm tra step OK
>
> ⚠️ **Tiền đề BẮT BUỘC**: phải có cụm **Async/Semi-sync 1 master + 2 replicas** đang chạy (Demo 01). MHA chỉ cài LÊN TOP, không tự dựng replication. Nếu chưa có → chạy [Demo 01 MANUAL-SETUP](../01-async-semisync/manual-setup.md) trước.

## 0. Topology & biến môi trường

| Host  | IP              | Vai trò                                          | server_id |
|-------|-----------------|--------------------------------------------------|-----------|
| node1 | 192.168.10.11   | MySQL Master (RW) + mha4mysql-node              | 1         |
| node2 | 192.168.10.12   | MySQL Replica (RO) + mha4mysql-node             | 2         |
| node3 | 192.168.10.13   | MySQL Replica (RO) + mha4mysql-node             | 3         |
| mgmt  | 192.168.10.20   | MHA Manager (`masterha_manager`) + mha4mysql-node | —         |
| VIP   | 192.168.10.100  | Floating IP gắn vào master hiện thời             | —         |

Credentials mặc định (xem [scripts/common/env.sh](../../scripts/common/env.sh)):

```
MYSQL_ROOT_PWD = ChangeMe!Root#2026
REPL_USER      = repl                       # user replication, đã có từ Demo 01
REPL_PWD       = ChangeMe!Repl#2026
ADMIN_PWD      = ChangeMe!Admin#2026        # dùng cho user mha@%
CLUSTER_NAME   = myCluster                  # tên config file /etc/mha/<name>.cnf
VIP            = 192.168.10.100
```

Khi MHA failover, **VIP move từ master cũ sang master mới**. App connect tới VIP thay vì IP cụ thể → transparent failover.

Cấu trúc hook:

```
mgmt (manager)
  │  SSH (root, key-based) + MySQL (user 'mha')
  ▼
node1 ←─── relay binlog ───→ node2 ←──→ node3
(crash)                     (new master)  (follow new)
  │
  └── masterha_manager phát hiện chết → chọn replica có position cao nhất
      → relay binlog còn sót → SET read_only=0 → gọi master_ip_failover.sh
      → SSH move VIP → CHANGE MASTER trên các replica còn lại
```

---

## B0 · Prerequisites — Verify Demo 01 đang chạy

🖥️ **Where**: HOST

Trước khi cài MHA, **phải** xác nhận:

```bash
cd vagrant

# 1) 4 VMs running
vagrant status
# Mong đợi: node1, node2, node3, mgmt = running

# 2) node1 là master với semi-sync ON, 2 clients
vagrant ssh node1 -c "mysql -uroot -p'ChangeMe!Root#2026' -e \"
  SHOW STATUS LIKE 'Rpl_semi_sync_source_status';
  SHOW STATUS LIKE 'Rpl_semi_sync_source_clients';
\""
# Mong đợi: Rpl_semi_sync_source_status=ON, Rpl_semi_sync_source_clients=2

# 3) node2, node3 đang replicate từ node1
for N in node2 node3; do
  vagrant ssh $N -c "mysql -uroot -p'ChangeMe!Root#2026' -e 'SHOW REPLICA STATUS\G' | egrep 'Source_Host|Replica_IO_Running|Replica_SQL_Running'"
done
# Mong đợi: Source_Host=node1, Replica_IO_Running=Yes, Replica_SQL_Running=Yes
```

### B0.1 — Đặt `relay_log_purge=0` trên replicas (MHA cần)

🖥️ **Where**: HOST → node2 + node3

MHA cần relay log của replica **không** bị tự xoá để dùng làm "tail binlog" khi master cũ chết. MySQL mặc định `relay_log_purge=1`. Fix:

```bash
for N in node2 node3; do
  vagrant ssh $N -c "mysql -uroot -p'ChangeMe!Root#2026' -e \"
    SET PERSIST relay_log_purge=0;
    SET GLOBAL relay_log_purge=0;
    SELECT @@relay_log_purge;
  \""
done
```

✅ **Verify**:

```bash
for N in node2 node3; do
  vagrant ssh $N -c "mysql -uroot -p'ChangeMe!Root#2026' -N -e 'SELECT @@relay_log_purge;'"
done
# Mong đợi: 0 (cả hai)
```

> **Tại sao**: Khi master chết, MHA SSH vào master cũ để copy `mysql-bin.*` còn sót, đồng thời lấy relay log của replica có position cao nhất làm "delta" để các replica khác catch-up. Nếu `relay_log_purge=1` thì relay log đã bị xoá khi SQL thread áp xong → MHA mất một mảnh dữ liệu.

---

## B1 · Precheck (tương đương `01-precheck.sh`)

🖥️ **Where**: HOST

Script `01-precheck.sh` đóng gói các check ở B0 + auto-fix `relay_log_purge`. Manual version:

```bash
cd vagrant

# 1) VMs running
for N in node1 node2 node3 mgmt; do
  STATE=$(vagrant status "$N" --machine-readable 2>/dev/null | awk -F, -v n="$N" '$2==n && $3=="state"{print $4; exit}')
  echo "[$N] state=$STATE"
done

# 2) MySQL active trên 3 DB nodes
for N in node1 node2 node3; do
  vagrant ssh $N -c "sudo systemctl is-active mysql"
done

# 3) Semi-sync ON với 2 clients
vagrant ssh node1 -c "mysql -uroot -p'ChangeMe!Root#2026' -N -B -e \"
  SHOW STATUS LIKE 'Rpl_semi_sync_source_status';
  SHOW STATUS LIKE 'Rpl_semi_sync_source_clients';\""

# 4) Replica IO/SQL Yes trên node2, node3
for N in node2 node3; do
  vagrant ssh $N -c "mysql -uroot -p'ChangeMe!Root#2026' -e 'SHOW REPLICA STATUS\G'" | egrep "Replica_IO_Running|Replica_SQL_Running" | head -2
done

# 5) relay_log_purge=0
for N in node2 node3; do
  vagrant ssh $N -c "mysql -uroot -p'ChangeMe!Root#2026' -N -B -e 'SELECT @@relay_log_purge;'"
done
```

✅ **Pass criteria**: tất cả check trả về kết quả mong đợi. Nếu fail → fix theo gợi ý (Phụ lục A).

---

## B2 · SSH passwordless mesh

MHA cần SSH **2 chiều** giữa:
- `mgmt → node1/2/3` (manager copy binlog, gọi failover hook)
- `node1 ↔ node2`, `node1 ↔ node3`, `node2 ↔ node3` (DB nodes relay binlog cho nhau khi failover)

Tất cả dùng user `root` + RSA key.

### B2.1 — Bật `PermitRootLogin yes` + sinh key trên mgmt

🖥️ **Where**: HOST → mgmt

```bash
vagrant ssh mgmt -c "
  sudo bash -c '
    sed -i \"s/^#\\?PermitRootLogin.*/PermitRootLogin yes/\" /etc/ssh/sshd_config
    systemctl reload sshd 2>/dev/null || systemctl reload ssh
    echo \"root:ChangeMe!Root#2026\" | chpasswd
    [ -f /root/.ssh/id_rsa ] || ssh-keygen -t rsa -b 4096 -N \"\" -f /root/.ssh/id_rsa
    cat /root/.ssh/id_rsa.pub
  '
"
```

Lưu lại output `ssh-rsa ...` (pubkey của mgmt).

### B2.2 — Copy pubkey mgmt vào authorized_keys của node1/2/3

🖥️ **Where**: HOST → node1/2/3

```bash
MGMT_PUB=$(vagrant ssh mgmt -c "sudo cat /root/.ssh/id_rsa.pub" | tr -d '\r' | grep '^ssh-')

for N in node1 node2 node3; do
  vagrant ssh $N -c "
    sudo bash -c '
      sed -i \"s/^#\\?PermitRootLogin.*/PermitRootLogin yes/\" /etc/ssh/sshd_config
      systemctl reload sshd 2>/dev/null || systemctl reload ssh
      mkdir -p /root/.ssh && chmod 700 /root/.ssh
      grep -qxF \"${MGMT_PUB}\" /root/.ssh/authorized_keys 2>/dev/null || echo \"${MGMT_PUB}\" >> /root/.ssh/authorized_keys
      chmod 600 /root/.ssh/authorized_keys
      cat > /root/.ssh/config <<EOF
Host *
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null
  LogLevel ERROR
EOF
      chmod 600 /root/.ssh/config
    '
  "
done
```

### B2.3 — Sinh key cho TỪNG DB node + cross-install pubkeys (mesh)

🖥️ **Where**: HOST → node1, node2, node3

```bash
# 1) Sinh key trên mỗi DB node
declare -A NODE_PUB
for N in node1 node2 node3; do
  vagrant ssh $N -c "sudo bash -c '[ -f /root/.ssh/id_rsa ] || ssh-keygen -t rsa -b 4096 -N \"\" -f /root/.ssh/id_rsa; cat /root/.ssh/id_rsa.pub'"
  NODE_PUB[$N]=$(vagrant ssh $N -c "sudo cat /root/.ssh/id_rsa.pub" | tr -d '\r' | grep '^ssh-')
done

# 2) Cài pubkey của 3 DB nodes vào authorized_keys của nhau
for TARGET in node1 node2 node3; do
  for SRC in node1 node2 node3; do
    [[ "$SRC" == "$TARGET" ]] && continue
    PUB="${NODE_PUB[$SRC]}"
    vagrant ssh $TARGET -c "
      sudo bash -c '
        mkdir -p /root/.ssh && chmod 700 /root/.ssh
        grep -qxF \"${PUB}\" /root/.ssh/authorized_keys 2>/dev/null || echo \"${PUB}\" >> /root/.ssh/authorized_keys
        chmod 600 /root/.ssh/authorized_keys
      '
    "
  done
done
```

✅ **Verify**:

```bash
# mgmt → các node OK
for IP in 192.168.10.11 192.168.10.12 192.168.10.13; do
  vagrant ssh mgmt -c "sudo ssh -o ConnectTimeout=5 root@${IP} 'hostname'"
done

# node ↔ node OK (cặp khác nhau)
for SRC in node1 node2 node3; do
  for DST in 192.168.10.11 192.168.10.12 192.168.10.13; do
    echo -n "$SRC -> $DST: "
    vagrant ssh $SRC -c "sudo ssh -o ConnectTimeout=5 root@$DST 'hostname'" 2>&1 | tail -1
  done
done
# Mong đợi: tất cả các cặp KHÁC nhau đều in được hostname (self-SSH có thể fail, không sao)
```

---

## B3 · Cài `mha4mysql-node` trên 3 DB nodes

🖥️ **Where**: HOST → node1, node2, node3

`mha4mysql-node` cung cấp các tool `save_binary_logs`, `apply_diff_relay_logs`, `purge_relay_logs` — MHA manager SSH vào các DB node và gọi các tool này.

### B3.1 — Cài Perl deps + arping + package mha4mysql-node

```bash
for N in node1 node2 node3; do
  vagrant ssh $N -c "
    sudo bash -c '
      apt-get update -qq
      # Perl deps: DBD::MySQL, Config::Tiny, Log::Dispatch, Parallel::ForkManager
      # iputils-arping: gratuitous ARP để clear ARP cache khi VIP move
      apt-get install -y perl libdbd-mysql-perl libconfig-tiny-perl liblog-dispatch-perl libparallel-forkmanager-perl iputils-arping
      wget -qO /tmp/mha-node.deb https://github.com/yoshinorim/mha4mysql-node/releases/download/v0.58/mha4mysql-node_0.58-0_all.deb
      dpkg -i /tmp/mha-node.deb
    '
  "
done
```

### B3.2 — Patch `MHA/NodeUtil.pm` cho MySQL 8.0 (CRITICAL)

🖥️ **Where**: HOST → node1, node2, node3

**Bug**: MHA 0.58's `parse_mysql_version` dùng regex `/(\d+)/g` global → match cả số trong `x86_64`. Với MySQL 8.0.46, chuỗi `Ver 8.0.46 for Linux on x86_64` cho ra `[8, 0, 46, 86, 64]` (5 số). `sprintf('%03d%03d%03d', @list)` báo "Redundant argument in sprintf" → `masterha_check_repl` fail.

Fix: chỉ lấy 3 phần tử đầu.

```bash
for N in node1 node2 node3; do
  vagrant ssh $N -c "
    sudo python3 <<'PYEOF'
import io
p = '/usr/share/perl5/MHA/NodeUtil.pm'
with io.open(p, 'r', encoding='utf-8') as f: s = f.read()
old1 = \"  my \$result = sprintf( '%03d%03d%03d', \$str =~ m/(\\\\d+)/g );\"
new1 = \"  my @v = (\$str =~ m/(\\\\d+)/g); my \$result = sprintf( '%03d%03d%03d', \$v[0]||0, \$v[1]||0, \$v[2]||0 ); # MHA_PATCH_MYSQL8\"
old2 = \"  my \$result = sprintf( '%03d%03d', \$str =~ m/(\\\\d+)/g );\"
new2 = \"  my @v = (\$str =~ m/(\\\\d+)/g); my \$result = sprintf( '%03d%03d', \$v[0]||0, \$v[1]||0 ); # MHA_PATCH_MYSQL8\"
s = s.replace(old1, new1).replace(old2, new2)
with io.open(p, 'w', encoding='utf-8') as f: f.write(s)
PYEOF
    sudo grep -c MHA_PATCH_MYSQL8 /usr/share/perl5/MHA/NodeUtil.pm
  "
done
# Mong đợi: 2 (xuất hiện 2 chỗ patched)
```

### B3.3 — Tạo user `mha@%` (CHỈ trên master)

🖥️ **Where**: HOST → node1 (master)

Replicas đang `super_read_only=ON` → không CREATE USER được. Tạo trên master, user sẽ replicate sang.

```bash
vagrant ssh node1 -c "mysql -uroot -p'ChangeMe!Root#2026' <<'SQL'
CREATE USER IF NOT EXISTS 'mha'@'%' IDENTIFIED BY 'ChangeMe!Admin#2026';
ALTER USER 'mha'@'%' IDENTIFIED BY 'ChangeMe!Admin#2026';
GRANT ALL PRIVILEGES ON *.* TO 'mha'@'%';
FLUSH PRIVILEGES;
SQL
"
```

✅ **Verify**:

```bash
for N in node1 node2 node3; do
  echo "--- $N ---"
  vagrant ssh $N -c "
    dpkg -l | grep mha4mysql-node
    which save_binary_logs
    sudo grep -c MHA_PATCH_MYSQL8 /usr/share/perl5/MHA/NodeUtil.pm
    mysql -uroot -p'ChangeMe!Root#2026' -N -e \"SELECT user,host FROM mysql.user WHERE user='mha';\"
  "
done
# Mong đợi: package installed, /usr/bin/save_binary_logs tồn tại, patch=2, user mha@% có
```

---

## B4 · Cài `mha4mysql-manager` + config trên mgmt

🖥️ **Where**: HOST → mgmt

### B4.1 — Cài node + manager package

⚠️ `mha4mysql-manager` **depends on** `mha4mysql-node` — phải cài node trước trên mgmt (dù mgmt không chạy MySQL).

```bash
vagrant ssh mgmt -c "
  sudo bash -c '
    apt-get update -qq
    apt-get install -y perl libdbd-mysql-perl libconfig-tiny-perl liblog-dispatch-perl libparallel-forkmanager-perl libmail-sender-perl || true
    # 1) Node (dependency)
    wget -qO /tmp/mha-node.deb https://github.com/yoshinorim/mha4mysql-node/releases/download/v0.58/mha4mysql-node_0.58-0_all.deb
    dpkg -i /tmp/mha-node.deb || true
    # 2) Fix broken deps nếu có
    apt-get install -f -y
    # 3) Manager
    wget -qO /tmp/mha-mgr.deb https://github.com/yoshinorim/mha4mysql-manager/releases/download/v0.58/mha4mysql-manager_0.58-0_all.deb
    dpkg -i /tmp/mha-mgr.deb
  '
"
```

### B4.2 — Patch `NodeUtil.pm` trên mgmt (cùng fix MySQL 8.0)

```bash
vagrant ssh mgmt -c "
  sudo python3 <<'PYEOF'
import io
p = '/usr/share/perl5/MHA/NodeUtil.pm'
with io.open(p, 'r', encoding='utf-8') as f: s = f.read()
old1 = \"  my \$result = sprintf( '%03d%03d%03d', \$str =~ m/(\\\\d+)/g );\"
new1 = \"  my @v = (\$str =~ m/(\\\\d+)/g); my \$result = sprintf( '%03d%03d%03d', \$v[0]||0, \$v[1]||0, \$v[2]||0 ); # MHA_PATCH_MYSQL8\"
old2 = \"  my \$result = sprintf( '%03d%03d', \$str =~ m/(\\\\d+)/g );\"
new2 = \"  my @v = (\$str =~ m/(\\\\d+)/g); my \$result = sprintf( '%03d%03d', \$v[0]||0, \$v[1]||0 ); # MHA_PATCH_MYSQL8\"
s = s.replace(old1, new1).replace(old2, new2)
with io.open(p, 'w', encoding='utf-8') as f: f.write(s)
PYEOF
  sudo grep -c MHA_PATCH_MYSQL8 /usr/share/perl5/MHA/NodeUtil.pm
"
```

### B4.3 — Tạo thư mục + config file

📝 **File**: `/etc/mha/myCluster.cnf`

```bash
vagrant ssh mgmt -c "
  sudo bash -c '
    mkdir -p /etc/mha /var/log/mha/myCluster /var/lib/mha

    cat >/etc/mha/myCluster.cnf <<EOF
[server default]
user=mha
password=ChangeMe!Admin#2026
ssh_user=root
repl_user=repl
repl_password=ChangeMe!Repl#2026
manager_workdir=/var/lib/mha/myCluster
manager_log=/var/log/mha/myCluster/manager.log
remote_workdir=/var/lib/mha
ping_interval=3
master_binlog_dir=/var/lib/mysql
master_ip_failover_script=/etc/mha/master_ip_failover.sh
secondary_check_script=masterha_secondary_check -s 192.168.10.12 -s 192.168.10.13

[server1]
hostname=192.168.10.11
candidate_master=1

[server2]
hostname=192.168.10.12
candidate_master=1

[server3]
hostname=192.168.10.13
no_master=0
EOF
  '
"
```

**Giải thích config**:
- `user/password` = `mha/ChangeMe!Admin#2026` → MHA dùng để check MySQL state qua mysql client.
- `repl_user/repl_password` = `repl/ChangeMe!Repl#2026` → dùng để CHANGE MASTER trên replica sau failover.
- `ping_interval=3` → 3 giây ping master 1 lần. MHA chỉ failover sau 3 ping fail liên tiếp → tổng ~9s detection time.
- `secondary_check_script=masterha_secondary_check -s ...` → trước khi failover, gọi script này để **xác nhận** master thực sự chết (tránh false-positive khi mgmt mất kết nối với master nhưng master vẫn sống). Yêu cầu ít nhất 1 trong các `-s` host xác nhận không reach được master.
- `master_ip_failover_script` → hook bash chạy khi master move; nhiệm vụ là `ip addr del` trên master cũ + `ip addr add` trên master mới.
- `candidate_master=1` (server1, server2) → ưu tiên promote. `no_master=0` (server3) → vẫn có thể làm master nhưng không ưu tiên.

### B4.4 — Tạo `master_ip_failover.sh` (VIP move hook)

📝 **File**: `/etc/mha/master_ip_failover.sh`

```bash
vagrant ssh mgmt -c "
  sudo bash -c '
    cat >/etc/mha/master_ip_failover.sh <<EOSCRIPT
#!/usr/bin/env bash
# VIP failover hook gọi bởi MHA. Tham số do MHA truyền (--command=start|stop|stopssh|status).
# Auto-detect interface ở từng node thay vì hardcode (Vagrant: eth0=NAT, eth1=hostonly).
set -e
COMMAND=\"\"; NEW_MASTER_HOST=\"\"; ORIG_MASTER_HOST=\"\"
for arg in \"\\\$@\"; do
  case \"\\\$arg\" in
    --command=*)            COMMAND=\"\\\${arg#*=}\" ;;
    --new_master_host=*)    NEW_MASTER_HOST=\"\\\${arg#*=}\" ;;
    --orig_master_host=*)   ORIG_MASTER_HOST=\"\\\${arg#*=}\" ;;
  esac
done
VIP_CIDR=\"192.168.10.100/24\"
VIP_ADDR=\"192.168.10.100\"
detect_iface() {
  local host=\"\\\$1\"
  ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 root@\\\${host} \\
    \"ip -4 -o addr show | awk '\\\\\\\$4 ~ /^192\\\\\\\\.168\\\\\\\\.10\\\\\\\\./{print \\\\\\\$2; exit}'\" 2>/dev/null | tr -d \"\\r\"
}
case \"\\\$COMMAND\" in
  stop|stopssh)
    IFACE=\\\$(detect_iface \"\\\${ORIG_MASTER_HOST}\")
    [[ -z \"\\\$IFACE\" ]] && IFACE=eth1
    ssh -o StrictHostKeyChecking=no root@\\\${ORIG_MASTER_HOST} \\
      \"ip addr del \\\${VIP_CIDR} dev \\\${IFACE}\" 2>/dev/null || true
    ;;
  start)
    IFACE=\\\$(detect_iface \"\\\${NEW_MASTER_HOST}\")
    [[ -z \"\\\$IFACE\" ]] && IFACE=eth1
    ssh -o StrictHostKeyChecking=no root@\\\${NEW_MASTER_HOST} \"
      ip addr add \\\${VIP_CIDR} dev \\\${IFACE} 2>/dev/null || true
      (command -v arping >/dev/null && arping -U -I \\\${IFACE} \\\${VIP_ADDR} -c 3) || true
    \"
    ;;
  status) exit 0 ;;
esac
EOSCRIPT
    chmod +x /etc/mha/master_ip_failover.sh
  '
"
```

> **Auto-detect interface** quan trọng vì Vagrant đặt NAT trên `eth0` (default route, không phải private net), private net trên `eth1`. Nếu hardcode `eth0`, VIP sẽ gắn nhầm vào card NAT — host khác không reach được.

### B4.5 — Run `masterha_check_ssh` + `masterha_check_repl`

```bash
vagrant ssh mgmt -c "sudo masterha_check_ssh --conf=/etc/mha/myCluster.cnf"
# Mong đợi: "All SSH connection tests passed successfully."

vagrant ssh mgmt -c "sudo masterha_check_repl --conf=/etc/mha/myCluster.cnf"
# Mong đợi: "MySQL Replication Health is OK."
```

> ⚠️ `masterha_check_ssh` trong MHA 0.58 có bug "Use of uninitialized value in exit" → exit code = 255 dù check PASS. Đừng dựa vào exit code; grep "passed successfully" trong output.

### B4.6 — Start manager dưới dạng daemon

```bash
vagrant ssh mgmt -c "
  sudo bash -c '
    pkill -f \"masterha_manager --conf=/etc/mha/myCluster.cnf\" 2>/dev/null || true
    sleep 1
    nohup masterha_manager --conf=/etc/mha/myCluster.cnf \\
      --remove_dead_master_conf --ignore_last_failover \\
      >/var/log/mha/myCluster/manager.stdout 2>&1 &
    disown 2>/dev/null || true
  '
"
sleep 3
vagrant ssh mgmt -c "sudo masterha_check_status --conf=/etc/mha/myCluster.cnf"
# Mong đợi: "myCluster (pid:NNN) is running(0:PING_OK), master:192.168.10.11"
```

**Cờ giải thích**:
- `--remove_dead_master_conf` → sau failover, MHA tự xoá section `[server1]` khỏi config để không bị check_status fail vì master cũ vẫn die.
- `--ignore_last_failover` → bỏ qua lock file `myCluster.failover.complete` (MHA mặc định không cho failover liên tiếp trong 8h để tránh flapping). Demo cần bật.

---

## B5 · Verify (tương đương `05-verify.sh`)

🖥️ **Where**: HOST

```bash
# 1) SSH check (chạy lại để verify chính thức)
vagrant ssh mgmt -c "sudo masterha_check_ssh --conf=/etc/mha/myCluster.cnf 2>&1" | grep "passed successfully"

# 2) Replication check
vagrant ssh mgmt -c "sudo masterha_check_repl --conf=/etc/mha/myCluster.cnf 2>&1" | grep "Replication Health is OK"

# 3) Manager status
vagrant ssh mgmt -c "sudo masterha_check_status --conf=/etc/mha/myCluster.cnf"
# Mong đợi: PING_OK, master:192.168.10.11
```

---

## B6 · Bind VIP lên master ban đầu (node1)

🖥️ **Where**: HOST → node1

Lần đầu bring-up MHA không tự gắn VIP — phải tự `ip addr add` lên master.

```bash
# 1) Tìm interface chứa private IP trên node1
IFACE=$(vagrant ssh node1 -c "ip -4 -o addr show | awk '\$4 ~ /^192\\.168\\.10\\./{print \$2; exit}'" | tr -d '\r')
echo "iface=${IFACE}"   # Vagrant Ubuntu: eth1

# 2) Gắn VIP
vagrant ssh node1 -c "
  if ip -4 addr show ${IFACE} | grep -q '192.168.10.100/24'; then
    echo 'VIP đã có, skip'
  else
    sudo ip addr add 192.168.10.100/24 dev ${IFACE}
    sudo arping -U -I ${IFACE} 192.168.10.100 -c 3 || true
  fi
  ip -4 addr show ${IFACE} | grep 'inet '
"
```

✅ **Verify từ mgmt**:

```bash
vagrant ssh mgmt -c "ping -c 2 -W 2 192.168.10.100 && echo PING_OK"
```

---

## B7 · Failover Test (DESTRUCTIVE)

🖥️ **Where**: HOST

Mô phỏng master chết bằng `vagrant halt --force node1`. MHA detect → promote node2 → move VIP → CHANGE MASTER trên node3.

### B7.1 — Insert sentinel vào master

```bash
SENT="mha-sentinel-$(date +%s)"
vagrant ssh node1 -c "mysql -uroot -p'ChangeMe!Root#2026' -e \"
  CREATE DATABASE IF NOT EXISTS smoke_db;
  CREATE TABLE IF NOT EXISTS smoke_db.t(id INT PRIMARY KEY AUTO_INCREMENT, val VARCHAR(64), ts TIMESTAMP DEFAULT CURRENT_TIMESTAMP);
  INSERT INTO smoke_db.t(val) VALUES('${SENT}');
\""

# Đợi replicas thấy sentinel (semi-sync nên 2-3s là max)
for N in node2 node3; do
  vagrant ssh $N -c "mysql -uroot -p'ChangeMe!Root#2026' -N -e \"SELECT COUNT(*) FROM smoke_db.t WHERE val='${SENT}';\""
done
# Mong đợi: 1 (cả hai)
```

### B7.2 — Halt master (mô phỏng crash)

```bash
HALT_TS=$(date +%s)
echo "HALT_TS=${HALT_TS} ($(date -d @${HALT_TS}))"
vagrant halt --force node1
```

### B7.3 — Poll manager.log tới khi failover xong

```bash
# Trong 1 cửa sổ khác (hoặc loop)
for i in $(seq 1 60); do
  LINE=$(vagrant ssh mgmt -c "sudo grep -E 'Master failover .* completed successfully' /var/log/mha/myCluster/manager.log 2>/dev/null | tail -n1" | tr -d '\r')
  if [[ -n "$LINE" ]]; then
    echo "FAILOVER DONE: $LINE"
    PROMOTE_RTO=$(( $(date +%s) - HALT_TS ))
    echo "PROMOTE_RTO=${PROMOTE_RTO}s"
    break
  fi
  echo "waiting... ${i}*2s"
  sleep 2
done
```

Trong demo này: **PROMOTE_RTO ≈ 95s** (ping_interval 3s × 3 + secondary_check + binlog copy + relay apply + VIP move + CHANGE MASTER trên replica còn lại).

### B7.4 — Verify failover

```bash
# 1) read_only=0 trên node2 hoặc node3 (master mới)
for N in node2 node3; do
  RO=$(vagrant ssh $N -c "mysql -uroot -p'ChangeMe!Root#2026' -N -e 'SELECT @@read_only;'")
  echo "$N read_only=$RO"
done
# Mong đợi: 1 trong 2 = 0 (master mới). Ở demo: node2=0, node3=1

# 2) VIP đã trên master mới (giả sử node2)
vagrant ssh node2 -c "ip -4 -o addr show | grep 192.168.10"
# Mong đợi: thấy cả 192.168.10.12 và 192.168.10.100

# 3) node3 đã CHANGE MASTER về node2
vagrant ssh node3 -c "mysql -uroot -p'ChangeMe!Root#2026' -e 'SHOW REPLICA STATUS\G'" | egrep "Source_Host|Replica_IO|Replica_SQL"
# Mong đợi: Source_Host=192.168.10.12, Replica_IO_Running=Yes, Replica_SQL_Running=Yes

# 4) Insert post-failover qua master mới (qua VIP)
vagrant ssh mgmt -c "mysql -uroot -p'ChangeMe!Root#2026' -h192.168.10.100 -e 'INSERT INTO smoke_db.t(val) VALUES(\"post-failover\");' 2>/dev/null || echo 'root@VIP không có grants — dùng user khác. Để chứng minh write-OK, ssh thẳng node2.'"

vagrant ssh node2 -c "mysql -uroot -p'ChangeMe!Root#2026' -e 'INSERT INTO smoke_db.t(val) VALUES(\"post-failover\"); SELECT * FROM smoke_db.t ORDER BY id DESC LIMIT 3;'"
```

✅ **Pass criteria**:
- Có 1 node có `read_only=0` (master mới)
- VIP `192.168.10.100` trên master mới (eth1)
- Replica còn lại có `Source_Host` = IP master mới, `Replica_IO_Running=Yes`
- INSERT vào master mới thành công

Sau failover, MHA tự **dừng manager** (logic: failover xong → manager exit, expect admin can thiệp rồi restart). Nếu chạy lại check_status sẽ thấy `NOT_RUNNING`.

---

## B8 · Rebuild old master thành replica (sau failover)

🖥️ **Where**: HOST

### B8.1 — Power-on master cũ (node1)

```bash
vagrant up node1

# Đợi MySQL ready
for i in $(seq 1 60); do
  if vagrant ssh node1 -c "mysqladmin -uroot -p'ChangeMe!Root#2026' ping 2>/dev/null | grep -q alive"; then
    echo "MySQL trên node1 ready (${i}*2s)"; break
  fi
  sleep 2
done
```

### B8.2 — Configure node1 làm replica của master mới (node2)

⚠️ Giả định master mới = node2. Auto-detect từ `read_only`:

```bash
NEW_MASTER_IP=""
for N in node2 node3; do
  RO=$(vagrant ssh $N -c "mysql -uroot -p'ChangeMe!Root#2026' -N -e 'SELECT @@read_only;'")
  [[ "$RO" == "0" ]] && case "$N" in
    node2) NEW_MASTER_IP=192.168.10.12 ;;
    node3) NEW_MASTER_IP=192.168.10.13 ;;
  esac
done
echo "NEW_MASTER_IP=${NEW_MASTER_IP}"

vagrant ssh node1 -c "mysql -uroot -p'ChangeMe!Root#2026' <<SQL
STOP REPLICA;
RESET REPLICA ALL;
CHANGE REPLICATION SOURCE TO
  SOURCE_HOST='${NEW_MASTER_IP}',
  SOURCE_USER='repl',
  SOURCE_PASSWORD='ChangeMe!Repl#2026',
  SOURCE_AUTO_POSITION=1,
  GET_SOURCE_PUBLIC_KEY=1;
START REPLICA;
SET GLOBAL read_only=1;
SET GLOBAL super_read_only=1;
SQL
"
```

✅ **Verify**:

```bash
vagrant ssh node1 -c "mysql -uroot -p'ChangeMe!Root#2026' -e 'SHOW REPLICA STATUS\G'" | egrep "Source_Host|Replica_IO|Replica_SQL|Seconds_Behind"
# Mong đợi: Source_Host=192.168.10.12, IO=Yes, SQL=Yes, Seconds_Behind_Source=0
```

### B8.3 — Add lại `[server1]` vào config + restart manager

`--remove_dead_master_conf` đã xoá section `[server1]` sau failover. Add lại nếu thiếu, xoá lock failover, restart manager.

```bash
vagrant ssh mgmt -c "
  sudo bash -c '
    rm -f /var/lib/mha/myCluster/*.failover.complete 2>/dev/null || true

    if ! grep -q \"^\\[server1\\]\" /etc/mha/myCluster.cnf; then
      cat >>/etc/mha/myCluster.cnf <<EOF

[server1]
hostname=192.168.10.11
candidate_master=1
EOF
    fi

    masterha_check_repl --conf=/etc/mha/myCluster.cnf
    nohup masterha_manager --conf=/etc/mha/myCluster.cnf \\
      --remove_dead_master_conf --ignore_last_failover \\
      >/var/log/mha/myCluster/manager.stdout 2>&1 &
  '
"

sleep 3
vagrant ssh mgmt -c "sudo masterha_check_status --conf=/etc/mha/myCluster.cnf"
# Mong đợi: "myCluster (pid:NNN) is running(0:PING_OK), master:192.168.10.12"
```

Sau B8: cluster topology mới = **node2 (master, VIP) ← node1 (replica), node3 (replica)**. MHA đang giám sát từ mgmt.

---

## B9 · Rollback (OPTIONAL)

🖥️ **Where**: HOST

### B9.1 — Soft rollback: stop manager, xoá MHA artifacts, giữ MySQL

```bash
# 1) Stop manager trên mgmt
vagrant ssh mgmt -c "
  sudo pkill -f 'masterha_manager --conf=/etc/mha/myCluster.cnf' 2>/dev/null || true
  sudo rm -rf /etc/mha /var/log/mha /var/lib/mha
  # Optional: gỡ package
  sudo dpkg --purge mha4mysql-manager mha4mysql-node 2>/dev/null || true
"

# 2) Trên DB nodes: gỡ package + xoá user mha
for N in node1 node2 node3; do
  vagrant ssh $N -c "
    sudo dpkg --purge mha4mysql-node 2>/dev/null || true
    # Restore relay_log_purge=1 (mặc định MySQL)
    mysql -uroot -p'ChangeMe!Root#2026' -e 'SET GLOBAL relay_log_purge=1; RESET PERSIST relay_log_purge;' 2>/dev/null || true
  "
done

# 3) Drop user mha trên master hiện thời (đang là node2)
vagrant ssh node2 -c "mysql -uroot -p'ChangeMe!Root#2026' -e \"DROP USER IF EXISTS 'mha'@'%'; FLUSH PRIVILEGES;\""

# 4) Gỡ VIP trên master hiện thời
vagrant ssh node2 -c "sudo ip addr del 192.168.10.100/24 dev eth1 2>/dev/null || true"
```

### B9.2 — Hard rollback: destroy VMs

```bash
cd vagrant
vagrant destroy -f
```

---

## Phụ lục A — Trouble-shooting nhanh

### A1. `relay_log_purge=1` (precheck fail ở B0/B1)

**Triệu chứng**: `SELECT @@relay_log_purge;` = 1 trên replica.

**Fix**:

```bash
for N in node2 node3; do
  vagrant ssh $N -c "mysql -uroot -p'ChangeMe!Root#2026' -e 'SET PERSIST relay_log_purge=0; SET GLOBAL relay_log_purge=0;'"
done
```

`SET PERSIST` ghi vào `mysqld-auto.cnf` → giữ sau restart, không cần sửa `my.cnf`.

### A2. `super_read_only=ON` khi CREATE USER trên replica (B3.3)

**Triệu chứng**: `ERROR 1290 (HY000): The MySQL server is running with the --super-read-only option`.

**Fix**: tạo user CHỈ trên master; user sẽ replicate sang replicas qua statement-based / GTID. Đừng `SET GLOBAL super_read_only=0` thủ công — sẽ phá invariant của replica.

### A3. `mha4mysql-manager : Depends: mha4mysql-node` (B4.1)

**Triệu chứng**: `dpkg -i /tmp/mha-mgr.deb` báo "depends on mha4mysql-node; however: Package mha4mysql-node is not installed."

**Fix**: cài node trước trên mgmt:

```bash
vagrant ssh mgmt -c "sudo dpkg -i /tmp/mha-node.deb || sudo apt-get install -f -y; sudo dpkg -i /tmp/mha-mgr.deb"
```

### A4. `masterha_check_repl` báo `Redundant argument in sprintf at NodeUtil.pm line 201` (B4.5)

**Triệu chứng** (MySQL 8.0.X + MHA 0.58):

```
[error] Error happened on checking configurations. Redundant argument in sprintf at /usr/share/perl5/MHA/NodeUtil.pm line 201.
[error] Error happened on monitoring servers.
MySQL Replication Health is NOT OK!
```

**Nguyên nhân**: regex `m/(\d+)/g` global match TẤT CẢ số → "Ver 8.0.46 for Linux on x86_64" → `[8, 0, 46, 86, 64]` → `sprintf('%03d%03d%03d', ...)` thừa 2 args.

**Fix**: patch theo B3.2/B4.2 (chỉ lấy 3 phần tử đầu).

### A5. `masterha_check_ssh` exit 255 dù tests passed (B4.5)

**Triệu chứng**:

```
... All SSH connection tests passed successfully.
Use of uninitialized value in exit at /usr/bin/masterha_check_ssh line 44.
$?  = 255
```

**Nguyên nhân**: `exit MHA::SSHCheck::main(@ARGV)` — `main()` return `undef`. Perl warning, exit code rác.

**Fix script**: đừng dựa exit code; grep `"passed successfully"` trong stdout:

```bash
OUT=$(sudo masterha_check_ssh --conf=/etc/mha/myCluster.cnf 2>&1 || true)
echo "$OUT" | grep -q "All SSH connection tests passed successfully" && echo OK || echo FAIL
```

### A6. `arping: command not found` khi VIP move

**Triệu chứng**: master_ip_failover.sh log "command not found".

**Fix**: cài `iputils-arping` trên TẤT CẢ DB nodes (B3.1). Nếu VIP đã gắn nhưng ARP cache neighbor còn ghi MAC master cũ → ping vẫn fail. arping `-U` gửi gratuitous ARP để force update.

### A7. VIP gắn lên interface NAT (`eth0`) thay vì hostonly (`eth1`)

**Triệu chứng**: `master_ip_failover.sh` hardcode `IFACE="eth0"`, nhưng Vagrant Ubuntu đặt private net trên `eth1`. VIP gắn lên eth0 → host khác không reach.

**Fix**: dùng auto-detect (B4.4):

```bash
IFACE=$(ssh root@${host} "ip -4 -o addr show | awk '\$4 ~ /^192\\.168\\.10\\./{print \$2; exit}'")
```

### A8. Manager tự dừng sau failover, không restart được

**Triệu chứng**: `masterha_check_status` báo `is stopped(2:NOT_RUNNING)`. Restart bằng `masterha_manager` báo:

```
Last failover was done at 2026-05-19 ... . Current time is too early to do failover again.
```

**Fix**: xoá lock file + dùng `--ignore_last_failover`:

```bash
vagrant ssh mgmt -c "
  sudo rm -f /var/lib/mha/myCluster/myCluster.failover.complete
  sudo nohup masterha_manager --conf=/etc/mha/myCluster.cnf \\
    --remove_dead_master_conf --ignore_last_failover \\
    >/var/log/mha/myCluster/manager.stdout 2>&1 &
"
```

### A9. `masterha_check_repl` báo "There is no alive server" hoặc "Got error on MySQL select"

**Nguyên nhân thường gặp**:
- User `mha@%` chưa có trên master → check via `SELECT user,host FROM mysql.user WHERE user='mha';`
- Password sai trong config — kiểm tra `password=` và `repl_password=` trong `/etc/mha/myCluster.cnf`
- Firewall block port 3306 từ mgmt — `vagrant ssh mgmt -c "nc -zv 192.168.10.11 3306"`

### A10. Failover xong nhưng `[server1]` bị xoá khỏi config — `masterha_check_repl` báo "missing server1"

**Nguyên nhân**: `--remove_dead_master_conf` xoá section của master chết.

**Fix**: add lại trước khi restart manager (xem B8.3).

---

## Phụ lục B — Tóm tắt files config

### B.1 `/etc/mha/myCluster.cnf` (trên mgmt)

```ini
[server default]
user=mha
password=ChangeMe!Admin#2026
ssh_user=root
repl_user=repl
repl_password=ChangeMe!Repl#2026
manager_workdir=/var/lib/mha/myCluster
manager_log=/var/log/mha/myCluster/manager.log
remote_workdir=/var/lib/mha
ping_interval=3
master_binlog_dir=/var/lib/mysql
master_ip_failover_script=/etc/mha/master_ip_failover.sh
secondary_check_script=masterha_secondary_check -s 192.168.10.12 -s 192.168.10.13

[server1]
hostname=192.168.10.11
candidate_master=1

[server2]
hostname=192.168.10.12
candidate_master=1

[server3]
hostname=192.168.10.13
no_master=0
```

### B.2 `/etc/mha/master_ip_failover.sh` (trên mgmt, chmod +x)

Xem B4.4 (hook bash detect interface động + arping).

### B.3 `/root/.ssh/config` (trên tất cả 4 hosts)

```
Host *
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null
  LogLevel ERROR
```

### B.4 Files quan trọng trên DB nodes (đã đặt từ Demo 01)

- `/etc/mysql/mysql.conf.d/zz-semisync.cnf` — semi-sync plugin load + enable
- `mysqld-auto.cnf` (do `SET PERSIST relay_log_purge=0` ghi) — chỉ trên node2/3

### B.5 Log files (mgmt)

- `/var/log/mha/myCluster/manager.log` — main log
- `/var/log/mha/myCluster/manager.stdout` — stdout của daemon
- `/var/lib/mha/myCluster/*.failover.complete` — lock failover (xoá khi muốn force re-failover)

---

## Phụ lục C — Mapping bash scripts ↔ manual steps

| Manual step | Script tương đương                              | Mô tả                                  |
|-------------|--------------------------------------------------|----------------------------------------|
| B0          | (tiền đề — Demo 01 phải xong)                   | Async/semi-sync 1M + 2R                |
| B1          | `demo/04-mha/01-precheck.sh`                    | Validate Demo 01 + auto-fix relay_log_purge |
| B2          | `demo/04-mha/02-ssh-trust.sh`                   | Mesh SSH mgmt↔nodes + node↔node       |
| B3          | `demo/04-mha/03-mha-node-install.sh` + `scripts/mha/node-setup.sh` | Cài mha-node, arping, patch NodeUtil, tạo user mha |
| B4          | `demo/04-mha/04-mha-manager-install.sh` + `scripts/mha/manager-setup.sh` | Cài mha-manager, patch, ghi config + hook, start daemon |
| B5          | `demo/04-mha/05-verify.sh`                      | masterha_check_ssh / check_repl / check_status |
| B6          | `demo/04-mha/06-vip-bind.sh`                    | Gắn VIP lên master ban đầu             |
| B7          | `demo/04-mha/07-failover-test.sh`               | Halt master, đo RTO, verify VIP move + slave follow |
| B8          | `demo/04-mha/08-rebuild-old-master.sh`          | Power-on master cũ, CHANGE MASTER, add lại server1, restart manager |
| B9          | `demo/04-mha/09-rollback.sh`                    | Soft/hard rollback                     |

Chạy nhanh end-to-end (B1→B6):

```bash
cd demo/04-mha
bash run-all.sh         # Linux/macOS/WSL/Git Bash
# hoặc
.\run-all.ps1           # Windows PowerShell
```

B7/B8/B9 chạy thủ công vì destructive.


---

!!! info "Nguồn gốc"
    `HA/Mysql/demo/04-mha/MANUAL-SETUP.md`
