---
title: Hướng dẫn setup THỦ CÔNG — Demo 05 Orchestrator (openark/orchestrator)
course: 06-high-availability
source: HA/Mysql/demo/05-orchestrator/MANUAL-SETUP.md
---

# Hướng dẫn setup THỦ CÔNG — Demo 05 Orchestrator (openark/orchestrator)

> Tài liệu này ghi lại **TỪNG CÂU LỆNH** để dựng giải pháp 05 (Orchestrator) mà không cần `run-all.sh` / `run-all.ps1`. Copy-paste theo thứ tự từ trên xuống. Mỗi bước nêu rõ:
> - 🖥️ **Where**: chạy ở đâu (HOST / node1 / node2 / node3 / mgmt)
> - 💻 **Command**: lệnh CLI hoặc SQL
> - 📝 **File**: cấu hình cần ghi (nếu có)
> - ✅ **Verify**: cách kiểm tra step OK
>
> ⚠️ **Tiền đề BẮT BUỘC**: phải có cụm **Async/Semi-sync 1 master + 2 replicas** đang chạy (Demo 01). Orchestrator chỉ là **topology manager** — không tự dựng replication. Nếu chưa có → chạy [Demo 01 MANUAL-SETUP](../01-async-semisync/manual-setup.md) trước.

## 0. Topology & biến môi trường

| Host  | IP              | Vai trò                                                 | RAM   |
|-------|-----------------|---------------------------------------------------------|-------|
| node1 | 192.168.10.11   | MySQL Master (RW) — từ Demo 01                          | 2 GB  |
| node2 | 192.168.10.12   | MySQL Replica (RO) — từ Demo 01                         | 2 GB  |
| node3 | 192.168.10.13   | MySQL Replica (RO) — từ Demo 01                         | 2 GB  |
| mgmt  | 192.168.10.20   | Orchestrator daemon (Go) + MySQL backend (DB `orchestrator`) | 1.5 GB |

Credentials mặc định (xem [scripts/common/env.sh](../../scripts/common/env.sh)):

```
MYSQL_ROOT_PWD = ChangeMe!Root#2026
REPL_USER      = repl                       # user replication, đã có từ Demo 01
REPL_PWD       = ChangeMe!Repl#2026
ADMIN_PWD      = ChangeMe!Admin#2026        # cho user orchestrator@<mgmt> + HTTP basic auth
MGMT_IP        = 192.168.10.20
```

Khác MHA: Orchestrator **KHÔNG** dùng VIP. App connect trực tiếp master (hoặc qua ProxySQL — Demo 07). Orchestrator chỉ làm 3 việc:
1. **Discover** topology định kỳ (default `InstancePollSeconds=5`).
2. **Detect** master fail (multi-mode: I/O lỗi, all replicas mất kết nối, raft consensus).
3. **Recover** = chọn replica có position cao nhất → SET read_only=0 → fix relay chain → gọi Pre/PostFailover hooks.

```
                       ┌─────────────────────────────┐
        Browser ─────▶ │  Web UI :3000 (basic auth)  │
                       │  mgmt 192.168.10.20         │
                       │  Orchestrator (Go daemon)   │
                       └──────────────┬──────────────┘
                                      │ MySQL TCP, SHOW SLAVE HOSTS, probe
       ┌──────────────────────────────┼──────────────────────────────┐
       ▼                              ▼                              ▼
   node1 (master)                node2 (replica)                node3 (replica)
       └──── async/semi-sync replication (Demo 01) ──────┘
```

---

## B0 · Prerequisites — Verify Demo 01 đang chạy

🖥️ **Where**: HOST

Trước khi cài Orchestrator, **phải** xác nhận:

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
# Mong đợi: Source_Host=node1 (hoặc IP), IO/SQL Running=Yes

# 4) report_host phải set (orchestrator dùng để parse SHOW SLAVE HOSTS)
for N in node1 node2 node3; do
  vagrant ssh $N -c "mysql -uroot -p'ChangeMe!Root#2026' -N -e 'SELECT @@report_host;'"
done
# Mong đợi: 192.168.10.11 / 12 / 13 (KHÔNG được empty)
```

> **Tại sao cần `report_host`**: Orchestrator gọi `SHOW SLAVE HOSTS` trên master → trả về danh sách replica với hostname từ `report_host`. Nếu `report_host` empty, orchestrator lấy hostname Linux (có thể là `node1` hoặc bất kỳ) → không khớp với cluster IPs → discover sai.

---

## B1 · Precheck (tương đương `01-precheck.sh`)

🖥️ **Where**: HOST

Script `01-precheck.sh` đóng gói các check ở B0. Manual version:

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

# 5) report_host
for N in node1 node2 node3; do
  vagrant ssh $N -c "mysql -uroot -p'ChangeMe!Root#2026' -N -B -e 'SELECT @@report_host;'"
done
```

✅ **Pass criteria**: tất cả check trả về kết quả mong đợi. Nếu fail → fix Demo 01 trước.

---

## B2 · Cài Orchestrator + backend + grant user

⚠️ Bước B2 có **5 sub-bug đã fix** trong scripts — manual cũng phải đi qua tất cả 5 (xem [Phụ lục A](#phụ-lục-a--trouble-shooting-nhanh)).

### B2.1 — Đảm bảo SSH trust mgmt ↔ nodes (cần cho GRANT qua SSH)

🖥️ **Where**: HOST

Orchestrator service chỉ cần MySQL TCP tới các nodes. Nhưng **setup user** thì khác: trên DB nodes, `root` chỉ accept `@'localhost'` → không thể `mysql -h<IP> -uroot` từ mgmt. Workaround: SSH vào từng node và chạy mysql localhost trên đó.

Vagrant provisioner `ssh-trust` cài cluster keypair (`vagrant/provision/cluster_id_rsa`) lên `/root/.ssh/id_rsa` của TẤT CẢ 4 VMs:

```bash
# Sinh keypair nếu chưa có (đã commit-gitignored, sinh local)
if [[ ! -f vagrant/provision/cluster_id_rsa ]]; then
  bash vagrant/provision/generate-ssh-key.sh
fi

# Đẩy keypair lên 4 VMs
cd vagrant
vagrant provision --provision-with ssh-trust
```

✅ **Verify**:

```bash
vagrant ssh mgmt -c "sudo ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no root@192.168.10.11 'hostname && whoami'"
# Mong đợi: node1 / root
```

### B2.2 — Cài MySQL trên mgmt (Orchestrator backend store)

🖥️ **Where**: HOST → mgmt

> **CRITICAL FIX**: Vagrantfile chỉ register provisioner `install-mysql` cho VM role=db. `mgmt` role=mgmt **KHÔNG** có provisioner này → `vagrant provision mgmt --provision-with install-mysql` là no-op silent. Phải gọi script trực tiếp.

```bash
vagrant ssh mgmt -c "sudo bash /vagrant/scripts/common/01-install-mysql.sh"
```

Script này:
- Cài `mysql-server` 8.0 community + shell + router (Ubuntu 22.04 jammy)
- Set root password = `ChangeMe!Root#2026`
- Bind 0.0.0.0:3306, GTID ON, log-bin ON, binlog ROW
- `server_id` = random (10-1010 cho mgmt — không đụng 1/2/3 của DB nodes)
- `report_host` = IP đầu tiên của hostname (mgmt: `192.168.10.20`)

✅ **Verify**:

```bash
vagrant ssh mgmt -c "
  command -v mysql
  sudo systemctl is-active mysql
  mysql -uroot -p'ChangeMe!Root#2026' -e 'SELECT VERSION(), @@server_id;'
"
# Mong đợi: /usr/bin/mysql; active; 8.0.46 + server_id random
```

### B2.3 — Tải Orchestrator binary + orchestrator-client (.deb)

🖥️ **Where**: HOST → mgmt

```bash
vagrant ssh mgmt -c "
  sudo bash -c '
    wget -qO /tmp/orc.deb     https://github.com/openark/orchestrator/releases/download/v3.2.6/orchestrator_3.2.6_amd64.deb
    wget -qO /tmp/orc-cli.deb https://github.com/openark/orchestrator/releases/download/v3.2.6/orchestrator-client_3.2.6_amd64.deb
    # orchestrator depends on jq — apt-get install -f -y resolve khi dpkg fail
    dpkg -i /tmp/orc.deb || apt-get install -f -y
    dpkg -i /tmp/orc-cli.deb || true
  '
"
```

✅ **Verify**:

```bash
vagrant ssh mgmt -c "dpkg -l | grep -E 'orchestrator|jq' | head -5"
# Mong đợi: orchestrator 1:3.2.6, orchestrator-client 1:3.2.6, jq, libjq1
```

### B2.4 — Tạo backend DB `orchestrator` trên mgmt MySQL

🖥️ **Where**: HOST → mgmt

```bash
vagrant ssh mgmt -c "
  mysql -uroot -p'ChangeMe!Root#2026' -h127.0.0.1 <<'SQL'
CREATE DATABASE IF NOT EXISTS orchestrator;
CREATE USER IF NOT EXISTS 'orchestrator'@'127.0.0.1' IDENTIFIED BY 'ChangeMe!Admin#2026';
GRANT ALL ON orchestrator.* TO 'orchestrator'@'127.0.0.1';
FLUSH PRIVILEGES;
SQL
"
```

### B2.5 — Grant user `orchestrator@<mgmt_ip>` trên DB nodes (CHỈ trên MASTER)

🖥️ **Where**: HOST → node1 (master)

> **CRITICAL FIX**: replicas có `super_read_only=ON` → CREATE USER trên replica báo `ERROR 1290 (HY000): The MySQL server is running with the --super-read-only option`. **Chỉ chạy trên master**; user sẽ replicate sang replicas qua statement-based / GTID.

```bash
vagrant ssh node1 -c "mysql -uroot -p'ChangeMe!Root#2026' <<'SQL'
CREATE USER IF NOT EXISTS 'orchestrator'@'192.168.10.20' IDENTIFIED BY 'ChangeMe!Admin#2026';
ALTER USER 'orchestrator'@'192.168.10.20' IDENTIFIED BY 'ChangeMe!Admin#2026';
GRANT SUPER, PROCESS, REPLICATION SLAVE, RELOAD ON *.* TO 'orchestrator'@'192.168.10.20';
GRANT SELECT ON mysql.slave_master_info TO 'orchestrator'@'192.168.10.20';
CREATE DATABASE IF NOT EXISTS meta;
GRANT SELECT, INSERT, UPDATE, DELETE ON meta.* TO 'orchestrator'@'192.168.10.20';
FLUSH PRIVILEGES;
SQL
"

# Đợi 3s rồi verify user đã replicate sang replicas
sleep 3
for IP in 192.168.10.12 192.168.10.13; do
  echo -n "[$IP] orchestrator@mgmt count="
  vagrant ssh mgmt -c "sudo ssh -o ConnectTimeout=5 root@${IP} \"
    MYSQL_PWD='ChangeMe!Root#2026' mysql -uroot -N -B -e \\\"
      SELECT COUNT(*) FROM mysql.user WHERE user='orchestrator' AND host='192.168.10.20';\\\"\"" | tr -d '\r'
done
# Mong đợi: count=1 trên cả 2 replica
```

**Giải thích privileges**:
- `SUPER, RELOAD` → orchestrator điều khiển master/replica (SET GLOBAL, RESET REPLICA, FLUSH).
- `PROCESS` → đọc `INFORMATION_SCHEMA.PROCESSLIST`.
- `REPLICATION SLAVE` → đọc binlog metadata (cần cho `SHOW SLAVE HOSTS`).
- `SELECT mysql.slave_master_info` → đọc replication config (host, user, pos).
- `meta.*` (CRUD) → orchestrator dùng schema `meta` để pseudo-GTID + heartbeat (optional).

### B2.6 — Ghi `/etc/orchestrator.conf.json` trên mgmt

🖥️ **Where**: HOST → mgmt

📝 **File**: `/etc/orchestrator.conf.json`

```bash
vagrant ssh mgmt -c "
  sudo bash -c 'cat >/etc/orchestrator.conf.json <<EOF
{
  \"MySQLTopologyUser\": \"orchestrator\",
  \"MySQLTopologyPassword\": \"ChangeMe!Admin#2026\",
  \"MySQLOrchestratorHost\": \"127.0.0.1\",
  \"MySQLOrchestratorPort\": 3306,
  \"MySQLOrchestratorDatabase\": \"orchestrator\",
  \"MySQLOrchestratorUser\": \"orchestrator\",
  \"MySQLOrchestratorPassword\": \"ChangeMe!Admin#2026\",

  \"DefaultInstancePort\": 3306,
  \"DiscoverByShowSlaveHosts\": true,
  \"InstancePollSeconds\": 5,
  \"HostnameResolveMethod\": \"none\",
  \"MySQLHostnameResolveMethod\": \"@@report_host\",

  \"RecoverMasterClusterFilters\": [\"*\"],
  \"RecoverIntermediateMasterClusterFilters\": [\"*\"],
  \"RecoveryPeriodBlockSeconds\": 300,

  \"FailMasterPromotionOnLagMinutes\": 0,
  \"ApplyMySQLPromotionAfterMasterFailover\": true,
  \"MasterFailoverDetachReplicaMasterHost\": true,
  \"PreFailoverProcesses\": [\"echo PreFailover: {failureType} on {failureCluster} >> /var/log/orchestrator-recovery.log\"],
  \"PostFailoverProcesses\": [\"echo PostFailover: {failureType} -> {successorHost} >> /var/log/orchestrator-recovery.log\"],

  \"HTTPAuthUser\": \"admin\",
  \"HTTPAuthPassword\": \"ChangeMe!Admin#2026\",
  \"AuthenticationMethod\": \"basic\",
  \"ListenAddress\": \":3000\"
}
EOF'
"
```

**Giải thích config quan trọng** (3 fix critical đã embed):

| Key                                       | Giá trị             | Tại sao                                                                                                                                                            |
|-------------------------------------------|---------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `HostnameResolveMethod`                   | `"none"`            | **FIX**: nếu để `"default"`, orchestrator reverse-resolve IP → hostname (`192.168.10.11` → `node1`) qua `/etc/hosts`. Sau đó query bằng IP báo `clusterHint=192.168.10.11:3306 ... Unable to determine cluster name`. Để `none` giữ IP làm instance key. |
| `MySQLHostnameResolveMethod`              | `"@@report_host"`   | Lấy IP từ `@@report_host` của mỗi node (đã set = IP cluster trong install-mysql.sh) làm canonical hostname.                                                          |
| `FailMasterPromotionOnLagMinutes`         | `0`                 | **FIX**: nếu set > 0 mà không có `ReplicationLagQuery` → service exit với `FATAL nonzero FailMasterPromotionOnLagMinutes requires ReplicationLagQuery to be set`. Set 0 disable check.                  |
| `ApplyMySQLPromotionAfterMasterFailover`  | `true`              | Sau promote: tự `SET read_only=0; STOP REPLICA; RESET REPLICA ALL` trên master mới.                                                                                |
| `MasterFailoverDetachReplicaMasterHost`   | `true`              | Sau failover: detach master cũ (bằng cách set `Master_Host` invalid) → ngăn nó tự re-attach khi power-on.                                                          |
| `RecoveryPeriodBlockSeconds`              | `300`               | Anti-flapping: trong 5 phút sau 1 recovery, **không** recovery thêm. Demo B7 override qua API.                                                                     |
| `DiscoverByShowSlaveHosts`                | `true`              | Auto-discover replicas qua `SHOW SLAVE HOSTS` trên master (cần `report_host` set).                                                                                 |
| `InstancePollSeconds`                     | `5`                 | Probe interval. Càng nhỏ detection càng nhanh nhưng tải MySQL tăng.                                                                                                |
| `HTTPAuthUser` + `HTTPAuthPassword`       | basic auth          | Web UI + API yêu cầu basic auth — `admin` / `ChangeMe!Admin#2026`.                                                                                                  |

### B2.7 — Setup `ORCHESTRATOR_API` cho orchestrator-client (basic auth)

🖥️ **Where**: HOST → mgmt

📝 **File**: `/etc/profile.d/orchestrator-client.sh`

> **FIX**: orchestrator-client gọi `http://localhost:3000/api/...` mặc định. Khi `AuthenticationMethod=basic`, API trả 401. Phải nhúng credentials vào URL.
> Mật khẩu có `#` (gen-delim trong URI) → phải URL-encode → `ChangeMe!Admin#2026` → `ChangeMe!Admin%232026`.

```bash
vagrant ssh mgmt -c "
  sudo tee /etc/profile.d/orchestrator-client.sh >/dev/null <<'EOF'
export ORCHESTRATOR_API=\"http://admin:ChangeMe!Admin%232026@127.0.0.1:3000/api\"
EOF
  sudo chmod 644 /etc/profile.d/orchestrator-client.sh
"
```

✅ **Verify**: từ session interactive mới sẽ tự source. Hoặc test ngay:

```bash
vagrant ssh mgmt -c "source /etc/profile.d/orchestrator-client.sh; echo \$ORCHESTRATOR_API"
# Mong đợi: http://admin:ChangeMe!Admin%232026@127.0.0.1:3000/api
```

### B2.8 — Start orchestrator service

🖥️ **Where**: HOST → mgmt

```bash
vagrant ssh mgmt -c "sudo systemctl enable --now orchestrator"

# Đợi API ready (≤30s)
for i in $(seq 1 30); do
  RESP=$(vagrant ssh mgmt -c "curl -fsS -u admin:'ChangeMe!Admin#2026' http://127.0.0.1:3000/api/status 2>/dev/null" | tr -d '\r')
  if echo "$RESP" | grep -q '"Code":"OK"'; then
    echo "API ready sau ${i}s"; break
  fi
  sleep 1
done
```

✅ **Verify**:

```bash
vagrant ssh mgmt -c "
  sudo systemctl is-active orchestrator
  sudo ss -tlnp 2>/dev/null | grep ':3000'
  curl -fsS -u admin:'ChangeMe!Admin#2026' http://127.0.0.1:3000/api/health 2>/dev/null
"
# Mong đợi: active; LISTEN :3000 orchestrator; JSON {"Code":"OK","Message":"Application node is healthy",...}
```

Mở browser host → http://192.168.10.20:3000 (admin / `ChangeMe!Admin#2026`) — Web UI hiện cluster (sau B3).

---

## B3 · Discover topology (tương đương `03-discover-topology.sh`)

🖥️ **Where**: HOST → mgmt

Orchestrator chưa biết cluster cho đến khi mình `discover -i <hint>`. Hint = 1 IP của 1 node bất kỳ.

```bash
vagrant ssh mgmt -c "
  source /etc/profile.d/orchestrator-client.sh

  # 1) Discover từ master (sẽ auto-discover replicas qua SHOW SLAVE HOSTS)
  orchestrator-client -c discover -i 192.168.10.11:3306

  # 2) Force discover từng replica để pickup ngay (đỡ phải đợi InstancePollSeconds)
  orchestrator-client -c discover -i 192.168.10.12:3306 || true
  orchestrator-client -c discover -i 192.168.10.13:3306 || true

  sleep 5
  orchestrator-client -c topology -i 192.168.10.11:3306
"
```

✅ **Verify output**:

```
192.168.10.11:3306   [0s,ok,8.0.46,rw,ROW,>>,GTID]
+ 192.168.10.12:3306 [0s,ok,8.0.46,ro,ROW,>>,GTID]
+ 192.168.10.13:3306 [0s,ok,8.0.46,ro,ROW,>>,GTID]
```

Flags trong `[ ... ]`:
- `0s` — replication lag
- `ok` — last seen probe OK
- `rw` / `ro` — read_only flag
- `ROW` — binlog_format
- `>>` — log_slave_updates ON
- `GTID` — GTID mode ON

---

## B4 · Verify (tương đương `04-verify.sh`)

🖥️ **Where**: HOST

```bash
# 1) Service active
vagrant ssh mgmt -c "sudo systemctl is-active orchestrator"   # active

# 2) Port 3000 listening
vagrant ssh mgmt -c "sudo ss -tlnp 2>/dev/null | grep ':3000 '"

# 3) /api/health
vagrant ssh mgmt -c "curl -fsS -u admin:'ChangeMe!Admin#2026' http://127.0.0.1:3000/api/health 2>/dev/null | head -c 200"
# Mong đợi: {"Code":"OK","Message":"Application node is healthy",...}

# 4) Topology — 3 nodes
vagrant ssh mgmt -c "orchestrator-client -c topology -i 192.168.10.11:3306"

# 5) which-cluster-master = node1
vagrant ssh mgmt -c "orchestrator-client -c which-cluster-master -i 192.168.10.11:3306"
# Mong đợi: 192.168.10.11:3306
```

> **CRITICAL FIX**: dùng `which-cluster-master` (master ghi-được của cluster), **KHÔNG** dùng `which-master -i nodeN`. `which-master` trả về **parent** của nodeN trong tree — nếu nodeN là master, kết quả = `:0` (no parent) → script báo fail nhầm.

```bash
# 6) replication-analysis sạch (no DeadMaster)
vagrant ssh mgmt -c "orchestrator-client -c replication-analysis"
# Mong đợi: empty (không có DeadMaster/UnreachableMaster lines)
```

✅ **Pass criteria**: 6/6 checks OK.

---

## B5 · Smoke test (tương đương `05-smoke-test.sh`)

🖥️ **Where**: HOST

Orchestrator KHÔNG phải proxy → app vẫn connect trực tiếp master IP. Smoke test mô phỏng:
1. Insert 200 rows vào master (node1).
2. Đo lag để replicas catch-up.

```bash
# 0) Tìm master từ orchestrator
MASTER=$(vagrant ssh mgmt -c "orchestrator-client -c which-cluster-master -i 192.168.10.11:3306 2>/dev/null" | tr -d '\r' | tail -n1)
echo "Master = ${MASTER}"   # 192.168.10.11:3306

# 1) Setup schema + bulk insert
vagrant ssh node1 -c "mysql -uroot -p'ChangeMe!Root#2026' -e \"
  DROP DATABASE IF EXISTS smoke_db;
  CREATE DATABASE smoke_db CHARACTER SET utf8mb4;
  CREATE TABLE smoke_db.t(id INT PRIMARY KEY AUTO_INCREMENT, val VARCHAR(64), ts DATETIME(6) DEFAULT CURRENT_TIMESTAMP(6)) ENGINE=InnoDB;\""

ROWS=200
INSERT_START=$(date +%s.%N)
SQL="USE smoke_db;"; for i in $(seq 1 $ROWS); do SQL+="INSERT INTO t(val) VALUES('row-$i');"; done
printf '%s' "$SQL" | vagrant ssh node1 -c "mysql -uroot -p'ChangeMe!Root#2026' 2>/dev/null"
INSERT_END=$(date +%s.%N)
echo "insert ${ROWS} rows: $(awk -v s=$INSERT_START -v e=$INSERT_END 'BEGIN{printf "%.3fs", e-s}')"

# 2) Đợi từng node thấy 200 rows
for N in node1 node2 node3; do
  START=$(date +%s.%N)
  for i in $(seq 1 300); do
    CNT=$(vagrant ssh $N -c "mysql -uroot -p'ChangeMe!Root#2026' -N -B -e 'SELECT COUNT(*) FROM smoke_db.t;' 2>/dev/null" | tr -d '\r')
    [[ "$CNT" -ge "$ROWS" ]] && break
    sleep 0.1
  done
  END=$(date +%s.%N)
  echo "[$N] thấy $CNT rows sau $(awk -v s=$START -v e=$END 'BEGIN{printf "%.3fs", e-s}')"
done
```

✅ **Pass criteria**: cả 3 node đạt `$ROWS` rows trong < 30s. Trên lab Vagrant typical: insert ~7s + replication catch-up ~7s.

---

## B6 · Graceful failover (planned switchover)

🖥️ **Where**: HOST

`graceful-master-takeover` = planned promote, **không** halt VM, downtime ~5s. Quy trình orchestrator:
1. Lock master cũ (`FLUSH TABLES WITH READ LOCK` hoặc `SET GLOBAL super_read_only=1`).
2. Đợi candidate replica catch-up (apply hết binlog từ master cũ).
3. Promote candidate: `STOP REPLICA; RESET REPLICA ALL; SET read_only=0`.
4. Re-attach replica còn lại vào master mới: `CHANGE REPLICATION SOURCE`.
5. Detach master cũ (giữ `read_only=1`, không follow ai — chờ admin xử lý).

```bash
NEW_MASTER_IP=192.168.10.12   # promote node2

# Current master
OLD_MASTER=$(vagrant ssh mgmt -c "orchestrator-client -c which-cluster-master -i 192.168.10.11:3306 2>/dev/null" | tr -d '\r' | tail -n1)
echo "Old master = ${OLD_MASTER}"

# Graceful takeover
START=$(date +%s)
vagrant ssh mgmt -c "orchestrator-client -c graceful-master-takeover -i ${OLD_MASTER} -d ${NEW_MASTER_IP}:3306"
DUR=$(( $(date +%s) - START ))
echo "graceful-master-takeover xong sau ${DUR}s"   # typical 5-10s
```

> **CRITICAL FIX**: dùng `-i <clusterHint>` thay vì `-alias myCluster`. Tham số `-alias` cần `DetectClusterAliasQuery` config trong orchestrator để map cluster_name → alias. Mặc định alias không set → báo `Unable to determine cluster name. clusterHint=myCluster`. `-i` accept bất kỳ instance của cluster làm hint.

✅ **Verify**:

```bash
sleep 3
# 1) Master mới = node2
vagrant ssh mgmt -c "orchestrator-client -c which-cluster-master -i ${NEW_MASTER_IP}:3306"
# Mong đợi: 192.168.10.12:3306

# 2) Test INSERT trên master mới
vagrant ssh node2 -c "mysql -uroot -p'ChangeMe!Root#2026' -e \"
  USE smoke_db;
  INSERT INTO t(val) VALUES('post-graceful-switchover');
  SELECT @@hostname AS now_master, @@read_only;\""
# Mong đợi: now_master=node2, @@read_only=0

# 3) Topology mới
vagrant ssh mgmt -c "orchestrator-client -c topology -i ${NEW_MASTER_IP}:3306"
```

Expect:
```
192.168.10.12:3306   [0s,ok,rw,...]               ← master mới
- 192.168.10.11:3306 [null,nonreplicating,ro,...,downtimed]   ← master cũ, detached
+ 192.168.10.13:3306 [0s,ok,ro,...]               ← replica đã re-attach
```

**Rollback master về node1** (tuỳ chọn):

```bash
vagrant ssh mgmt -c "orchestrator-client -c graceful-master-takeover -i 192.168.10.12:3306 -d 192.168.10.11:3306"
```

---

## B7 · Force failover test (DESTRUCTIVE)

🖥️ **Where**: HOST

Mô phỏng master chết bằng `vagrant halt --force`. Orchestrator detect (multi-mode: TCP fail + replicas lost) → promote replica có position cao nhất.

### B7.1 — Tìm master hiện thời

```bash
MASTER=$(vagrant ssh mgmt -c "orchestrator-client -c which-cluster-master -i 192.168.10.11:3306 2>/dev/null" | tr -d '\r' | tail -n1)
case "${MASTER}" in
  *192.168.10.11*) MASTER_HOST=node1; MASTER_IP=192.168.10.11 ;;
  *192.168.10.12*) MASTER_HOST=node2; MASTER_IP=192.168.10.12 ;;
  *192.168.10.13*) MASTER_HOST=node3; MASTER_IP=192.168.10.13 ;;
esac
echo "Master = ${MASTER_HOST} (${MASTER_IP})"
```

### B7.2 — Insert sentinel vào master

```bash
SENT="orc-failover-$(date +%s)"
vagrant ssh "${MASTER_HOST}" -c "mysql -uroot -p'ChangeMe!Root#2026' -e \"
  CREATE DATABASE IF NOT EXISTS smoke_db;
  CREATE TABLE IF NOT EXISTS smoke_db.t(id INT PRIMARY KEY AUTO_INCREMENT, val VARCHAR(64), ts DATETIME(6) DEFAULT CURRENT_TIMESTAMP(6));
  INSERT INTO smoke_db.t(val) VALUES('${SENT}');\""
```

### B7.3 — Bật global recoveries

Default `RecoveryPeriodBlockSeconds=300` chỉ block sau 1 recovery. Để chắc chắn không bị block từ recovery cũ:

```bash
vagrant ssh mgmt -c "
  curl -fsS -u admin:'ChangeMe!Admin#2026' -X POST 'http://127.0.0.1:3000/api/disable-global-recoveries' 2>/dev/null || true
  curl -fsS -u admin:'ChangeMe!Admin#2026' 'http://127.0.0.1:3000/api/enable-global-recoveries' 2>/dev/null
  echo
"
```

### B7.4 — Halt master

```bash
HALT_TS=$(date +%s)
vagrant halt --force "${MASTER_HOST}"
echo "HALT_TS=${HALT_TS}"
```

### B7.5 — Poll detection + promote

```bash
NEW_MASTER_IP=""
for i in $(seq 1 60); do
  # Query which-cluster-master từ 1 replica còn sống
  for ALIVE in node1 node2 node3; do
    [[ "$ALIVE" == "${MASTER_HOST}" ]] && continue
    case "$ALIVE" in
      node1) ALIVE_IP=192.168.10.11 ;;
      node2) ALIVE_IP=192.168.10.12 ;;
      node3) ALIVE_IP=192.168.10.13 ;;
    esac
    CUR_M=$(vagrant ssh mgmt -c "orchestrator-client -c which-cluster-master -i ${ALIVE_IP}:3306 2>/dev/null" | tr -d '\r' | tail -n1 || true)
    if [[ -n "${CUR_M}" && "${CUR_M}" != *"${MASTER_IP}"* ]]; then
      NEW_MASTER_IP=$(echo "${CUR_M}" | grep -oE '[0-9.]+:[0-9]+' | head -1 | cut -d: -f1)
      if [[ -n "${NEW_MASTER_IP}" && "${NEW_MASTER_IP}" != "${MASTER_IP}" ]]; then
        PROMOTE_RTO=$(( $(date +%s) - HALT_TS ))
        echo "NEW MASTER = ${NEW_MASTER_IP} (qua ${ALIVE}) sau ${PROMOTE_RTO}s"
        break 2
      fi
    fi
  done
  [[ $((i % 5)) -eq 0 ]] && echo "waiting... ${i}*2s"
  sleep 2
done
```

### B7.6 — Verify master mới

```bash
case "${NEW_MASTER_IP}" in
  192.168.10.11) NEW_MASTER_HOST=node1 ;;
  192.168.10.12) NEW_MASTER_HOST=node2 ;;
  192.168.10.13) NEW_MASTER_HOST=node3 ;;
esac

# 1) Replica còn lại đã follow master mới?
for N in node1 node2 node3; do
  [[ "$N" == "${MASTER_HOST}" || "$N" == "${NEW_MASTER_HOST}" ]] && continue
  SRC=$(vagrant ssh "$N" -c "mysql -uroot -p'ChangeMe!Root#2026' -e 'SHOW REPLICA STATUS\G' 2>/dev/null" | awk -F': ' '/Source_Host/{print $2}' | tr -d ' \r' | head -1)
  echo "[$N] Source_Host = ${SRC}"
done
# Mong đợi: Source_Host = ${NEW_MASTER_IP}

# 2) INSERT vào master mới
WRITE_RTO=""
for i in $(seq 1 30); do
  if vagrant ssh "${NEW_MASTER_HOST}" -c "mysql -uroot -p'ChangeMe!Root#2026' -e \"USE smoke_db; INSERT INTO t(val) VALUES('post-force-failover');\" 2>/dev/null" >/dev/null; then
    WRITE_RTO=$(( $(date +%s) - HALT_TS ))
    echo "INSERT OK sau ${WRITE_RTO}s"
    break
  fi
  sleep 1
done
```

### B7.7 — Audit recovery (orchestrator log của failover)

```bash
vagrant ssh mgmt -c "orchestrator-client -c audit-recovery 2>&1 | tail -20"
# Mong đợi: 1 entry IsSuccessful=true RecoveryName=Cluster: <ip>:3306; ...
```

✅ **Pass criteria**:
- Có master mới ≠ master cũ
- Replica còn lại follow master mới (IO/SQL Running)
- INSERT vào master mới thành công
- Demo này observed: **PROMOTE_RTO ≈ 263s, WRITE_RTO ≈ 276s** (chậm vì poll interval 2s + multi-mode detection cần verify từ nhiều nguồn). Production thường < 30s với tuned config (giảm `InstancePollSeconds`, dùng raft 3-node để consensus nhanh hơn).

---

## B8 · Rebuild old master thành replica (sau B7)

🖥️ **Where**: HOST

Sau force failover, master cũ vẫn halted. Restart → tự follow master mới qua GTID (auto position).

### B8.1 — Power-on master cũ

```bash
vagrant up "${MASTER_HOST}"

# Đợi MySQL ready (≤120s)
for i in $(seq 1 60); do
  if vagrant ssh "${MASTER_HOST}" -c "mysqladmin -uroot -p'ChangeMe!Root#2026' ping 2>/dev/null" | grep -q alive; then
    echo "MySQL ${MASTER_HOST} ready (${i}*2s)"; break
  fi
  sleep 2
done
```

### B8.2 — Configure CHANGE REPLICATION SOURCE → master mới

⚠️ Sau failover, orchestrator với `MasterFailoverDetachReplicaMasterHost=true` đã "detach" master cũ (set invalid SOURCE_HOST). Khi power-on, replica thread không start. Phải tự CHANGE REPLICATION SOURCE.

```bash
vagrant ssh "${MASTER_HOST}" -c "mysql -uroot -p'ChangeMe!Root#2026' <<SQL
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

sleep 5
vagrant ssh "${MASTER_HOST}" -c "mysql -uroot -p'ChangeMe!Root#2026' -e 'SHOW REPLICA STATUS\G'" | egrep "Source_Host|Replica_IO|Replica_SQL|Seconds_Behind|Last_Error"
# Mong đợi: Source_Host=${NEW_MASTER_IP}, IO=Yes, SQL=Yes, Seconds_Behind=0, Last_Error=empty
```

### B8.3 — Force orchestrator re-discover

Orchestrator có thể vẫn cache trạng thái "dead". Force discover lại:

```bash
vagrant ssh mgmt -c "orchestrator-client -c discover -i ${MASTER_IP}:3306"
sleep 5
vagrant ssh mgmt -c "orchestrator-client -c topology -i ${NEW_MASTER_IP}:3306"
# Mong đợi: 3 nodes, master mới rw, 2 còn lại ro - không còn 'downtimed' / 'nonreplicating'
```

Nếu master cũ vẫn `downtimed`, end downtime:

```bash
vagrant ssh mgmt -c "orchestrator-client -c end-downtime -i ${MASTER_IP}:3306"
```

---

## B9 · Rollback (OPTIONAL)

🖥️ **Where**: HOST

### B9.1 — Soft rollback: stop daemon + uninstall orchestrator (giữ MySQL + replication)

```bash
vagrant ssh mgmt -c "
  sudo bash -c '
    systemctl stop orchestrator 2>/dev/null || true
    systemctl disable orchestrator 2>/dev/null || true
    dpkg -P orchestrator orchestrator-client 2>/dev/null || true
    rm -rf /etc/orchestrator.conf.json /var/lib/orchestrator
    rm -f /etc/profile.d/orchestrator-client.sh
    mysql -uroot -p\"ChangeMe!Root#2026\" -e \"DROP DATABASE IF EXISTS orchestrator;\" 2>/dev/null || true
  '
"

# Drop user 'orchestrator'@'192.168.10.20' trên master hiện thời (sẽ replicate sang replicas)
CURRENT_MASTER_HOST=node1   # đổi nếu master đã failover sang node khác
vagrant ssh ${CURRENT_MASTER_HOST} -c "mysql -uroot -p'ChangeMe!Root#2026' -e \"
  DROP USER IF EXISTS 'orchestrator'@'192.168.10.20';
  FLUSH PRIVILEGES;\""
```

### B9.2 — Hard rollback: destroy VMs

```bash
cd vagrant
vagrant destroy -f
```

---

## Phụ lục A — Trouble-shooting nhanh

### A1. `mysql: command not found` khi cài backend (B2.2)

**Triệu chứng**: `02-orchestrator-install.sh` log
```
/vagrant/scripts/orchestrator/../common/env.sh: line 45: mysql: command not found
```

**Nguyên nhân**: Vagrantfile chỉ register provisioner `install-mysql` cho VM `role=db`. Trên `mgmt` (role=mgmt) provisioner KHÔNG tồn tại → `vagrant provision mgmt --provision-with install-mysql` là **no-op silent**.

**Fix**: gọi script install trực tiếp qua `vagrant ssh`:

```bash
vagrant ssh mgmt -c "sudo bash /vagrant/scripts/common/01-install-mysql.sh"
```

(Đã fix trong [demo/05-orchestrator/02-orchestrator-install.sh:30-43](02-orchestrator-install.sh).)

### A2. `ERROR 1045 Access denied for user 'root'@'mgmt'` khi GRANT trên DB nodes (B2.5)

**Triệu chứng**:
```
ERROR 1045 (28000): Access denied for user 'root'@'mgmt' (using password: YES)
```

**Nguyên nhân**: trên DB nodes, MySQL root chỉ accept `@'localhost'`. `mysql -h<IP> -uroot` từ mgmt không match user account nào.

**Fix**: SSH vào node và chạy mysql localhost trên đó. Cần ssh-trust trước (B2.1):

```bash
ssh -o StrictHostKeyChecking=no root@192.168.10.11 \
  "MYSQL_PWD='ChangeMe!Root#2026' mysql -uroot -e 'CREATE USER ...'"
```

(Đã fix trong [scripts/orchestrator/orchestrator-setup.sh:27-49](../../scripts/orchestrator/orchestrator-setup.sh).)

### A3. `ERROR 1290 super-read-only` khi GRANT trên replica (B2.5)

**Triệu chứng**:
```
ERROR 1290 (HY000) at line 1: The MySQL server is running with the --super-read-only option so it cannot execute this statement
```

**Nguyên nhân**: replicas có `super_read_only=ON` từ Demo 01 → CREATE USER/GRANT bị block.

**Fix**: chạy CHỈ trên master; DDL sẽ replicate sang replicas qua binlog. Verify count=1 trên cả 2 replica sau 3s.

### A4. Orchestrator service fail với `FATAL nonzero FailMasterPromotionOnLagMinutes requires ReplicationLagQuery` (B2.8)

**Triệu chứng**: `systemctl status orchestrator` → `failed`, journal log:
```
FATAL nonzero FailMasterPromotionOnLagMinutes requires ReplicationLagQuery to be set
```

**Nguyên nhân**: `FailMasterPromotionOnLagMinutes: 1` cần `ReplicationLagQuery` (custom query trả lag thực) — orchestrator không tự fallback về `Seconds_Behind_Source`.

**Fix**: hoặc set `FailMasterPromotionOnLagMinutes: 0` (disable check) hoặc add `ReplicationLagQuery` trỏ tới heartbeat table.

Demo dùng cách 1. (Đã fix trong [scripts/orchestrator/orchestrator-setup.sh:64](../../scripts/orchestrator/orchestrator-setup.sh).)

### A5. `orchestrator-client: Cannot access orchestrator at http://localhost:3000/api` (B3)

**Triệu chứng**:
```
orchestrator-client[NNN]: Cannot access orchestrator at http://localhost:3000/api.
Check ORCHESTRATOR_API is configured correctly and orchestrator is running
```

**Nguyên nhân**: orchestrator-client gọi mặc định `http://localhost:3000/api` (không có credentials). Khi `AuthenticationMethod=basic`, API trả 401 → client báo "cannot access".

**Fix**: setup `ORCHESTRATOR_API` env var trong `/etc/profile.d/orchestrator-client.sh` với credentials URL-encoded:

```bash
export ORCHESTRATOR_API="http://admin:ChangeMe!Admin%232026@127.0.0.1:3000/api"
#                                            ^^^^^         ← '#' phải encode thành %23
```

Cũng phải đợi service ready: poll `/api/status` cho đến khi trả `"Code":"OK"`. (Đã fix trong [scripts/orchestrator/orchestrator-setup.sh:75-91](../../scripts/orchestrator/orchestrator-setup.sh).)

### A6. `Unable to determine cluster name. clusterHint=192.168.10.11:3306` khi `topology`/`which-cluster-master` (B3)

**Triệu chứng**:
```
$ orchestrator-client -c topology -i 192.168.10.11:3306
2026-05-19 09:20:16 ERROR Unable to determine cluster name. clusterHint=192.168.10.11:3306
```

**Nguyên nhân**: `HostnameResolveMethod: "default"` khiến orchestrator reverse-resolve IP qua `/etc/hosts` → instance được lưu trong backend là `node1:3306` thay vì `192.168.10.11:3306`. Khi script query bằng IP, không match cluster.

```sql
-- Backend DB ở trạng thái lỗi:
SELECT hostname, port, cluster_name FROM database_instance;
-- hostname=node1, cluster_name=node1:3306   ← key là hostname, không phải IP
```

**Fix**: set `HostnameResolveMethod: "none"` + `MySQLHostnameResolveMethod: "@@report_host"`. Sau đó **wipe + recreate backend DB** (orchestrator không re-key instances cũ):

```bash
vagrant ssh mgmt -c "sudo systemctl stop orchestrator"
vagrant ssh mgmt -c "mysql -uroot -p'ChangeMe!Root#2026' -e 'DROP DATABASE orchestrator; CREATE DATABASE orchestrator;'"
# Sửa /etc/orchestrator.conf.json (HostnameResolveMethod="none") rồi restart
vagrant ssh mgmt -c "sudo systemctl start orchestrator"
# Discover lại
vagrant ssh mgmt -c "orchestrator-client -c discover -i 192.168.10.11:3306"
```

(Đã fix trong [scripts/orchestrator/orchestrator-setup.sh:53-54](../../scripts/orchestrator/orchestrator-setup.sh).)

### A7. `which-master -i nodeN` trả về `:0` (B4)

**Triệu chứng**:
```
$ orchestrator-client -c which-master -i 192.168.10.11:3306
:0
```

**Nguyên nhân**: `which-master` trả **parent** của instance trong replication tree. Khi instance ĐÃ là master, không có parent → `:0`. Đây không phải bug, là semantics đúng.

**Fix**: dùng `which-cluster-master` (master ghi-được của CLUSTER) thay vì `which-master`:

```bash
orchestrator-client -c which-cluster-master -i 192.168.10.11:3306
# → 192.168.10.11:3306
```

(Đã fix trong [demo/05-orchestrator/03,04,05,06,07-*.sh](03-discover-topology.sh).)

### A8. `Unable to determine cluster name. clusterHint=myCluster` khi graceful-master-takeover (B6)

**Triệu chứng**:
```
$ orchestrator-client -c graceful-master-takeover -alias myCluster -d 192.168.10.12:3306
2026-05-19 09:27:39 ERROR Unable to determine cluster name. clusterHint=myCluster
```

**Nguyên nhân**: tham số `-alias` cần `DetectClusterAliasQuery` config trong orchestrator để map cluster_name → alias. Mặc định query này empty → không có alias → orchestrator không tìm thấy cluster qua "myCluster".

**Fix**: dùng `-i <clusterHint>` (instance IP:port) thay vì `-alias`. Orchestrator tra cluster_name từ instance:

```bash
orchestrator-client -c graceful-master-takeover -i 192.168.10.11:3306 -d 192.168.10.12:3306
```

(Đã fix trong [demo/05-orchestrator/06-graceful-failover.sh:39](06-graceful-failover.sh).)

### A9. PROMOTE_RTO chậm bất thường (B7, > 60s)

**Triệu chứng**: B7 mất 200-300s thay vì < 30s như production tuned config.

**Nguyên nhân + cách rút ngắn**:
- `InstancePollSeconds=5` (default) → giảm còn `2` để probe nhanh hơn.
- `RecoveryPeriodBlockSeconds=300` chỉ block sau 1 recovery, không ảnh hưởng detection — không cần đổi.
- Multi-mode detection cần verify từ nhiều nguồn (mỗi probe = 2s). Lab có 3 nodes, sau B6 node1 detached → chỉ còn 2 nodes report → orchestrator strict hơn để tránh false-positive.
- Production thường có 5+ nodes hoặc Raft 3-node consensus → detection ổn định nhanh hơn.

**Cách tăng tốc cho demo**:

```bash
# 1) Sửa /etc/orchestrator.conf.json:
"InstancePollSeconds": 2,
"FailureDetectionPeriodBlockMinutes": 1,

# 2) Sửa demo/05-orchestrator/07-force-failover-test.sh dòng 84:
sleep 1   # thay vì sleep 2
```

### A10. Web UI hiện "Loading..." mãi, không thấy topology

**Triệu chứng**: http://192.168.10.20:3000 login OK nhưng dashboard rỗng.

**Nguyên nhân + Fix**: chưa `discover` cluster lần đầu. Browse tới "Discover" tab → nhập `192.168.10.11:3306` → "Submit". Hoặc CLI:

```bash
vagrant ssh mgmt -c "orchestrator-client -c discover -i 192.168.10.11:3306"
```

Sau ~5s refresh UI → cluster xuất hiện.

---

## Phụ lục B — Tóm tắt files config

### B.1 `/etc/orchestrator.conf.json` (trên mgmt)

```json
{
  "MySQLTopologyUser": "orchestrator",
  "MySQLTopologyPassword": "ChangeMe!Admin#2026",
  "MySQLOrchestratorHost": "127.0.0.1",
  "MySQLOrchestratorPort": 3306,
  "MySQLOrchestratorDatabase": "orchestrator",
  "MySQLOrchestratorUser": "orchestrator",
  "MySQLOrchestratorPassword": "ChangeMe!Admin#2026",

  "DefaultInstancePort": 3306,
  "DiscoverByShowSlaveHosts": true,
  "InstancePollSeconds": 5,
  "HostnameResolveMethod": "none",
  "MySQLHostnameResolveMethod": "@@report_host",

  "RecoverMasterClusterFilters": ["*"],
  "RecoverIntermediateMasterClusterFilters": ["*"],
  "RecoveryPeriodBlockSeconds": 300,

  "FailMasterPromotionOnLagMinutes": 0,
  "ApplyMySQLPromotionAfterMasterFailover": true,
  "MasterFailoverDetachReplicaMasterHost": true,
  "PreFailoverProcesses": ["echo PreFailover: {failureType} on {failureCluster} >> /var/log/orchestrator-recovery.log"],
  "PostFailoverProcesses": ["echo PostFailover: {failureType} -> {successorHost} >> /var/log/orchestrator-recovery.log"],

  "HTTPAuthUser": "admin",
  "HTTPAuthPassword": "ChangeMe!Admin#2026",
  "AuthenticationMethod": "basic",
  "ListenAddress": ":3000"
}
```

### B.2 `/etc/profile.d/orchestrator-client.sh` (trên mgmt)

```sh
export ORCHESTRATOR_API="http://admin:ChangeMe!Admin%232026@127.0.0.1:3000/api"
```

### B.3 `/root/.ssh/id_rsa` + `authorized_keys` (trên 4 hosts)

Source: `vagrant/provision/cluster_id_rsa{.pub}` (sinh local bởi `generate-ssh-key.sh`, gitignored).

```
Host node1 node2 node3 mgmt 192.168.10.*
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null
  LogLevel ERROR
```

### B.4 Files quan trọng trên DB nodes (đã đặt từ Demo 01)

- `/etc/mysql/mysql.conf.d/zz-mysql-ha.cnf` — server_id, `report_host=<IP>`, GTID, binlog
- `/etc/mysql/mysql.conf.d/zz-semisync.cnf` — semi-sync plugin

### B.5 Log files (mgmt)

- `journalctl -u orchestrator` — main log (systemd)
- `/var/log/orchestrator-recovery.log` — Pre/PostFailover hook output
- Backend DB `orchestrator.audit`, `orchestrator.topology_recovery` — full audit trail của discoveries + recoveries
- Backend DB `orchestrator.database_instance` — bảng lưu state hiện thời của tất cả instances

---

## Phụ lục C — Mapping bash scripts ↔ manual steps

| Manual step | Script tương đương                                                                                | Mô tả                                                                  |
|-------------|---------------------------------------------------------------------------------------------------|------------------------------------------------------------------------|
| B0          | (tiền đề — Demo 01 phải xong)                                                                     | Async/semi-sync 1M + 2R                                                |
| B1          | [`demo/05-orchestrator/01-precheck.sh`](01-precheck.sh)                                           | Validate Demo 01 + check report_host                                   |
| B2.1        | `vagrant provision --provision-with ssh-trust` (auto-run trong 02-orchestrator-install.sh)        | SSH keypair lên 4 VMs                                                  |
| B2.2        | [`scripts/common/01-install-mysql.sh`](../../scripts/common/01-install-mysql.sh) trên mgmt        | Cài MySQL 8.0 + config server_id + report_host                         |
| B2.3-B2.8   | [`demo/05-orchestrator/02-orchestrator-install.sh`](02-orchestrator-install.sh) + [`scripts/orchestrator/orchestrator-setup.sh`](../../scripts/orchestrator/orchestrator-setup.sh) | Cài orchestrator deb + backend DB + grant nodes + config + start service |
| B3          | [`demo/05-orchestrator/03-discover-topology.sh`](03-discover-topology.sh)                         | `orchestrator-client -c discover` + `topology`                         |
| B4          | [`demo/05-orchestrator/04-verify.sh`](04-verify.sh)                                               | API health + topology + which-cluster-master + replication-analysis    |
| B5          | [`demo/05-orchestrator/05-smoke-test.sh`](05-smoke-test.sh)                                       | Insert 200 rows + đo lag                                               |
| B6          | [`demo/05-orchestrator/06-graceful-failover.sh`](06-graceful-failover.sh)                         | `graceful-master-takeover -i ... -d ...`                               |
| B7          | [`demo/05-orchestrator/07-force-failover-test.sh`](07-force-failover-test.sh)                     | Halt master, poll which-cluster-master, đo PROMOTE_RTO + WRITE_RTO     |
| B8          | (manual — không có script auto)                                                                   | Power-on master cũ + CHANGE REPLICATION SOURCE → master mới + discover |
| B9          | [`demo/05-orchestrator/08-rollback.sh`](08-rollback.sh) (MODE=soft\|hard)                          | Stop daemon + uninstall + drop schema + drop user (soft); destroy VMs (hard) |

Chạy nhanh end-to-end (B1 → B6):

```bash
cd demo/05-orchestrator
bash run-all.sh         # Linux/macOS/WSL/Git Bash
# hoặc
.\run-all.ps1           # Windows PowerShell
```

B7/B8/B9 chạy thủ công vì destructive (B7 halt master) hoặc OPTIONAL (B8/B9).


---

!!! info "Nguồn gốc"
    `HA/Mysql/demo/05-orchestrator/MANUAL-SETUP.md`
