#!/usr/bin/env bash
# 07-rollback.sh — Tháo ProxySQL. MODE=soft|hard.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RESULTS="${SCRIPT_DIR}/results"
LOG="${RESULTS}/07-rollback.log"
mkdir -p "${RESULTS}"

# shellcheck disable=SC1091
source "${REPO_ROOT}/scripts/common/env.sh"

MODE="${MODE:-soft}"
log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" | tee -a "${LOG}"; }

cd "${REPO_ROOT}/vagrant"

if [[ "${MODE}" == "hard" ]]; then
  log "==> HARD rollback: destroy VMs"
  vagrant destroy -f 2>&1 | tee -a "${LOG}"
  rm -f provision/cluster_id_rsa provision/cluster_id_rsa.pub
  exit 0
fi

log "==> SOFT rollback: stop ProxySQL + drop appdb + drop users (giữ backend)"

vagrant ssh mgmt -c "
  sudo bash -c '
    systemctl stop proxysql 2>/dev/null || true
    systemctl disable proxysql 2>/dev/null || true
    apt-get remove --purge -y proxysql 2>/dev/null || true
    rm -rf /var/lib/proxysql
  '
" 2>&1 | tee -a "${LOG}"

for IP in "${NODE1_IP}" "${NODE2_IP}" "${NODE3_IP}"; do
  log "--- Drop appuser + monitor + appdb trên ${IP} ---"
  vagrant ssh node1 -c "
    mysql -uroot -p'${MYSQL_ROOT_PWD}' -h${IP} -e \"
      DROP USER IF EXISTS '${APP_USER}'@'%';
      DROP USER IF EXISTS 'monitor'@'%';
      DROP DATABASE IF EXISTS appdb;
      FLUSH PRIVILEGES;\" 2>/dev/null || true
  " 2>&1 | tee -a "${LOG}"
done

log "==> Soft rollback xong. Backend (Demo 01/06) vẫn nguyên."
log "    Demo lại: bash demo/07-proxysql/02-install-proxysql.sh"
log "    Hard: MODE=hard bash demo/07-proxysql/07-rollback.sh"
