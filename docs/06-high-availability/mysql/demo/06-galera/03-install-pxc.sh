#!/usr/bin/env bash
# 03-install-pxc.sh — Cài Percona XtraDB Cluster 8.0 trên 3 nodes.
# QUAN TRỌNG: thay thế MySQL community. Không chạy install-mysql.sh trước.
# Gọi upstream scripts/galera/install-pxc.sh — ghi config nhưng KHÔNG start service.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RESULTS="${SCRIPT_DIR}/results"
LOG="${RESULTS}/03-install-pxc.log"
mkdir -p "${RESULTS}"

# shellcheck disable=SC1091
source "${REPO_ROOT}/scripts/common/env.sh"

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" | tee -a "${LOG}"; }

cd "${REPO_ROOT}/vagrant"

DB_NODES=(node1 node2 node3)

# Guard: nếu MySQL community đã cài, cần dọn trước
log "==> Kiểm tra xem MySQL community đã cài chưa (PXC không tương thích cùng host)"
for N in "${DB_NODES[@]}"; do
  HAS_COMM=$(vagrant ssh "$N" -c "dpkg -l 2>/dev/null | grep -E '^ii  mysql-server-8\\.|^ii  mysql-server-core' | head -n1 || true" | tr -d '\r')
  if [[ -n "${HAS_COMM}" ]]; then
    log "[FAIL] [${N}] đã cài MySQL community: ${HAS_COMM}"
    log "       PXC thay thế hẳn package này. Hãy chạy: vagrant ssh ${N} -c 'sudo systemctl stop mysql; sudo apt-get remove --purge mysql-server-* mysql-client-* -y; sudo rm -rf /var/lib/mysql'"
    log "       Hoặc: MODE=hard bash 09-rollback.sh (destroy VMs) rồi chạy lại từ 01-vagrant-up.sh"
    exit 1
  fi
done

for N in "${DB_NODES[@]}"; do
  log "==> [${N}] cài Percona XtraDB Cluster (~250 MB, có thể mất vài phút)"
  vagrant ssh "${N}" -c "sudo bash /vagrant/scripts/galera/install-pxc.sh" 2>&1 | tee -a "${LOG}"
done

log "==> Verify PXC cài + config nhưng service CHƯA START"
for N in "${DB_NODES[@]}"; do
  vagrant ssh "$N" -c "
    dpkg -l | grep percona-xtradb-cluster | head -n3
    echo '--- zz-pxc.cnf ---'
    sudo cat /etc/mysql/mysql.conf.d/zz-pxc.cnf 2>/dev/null || sudo cat /etc/percona-xtradb-cluster.conf.d/zz-pxc.cnf 2>/dev/null
    echo '--- mysql service state ---'
    sudo systemctl is-active mysql || true
  " 2>&1 | tee -a "${LOG}"
done

log "==> Bước 3 hoàn tất. Tiếp theo: bash demo/06-galera/04-bootstrap-node1.sh"
