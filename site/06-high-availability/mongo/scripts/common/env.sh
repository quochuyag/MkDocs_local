#!/usr/bin/env bash
# scripts/common/env.sh — Biến môi trường dùng chung cho toàn bộ MongoDB HA toolkit.
# Source ở đầu mọi script: source "$(dirname "$0")/../common/env.sh"

# --- Topology hosts ---
export NODE1_HOST="${NODE1_HOST:-node1}"
export NODE2_HOST="${NODE2_HOST:-node2}"
export NODE3_HOST="${NODE3_HOST:-node3}"
export MGMT_HOST="${MGMT_HOST:-mgmt}"

export NODE1_IP="${NODE1_IP:-192.168.20.11}"
export NODE2_IP="${NODE2_IP:-192.168.20.12}"
export NODE3_IP="${NODE3_IP:-192.168.20.13}"
export MGMT_IP="${MGMT_IP:-192.168.20.20}"

# --- Replica set / cluster names ---
export RS_NAME="${RS_NAME:-rs0}"               # primary replica set (runbook 01)
export PSA_RS_NAME="${PSA_RS_NAME:-rspsa}"     # PSA topology (runbook 02)
export CFG_RS_NAME="${CFG_RS_NAME:-cfgrs}"     # config server RS (runbook 03)
export SHARD1_RS_NAME="${SHARD1_RS_NAME:-shard1rs}"
export SHARD2_RS_NAME="${SHARD2_RS_NAME:-shard2rs}"

# --- Ports ---
# Replica set chính dùng 27017. Sharded cluster đa instance cùng host:
#   27017 = mongos (trên mgmt)
#   27018 = mongod shard members (trên node1/2/3)
#   27019 = mongod config server members (trên node1/2/3)
#   27020 = arbiter (PSA topology runbook 02)
export MONGOD_PORT=27017
export SHARD_PORT=27018
export CFG_PORT=27019
export ARBITER_PORT=27020
export MONGOS_PORT=27017

# --- Paths ---
export MONGO_DATA_DIR="${MONGO_DATA_DIR:-/var/lib/mongodb}"
export MONGO_LOG_DIR="${MONGO_LOG_DIR:-/var/log/mongodb}"
export MONGO_CONF_DIR="${MONGO_CONF_DIR:-/etc/mongodb}"
export MONGO_KEYFILE="${MONGO_KEYFILE:-/etc/mongodb/keyfile}"
export MONGO_TLS_DIR="${MONGO_TLS_DIR:-/etc/mongodb/tls}"

# --- Backup paths ---
export BACKUP_ROOT="${BACKUP_ROOT:-/var/backups/mongo}"
export OPLOG_BACKUP_DIR="${OPLOG_BACKUP_DIR:-${BACKUP_ROOT}/oplog}"

# --- Users ---
# Root admin (root role on admin DB), tạo trên Primary lần đầu sau khi initiate RS.
export MONGO_ADMIN_USER="${MONGO_ADMIN_USER:-admin}"
export MONGO_ADMIN_PWD="${MONGO_ADMIN_PWD:-ChangeMe!Admin#2026}"
# Cluster admin (clusterAdmin + clusterManager) — dùng cho rs.* và sh.* ops.
export CLUSTER_ADMIN_USER="${CLUSTER_ADMIN_USER:-clusteradmin}"
export CLUSTER_ADMIN_PWD="${CLUSTER_ADMIN_PWD:-ChangeMe!Cluster#2026}"
# App user — read/write trên 1 DB.
export APP_DB="${APP_DB:-appdb}"
export APP_USER="${APP_USER:-appuser}"
export APP_PWD="${APP_PWD:-ChangeMe!App#2026}"
# Backup user — backup role.
export BACKUP_USER="${BACKUP_USER:-backupuser}"
export BACKUP_PWD="${BACKUP_PWD:-ChangeMe!Backup#2026}"

# --- MongoDB version ---
export MONGO_MAJOR="${MONGO_MAJOR:-7.0}"        # 6.0 / 7.0 / 8.0
export MONGO_EDITION="${MONGO_EDITION:-org}"    # org = Community, enterprise = Enterprise

# --- Helpers ---
require_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "ERROR: phải chạy với quyền root/sudo." >&2
    exit 1
  fi
}

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }

# mongosh authenticated as admin trên localhost. Truyền JS qua stdin hoặc --eval.
# Sử dụng: mongo_admin_local --eval "rs.status()"
mongo_admin_local() {
  local port="${MONGO_PORT_OVERRIDE:-${MONGOD_PORT}}"
  mongosh --quiet --host 127.0.0.1 --port "${port}" \
    -u "${MONGO_ADMIN_USER}" -p "${MONGO_ADMIN_PWD}" \
    --authenticationDatabase admin "$@"
}

# mongosh KHÔNG auth (chỉ dùng được trước khi tạo admin user / với localhost exception).
mongo_local_noauth() {
  local port="${MONGO_PORT_OVERRIDE:-${MONGOD_PORT}}"
  mongosh --quiet --host 127.0.0.1 --port "${port}" "$@"
}

# Đợi mongod sẵn sàng accept connections.
wait_for_mongod() {
  local port="${1:-${MONGOD_PORT}}"
  local tries="${2:-60}"
  for ((i=0; i<tries; i++)); do
    if mongosh --quiet --host 127.0.0.1 --port "${port}" --eval 'db.runCommand({ping:1}).ok' 2>/dev/null | grep -q 1; then
      return 0
    fi
    sleep 2
  done
  echo "ERROR: mongod port ${port} không lên sau $((tries*2))s." >&2
  return 1
}
