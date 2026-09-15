#!/usr/bin/env bash
# 01-vagrant-up.sh — Spin up 4 VMs Ubuntu 22.04 cho lab Group Replication thuần.
# Chạy trên HOST (Windows Git Bash / WSL / macOS / Linux).
# Idempotent: VMs đã 'running' thì skip.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RESULTS="${SCRIPT_DIR}/results"
LOG="${RESULTS}/01-vagrant-up.log"
mkdir -p "${RESULTS}"

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" | tee -a "${LOG}"; }

log "==> Kiểm tra prerequisites"
command -v vagrant   >/dev/null || { echo "ERROR: chưa cài vagrant"; exit 1; }
command -v VBoxManage >/dev/null || { echo "ERROR: chưa cài VirtualBox"; exit 1; }
vagrant --version    | tee -a "${LOG}"
VBoxManage --version | tee -a "${LOG}"

export VAGRANT_DEFAULT_PROVIDER="virtualbox"
log "==> VAGRANT_DEFAULT_PROVIDER=${VAGRANT_DEFAULT_PROVIDER}"

cd "${REPO_ROOT}/vagrant"

log "==> Sinh SSH key dùng chung cho cluster (idempotent)"
if [[ ! -f provision/cluster_id_rsa ]]; then
  bash provision/generate-ssh-key.sh | tee -a "${LOG}"
else
  log "    đã có provision/cluster_id_rsa, bỏ qua"
fi

# --- Reset lab: mỗi demo có VMs riêng, KHÔNG share state với demo khác.
# Default = destroy lab cũ. Set KEEP_VMS=1 để skip (debug / iterate cùng demo nhanh).
if [[ "${KEEP_VMS:-0}" == "1" ]]; then
  log "==> KEEP_VMS=1 → bỏ qua destroy, dùng state VMs hiện tại"
else
  log "==> Reset lab: vagrant destroy -f (mọi state cũ sẽ bị xoá)"
  vagrant destroy -f 2>&1 | tee -a "${LOG}" || log "    (chưa có VM hoặc destroy lỗi nhẹ — tiếp tục)"
fi

VMS=(node1 node2 node3 mgmt)

vm_state() {
  vagrant status "$1" --machine-readable 2>/dev/null \
    | awk -F, -v n="$1" '$2==n && $3=="state"{print $4; exit}'
}

bring_up() {
  local vm="$1" tries="${2:-2}" attempt=1
  while (( attempt <= tries )); do
    local state; state=$(vm_state "$vm")
    if [[ "$state" == "running" ]]; then
      log "    ${vm}: đã running (skip)"
      return 0
    fi
    log "    ${vm}: attempt ${attempt}/${tries} (state=${state:-unknown})"
    if vagrant up "$vm" --provider=virtualbox --no-destroy-on-error 2>&1 | tee -a "${LOG}"; then
      state=$(vm_state "$vm")
      if [[ "$state" == "running" ]]; then return 0; fi
    fi
    log "    ${vm}: chưa lên, đợi 10s rồi thử lại"
    sleep 10
    attempt=$((attempt+1))
  done
  log "    ${vm}: FAIL sau ${tries} lần"
  return 1
}

log "==> vagrant up (tuần tự, có retry — boot_timeout=1200s từ Vagrantfile)"
for vm in "${VMS[@]}"; do
  log "==> bring up ${vm}"
  bring_up "$vm" 2 || {
    log "[FAIL] ${vm} không boot được. Xem log + chạy 'vagrant ssh-config ${vm}' để debug."
    exit 1
  }
done

log "==> Kiểm tra trạng thái VM"
vagrant status 2>&1 | tee -a "${LOG}"

log "==> Test connectivity giữa các node"
for HOST in node1 node2 node3 mgmt; do
  log "    ${HOST} <-> các node khác:"
  vagrant ssh "${HOST}" -c "for T in node1 node2 node3 mgmt; do \
    [ \"\$T\" = \"\$(hostname)\" ] && continue; \
    ping -c1 -W2 \$T >/dev/null && echo \"    \$(hostname) -> \$T OK\" || echo \"    \$(hostname) -> \$T FAIL\"; \
  done" 2>&1 | tee -a "${LOG}"
done

log "==> Bước 1 hoàn tất. Tiếp theo: bash demo/03-group-replication/02-prepare-os.sh"
