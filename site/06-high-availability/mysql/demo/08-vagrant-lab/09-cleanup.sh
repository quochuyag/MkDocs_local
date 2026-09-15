#!/usr/bin/env bash
# 09-cleanup.sh — Destroy toàn bộ lab + xoá shared SSH key.
# Sử dụng vagrant/cleanup.sh từ thư mục gốc (đã có tools đầy đủ).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RESULTS="${SCRIPT_DIR}/results"
LOG="${RESULTS}/09-cleanup.log"
mkdir -p "${RESULTS}"

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" | tee -a "${LOG}"; }

cd "${REPO_ROOT}/vagrant"

# Pass-through các flag (--all, --yes, --dry-run, ...)
if [[ -x cleanup.sh ]]; then
  log "==> Gọi vagrant/cleanup.sh \"$@\""
  bash cleanup.sh "$@" 2>&1 | tee -a "${LOG}"
else
  log "==> Fallback: vagrant destroy -f"
  vagrant destroy -f 2>&1 | tee -a "${LOG}"
  rm -f provision/cluster_id_rsa provision/cluster_id_rsa.pub
fi

log "==> Cleanup xong."
