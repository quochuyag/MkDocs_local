#!/usr/bin/env bash
# 03-configure-galera.sh — CHỈ chạy khi BACKEND=galera. Bổ sung mysql_galera_hostgroups.
# Gọi upstream scripts/proxysql/proxysql-galera.sh.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RESULTS="${SCRIPT_DIR}/results"
LOG="${RESULTS}/03-configure-galera.log"
mkdir -p "${RESULTS}"

# shellcheck disable=SC1091
source "${REPO_ROOT}/scripts/common/env.sh"

BACKEND="${BACKEND:-async-semisync}"

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" | tee -a "${LOG}"; }

cd "${REPO_ROOT}/vagrant"

if [[ "${BACKEND}" != "galera" ]]; then
  log "==> BACKEND=${BACKEND} ≠ 'galera', SKIP step này."
  exit 0
fi

log "==> Setup mysql_galera_hostgroups (writer=10, backup=11, reader=20, offline=30)"
vagrant ssh mgmt -c "sudo bash /vagrant/scripts/proxysql/proxysql-galera.sh" 2>&1 | tee -a "${LOG}"

log "==> Verify"
vagrant ssh mgmt -c "
  mysql -uadmin -padmin -h127.0.0.1 -P${PROXYSQL_ADMIN_PORT} -e \"
    SELECT * FROM runtime_mysql_galera_hostgroups;
    SELECT hostgroup_id, hostname, port, status FROM runtime_mysql_servers ORDER BY hostgroup_id, hostname;\"
" 2>&1 | tee -a "${LOG}"

log "==> Bước 3 hoàn tất."
