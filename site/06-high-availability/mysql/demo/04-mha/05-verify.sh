#!/usr/bin/env bash
# 05-verify.sh — Verify MHA topology: masterha_check_ssh + masterha_check_repl + masterha_check_status.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RESULTS="${SCRIPT_DIR}/results"
LOG="${RESULTS}/05-verify.log"
mkdir -p "${RESULTS}"
: > "${LOG}"

# shellcheck disable=SC1091
source "${REPO_ROOT}/scripts/common/env.sh"

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" | tee -a "${LOG}"; }
pass=true
mark_fail() { pass=false; printf '[FAIL] %s\n' "$*" | tee -a "${LOG}"; }
mark_ok()   { printf '[ OK ] %s\n' "$*" | tee -a "${LOG}"; }

cd "${REPO_ROOT}/vagrant"

log "================ VERIFY MHA ================"

# 1 — masterha_check_ssh
log "--- masterha_check_ssh ---"
SSH_OUT=$(vagrant ssh mgmt -c "sudo masterha_check_ssh --conf=/etc/mha/${CLUSTER_NAME}.cnf 2>&1" || echo "EXIT_NONZERO")
echo "${SSH_OUT}" | tee -a "${LOG}"
if echo "${SSH_OUT}" | grep -q "All SSH connection tests passed successfully"; then
  mark_ok "SSH topology OK"
else
  mark_fail "SSH check fail — kiểm tra 02-ssh-trust.sh"
fi

# 2 — masterha_check_repl
log "--- masterha_check_repl ---"
REPL_OUT=$(vagrant ssh mgmt -c "sudo masterha_check_repl --conf=/etc/mha/${CLUSTER_NAME}.cnf 2>&1" || echo "EXIT_NONZERO")
echo "${REPL_OUT}" | tee -a "${LOG}"
if echo "${REPL_OUT}" | grep -q "MySQL Replication Health is OK"; then
  mark_ok "Replication health OK"
else
  mark_fail "Replication check fail"
fi

# 3 — masterha_check_status
log "--- masterha_check_status ---"
ST_OUT=$(vagrant ssh mgmt -c "sudo masterha_check_status --conf=/etc/mha/${CLUSTER_NAME}.cnf 2>&1" || echo "EXIT_NONZERO")
echo "${ST_OUT}" | tee -a "${LOG}"
if echo "${ST_OUT}" | grep -q "PING_OK"; then
  mark_ok "Manager PING_OK"
elif echo "${ST_OUT}" | grep -q "is stopped"; then
  mark_fail "Manager stopped — chạy lại 04-mha-manager-install.sh hoặc start manual"
else
  mark_fail "Status unknown"
fi

log "================ KẾT QUẢ ================"
if $pass; then
  log "VERIFY_PASS=true — MHA sẵn sàng."
  echo "VERIFY_PASS=true" >> "${LOG}"
  exit 0
else
  log "VERIFY_PASS=false — kiểm tra log."
  echo "VERIFY_PASS=false" >> "${LOG}"
  exit 1
fi
