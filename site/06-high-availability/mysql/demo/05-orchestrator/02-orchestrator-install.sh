#!/usr/bin/env bash
# 02-orchestrator-install.sh — Cài Orchestrator trên mgmt + backend DB + user trên 3 DB nodes.
# Gọi upstream scripts/orchestrator/orchestrator-setup.sh.
#
# LƯU Ý: upstream script đã cần MySQL local trên mgmt để làm backend store.
#        Demo 01 đã chạy `install-mysql` cho mgmt (qua common-prep + install-mysql),
#        nên MySQL local trên mgmt đã sẵn sàng.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RESULTS="${SCRIPT_DIR}/results"
LOG="${RESULTS}/02-orchestrator-install.log"
mkdir -p "${RESULTS}"

# shellcheck disable=SC1091
source "${REPO_ROOT}/scripts/common/env.sh"

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" | tee -a "${LOG}"; }

cd "${REPO_ROOT}/vagrant"

# Đảm bảo SSH trust giữa mgmt ↔ nodes (orchestrator-setup.sh chạy GRANT trên DB nodes
# qua ssh root@nodeN vì root MySQL chỉ accept @'localhost').
log "==> Đảm bảo ssh-trust provisioner đã chạy trên 4 VMs"
NEED_TRUST=0
for V in node1 node2 node3 mgmt; do
  HAS=$(vagrant ssh "$V" -c "sudo test -f /root/.ssh/id_rsa && echo yes || echo no" 2>/dev/null | tr -d '\r' | tail -n1)
  [[ "$HAS" != "yes" ]] && { NEED_TRUST=1; break; }
done
if [[ "$NEED_TRUST" == "1" ]]; then
  log "    chạy: vagrant provision --provision-with ssh-trust"
  vagrant provision --provision-with ssh-trust 2>&1 | tee -a "${LOG}"
fi

# Đảm bảo mgmt có MySQL local (Orchestrator backend store)
# LƯU Ý: Vagrantfile chỉ register provisioner `install-mysql` cho VM role=db.
# Trên mgmt (role=mgmt) provisioner KHÔNG tồn tại → `vagrant provision mgmt
# --provision-with install-mysql` là no-op. Phải chạy script install trực tiếp
# qua `vagrant ssh mgmt`.
log "==> [mgmt] Đảm bảo MySQL local sẵn sàng (backend cho orchestrator schema)"
HAS_MYSQL=$(vagrant ssh mgmt -c "command -v mysql >/dev/null && command -v mysqld >/dev/null && echo yes || echo no" | tr -d '\r' | tail -n1)
if [[ "${HAS_MYSQL}" != "yes" ]]; then
  log "    MySQL chưa có trên mgmt → chạy /vagrant/scripts/common/01-install-mysql.sh"
  vagrant ssh mgmt -c "sudo bash /vagrant/scripts/common/01-install-mysql.sh" 2>&1 | tee -a "${LOG}"
  # Verify lại sau khi cài
  HAS_MYSQL=$(vagrant ssh mgmt -c "command -v mysql >/dev/null && command -v mysqld >/dev/null && echo yes || echo no" | tr -d '\r' | tail -n1)
  if [[ "${HAS_MYSQL}" != "yes" ]]; then
    log "[FATAL] Cài MySQL trên mgmt thất bại. Xem ${LOG}."
    exit 1
  fi
fi
log "    MySQL trên mgmt: OK"

log "==> [mgmt] Cài Orchestrator + backend + tạo user 'orchestrator' trên 3 DB nodes"
vagrant ssh mgmt -c "sudo bash /vagrant/scripts/orchestrator/orchestrator-setup.sh" 2>&1 | tee -a "${LOG}"

log "==> Đợi 5s cho service orchestrator stable"
sleep 5

log "==> [mgmt] Verify service + HTTP API"
vagrant ssh mgmt -c "
  sudo systemctl is-active orchestrator
  sudo ss -tlnp | grep ':3000 ' || true
  curl -fsS -u admin:'${ADMIN_PWD}' http://127.0.0.1:3000/api/health 2>/dev/null | head -c 200 || echo '(curl fail)'
  echo
" 2>&1 | tee -a "${LOG}"

log "==> Web UI: http://${MGMT_IP}:3000 (login: admin / ${ADMIN_PWD})"
log "==> Bước 2 hoàn tất. Tiếp theo: bash demo/05-orchestrator/03-discover-topology.sh"
