#!/usr/bin/env bash
# orchestrator-setup.sh — cài Orchestrator + backend store (MySQL local) trên mgmt host.
set -euo pipefail
source "$(dirname "$0")/../common/env.sh"
require_root

ORC_VER="3.2.6"

log "==> Tải binary"
if command -v apt-get >/dev/null; then
  wget -qO /tmp/orc.deb "https://github.com/openark/orchestrator/releases/download/v${ORC_VER}/orchestrator_${ORC_VER}_amd64.deb"
  dpkg -i /tmp/orc.deb || apt-get install -f -y
  wget -qO /tmp/orc-cli.deb "https://github.com/openark/orchestrator/releases/download/v${ORC_VER}/orchestrator-client_${ORC_VER}_amd64.deb"
  dpkg -i /tmp/orc-cli.deb || true
else
  dnf install -y "https://github.com/openark/orchestrator/releases/download/v${ORC_VER}/orchestrator-${ORC_VER}-1.x86_64.rpm"
fi

log "==> Tạo backend DB cho Orchestrator (dùng MySQL local trên mgmt)"
mysql_root <<SQL
CREATE DATABASE IF NOT EXISTS orchestrator;
CREATE USER IF NOT EXISTS 'orchestrator'@'127.0.0.1' IDENTIFIED BY '${ADMIN_PWD}';
GRANT ALL ON orchestrator.* TO 'orchestrator'@'127.0.0.1';
FLUSH PRIVILEGES;
SQL

log "==> Tạo user trên MASTER (demo01 setup → node1); replicas nhận qua replication"
# LƯU Ý 1: trên DB nodes, root chỉ accept @'localhost' → không thể `mysql -h<IP>` từ mgmt.
#          Workaround: SSH (ssh-trust provisioner) và chạy mysql localhost trên đó.
# LƯU Ý 2: replicas có super_read_only=ON → KHÔNG chạy CREATE USER/GRANT trên replica;
#          DDL CREATE USER được binlog → tự nhân bản tới replicas.
ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no "root@${NODE1_IP}" \
    "MYSQL_PWD='${MYSQL_ROOT_PWD}' mysql -uroot" <<SQL
CREATE USER IF NOT EXISTS 'orchestrator'@'${MGMT_IP}' IDENTIFIED BY '${ADMIN_PWD}';
ALTER USER 'orchestrator'@'${MGMT_IP}' IDENTIFIED BY '${ADMIN_PWD}';
GRANT SUPER, PROCESS, REPLICATION SLAVE, RELOAD ON *.* TO 'orchestrator'@'${MGMT_IP}';
GRANT SELECT ON mysql.slave_master_info TO 'orchestrator'@'${MGMT_IP}';
CREATE DATABASE IF NOT EXISTS meta;
GRANT SELECT, INSERT, UPDATE, DELETE ON meta.* TO 'orchestrator'@'${MGMT_IP}';
FLUSH PRIVILEGES;
SQL

log "==> Đợi 3s cho user propagate qua replication"
sleep 3
for IP in "${NODE2_IP}" "${NODE3_IP}"; do
  HAS_USER=$(ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "root@${IP}" \
      "MYSQL_PWD='${MYSQL_ROOT_PWD}' mysql -uroot -N -B -e \"SELECT COUNT(*) FROM mysql.user WHERE user='orchestrator' AND host='${MGMT_IP}';\"" 2>/dev/null || echo 0)
  log "    [${IP}] user orchestrator@${MGMT_IP} count=${HAS_USER}"
done

log "==> Cấu hình /etc/orchestrator.conf.json"
cat >/etc/orchestrator.conf.json <<EOF
{
  "MySQLTopologyUser": "orchestrator",
  "MySQLTopologyPassword": "${ADMIN_PWD}",
  "MySQLOrchestratorHost": "127.0.0.1",
  "MySQLOrchestratorPort": ${MYSQL_PORT},
  "MySQLOrchestratorDatabase": "orchestrator",
  "MySQLOrchestratorUser": "orchestrator",
  "MySQLOrchestratorPassword": "${ADMIN_PWD}",

  "DefaultInstancePort": ${MYSQL_PORT},
  "DiscoverByShowSlaveHosts": true,
  "InstancePollSeconds": ${ORC_INSTANCE_POLL_SECONDS},
  "HostnameResolveMethod": "none",
  "MySQLHostnameResolveMethod": "@@report_host",

  "RecoverMasterClusterFilters": ["*"],
  "RecoverIntermediateMasterClusterFilters": ["*"],
  "RecoveryPeriodBlockSeconds": ${ORC_RECOVERY_BLOCK_SECONDS},

  "FailMasterPromotionOnLagMinutes": 0,
  "ApplyMySQLPromotionAfterMasterFailover": true,
  "MasterFailoverDetachReplicaMasterHost": true,
  "PreFailoverProcesses": ["echo 'PreFailover: {failureType} on {failureCluster}' >> /var/log/orchestrator-recovery.log"],
  "PostFailoverProcesses": ["echo 'PostFailover: {failureType} -> {successorHost}' >> /var/log/orchestrator-recovery.log"],

  "HTTPAuthUser": "admin",
  "HTTPAuthPassword": "${ADMIN_PWD}",
  "AuthenticationMethod": "basic",
  "ListenAddress": ":3000"
}
EOF

log "==> Setup ORCHESTRATOR_API cho orchestrator-client (basic auth)"
# urlenc password để escape '#' (RFC 3986) trong userinfo của URL
ENC_PWD=$(urlenc "${ADMIN_PWD}")
cat >/etc/profile.d/orchestrator-client.sh <<EOF
export ORCHESTRATOR_API="http://admin:${ENC_PWD}@127.0.0.1:3000/api"
EOF
chmod 644 /etc/profile.d/orchestrator-client.sh
# shellcheck disable=SC1091
source /etc/profile.d/orchestrator-client.sh

log "==> Start orchestrator service"
systemctl enable --now orchestrator

log "==> Đợi API /api/status ready (≤30s)"
for i in $(seq 1 30); do
  if curl -fsS -u "admin:${ADMIN_PWD}" http://127.0.0.1:3000/api/status 2>/dev/null | grep -q '"Code":"OK"'; then
    log "    API ready sau ${i}s"
    break
  fi
  sleep 1
done

log "==> Discover topology"
orchestrator-client -c discover -i ${NODE1_IP}:${MYSQL_PORT} || true
orchestrator-client -c topology -i ${NODE1_IP}:${MYSQL_PORT} || true

log "==> Web UI: http://${MGMT_IP}:3000  (admin / ${ADMIN_PWD})"
