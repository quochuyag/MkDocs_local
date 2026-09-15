#!/usr/bin/env bash
# 05-join-node2-node3.sh — Join node2, node3 vào cluster qua SST (xtrabackup stream).
# Gọi upstream scripts/galera/join-node.sh.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RESULTS="${SCRIPT_DIR}/results"
LOG="${RESULTS}/05-join-node2-node3.log"
mkdir -p "${RESULTS}"

# shellcheck disable=SC1091
source "${REPO_ROOT}/scripts/common/env.sh"

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" | tee -a "${LOG}"; }

cd "${REPO_ROOT}/vagrant"

# Join tuần tự (an toàn hơn parallel)
for N in node2 node3; do
  log "==> [${N}] systemctl start mysql → tự SST từ donor (có thể mất 1-3 phút)"
  vagrant ssh "${N}" -c "sudo bash /vagrant/scripts/galera/join-node.sh" 2>&1 | tee -a "${LOG}"
done

# Chuyển node1 từ mysql@bootstrap.service sang mysql.service.
# Lý do: bootstrap dùng /etc/default/mysql.bootstrap (wsrep_cluster_address=gcomm://)
# chỉ để init cluster. Khi đã có 2 nodes joined → primary view, node1 nên trở thành
# regular member để verify check `systemctl is-active mysql` OK và rolling restart sau này
# không phải đoán xem node nào đang ở bootstrap mode.
log "==> Promote node1 từ mysql@bootstrap.service → mysql.service (rejoin existing cluster)"
vagrant ssh node1 -c "
  sudo systemctl stop mysql@bootstrap.service
  sudo systemctl reset-failed mysql@bootstrap.service 2>/dev/null || true
  sudo systemctl start mysql
  # Đợi node1 sync lại với cluster (IST từ node2/3 vì grastate hợp lệ)
  for i in \$(seq 1 30); do
    STATE=\$(mysql -uroot -p'${MYSQL_ROOT_PWD}' -NB -e \"SHOW STATUS LIKE 'wsrep_local_state_comment'\" 2>/dev/null | awk '{print \$2}')
    echo \"   node1 state=\$STATE\"
    [[ \"\$STATE\" == \"Synced\" ]] && break
    sleep 2
  done
" 2>&1 | tee -a "${LOG}"

log "==> Đợi cluster ổn định 5s"
sleep 5

log "==> wsrep status trên cả 3 nodes"
for N in node1 node2 node3; do
  log "--- ${N} ---"
  vagrant ssh "$N" -c "
    mysql -uroot -p'${MYSQL_ROOT_PWD}' -e \"
      SHOW STATUS WHERE Variable_name IN
       ('wsrep_cluster_size','wsrep_cluster_status','wsrep_local_state_comment','wsrep_ready','wsrep_connected');\"
  " 2>&1 | tee -a "${LOG}"
done

log "==> Bước 5 hoàn tất. Tiếp theo: bash demo/06-galera/06-verify.sh"
