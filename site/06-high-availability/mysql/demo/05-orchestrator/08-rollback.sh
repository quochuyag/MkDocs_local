#!/usr/bin/env bash
# 08-rollback.sh — Tháo Orchestrator. MODE=soft|hard.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RESULTS="${SCRIPT_DIR}/results"
LOG="${RESULTS}/08-rollback.log"
mkdir -p "${RESULTS}"

# shellcheck disable=SC1091
source "${REPO_ROOT}/scripts/common/env.sh"

MODE="${MODE:-soft}"
log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" | tee -a "${LOG}"; }

cd "${REPO_ROOT}/vagrant"

if [[ "${MODE}" == "hard" ]]; then
  log "==> HARD rollback: destroy toàn bộ VMs"
  vagrant destroy -f 2>&1 | tee -a "${LOG}"
  rm -f provision/cluster_id_rsa provision/cluster_id_rsa.pub
  exit 0
fi

log "==> SOFT rollback: stop daemon + uninstall Orchestrator (giữ replication & VMs)"

vagrant ssh mgmt -c "
  sudo bash -c '
    systemctl stop orchestrator 2>/dev/null || true
    systemctl disable orchestrator 2>/dev/null || true
    dpkg -P orchestrator orchestrator-client 2>/dev/null || true
    rm -rf /etc/orchestrator.conf.json /var/lib/orchestrator
    mysql -uroot -p\"${MYSQL_ROOT_PWD}\" -e \"DROP DATABASE IF EXISTS orchestrator;\" 2>/dev/null || true
  '
" 2>&1 | tee -a "${LOG}"

for IP in "${NODE1_IP}" "${NODE2_IP}" "${NODE3_IP}"; do
  log "--- drop orchestrator user trên ${IP} ---"
  vagrant ssh node1 -c "mysql -uroot -p'${MYSQL_ROOT_PWD}' -h${IP} -e \"DROP USER IF EXISTS 'orchestrator'@'${MGMT_IP}'; FLUSH PRIVILEGES;\" 2>/dev/null || true" 2>&1 | tee -a "${LOG}"
done

log "==> Soft rollback xong. Demo 01 (replication) vẫn nguyên."
log "    Demo lại: bash demo/05-orchestrator/02-orchestrator-install.sh"
log "    Hard rollback: MODE=hard bash demo/05-orchestrator/08-rollback.sh"
