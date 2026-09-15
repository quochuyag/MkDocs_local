#!/usr/bin/env bash
# 08-split-brain-test.sh — Halt 2/3 node để cluster mất quorum.
# Kỳ vọng: node còn lại chuyển sang wsrep_cluster_status=non-Primary và REFUSE write.
# DESTRUCTIVE.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RESULTS="${SCRIPT_DIR}/results"
LOG="${RESULTS}/08-split-brain.log"
mkdir -p "${RESULTS}"
: > "${LOG}"

# shellcheck disable=SC1091
source "${REPO_ROOT}/scripts/common/env.sh"

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" | tee -a "${LOG}"; }

cd "${REPO_ROOT}/vagrant"

mysql_q() {
  local node="$1" sql="$2"
  vagrant ssh "$node" -c "mysql -uroot -p'${MYSQL_ROOT_PWD}' -N -B -e \"$sql\" 2>/dev/null" | tr -d '\r'
}

log "================ SPLIT-BRAIN TEST ================"
log "==> Trước test: 3 node Synced"

# Halt node2 + node3
log "==> Halt --force node2 và node3"
vagrant halt --force node2 2>&1 | tee -a "${LOG}"
vagrant halt --force node3 2>&1 | tee -a "${LOG}"

# Đợi cluster reconfigure
log "==> Đợi 15s cho node1 detect node2+node3 mất"
sleep 15

# Verify node1 thấy non-Primary
log "==> Trạng thái wsrep trên node1 sau khi 2 node mất:"
vagrant ssh node1 -c "
  mysql -uroot -p'${MYSQL_ROOT_PWD}' -e \"
    SHOW STATUS WHERE Variable_name IN
     ('wsrep_cluster_size','wsrep_cluster_status','wsrep_local_state_comment','wsrep_ready');\"
" 2>&1 | tee -a "${LOG}"

CS=$(mysql_q node1 "SHOW STATUS LIKE 'wsrep_cluster_status';" | awk '{print $2}')
RDY=$(mysql_q node1 "SHOW STATUS LIKE 'wsrep_ready';" | awk '{print $2}')
log "==> wsrep_cluster_status=${CS}  wsrep_ready=${RDY}"

# Thử insert — kỳ vọng FAIL
log "==> Thử INSERT trên node1 (kỳ vọng: error 'WSREP has not yet prepared node for application use')"
RES=$(vagrant ssh node1 -c "mysql -uroot -p'${MYSQL_ROOT_PWD}' -e \"INSERT INTO smoke_db.t(src,val) VALUES('node1','split-brain-probe');\" 2>&1" | tr -d '\r' || true)
echo "${RES}" | tee -a "${LOG}"

if echo "${RES}" | grep -qiE "WSREP|read-only|primary"; then
  log "[OK] node1 đã block write (cluster non-Primary đúng kỳ vọng)"
else
  log "[WARN] node1 vẫn chấp nhận write? Output: ${RES}"
fi

log ""
log "==> Recovery: power-on node2 + node3 để cluster phục hồi"
log "    vagrant up node2 node3"
log "    Sau đó các node tự rejoin (IST nếu data delta nhỏ, SST nếu lớn)."
log ""
log "==> Trong trường hợp THẬT cần force quorum (khi chỉ còn 1 node thật sự):"
log "    mysql -uroot -p... -e \"SET GLOBAL wsrep_provider_options='pc.bootstrap=true';\""
log "    (CẨN THẬN: có thể gây split-brain nếu 2 node kia thực ra vẫn sống)"
