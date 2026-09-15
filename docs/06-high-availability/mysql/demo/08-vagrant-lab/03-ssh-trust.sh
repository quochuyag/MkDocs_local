#!/usr/bin/env bash
# 03-ssh-trust.sh — Setup shared SSH key giữa 4 VMs (vagrant user, KHÔNG phải root).
# Dùng provisioner 'ssh-trust' đã định nghĩa trong Vagrantfile.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RESULTS="${SCRIPT_DIR}/results"
LOG="${RESULTS}/03-ssh-trust.log"
mkdir -p "${RESULTS}"

# shellcheck disable=SC1091
source "${REPO_ROOT}/scripts/common/env.sh"

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" | tee -a "${LOG}"; }

cd "${REPO_ROOT}/vagrant"

NODES=(node1 node2 node3 mgmt)

# Đảm bảo shared SSH key đã sinh (1 cặp dùng chung cho cluster)
if [[ ! -f provision/cluster_id_rsa ]]; then
  log "==> Sinh SSH key dùng chung"
  bash provision/generate-ssh-key.sh 2>&1 | tee -a "${LOG}"
fi

for N in "${NODES[@]}"; do
  log "==> [${N}] inject shared key (provisioner ssh-trust)"
  vagrant provision "${N}" --provision-with ssh-trust 2>&1 | tee -a "${LOG}"
done

log "==> Verify vagrant user SSH passwordless cross VMs"
for N in "${NODES[@]}"; do
  for T in "${NODES[@]}"; do
    [[ "$N" == "$T" ]] && continue
    RES=$(vagrant ssh "$N" -c "ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 ${T} hostname 2>/dev/null" | tr -d '\r' | tail -n1)
    if [[ "${RES}" == "${T}" ]]; then
      log "    [${N} -> ${T}] OK"
    else
      log "    [${N} -> ${T}] FAIL (got: '${RES}')"
    fi
  done
done

log "==> Bước 3 hoàn tất. Tiếp theo: bash demo/08-vagrant-lab/04-verify.sh"
