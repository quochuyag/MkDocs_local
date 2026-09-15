---
title: CLAUDE.md
course: 06-high-availability
source: HA/Mysql/CLAUDE.md
---

# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository purpose

Đây không phải application codebase — là **toolkit + runbooks** triển khai 7 giải pháp HA cho MySQL. Mọi "code" ở đây là bash scripts được chạy thủ công trên các DB nodes / mgmt host theo thứ tự được mô tả trong các runbook tương ứng. Không có build system, không có test runner, không có CI.

## Cấu trúc cấp cao

```
scripts/
  common/             # Chạy TRƯỚC trên mọi node (OS prep, install MySQL, firewall)
    env.sh            # Single source of truth cho topology IPs, credentials, ports
    00-prepare-os.sh
    01-install-mysql.sh
    02-firewall.sh
  async-semisync/     # Runbook 01 — native replication
  innodb-cluster/     # Runbook 02 — GR + Router via mysqlsh dba.*
  group-replication/  # Runbook 03 — GR thuần (không qua mysqlsh)
  mha/                # Runbook 04 — MHA manager + node
  orchestrator/       # Runbook 05 — openark/orchestrator
  galera/             # Runbook 06 — Percona XtraDB Cluster 8.0
  proxysql/           # Runbook 07 — proxy layer (ghép với 1 backend HA)
runbooks/             # Markdown 00-overview + 01..08 — bao gồm matrix, các bước, verify, ops, rollback
vagrant/              # Runbook 08 — lab 4 VMs (node1/2/3 + mgmt) Ubuntu 22.04
  Vagrantfile
  Makefile            # full-bootstrap = up + prep + install-mysql + ssh-trust
  provision/          # cluster_id_rsa sinh local (gitignored), generate-ssh-key.sh
configs/              # Reserved cho sample my.cnf snippets
```

Mỗi script nguồn `scripts/common/env.sh` ở đầu — đó là cách inject topology/credentials. **Khi sửa scripts, không hardcode IP/password**: thêm biến vào `env.sh` rồi tham chiếu `${VAR}`.

## Quy ước

- **Mọi script khởi đầu bằng**: `set -euo pipefail; source "$(dirname "$0")/../common/env.sh"; require_root`. Giữ nguyên pattern này khi thêm script mới.
- **Helper functions** trong `env.sh`: `mysql_root` (mysql client với root password), `require_root`, `log`. Dùng các helper này thay vì lặp lại boilerplate.
- **Idempotency** ưu tiên: dùng `CREATE USER IF NOT EXISTS`, `INSTALL PLUGIN` trong try-block hoặc dạng `|| true`. Script thường được chạy lại để recover từ lỗi giữa chừng.
- Mỗi runbook follow cấu trúc giống nhau: Khi nào dùng → Kiến trúc → Tiền đề → Các bước → Verify → Vận hành → Rollback → Tham khảo. Giữ format này khi thêm runbook.

## Topology giả định (xem `scripts/common/env.sh`)

- 3 DB nodes: `node1=192.168.10.11`, `node2=192.168.10.12`, `node3=192.168.10.13`
- 1 management host: `mgmt=192.168.10.20` (chạy MHA manager / Orchestrator / ProxySQL)
- VIP failover: `192.168.10.100` (khi dùng MHA hook `master_ip_failover.sh`)
- OS chính: Ubuntu 22.04. Branch RHEL/Rocky có ghi chú nhánh `dnf` trong cùng script.
- MySQL 8.0 community cho tất cả runbook ngoại trừ Galera (dùng PXC 8.0 — incompatible với MySQL community trên cùng host).

## Cross-runbook constraints

- Một host chỉ chọn **một** giải pháp data-plane tại một thời điểm. Không trộn InnoDB Cluster với Galera. ProxySQL/Orchestrator/MHA là control-plane và có thể ghép trên top.
- Async/Semi-sync (runbook 01) là **tiền đề** cho MHA (04) và Orchestrator (05) — chạy 01 trước.
- Galera (06) thay thế hẳn package MySQL community → **KHÔNG chạy** `common/01-install-mysql.sh` nếu chọn Galera; chạy `galera/install-pxc.sh` thay thế.

## Đầu vào khi sửa repo

- Thay đổi IPs, hostnames, mật khẩu → sửa duy nhất `scripts/common/env.sh`.
- Thêm giải pháp mới → tạo thư mục `scripts/<name>/`, viết script, thêm runbook `runbooks/0X-<name>.md`, update `README.md` và `runbooks/00-overview.md` matrix.
- Thêm step verify → đặt vào section **Verify** trong runbook tương ứng, không tạo file riêng.

## Không có CI/build/test

- Validation duy nhất là **chạy script thật trên lab VM**. Không có lint config (shellcheck chưa wire). Khi sửa shell, chạy thủ công `shellcheck scripts/**/*.sh` trước khi commit.
- Không có unit test cho bash. "Test" = chạy `verify` block trong runbook tương ứng.


---

!!! info "Nguồn gốc"
    `HA/Mysql/CLAUDE.md`
