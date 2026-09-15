---
title: Demo 04 — MHA (Master High Availability Manager)
course: 06-high-availability
source: HA/Mysql/demo/04-mha/README.md
---

# Demo 04 — MHA (Master High Availability Manager)

Bộ kịch bản end-to-end dựng cụm **Async/Semi-sync + MHA Manager** trên Vagrant. MHA giám sát master, tự động failover sang replica khi master chết, copy binlog còn sót lại để giảm mất dữ liệu, và move VIP qua hook.

> Tham chiếu runbook gốc: [../../runbooks/04-mha.md](../../runbooks/004-mha.md)
> **Tiền đề**: cần chạy [Demo 01](../01-async-semisync/) trước (semi-sync replication 1 master + 2 replicas).
> Topology: xem [../../scripts/common/env.sh](../../scripts/common/env.sh)

## Topology demo

| Host  | IP             | Vai trò                            | RAM    |
|-------|----------------|------------------------------------|--------|
| node1 | 192.168.10.11  | MySQL Master (RW) + mha4mysql-node | 2 GB   |
| node2 | 192.168.10.12  | MySQL Replica (RO) + mha4mysql-node | 2 GB  |
| node3 | 192.168.10.13  | MySQL Replica (RO) + mha4mysql-node | 2 GB  |
| mgmt  | 192.168.10.20  | MHA Manager + masterha_manager     | 1.5 GB |
| VIP   | 192.168.10.100 | Floating IP gắn vào master         | —      |

```
                  ┌───────────────────────┐
                  │  mgmt (manager)       │ masterha_manager (Perl daemon)
                  └──────────┬────────────┘
                             │ SSH (root) + MySQL (mha user)
       ┌─────────────────────┼─────────────────────┐
       ▼                     ▼                     ▼
   node1 (master, VIP)   node2 (replica)       node3 (replica)
   mha4mysql-node        mha4mysql-node        mha4mysql-node
       └────── semi-sync replication (Demo 01) ──────┘
```

## Khi master chết

1. Manager ping master fail ≥ 3 lần → confirm chết qua `secondary_check_script` (ping từ secondary).
2. SSH vào master cũ → copy `mysql-bin.*` còn sót sang manager.
3. Chọn replica có position cao nhất → relay binlog còn lại lên đó.
4. Promote replica thành master mới (`STOP REPLICA; RESET REPLICA ALL;`).
5. 2 replica còn lại `CHANGE REPLICATION SOURCE` về master mới, `START REPLICA`.
6. Gọi `master_ip_failover.sh` để move VIP `192.168.10.100` từ master cũ → master mới.

## Yêu cầu host

- Vagrant ≥ 2.3, VirtualBox ≥ 7.0
- RAM host ≥ 8 GB (4 VMs), disk trống ≥ 25 GB
- **Đã chạy thành công Demo 01** — cụm semi-sync 1 master + 2 replicas đã sẵn sàng

## Cấu trúc demo

| Bước | Shell script | Chạy ở đâu | Vai trò |
|------|--------------|------------|---------|
| 0 | [00-overview.md](000-overview.md) | (đọc) | Mục tiêu, kiến trúc |
| 1 | [01-precheck.sh](01-precheck.sh) | Host | Kiểm tra Demo 01 đã chạy thành công |
| 2 | [02-ssh-trust.sh](02-ssh-trust.sh) | Host → 4 VMs | SSH passwordless từ mgmt → node1/2/3 (root user) |
| 3 | [03-mha-node-install.sh](03-mha-node-install.sh) | Host → 3 DB VMs | Cài mha4mysql-node trên node1/2/3 |
| 4 | [04-mha-manager-install.sh](04-mha-manager-install.sh) | Host → mgmt | Cài mha4mysql-manager + config file + start daemon |
| 5 | [05-verify.sh](05-verify.sh) | Host | `masterha_check_ssh`, `masterha_check_repl`, `masterha_check_status` |
| 6 | [06-vip-bind.sh](06-vip-bind.sh) | Host → node1 | Gắn VIP 192.168.10.100 lên master ban đầu (node1) |
| 7 | [07-failover-test.sh](07-failover-test.sh) | Host | halt node1 → MHA auto-failover → đo RTO + verify VIP move |
| 8 | [08-rebuild-old-master.sh](08-rebuild-old-master.sh) | Host | Sau failover, rebuild node1 thành replica của master mới |
| 9 | [09-rollback.sh](09-rollback.sh) | Host | Stop manager, xoá MHA, optional destroy VMs |

## Chạy nhanh — end-to-end

```bash
cd demo/04-mha
bash run-all.sh      # Linux/macOS/WSL/Git Bash
# hoặc
.\run-all.ps1        # Windows PowerShell
```

`run-all` thực hiện **B1 → B6** (precheck → manager up + VIP bound). **B7 (failover)** và **B8/B9** chạy thủ công vì destructive.

## Output & báo cáo

- `results/05-verify.log` — kết quả `masterha_check_*`
- `results/07-failover.log` — log MHA failover + RTO
- `results/report.md` — template báo cáo demo

## Tham khảo
- Runbook gốc: [runbooks/04-mha.md](../../runbooks/004-mha.md)
- mha4mysql-manager: https://github.com/yoshinorim/mha4mysql-manager/wiki


---

!!! info "Nguồn gốc"
    `HA/Mysql/demo/04-mha/README.md`
