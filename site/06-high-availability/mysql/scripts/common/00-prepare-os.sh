#!/usr/bin/env bash
# 00-prepare-os.sh — chạy trên TẤT CẢ nodes trước khi cài MySQL.
# Mục tiêu: hostname, /etc/hosts, NTP, swap, SELinux/AppArmor, sysctl, ulimit.
set -euo pipefail
source "$(dirname "$0")/env.sh"
require_root

# Dọn state MySQL repo còn sót từ lần B3 fail trước (key A8D3785C expired sẽ
# làm `apt-get update` ở step NTP fail). Prepare-os không cần repo MySQL —
# B3 sẽ setup lại sạch sẽ với key mới.
if command -v apt-get >/dev/null; then
  if [[ -f /etc/apt/sources.list.d/mysql.list || -f /etc/apt/sources.list.d/mysql.list.distUpgrade ]]; then
    log "==> Dọn /etc/apt/sources.list.d/mysql.list* (sẽ tái tạo ở B3)"
    rm -f /etc/apt/sources.list.d/mysql.list /etc/apt/sources.list.d/mysql.list.distUpgrade
    # Xoá luôn key cũ (cả keybox của mysql-apt-config lẫn keyring fix-up trước đó)
    rm -f /etc/apt/trusted.gpg.d/mysql.gpg /etc/apt/keyrings/mysql.gpg
  fi
fi

log "==> Cập nhật /etc/hosts (idempotent — xoá block cũ trước khi append)"
# Dùng marker để rerun không duplicate block
sed -i '/# >>> mysql-ha cluster >>>/,/# <<< mysql-ha cluster <<</d' /etc/hosts
cat >>/etc/hosts <<EOF
# >>> mysql-ha cluster >>>
${NODE1_IP}  ${NODE1_HOST}
${NODE2_IP}  ${NODE2_HOST}
${NODE3_IP}  ${NODE3_HOST}
${MGMT_IP}   ${MGMT_HOST}
# <<< mysql-ha cluster <<<
EOF

log "==> Tắt swap (khuyến nghị với MySQL)"
swapoff -a || true
# Chỉ comment dòng swap CHƯA bị comment (tránh '##swap' ở rerun)
sed -i.bak -E '/^[^#].*\sswap\s/s/^/#/' /etc/fstab

log "==> Đồng bộ thời gian (chronyd / systemd-timesyncd)"
if command -v timedatectl >/dev/null; then
  timedatectl set-ntp true || true
fi
if command -v dnf >/dev/null; then
  dnf install -y chrony && systemctl enable --now chronyd
elif command -v apt-get >/dev/null; then
  DEBIAN_FRONTEND=noninteractive apt-get update
  apt-get install -y chrony && systemctl enable --now chrony
fi

log "==> sysctl tuning cho MySQL/cluster"
cat >/etc/sysctl.d/99-mysql-ha.conf <<'EOF'
vm.swappiness = 1
net.core.somaxconn = 65535
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_keepalive_time = 60
net.ipv4.tcp_keepalive_intvl = 10
net.ipv4.tcp_keepalive_probes = 6
fs.aio-max-nr = 1048576
fs.file-max = 2097152
EOF
sysctl --system >/dev/null

log "==> ulimit / systemd limits cho mysql user"
mkdir -p /etc/systemd/system/mysql.service.d /etc/systemd/system/mysqld.service.d
cat >/etc/systemd/system/mysql.service.d/limits.conf <<'EOF'
[Service]
LimitNOFILE=1048576
LimitNPROC=65535
EOF
cp /etc/systemd/system/mysql.service.d/limits.conf /etc/systemd/system/mysqld.service.d/limits.conf
systemctl daemon-reload || true

log "==> Xử lý SELinux / AppArmor (chuyển sang permissive cho lab)"
if command -v setenforce >/dev/null; then setenforce 0 || true; fi
if [[ -f /etc/selinux/config ]]; then sed -i 's/^SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config; fi
if command -v aa-status >/dev/null; then
  systemctl disable --now apparmor || true
fi

log "==> Hoàn tất prepare-os trên $(hostname)"
