#!/usr/bin/env bash
# 05-snapshot-clean.sh — Optional: snapshot "clean" cho 4 VMs để rollback nhanh.
# Hữu ích khi test các demo HA destructive (failover, split-brain) và muốn reset.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RESULTS="${SCRIPT_DIR}/results"
LOG="${RESULTS}/05-snapshot-clean.log"
mkdir -p "${RESULTS}"

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" | tee -a "${LOG}"; }

cd "${REPO_ROOT}/vagrant"

NODES=(node1 node2 node3 mgmt)
SNAPSHOT="${SNAPSHOT:-clean}"

log "==> Snapshot tên '${SNAPSHOT}' cho 4 VMs (có thể mất 1-2 phút)"
for N in "${NODES[@]}"; do
  # Xoá snapshot cũ cùng tên nếu có, để tạo lại
  HAS=$(vagrant snapshot list "$N" 2>/dev/null | grep -c "^${SNAPSHOT}\$" || true)
  if [[ "$HAS" -gt "0" ]]; then
    log "    [${N}] snapshot '${SNAPSHOT}' đã tồn tại — xoá"
    vagrant snapshot delete "$N" "${SNAPSHOT}" 2>&1 | tee -a "${LOG}" || true
  fi
  log "    [${N}] snapshot save '${SNAPSHOT}'"
  vagrant snapshot save "$N" "${SNAPSHOT}" 2>&1 | tee -a "${LOG}"
done

log "==> Liệt kê tất cả snapshots"
for N in "${NODES[@]}"; do
  log "    --- ${N} ---"
  vagrant snapshot list "$N" 2>&1 | tee -a "${LOG}" || true
done

log "==> Để rollback toàn bộ 4 VMs về snapshot '${SNAPSHOT}':"
log "    for N in node1 node2 node3 mgmt; do vagrant snapshot restore \$N ${SNAPSHOT}; done"
