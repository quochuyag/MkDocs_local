---
title: Runbook 05 — Orchestrator (GitHub fork bởi openark)
course: 06-high-availability
source: HA/Mysql/runbooks/05-orchestrator.md
---

# Runbook 05 — Orchestrator (GitHub fork bởi openark)

Orchestrator (Go) là replication topology manager: hiển thị topology, refactor topology bằng drag-and-drop, anti-flapping, detection nhiều loại failure (DeadMaster, DeadIntermediateMaster, UnreachableMaster), tự động recover.

## 1. Khi nào chọn

| Tiêu chí | Orchestrator | MHA |
|---|---|---|
| Tự động phát hiện topology | Có (qua `SHOW SLAVE HOSTS`) | Không, khai báo tay |
| Web UI | Có (port 3000) | Không |
| Raft HA cho bản thân Orchestrator | Có (3+ nodes Orchestrator) | Không |
| GR/InnoDB Cluster support | Không (chỉ async/semi-sync) | Không |
| Bảo trì hoạt động | Hoạt động tích cực | Maintenance mode |

## 2. Tiền đề

- Async/Semi-sync replication đã hoạt động (Runbook 01).
- 1 host mgmt (có thể cũng cài MySQL local làm backend) — có thể chạy 3 hosts Orchestrator Raft cho HA của bản thân Orchestrator.

## 3. Cài đặt

```bash
bash scripts/orchestrator/orchestrator-setup.sh
```
Script:
1. Tải `.deb`/`.rpm` từ GitHub v3.2.6.
2. Tạo DB backend `orchestrator` trong MySQL local của mgmt.
3. Tạo user `orchestrator@<mgmt_ip>` trên cả 3 DB nodes với quyền `SUPER, PROCESS, REPLICATION SLAVE, RELOAD, SELECT ...`.
4. Ghi `/etc/orchestrator.conf.json` với `RecoverMasterClusterFilters=["*"]`, `ApplyMySQLPromotionAfterMasterFailover=true`.
5. `systemctl enable --now orchestrator`.
6. `orchestrator-client -c discover -i node1:3306` để phát hiện topology.

Web UI: `http://<mgmt_ip>:3000` — login `admin / <ADMIN_PWD>`.

## 4. Vận hành

| Tác vụ | Lệnh |
|---|---|
| Xem topology | `bash scripts/orchestrator/orchestrator-ops.sh topology` |
| Phát hiện node mới | `bash scripts/orchestrator/orchestrator-ops.sh discover node4:3306` |
| Graceful switchover | `bash scripts/orchestrator/orchestrator-ops.sh graceful-failover node2:3306` |
| Force recover (master đã chết) | `bash scripts/orchestrator/orchestrator-ops.sh force-failover node1:3306` |
| Đặt replica thành master | `orchestrator-client -c move-up -i node2:3306` |
| Anti-flapping cooldown | `RecoveryPeriodBlockSeconds` trong config |

### 4.1 Tích hợp với Pre/PostFailover hooks
Trong `/etc/orchestrator.conf.json`:
```json
"PreFailoverProcesses": [
  "curl -X POST https://alerts.internal/incident -d 'failover starting on {failureCluster}'"
],
"PostFailoverProcesses": [
  "sh /usr/local/bin/move-vip.sh {successorHost}",
  "curl -X POST https://alerts.internal/incident -d 'failover done -> {successorHost}'"
]
```
Sau đó: `systemctl reload orchestrator`.

### 4.2 Tích hợp ProxySQL/Consul
Hooks ghi vào Consul KV hoặc gọi ProxySQL admin để update writer hostgroup tự động:
```bash
"PostFailoverProcesses": [
  "mysql -uadmin -padmin -h<proxysql> -P6032 -e \"UPDATE mysql_servers SET hostgroup_id=10 WHERE hostname='{successorHost}'; LOAD MYSQL SERVERS TO RUNTIME;\""
]
```

## 5. Raft HA cho Orchestrator chính nó

3 mgmt hosts, mỗi host cài Orchestrator + backend MySQL riêng (KHÔNG share). Thêm vào config:
```json
"RaftEnabled": true,
"RaftDataDir": "/var/lib/orchestrator",
"RaftBind": "<this_host>",
"DefaultRaftPort": 10008,
"RaftNodes": ["mgmt1", "mgmt2", "mgmt3"]
```

## 6. Rollback / tháo

```bash
systemctl stop orchestrator && systemctl disable orchestrator
apt-get remove orchestrator orchestrator-client    # hoặc rpm -e
mysql -uroot -p -e "DROP DATABASE orchestrator;"
# Trên mỗi DB node: DROP USER 'orchestrator'@'<mgmt>';
```

## 7. Tham khảo
- https://github.com/openark/orchestrator/wiki


---

!!! info "Nguồn gốc"
    `HA/Mysql/runbooks/05-orchestrator.md`
