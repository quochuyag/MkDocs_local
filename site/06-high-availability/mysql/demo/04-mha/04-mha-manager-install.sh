#!/usr/bin/env bash
# 04-mha-manager-install.sh — Cài mha4mysql-manager trên mgmt + sinh config + start daemon.
# Gọi upstream scripts/mha/manager-setup.sh (đã làm: install package, ghi /etc/mha/<cluster>.cnf,
# sinh master_ip_failover.sh, masterha_check_ssh, masterha_check_repl, start manager background).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RESULTS="${SCRIPT_DIR}/results"
LOG="${RESULTS}/04-mha-manager-install.log"
mkdir -p "${RESULTS}"

# shellcheck disable=SC1091
source "${REPO_ROOT}/scripts/common/env.sh"

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" | tee -a "${LOG}"; }

cd "${REPO_ROOT}/vagrant"

log "==> [mgmt] cài mha4mysql-manager"
vagrant ssh mgmt -c "sudo bash /vagrant/scripts/mha/manager-setup.sh" 2>&1 | tee -a "${LOG}"

log "==> Đợi 3s cho manager warm-up"
sleep 3

log "==> [mgmt] masterha_check_status"
vagrant ssh mgmt -c "sudo masterha_check_status --conf=/etc/mha/${CLUSTER_NAME}.cnf" 2>&1 | tee -a "${LOG}" || true

log "==> [mgmt] xem cấu hình + log đầu"
vagrant ssh mgmt -c "
  echo '--- /etc/mha/${CLUSTER_NAME}.cnf ---'
  sudo cat /etc/mha/${CLUSTER_NAME}.cnf
  echo '--- /var/log/mha/${CLUSTER_NAME}/manager.log (last 30 lines) ---'
  sudo tail -n 30 /var/log/mha/${CLUSTER_NAME}/manager.log 2>/dev/null || echo '(log chưa có)'
" 2>&1 | tee -a "${LOG}"

log "==> Bước 4 hoàn tất. Tiếp theo: bash demo/04-mha/05-verify.sh"
