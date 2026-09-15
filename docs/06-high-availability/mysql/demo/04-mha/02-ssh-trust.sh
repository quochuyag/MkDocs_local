#!/usr/bin/env bash
# 02-ssh-trust.sh — Setup SSH passwordless từ root@mgmt sang root@node1/2/3.
# Đây là tiền đề BẮT BUỘC của MHA: manager dùng SSH (root) để copy binlog từ master cũ.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RESULTS="${SCRIPT_DIR}/results"
LOG="${RESULTS}/02-ssh-trust.log"
mkdir -p "${RESULTS}"

# shellcheck disable=SC1091
source "${REPO_ROOT}/scripts/common/env.sh"

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" | tee -a "${LOG}"; }

cd "${REPO_ROOT}/vagrant"

log "==> [mgmt] Bật root login + sinh SSH key (nếu chưa có)"
vagrant ssh mgmt -c "
  sudo bash -c '
    # Cho phép root login (chỉ trong lab)
    sed -i \"s/^#\\?PermitRootLogin.*/PermitRootLogin yes/\" /etc/ssh/sshd_config
    systemctl reload sshd 2>/dev/null || systemctl reload ssh
    # Tạo root password (lab only)
    echo \"root:${MYSQL_ROOT_PWD}\" | chpasswd
    # Sinh SSH key cho root nếu chưa có
    [ -f /root/.ssh/id_rsa ] || ssh-keygen -t rsa -b 4096 -N \"\" -f /root/.ssh/id_rsa
    cat /root/.ssh/id_rsa.pub
  '
" 2>&1 | tee -a "${LOG}"

# Lấy pubkey của root@mgmt
MGMT_PUB=$(vagrant ssh mgmt -c "sudo cat /root/.ssh/id_rsa.pub" | tr -d '\r' | grep '^ssh-' | head -n1)
if [[ -z "${MGMT_PUB}" ]]; then
  log "[FAIL] Không lấy được pubkey từ root@mgmt"
  exit 1
fi
log "==> Pubkey mgmt (head): ${MGMT_PUB:0:60}..."

log "==> Copy pubkey mgmt vào /root/.ssh/authorized_keys trên 3 DB nodes"
for N in node1 node2 node3; do
  vagrant ssh "$N" -c "
    sudo bash -c '
      sed -i \"s/^#\\?PermitRootLogin.*/PermitRootLogin yes/\" /etc/ssh/sshd_config
      systemctl reload sshd 2>/dev/null || systemctl reload ssh
      mkdir -p /root/.ssh && chmod 700 /root/.ssh
      grep -qxF \"${MGMT_PUB}\" /root/.ssh/authorized_keys 2>/dev/null || echo \"${MGMT_PUB}\" >> /root/.ssh/authorized_keys
      chmod 600 /root/.ssh/authorized_keys
      # disable strict host check cho lab
      cat > /root/.ssh/config <<EOF
Host *
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null
  LogLevel ERROR
EOF
      chmod 600 /root/.ssh/config
    '
  " 2>&1 | tee -a "${LOG}"
done

# Đồng thời mgmt → các node bằng IP (MHA dùng IP trong config)
log "==> [mgmt] Tạo ~/.ssh/config cho root để bỏ strict host check"
vagrant ssh mgmt -c "
  sudo bash -c '
    cat > /root/.ssh/config <<EOF
Host *
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null
  LogLevel ERROR
EOF
    chmod 600 /root/.ssh/config
  '
" 2>&1 | tee -a "${LOG}"

log "==> Test SSH passwordless từ root@mgmt"
for N_IP in "${NODE1_IP}" "${NODE2_IP}" "${NODE3_IP}"; do
  RES=$(vagrant ssh mgmt -c "sudo ssh -o ConnectTimeout=5 root@${N_IP} 'hostname && id -un'" 2>&1 | tail -n2 | tr '\r\n' ' ')
  log "    mgmt -> ${N_IP}: ${RES}"
done

# Full mesh SSH trust giữa các DB nodes — MHA dùng để relay binlog từ master cũ
# sang replica có position cao nhất khi failover. masterha_check_ssh sẽ thử ssh giữa từng cặp.
log "==> [mesh] sinh SSH key root cho từng DB node + thu thập pubkey"
declare -A NODE_PUB
for N in node1 node2 node3; do
  vagrant ssh "$N" -c "
    sudo bash -c '
      [ -f /root/.ssh/id_rsa ] || ssh-keygen -t rsa -b 4096 -N \"\" -f /root/.ssh/id_rsa
      cat /root/.ssh/id_rsa.pub
    '
  " 2>&1 | tee -a "${LOG}"
  NODE_PUB[$N]=$(vagrant ssh "$N" -c "sudo cat /root/.ssh/id_rsa.pub" | tr -d '\r' | grep '^ssh-' | head -n1)
done

log "==> [mesh] cài pubkey của 3 DB nodes vào authorized_keys của nhau"
for TARGET in node1 node2 node3; do
  for SRC in node1 node2 node3; do
    [[ "$SRC" == "$TARGET" ]] && continue
    PUB="${NODE_PUB[$SRC]}"
    [[ -z "$PUB" ]] && { log "    [WARN] pubkey của ${SRC} rỗng — skip"; continue; }
    vagrant ssh "$TARGET" -c "
      sudo bash -c '
        mkdir -p /root/.ssh && chmod 700 /root/.ssh
        grep -qxF \"${PUB}\" /root/.ssh/authorized_keys 2>/dev/null || echo \"${PUB}\" >> /root/.ssh/authorized_keys
        chmod 600 /root/.ssh/authorized_keys
      '
    " 2>&1 | tee -a "${LOG}"
  done
done

log "==> [mesh] Test SSH between DB nodes (chỉ pair khác nhau — self-SSH không cần)"
# Mapping IP -> hostname để skip self-SSH (node1 -> 192.168.10.11 luôn fail vì không cài key
# vào authorized_keys của chính nó; MHA cũng không cần self-SSH).
declare -A IP_HOST=( ["${NODE1_IP}"]=node1 ["${NODE2_IP}"]=node2 ["${NODE3_IP}"]=node3 )
FAIL_PAIR=0
for SRC in node1 node2 node3; do
  for DST_IP in "${NODE1_IP}" "${NODE2_IP}" "${NODE3_IP}"; do
    DST_NAME="${IP_HOST[$DST_IP]:-}"
    [[ "$SRC" == "$DST_NAME" ]] && { log "    ${SRC} -> ${DST_IP}: SKIP (self)"; continue; }
    # Wrap với || true: với set -e + pipefail, ssh fail trong $() subshell sẽ kill script.
    # Mục đích loop này CHỈ là diagnostic — không nên fail script vì 1 cặp.
    RES=$(vagrant ssh "$SRC" -c "sudo ssh -o ConnectTimeout=5 -o BatchMode=yes root@${DST_IP} 'hostname'" 2>&1 || true)
    RES=$(echo "$RES" | tail -n1 | tr -d '\r')
    log "    ${SRC} -> ${DST_IP}: ${RES}"
    # Kỳ vọng RES = hostname (node1/node2/node3). Nếu chứa "Permission denied" → fail pair.
    if echo "$RES" | grep -qE "Permission denied|Connection refused|timed out"; then
      FAIL_PAIR=$((FAIL_PAIR+1))
    fi
  done
done

if (( FAIL_PAIR > 0 )); then
  log "[FAIL] Có ${FAIL_PAIR} cặp SSH between DB nodes thất bại. masterha_check_ssh sẽ fail."
  log "       Kiểm tra /root/.ssh/authorized_keys trên mỗi node."
  exit 1
fi

log "==> Bước 2 hoàn tất. Tiếp theo: bash demo/04-mha/03-mha-node-install.sh"
