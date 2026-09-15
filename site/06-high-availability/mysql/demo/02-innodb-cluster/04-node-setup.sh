#!/usr/bin/env bash
# 04-node-setup.sh — Chạy node-setup.sh trên 3 db nodes:
#   - Tạo user clusteradmin
#   - dba.configureInstance() → MySQL Shell tự fix config + restart nếu cần
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RESULTS="${SCRIPT_DIR}/results"
LOG="${RESULTS}/04-node-setup.log"
mkdir -p "${RESULTS}"

# shellcheck disable=SC1091
source "${REPO_ROOT}/scripts/common/env.sh"

# ADMIN_PWD chứa '#' (fragment delim) → URL-encode cho mysqlsh URI (xem env.sh::urlenc).
# Không dùng cho mysql CLI -p '${ADMIN_PWD}' (CLI nhận raw, không parse URI).
ADMIN_PWD_ENC="$(urlenc "${ADMIN_PWD}")"

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" | tee -a "${LOG}"; }

cd "${REPO_ROOT}/vagrant"

DB_NODES=(node1 node2 node3)

for N in "${DB_NODES[@]}"; do
  log "==> node-setup trên ${N} (configureInstance có thể restart MySQL)"
  vagrant ssh "${N}" -c "sudo bash /vagrant/scripts/innodb-cluster/node-setup.sh" 2>&1 | tee -a "${LOG}"
done

log "==> Đợi 5s cho các MySQL service ổn định sau khi configureInstance"
sleep 5

log "==> Verify checkInstanceConfiguration trên mỗi node"
for N in "${DB_NODES[@]}"; do
  log "    --- ${N} ---"
  vagrant ssh "${N}" -c "
    mysqlsh --uri='${ADMIN_USER}:${ADMIN_PWD_ENC}@127.0.0.1:${MYSQL_PORT}' \
      -e \"print(JSON.stringify(dba.checkInstanceConfiguration('${ADMIN_USER}@127.0.0.1:${MYSQL_PORT}',{password:'${ADMIN_PWD}',interactive:false}),null,2));\" 2>&1 | tail -n 80
  " 2>&1 | tee -a "${LOG}"
done

log "==> Verify user clusteradmin & GR-related variables"
for N in "${DB_NODES[@]}"; do
  log "    --- ${N} ---"
  vagrant ssh "${N}" -c "
    mysql -uroot -p'${MYSQL_ROOT_PWD}' -N -e \"
      SELECT user,host FROM mysql.user WHERE user='${ADMIN_USER}';
      SELECT
        CONCAT('gtid_mode=',@@gtid_mode,
               ' enforce_gtid_consistency=',@@enforce_gtid_consistency,
               ' log_slave_updates=',@@log_slave_updates,
               ' binlog_format=',@@binlog_format,
               ' report_host=',@@report_host);\"
  " 2>&1 | tee -a "${LOG}"
done

log "==> Bước 4 hoàn tất. Tiếp theo: bash demo/02-innodb-cluster/05-cluster-bootstrap.sh"
