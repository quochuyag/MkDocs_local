#!/usr/bin/env bash
# 03-mha-node-install.sh — Cài mha4mysql-node trên node1/2/3.
# Gọi upstream scripts/mha/node-setup.sh.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RESULTS="${SCRIPT_DIR}/results"
LOG="${RESULTS}/03-mha-node-install.log"
mkdir -p "${RESULTS}"

# shellcheck disable=SC1091
source "${REPO_ROOT}/scripts/common/env.sh"

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" | tee -a "${LOG}"; }

cd "${REPO_ROOT}/vagrant"

for N in node1 node2 node3; do
  log "==> [${N}] cài mha4mysql-node + tạo user 'mha'@'%'"
  vagrant ssh "${N}" -c "sudo bash /vagrant/scripts/mha/node-setup.sh" 2>&1 | tee -a "${LOG}"
done

log "==> Verify package cài trên 3 nodes"
for N in node1 node2 node3; do
  vagrant ssh "$N" -c "
    dpkg -l | grep mha4mysql-node || true
    which save_binary_logs || true
    mysql -uroot -p'${MYSQL_ROOT_PWD}' -N -e \"SELECT user,host FROM mysql.user WHERE user='mha';\"
  " 2>&1 | tee -a "${LOG}"
done

log "==> Bước 3 hoàn tất. Tiếp theo: bash demo/04-mha/04-mha-manager-install.sh"
