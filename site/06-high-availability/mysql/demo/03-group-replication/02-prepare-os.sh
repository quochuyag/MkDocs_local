#!/usr/bin/env bash
# 02-prepare-os.sh — Chuẩn bị OS (hosts/swap/ntp/sysctl) cho toàn bộ 4 VMs.
# Chạy trên HOST. Gọi vagrant provision với provisioner "common-prep".
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RESULTS="${SCRIPT_DIR}/results"
LOG="${RESULTS}/02-prepare-os.log"
mkdir -p "${RESULTS}"

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" | tee -a "${LOG}"; }

cd "${REPO_ROOT}/vagrant"

NODES=(node1 node2 node3 mgmt)

for N in "${NODES[@]}"; do
  log "==> prepare-os trên ${N}"
  vagrant provision "${N}" --provision-with common-prep 2>&1 | tee -a "${LOG}"
done

log "==> Verify hosts file & swap & NTP trên mỗi node"
for N in "${NODES[@]}"; do
  log "    --- ${N} ---"
  vagrant ssh "${N}" -c "
    echo '/etc/hosts:';      grep -A4 'mysql-ha cluster' /etc/hosts || true
    echo 'swap:';            swapon --show || echo '  swap OFF (OK)'
    echo 'NTP:';              timedatectl | grep -E 'NTP|synchron' || true
    echo 'sysctl:';           sysctl vm.swappiness fs.file-max 2>/dev/null
  " 2>&1 | tee -a "${LOG}"
done

log "==> Bước 2 hoàn tất. Tiếp theo: bash demo/03-group-replication/03-install-mysql.sh"
