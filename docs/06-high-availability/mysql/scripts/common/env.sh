#!/usr/bin/env bash
# scripts/common/env.sh — Biến môi trường dùng chung cho toàn bộ runbooks.
# Source file này ở đầu mọi script: source "$(dirname "$0")/../common/env.sh"

# --- Topology ---
export NODE1_HOST="${NODE1_HOST:-node1}"
export NODE2_HOST="${NODE2_HOST:-node2}"
export NODE3_HOST="${NODE3_HOST:-node3}"
export MGMT_HOST="${MGMT_HOST:-mgmt}"

export NODE1_IP="${NODE1_IP:-192.168.10.11}"
export NODE2_IP="${NODE2_IP:-192.168.10.12}"
export NODE3_IP="${NODE3_IP:-192.168.10.13}"
export MGMT_IP="${MGMT_IP:-192.168.10.20}"
export VIP="${VIP:-192.168.10.100}"

# --- MySQL accounts ---
export MYSQL_ROOT_PWD="${MYSQL_ROOT_PWD:-ChangeMe!Root#2026}"
export REPL_USER="${REPL_USER:-repl}"
export REPL_PWD="${REPL_PWD:-ChangeMe!Repl#2026}"
export ADMIN_USER="${ADMIN_USER:-clusteradmin}"
export ADMIN_PWD="${ADMIN_PWD:-ChangeMe!Admin#2026}"
export APP_USER="${APP_USER:-appuser}"
export APP_PWD="${APP_PWD:-ChangeMe!App#2026}"

# --- Cluster identity ---
export CLUSTER_NAME="${CLUSTER_NAME:-myCluster}"
export GR_GROUP_UUID="${GR_GROUP_UUID:-aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa}"
export GALERA_CLUSTER_NAME="${GALERA_CLUSTER_NAME:-pxc-cluster}"

# --- Orchestrator tuning (lab defaults; production thường 300s/5s) ---
# RecoveryPeriodBlockSeconds=60 cho phép test failover nhiều lần liên tiếp;
# InstancePollSeconds=1 giảm DETECT_RTO. Trong prod hãy export 300/5.
export ORC_RECOVERY_BLOCK_SECONDS="${ORC_RECOVERY_BLOCK_SECONDS:-60}"
export ORC_INSTANCE_POLL_SECONDS="${ORC_INSTANCE_POLL_SECONDS:-1}"

# --- Ports ---
export MYSQL_PORT=3306
export MYSQL_X_PORT=33060
export GR_PORT=33061           # Group Replication
export GALERA_PORT=4567         # Galera replication
export GALERA_IST_PORT=4568     # Incremental State Transfer
export GALERA_SST_PORT=4444     # State Snapshot Transfer
export ROUTER_RW_PORT=6446
export ROUTER_RO_PORT=6447
export PROXYSQL_ADMIN_PORT=6032
export PROXYSQL_MYSQL_PORT=6033

# --- Helpers ---
mysql_root() {
  mysql -uroot -p"${MYSQL_ROOT_PWD}" -h127.0.0.1 -P"${MYSQL_PORT}" "$@"
}

# URL-encode password cho mysqlsh URI (--uri="user:pwd@host:port").
# Pwd mặc định chứa '#' (fragment delim) → mysqlsh báo "Invalid URI: Illegal character [#]".
# Escape các gen-delims theo RFC 3986. '%' phải escape trước.
urlenc() {
  local s="${1:-}"
  s="${s//%/%25}"
  s="${s//:/%3A}"
  s="${s//@/%40}"
  s="${s//\//%2F}"
  s="${s//#/%23}"
  s="${s//\?/%3F}"
  printf '%s' "$s"
}

require_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "ERROR: phải chạy với quyền root/sudo." >&2
    exit 1
  fi
}

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }
