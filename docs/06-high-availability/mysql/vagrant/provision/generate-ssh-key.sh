#!/usr/bin/env bash
# generate-ssh-key.sh — sinh 1 cặp SSH key chung cho cluster (cluster_id_rsa).
# Chạy 1 lần trên host trước khi `vagrant up` để các VM đều có chung key
# và có thể SSH passwordless lẫn nhau (cần cho MHA, ad-hoc ops).
set -euo pipefail
cd "$(dirname "$0")"

if [[ -f cluster_id_rsa ]]; then
  echo "cluster_id_rsa đã tồn tại. Xoá nếu muốn regenerate."
  exit 0
fi

ssh-keygen -t rsa -b 4096 -N '' -C 'mysql-ha-cluster' -f cluster_id_rsa
chmod 600 cluster_id_rsa
chmod 644 cluster_id_rsa.pub
echo "Đã sinh: $(pwd)/cluster_id_rsa (+ .pub)"
echo "Vagrantfile sẽ copy cặp này vào /root/.ssh/ trên mọi node khi chạy provisioner 'ssh-trust'."
