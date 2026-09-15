#!/usr/bin/env bash
# 01-vagrant-up.sh — Spin up 4 VMs Ubuntu 22.04 cho lab Galera (PXC).
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
# Trên Windows Git Bash, VBoxManage có thể không trong PATH — auto-detect.
if ! command -v VBoxManage >/dev/null; then
  for P in "/c/Program Files/Oracle/VirtualBox" "/c/Program Files (x86)/Oracle/VirtualBox"; do
    if [[ -x "${P}/VBoxManage.exe" ]]; then
      export PATH="${P}:${PATH}"
      break
    fi
  done
fi
command -v VBoxManage >/dev/null \
  || [[ -x "/c/Program Files/Oracle/VirtualBox/VBoxManage.exe" ]] \
  || { echo "ERROR: chưa cài VirtualBox (VBoxManage không tìm thấy)"; exit 1; }
vagrant --version    | tee -a "${LOG}"
( VBoxManage --version 2>/dev/null || "/c/Program Files/Oracle/VirtualBox/VBoxManage.exe" --version ) | tee -a "${LOG}"

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
  # Pre-clean: VBox đôi khi để lại VM <inaccessible> sau khi clone fail
  # (VERR_ALREADY_EXISTS khi rename temp_clone_* → mysql-ha-*).
  # `vagrant destroy` không recover được state này → phải unregister thủ công
  # qua VBoxManage trước, rồi xoá vagrant state để vagrant clone lại tươi.
  log "==> Pre-clean: phát hiện và xử lý VMs inaccessible (nếu có)"
  if command -v VBoxManage >/dev/null; then
    # liệt kê VMs có format `"<inaccessible>" {uuid}` và lấy UUID
    INACCESSIBLE_UUIDS=$(VBoxManage list vms 2>/dev/null \
      | awk -F'[{}]' '/<inaccessible>/{print $2}')
    if [[ -n "${INACCESSIBLE_UUIDS}" ]]; then
      for uuid in ${INACCESSIBLE_UUIDS}; do
        log "    unregister VM inaccessible: ${uuid}"
        VBoxManage unregistervm "${uuid}" 2>&1 | tee -a "${LOG}" || true
      done
      # Nếu vagrant state đang tham chiếu UUID inaccessible thì cũng phải xoá
      # (vagrant đọc file id để tìm VM; nếu UUID đã bị unregister, vagrant sẽ
      # vẫn report state=inaccessible đến khi xoá file đó).
      VAGRANT_DIR_LOCAL="${REPO_ROOT}/vagrant"
      if [[ -d "${VAGRANT_DIR_LOCAL}/.vagrant/machines" ]]; then
        for state_dir in "${VAGRANT_DIR_LOCAL}/.vagrant/machines"/*/virtualbox; do
          [[ -d "${state_dir}" ]] || continue
          state_uuid=$(cat "${state_dir}/id" 2>/dev/null || echo "")
          if [[ -n "${state_uuid}" ]] && echo "${INACCESSIBLE_UUIDS}" | grep -qi "${state_uuid}"; then
            log "    xoá vagrant state mồ côi: ${state_dir} (UUID ${state_uuid})"
            rm -rf "${state_dir}"
          fi
        done
      fi
    else
      log "    không có VM inaccessible"
    fi
  fi

  log "==> Reset lab: vagrant destroy -f (mọi state cũ sẽ bị xoá)"
  vagrant destroy -f 2>&1 | tee -a "${LOG}" || log "    (chưa có VM hoặc destroy lỗi nhẹ — tiếp tục)"

  # Post-destroy: VBox `vagrant destroy` xoá registration nhưng đôi khi để lại
  # orphan FS folders trong default machine folder (linked-clone Snapshots/ folder).
  # Lần clone tiếp theo sẽ fail "VERR_ALREADY_EXISTS" khi rename temp_clone_* về
  # tên đích đã tồn tại. Cũng có khi temp_clone_* tự nó bị register-stuck.
  log "==> Post-destroy: dọn orphan folders + temp_clone_* trong VBox storage"
  if command -v VBoxManage >/dev/null; then
    DEFAULT_VM_DIR=$(VBoxManage list systemproperties 2>/dev/null \
      | sed -n 's/^Default machine folder:[[:space:]]*//p')
    # Convert Windows path `D:\...` → POSIX `D:/...` cho bash filesystem ops
    DEFAULT_VM_DIR_BASH=$(echo "${DEFAULT_VM_DIR}" | sed 's#\\#/#g')

    if [[ -n "${DEFAULT_VM_DIR_BASH}" && -d "${DEFAULT_VM_DIR_BASH}" ]]; then
      # Lấy danh sách VMs còn register (chỉ tên, từ format `"name" {uuid}`)
      REGISTERED_NAMES=$(VBoxManage list vms 2>/dev/null | awk -F'"' 'NF>=2{print $2}')

      # Unregister bất kỳ VM `temp_clone_*` mồ côi
      # Dùng <(...) thay vì pipe để tránh pipefail + set -e khi grep no-match (exit 1)
      while IFS= read -r tcname; do
        [[ -z "${tcname}" ]] && continue
        log "    unregister VM mồ côi: ${tcname}"
        VBoxManage unregistervm "${tcname}" 2>&1 | tee -a "${LOG}" || true
      done < <(echo "${REGISTERED_NAMES}" | { grep -E '^temp_clone_' || true; })

      # Refresh sau khi unregister
      REGISTERED_NAMES=$(VBoxManage list vms 2>/dev/null | awk -F'"' 'NF>=2{print $2}')

      # Xoá orphan folders: mysql-ha-{node1,node2,node3,mgmt} không có VM register tương ứng
      for v in mysql-ha-node1 mysql-ha-node2 mysql-ha-node3 mysql-ha-mgmt; do
        folder="${DEFAULT_VM_DIR_BASH}/${v}"
        if [[ -d "${folder}" ]] && ! echo "${REGISTERED_NAMES}" | grep -qx "${v}"; then
          log "    xoá orphan folder: ${folder}"
          rm -rf "${folder}" 2>&1 | tee -a "${LOG}" \
            || log "    WARNING: không xoá hết được ${folder} (file đang lock?)"
        fi
      done

      # Xoá luôn temp_clone_* folders không gắn VM nào
      for tmp in "${DEFAULT_VM_DIR_BASH}"/temp_clone_*; do
        [[ -d "${tmp}" ]] || continue
        bn=$(basename "${tmp}")
        if ! echo "${REGISTERED_NAMES}" | grep -qx "${bn}"; then
          log "    xoá temp_clone mồ côi: ${tmp}"
          rm -rf "${tmp}" 2>&1 | tee -a "${LOG}" \
            || log "    WARNING: không xoá hết được ${tmp}"
        fi
      done
    else
      log "    (không lấy được Default machine folder, skip cleanup)"
    fi

    # Dọn vagrant state mồ côi: machine/<vm>/virtualbox/id trỏ UUID không còn
    # register → vagrant up sẽ báo state=inaccessible. Xoá để vagrant clone fresh.
    REGISTERED_UUIDS=$(VBoxManage list vms 2>/dev/null \
      | awk -F'[{}]' 'NF>=2{print tolower($2)}')
    VAGRANT_DIR_LOCAL="${REPO_ROOT}/vagrant"
    if [[ -d "${VAGRANT_DIR_LOCAL}/.vagrant/machines" ]]; then
      for state_dir in "${VAGRANT_DIR_LOCAL}/.vagrant/machines"/*/virtualbox; do
        [[ -d "${state_dir}" ]] || continue
        [[ -f "${state_dir}/id" ]] || continue
        state_uuid=$(tr 'A-Z' 'a-z' < "${state_dir}/id" 2>/dev/null)
        if [[ -n "${state_uuid}" ]] && ! echo "${REGISTERED_UUIDS}" | grep -qx "${state_uuid}"; then
          log "    xoá vagrant state mồ côi: ${state_dir} (UUID ${state_uuid} không còn register)"
          rm -rf "${state_dir}"
        fi
      done
    fi
  fi
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

log "==> Bước 1 hoàn tất. Tiếp theo: bash demo/06-galera/02-prepare-os.sh"
