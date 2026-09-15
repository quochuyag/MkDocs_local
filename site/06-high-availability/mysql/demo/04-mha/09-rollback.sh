#!/usr/bin/env bash
# 09-rollback.sh — Tháo MHA. MODE=soft (default, giữ replication & VMs) | hard (destroy VMs).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RESULTS="${SCRIPT_DIR}/results"
LOG="${RESULTS}/09-rollback.log"
mkdir -p "${RESULTS}"

# shellcheck disable=SC1091
source "${REPO_ROOT}/scripts/common/env.sh"

MODE="${MODE:-soft}"
log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" | tee -a "${LOG}"; }

cd "${REPO_ROOT}/vagrant"

if [[ "${MODE}" == "hard" ]]; then
  log "==> HARD rollback: destroy toàn bộ VMs"
  vagrant destroy -f 2>&1 | tee -a "${LOG}"
  rm -f provision/cluster_id_rsa provision/cluster_id_rsa.pub
  log "==> Hoàn tất."
  exit 0
fi

log "==> SOFT rollback: stop manager + xoá MHA (giữ replication & smoke_db)"

log "--- mgmt: stop manager + uninstall ---"
vagrant ssh mgmt -c "
  sudo bash -c '
    # Stop manager
    masterha_stop --conf=/etc/mha/${CLUSTER_NAME}.cnf 2>/dev/null || true
    # Kill nếu còn process
    pkill -f masterha_manager 2>/dev/null || true
    # Uninstall package
    dpkg -P mha4mysql-manager 2>/dev/null || true
    rm -rf /etc/mha /var/log/mha /var/lib/mha
  '
" 2>&1 | tee -a "${LOG}"

log "--- 3 nodes: uninstall mha4mysql-node + drop user mha ---"
for N in node1 node2 node3; do
  STATE=$(vagrant status "$N" --machine-readable 2>/dev/null | awk -F, -v n="$N" '$2==n && $3=="state"{print $4; exit}')
  [[ "$STATE" != "running" ]] && { log "    skip ${N} (state=${STATE})"; continue; }
  vagrant ssh "$N" -c "
    sudo dpkg -P mha4mysql-node 2>/dev/null || true
    mysql -uroot -p'${MYSQL_ROOT_PWD}' -e \"DROP USER IF EXISTS 'mha'@'%'; FLUSH PRIVILEGES;\" 2>/dev/null || true
  " 2>&1 | tee -a "${LOG}"
done

log "--- node1: gỡ VIP ${VIP} (nếu còn) ---"
vagrant ssh node1 -c "
  IFACE=\$(ip -4 -o addr show | awk '\$4 ~ /^192\\.168\\.10\\./{print \$2; exit}')
  if [ -n \"\$IFACE\" ] && ip -4 addr show \"\$IFACE\" | grep -q '${VIP}/24'; then
    sudo ip addr del ${VIP}/24 dev \"\$IFACE\"
    echo '    VIP gỡ'
  fi
" 2>&1 | tee -a "${LOG}" || true

log "==> Soft rollback xong. Demo 01 (replication) vẫn nguyên."
log "    Để demo MHA lại: bash demo/04-mha/03-mha-node-install.sh"
log "    Hard rollback (destroy VMs): MODE=hard bash demo/04-mha/09-rollback.sh"
