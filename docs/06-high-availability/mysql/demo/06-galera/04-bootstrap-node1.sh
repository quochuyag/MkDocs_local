#!/usr/bin/env bash
# 04-bootstrap-node1.sh — Khởi tạo cluster mới trên node1.
# Gọi upstream scripts/galera/bootstrap-node.sh.
# CHỈ chạy 1 LẦN khi tạo cluster mới — không lặp lại sau khi cluster lên.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RESULTS="${SCRIPT_DIR}/results"
LOG="${RESULTS}/04-bootstrap-node1.log"
mkdir -p "${RESULTS}"

# shellcheck disable=SC1091
source "${REPO_ROOT}/scripts/common/env.sh"

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" | tee -a "${LOG}"; }

cd "${REPO_ROOT}/vagrant"

log "==> Bootstrap PXC cluster trên node1 (systemctl start mysql@bootstrap.service)"
vagrant ssh node1 -c "sudo bash /vagrant/scripts/galera/bootstrap-node.sh" 2>&1 | tee -a "${LOG}"

log "==> Đợi 5s + verify wsrep status"
sleep 5
vagrant ssh node1 -c "
  mysql -uroot -p'${MYSQL_ROOT_PWD}' -e \"
    SHOW STATUS WHERE Variable_name IN
     ('wsrep_cluster_size','wsrep_cluster_status','wsrep_local_state_comment','wsrep_ready','wsrep_connected');\"
" 2>&1 | tee -a "${LOG}"

log "==> Bước 4 hoàn tất. Tiếp theo: bash demo/06-galera/05-join-node2-node3.sh"
