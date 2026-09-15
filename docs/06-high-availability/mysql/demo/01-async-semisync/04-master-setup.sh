#!/usr/bin/env bash
# 04-master-setup.sh — Bật semi-sync source trên node1, tạo user repl.
# Chạy trên HOST. Trigger scripts/async-semisync/master-setup.sh bên trong node1.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RESULTS="${SCRIPT_DIR}/results"
LOG="${RESULTS}/04-master-setup.log"
mkdir -p "${RESULTS}"

# shellcheck disable=SC1091
source "${REPO_ROOT}/scripts/common/env.sh"

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" | tee -a "${LOG}"; }

cd "${REPO_ROOT}/vagrant"

log "==> Trigger master-setup trên node1"
vagrant ssh node1 -c "sudo bash /vagrant/scripts/async-semisync/master-setup.sh" 2>&1 | tee -a "${LOG}"

log "==> Verify plugin + user repl + master status"
vagrant ssh node1 -c "
  mysql -uroot -p'${MYSQL_ROOT_PWD}' -e \"
    SELECT plugin_name,plugin_status FROM information_schema.plugins
      WHERE plugin_name LIKE 'rpl_semi_sync%';
    SHOW VARIABLES LIKE 'rpl_semi_sync_source%';
    SHOW STATUS LIKE 'Rpl_semi_sync_source%';
    SELECT user,host,plugin FROM mysql.user WHERE user='${REPL_USER}';
    SHOW MASTER STATUS\\G\"
" 2>&1 | tee -a "${LOG}"

log "==> Bước 4 hoàn tất. Tiếp theo: bash demo/01-async-semisync/05-replica-setup.sh"
