#!/usr/bin/env bash
# 02-install-proxysql.sh — Cài ProxySQL trên mgmt + monitor/app user trên 3 DB.
# Gọi upstream scripts/proxysql/proxysql-setup.sh (default config cho async/semi-sync).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RESULTS="${SCRIPT_DIR}/results"
LOG="${RESULTS}/02-install-proxysql.log"
mkdir -p "${RESULTS}"

# shellcheck disable=SC1091
source "${REPO_ROOT}/scripts/common/env.sh"

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" | tee -a "${LOG}"; }

cd "${REPO_ROOT}/vagrant"

# Galera/PXC chỉ tạo root@localhost mặc định. Tạo monitor + appuser local trên TỪNG node qua socket
# (vagrant ssh) thay vì connect remote từ mgmt — root@'%' không tồn tại sau install-pxc.
log "==> Tạo monitor + ${APP_USER} trên 3 DB nodes (local socket trên mỗi node)"
SQL_USERS="CREATE USER IF NOT EXISTS 'monitor'@'%' IDENTIFIED BY '${ADMIN_PWD}';
GRANT USAGE, REPLICATION CLIENT ON *.* TO 'monitor'@'%';
CREATE USER IF NOT EXISTS '${APP_USER}'@'%' IDENTIFIED WITH mysql_native_password BY '${APP_PWD}';
GRANT ALL ON appdb.* TO '${APP_USER}'@'%';
FLUSH PRIVILEGES;"

# Trên Galera chỉ cần apply một node — DDL được replicate qua wsrep. Nhưng tạo ở mọi node cho async backend.
for N in node1 node2 node3; do
  log "--- [$N] tạo users qua socket ---"
  vagrant ssh "$N" -c "mysql -uroot -p'${MYSQL_ROOT_PWD}' -e \"${SQL_USERS}\" 2>&1 | grep -v 'Using a password' || true" 2>&1 | tee -a "${LOG}"
done

log "==> [mgmt] cài ProxySQL + cấu hình admin :${PROXYSQL_ADMIN_PORT} (BOOTSTRAP_USERS=false)"
vagrant ssh mgmt -c "sudo BOOTSTRAP_USERS=false bash /vagrant/scripts/proxysql/proxysql-setup.sh" 2>&1 | tee -a "${LOG}"

log "==> Đợi 3s cho ProxySQL warm-up"
sleep 3

log "==> Verify service + ports"
vagrant ssh mgmt -c "
  sudo systemctl is-active proxysql
  sudo ss -tlnp | egrep ':${PROXYSQL_ADMIN_PORT}|:${PROXYSQL_MYSQL_PORT}' || true
" 2>&1 | tee -a "${LOG}"

log "==> runtime_mysql_servers (qua admin :${PROXYSQL_ADMIN_PORT})"
vagrant ssh mgmt -c "
  mysql -uadmin -padmin -h127.0.0.1 -P${PROXYSQL_ADMIN_PORT} -e \"
    SELECT hostgroup_id, hostname, port, status FROM runtime_mysql_servers ORDER BY hostgroup_id, hostname;\"
" 2>&1 | tee -a "${LOG}"

log "==> Bước 2 hoàn tất. Tiếp theo:"
log "    - BACKEND=async-semisync: bash demo/07-proxysql/04-verify.sh"
log "    - BACKEND=galera:         bash demo/07-proxysql/03-configure-galera.sh → 04-verify.sh"
