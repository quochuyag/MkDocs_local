#!/usr/bin/env bash
# 09-rollback.sh — Tháo Galera. MODE=soft|hard.
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
  exit 0
fi

log "==> SOFT rollback: stop mysql + drop smoke_db + uninstall PXC (giữ VMs)"

for N in node1 node2 node3; do
  STATE=$(vagrant status "$N" --machine-readable 2>/dev/null | awk -F, -v n="$N" '$2==n && $3=="state"{print $4; exit}')
  [[ "$STATE" != "running" ]] && { log "    skip ${N} (state=${STATE})"; continue; }
  log "--- ${N}: stop mysql + uninstall PXC ---"
  vagrant ssh "$N" -c "
    sudo bash -c '
      systemctl stop mysql 2>/dev/null || true
      systemctl stop mysql@bootstrap.service 2>/dev/null || true
      apt-get remove --purge -y \"percona-xtradb-cluster*\" 2>/dev/null || true
      rm -rf /var/lib/mysql /etc/mysql/mysql.conf.d/zz-pxc.cnf /etc/percona-xtradb-cluster.conf.d/zz-pxc.cnf
    '
  " 2>&1 | tee -a "${LOG}"
done

log "==> Soft rollback xong. VMs vẫn chạy nhưng đã sạch PXC."
log "    Demo lại: bash demo/06-galera/03-install-pxc.sh"
log "    Hard: MODE=hard bash demo/06-galera/09-rollback.sh"
