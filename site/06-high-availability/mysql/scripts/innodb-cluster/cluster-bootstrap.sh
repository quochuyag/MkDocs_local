#!/usr/bin/env bash
# cluster-bootstrap.sh — chạy CHỈ trên node1 (seed). Tạo cluster + add 2 node còn lại.
set -euo pipefail
source "$(dirname "$0")/../common/env.sh"
require_root

# Password chứa '#' nên phải URL-encode cho mysqlsh URI (xem env.sh::urlenc)
ADMIN_PWD_ENC="$(urlenc "${ADMIN_PWD}")"

log "==> Tạo cluster ${CLUSTER_NAME} trên ${NODE1_HOST}"
mysqlsh --uri="${ADMIN_USER}:${ADMIN_PWD_ENC}@${NODE1_IP}:${MYSQL_PORT}" <<JS
var cluster = dba.createCluster('${CLUSTER_NAME}', {
  memberWeight: 50,
  exitStateAction: 'READ_ONLY',
  consistency: 'BEFORE_ON_PRIMARY_FAILOVER'
});
print("Cluster created.\n");
JS

log "==> Add ${NODE2_HOST}"
mysqlsh --uri="${ADMIN_USER}:${ADMIN_PWD_ENC}@${NODE1_IP}:${MYSQL_PORT}" <<JS
var c = dba.getCluster('${CLUSTER_NAME}');
c.addInstance('${ADMIN_USER}@${NODE2_IP}:${MYSQL_PORT}', {
  password: '${ADMIN_PWD}',
  recoveryMethod: 'clone'
});
JS

log "==> Add ${NODE3_HOST}"
mysqlsh --uri="${ADMIN_USER}:${ADMIN_PWD_ENC}@${NODE1_IP}:${MYSQL_PORT}" <<JS
var c = dba.getCluster('${CLUSTER_NAME}');
c.addInstance('${ADMIN_USER}@${NODE3_IP}:${MYSQL_PORT}', {
  password: '${ADMIN_PWD}',
  recoveryMethod: 'clone'
});
JS

log "==> Trạng thái cluster"
mysqlsh --uri="${ADMIN_USER}:${ADMIN_PWD_ENC}@${NODE1_IP}:${MYSQL_PORT}" \
  -e "var c=dba.getCluster('${CLUSTER_NAME}'); print(JSON.stringify(c.status(),null,2));"

log "==> Bootstrap xong. Tiếp theo: chạy router-setup.sh trên app host hoặc mgmt host."
