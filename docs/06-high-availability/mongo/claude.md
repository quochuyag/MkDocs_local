---
title: CLAUDE.md
course: 06-high-availability
source: HA/mongo/CLAUDE.md
---

# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository purpose

Đây không phải application codebase — là **toolkit + runbooks** triển khai các giải pháp HA cho MongoDB (replica set, PSA, sharded cluster, backup/PITR, multi-region). Mọi "code" ở đây là bash scripts chạy thủ công trên các nodes theo thứ tự mô tả trong runbook tương ứng. Không có build system, không có test runner, không có CI.

## Cấu trúc cấp cao

```
scripts/
  common/             # Chạy TRƯỚC trên mọi node (OS prep, install MongoDB, firewall, keyFile)
    env.sh            # Single source of truth cho topology IPs, users, ports, paths
    00-prepare-os.sh  # THP off, swap off, sysctl, ulimit
    01-install-mongo.sh
    02-firewall.sh
    03-keyfile.sh     # Sinh keyFile internal auth — copy thủ công sang các nodes
    04-tls-self-signed.sh
  replica-set/        # Runbook 01 — PSS native replication (default)
  psa/                # Runbook 02 — Primary + Secondary + Arbiter
  sharded-cluster/    # Runbook 03 — config RS + shard RS + mongos
  hidden-delayed/     # Runbook 04 — add hidden+delayed member lên RS
  backup-pitr/        # Runbook 05 — mongodump + LVM snapshot + oplog tail + PITR replay
  multi-region/       # Runbook 06 — cross-region secondary + zone sharding
runbooks/             # Markdown 00-overview + 01..08 — matrix, các bước, verify, ops, rollback
vagrant/              # Runbook 08 — lab 4 VMs (node1/2/3 + mgmt) Ubuntu 22.04
  Vagrantfile
  Makefile            # full-bootstrap = up + prep + install-mongo + trust (keyfile + ssh)
  provision/          # cluster_id_rsa + keyfile sinh local (gitignored), generate-*.sh
```

Mỗi script source `scripts/common/env.sh` ở đầu — đó là cách inject topology/credentials/version. **Khi sửa scripts, không hardcode IP/password/port**: thêm biến vào `env.sh` rồi tham chiếu `${VAR}`.

## Quy ước

- **Mọi script khởi đầu bằng**: `set -euo pipefail; source "$(dirname "$0")/../common/env.sh"; require_root`. Giữ pattern này khi thêm script mới.
- **Helper functions** trong `env.sh`: `mongo_admin_local` (mongosh authenticated as admin@localhost), `mongo_local_noauth` (chỉ dùng trước khi tạo user), `wait_for_mongod`, `require_root`, `log`. Dùng helper thay vì lặp boilerplate.
- **Idempotency** ưu tiên: dùng `if [[ -s file ]]; then skip` hoặc `|| true` trên các lệnh tạo. Script thường chạy lại để recover từ lỗi giữa chừng.
- **Override port qua biến**: scripts hỗ trợ `MONGO_PORT_OVERRIDE`/`SHARD_PORT`/`CFG_PORT` khi cần multi-instance trên 1 VM (lab sharded cluster).
- Mỗi runbook follow cấu trúc giống nhau: Khi nào dùng → Kiến trúc → Tiền đề → Các bước → Verify → Vận hành → Rollback → Lưu ý → Tham khảo. Giữ format này khi thêm runbook.

## Topology giả định (xem `scripts/common/env.sh`)

- 3 DB nodes: `node1=192.168.20.11`, `node2=192.168.20.12`, `node3=192.168.20.13`
- 1 mgmt host: `mgmt=192.168.20.20` (chạy mongos / DR secondary / backup tooling)
- Subnet `192.168.20.0/24` khác MySQL (`192.168.10.0/24`) để 2 lab cùng tồn tại trên 1 host.
- OS chính: Ubuntu 22.04. Branch RHEL/Rocky có nhánh `dnf` trong cùng script.
- MongoDB 7.0 Community mặc định; đổi bằng `MONGO_MAJOR=8.0` trong env.sh.

## Port plan (quan trọng khi đọc/sửa scripts)

| Port | Role | Runbook |
|---|---|---|
| 27017 | mongod RS member / mongos | 01, 02 (data), 06; mongos ở 03 |
| 27018 | mongod shard member | 03 |
| 27019 | mongod config server | 03 |
| 27020 | mongod arbiter | 02 |

Sharded Cluster lab dùng cả 27017/27018/27019 trên cùng 3 VMs — multiple mongod instances với systemd units `mongod-cfg`, `mongod-shard1rs`, etc.

## Cross-runbook constraints

- Replica Set PSS (Runbook 01) là **tiền đề** cho 04 (hidden/delayed), 05 (backup), 06 (multi-region) — chạy 01 trước.
- Sharded Cluster (03) **không trộn** với Replica Set thuần trên cùng cluster — chọn 1 architecture. Trong lab có thể chạy đồng thời vì port khác nhau (port 27017 cho RS vs port 27018+27019 cho shard).
- PSA (02) và PSS (01) **mutually exclusive** trong cùng 1 cluster.
- Atlas (07) thay thế tất cả — không kết hợp self-host + Atlas trên cùng dataset.
- KeyFile **phải giống nhau** trên mọi members của cùng cluster. Sai → mongod refuse join.

## Đầu vào khi sửa repo

- Thay đổi IPs, hostnames, mật khẩu, MongoDB version → sửa duy nhất `scripts/common/env.sh`.
- Thêm giải pháp mới → tạo thư mục `scripts/<name>/`, viết script, thêm runbook `runbooks/0X-<name>.md`, update `README.md` table và `runbooks/00-overview.md` matrix.
- Thêm step verify → đặt vào section **Verify** trong runbook tương ứng, không tạo file riêng.
- Thêm port mới → cập nhật cả `env.sh` (export) lẫn `scripts/common/02-firewall.sh` (PORTS array).

## Không có CI/build/test

- Validation duy nhất là **chạy script thật trên lab VM**. Không có shellcheck wire.
- "Test" = chạy `Verify` block trong runbook tương ứng, hoặc `rs.status()` / `sh.status()`.
- Khi sửa shell, chạy `shellcheck scripts/**/*.sh` thủ công trước khi commit là good practice (chưa enforce).

## Vagrant lab nhanh

```bash
cd vagrant
make full-bootstrap     # up 4 VMs + prep OS + install MongoDB + copy keyfile/ssh-key
```

`make full-bootstrap` chỉ bootstrap base (chưa initiate RS / shard). Sau đó chọn 1 giải pháp HA và chạy script tương ứng theo Runbook 01-06.

Synced folder: `../` (repo root) → `/vagrant` trên VM. Edit script trên host → áp dụng ngay trên VM (không cần copy).


---

!!! info "Nguồn gốc"
    `HA/mongo/CLAUDE.md`
