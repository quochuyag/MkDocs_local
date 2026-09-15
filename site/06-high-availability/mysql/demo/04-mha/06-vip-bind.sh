#!/usr/bin/env bash
# 06-vip-bind.sh — Gắn VIP 192.168.10.100 lên master ban đầu (node1) để app dùng.
# Trong production: dùng Keepalived/Pacemaker. Đây là demo nên dùng `ip addr add` thuần.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RESULTS="${SCRIPT_DIR}/results"
LOG="${RESULTS}/06-vip-bind.log"
mkdir -p "${RESULTS}"
: > "${LOG}"

# shellcheck disable=SC1091
source "${REPO_ROOT}/scripts/common/env.sh"

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" | tee -a "${LOG}"; }

cd "${REPO_ROOT}/vagrant"

# Tìm interface có IP private (192.168.10.x) — thường là eth1 (Vagrantfile config)
log "==> Tìm interface chứa private IP trên node1"
IFACE=$(vagrant ssh node1 -c "ip -4 -o addr show | awk '\$4 ~ /^192\\.168\\.10\\./{print \$2; exit}'" | tr -d '\r')
log "    iface=${IFACE}"
if [[ -z "${IFACE}" ]]; then
  log "[FAIL] Không tìm được interface private trên node1"
  exit 1
fi

log "==> Gắn VIP ${VIP}/24 lên node1:${IFACE}"
vagrant ssh node1 -c "
  if ip -4 addr show ${IFACE} | grep -q '${VIP}/24'; then
    echo '    VIP đã có, skip'
  else
    sudo ip addr add ${VIP}/24 dev ${IFACE}
    sudo arping -U -I ${IFACE} ${VIP} -c 3 || true
    echo '    VIP đã gắn'
  fi
  ip -4 addr show ${IFACE} | grep 'inet '
" 2>&1 | tee -a "${LOG}"

log "==> Test VIP reachable từ mgmt"
# Dùng repl@'%' (đã có sẵn từ demo 01) cho mysql probe — root chỉ accept @'localhost'
# nên test cũ luôn báo [WARN] không có nghĩa. repl có grant USAGE => SELECT @@hostname OK.
vagrant ssh mgmt -c "
  ping -c 2 -W 2 ${VIP} && echo '    PING OK'
  out=\$(mysql -u${REPL_USER} -p'${REPL_PWD}' -h${VIP} -N -B -e 'SELECT @@hostname;' 2>&1) \
    && echo \"    MySQL via VIP OK → @@hostname=\${out}\" \
    || echo \"    [FAIL] MySQL connect via VIP: \${out}\"
" 2>&1 | tee -a "${LOG}"

log "==> Bước 6 hoàn tất. VIP đang trỏ về node1."
log "    Để test failover: bash demo/04-mha/07-failover-test.sh"
