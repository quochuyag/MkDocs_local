#!/usr/bin/env bash
# 04-verify.sh — Verify lab baseline. Read-only.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RESULTS="${SCRIPT_DIR}/results"
LOG="${RESULTS}/04-verify.log"
mkdir -p "${RESULTS}"
: > "${LOG}"

# shellcheck disable=SC1091
source "${REPO_ROOT}/scripts/common/env.sh"

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" | tee -a "${LOG}"; }
pass=true
mark_fail() { pass=false; printf '[FAIL] %s\n' "$*" | tee -a "${LOG}"; }
mark_ok()   { printf '[ OK ] %s\n' "$*" | tee -a "${LOG}"; }

cd "${REPO_ROOT}/vagrant"

NODES=(node1 node2 node3 mgmt)

log "================ VERIFY VAGRANT LAB ================"

# 1 — VM running
for N in "${NODES[@]}"; do
  STATE=$(vagrant status "$N" --machine-readable 2>/dev/null | awk -F, -v n="$N" '$2==n && $3=="state"{print $4; exit}')
  [[ "$STATE" == "running" ]] && mark_ok "[$N] running" || mark_fail "[$N] state=$STATE"
done

# 2 — Ping nội bộ
for N in "${NODES[@]}"; do
  for T in "${NODES[@]}"; do
    [[ "$N" == "$T" ]] && continue
    RES=$(vagrant ssh "$N" -c "ping -c1 -W2 ${T} >/dev/null 2>&1 && echo OK || echo FAIL" | tr -d '\r' | tail -n1)
    [[ "$RES" == "OK" ]] && mark_ok "[$N -> $T] ping OK" || mark_fail "[$N -> $T] ping $RES"
  done
done

# 3 — /etc/hosts
for N in "${NODES[@]}"; do
  CNT=$(vagrant ssh "$N" -c "grep -E 'node1|node2|node3|mgmt' /etc/hosts | wc -l" | tr -d '\r' | tail -n1)
  [[ "$CNT" -ge "4" ]] && mark_ok "[$N] /etc/hosts có ≥4 entries (${CNT})" || mark_fail "[$N] /etc/hosts thiếu entries (${CNT})"
done

# 4 — swap off
for N in "${NODES[@]}"; do
  SWAP=$(vagrant ssh "$N" -c "swapon --show 2>/dev/null | wc -l" | tr -d '\r' | tail -n1)
  [[ "$SWAP" == "0" ]] && mark_ok "[$N] swap OFF" || mark_fail "[$N] swap still ON ($SWAP entries)"
done

# 5 — NTP synced
for N in "${NODES[@]}"; do
  S=$(vagrant ssh "$N" -c "timedatectl 2>/dev/null | awk -F': ' '/synchron/{print \$2}' | tr -d ' \r'" | tail -n1)
  [[ "$S" == "yes" ]] && mark_ok "[$N] NTP synchronized" || mark_fail "[$N] NTP=$S"
done

# 6 — sysctl
for N in "${NODES[@]}"; do
  SW=$(vagrant ssh "$N" -c "sysctl -n vm.swappiness 2>/dev/null" | tr -d '\r' | tail -n1)
  FM=$(vagrant ssh "$N" -c "sysctl -n fs.file-max 2>/dev/null" | tr -d '\r' | tail -n1)
  [[ "$SW" -le "10" ]] && mark_ok "[$N] vm.swappiness=$SW" || mark_fail "[$N] vm.swappiness=$SW (cần ≤10)"
  [[ "$FM" -ge "1048576" ]] && mark_ok "[$N] fs.file-max=$FM" || mark_fail "[$N] fs.file-max=$FM"
done

# 7 — SSH trust giữa vagrant users
for N in "${NODES[@]}"; do
  for T in "${NODES[@]}"; do
    [[ "$N" == "$T" ]] && continue
    R=$(vagrant ssh "$N" -c "ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 ${T} hostname 2>/dev/null" | tr -d '\r' | tail -n1)
    [[ "$R" == "$T" ]] && mark_ok "[$N -> $T] ssh OK" || mark_fail "[$N -> $T] ssh fail (got: '$R')"
  done
done

log "================ KẾT QUẢ ================"
if $pass; then
  log "VERIFY_PASS=true — lab sẵn sàng cho bất kỳ demo HA nào"
  echo "VERIFY_PASS=true" >> "${LOG}"
  exit 0
else
  log "VERIFY_PASS=false"
  echo "VERIFY_PASS=false" >> "${LOG}"
  exit 1
fi
