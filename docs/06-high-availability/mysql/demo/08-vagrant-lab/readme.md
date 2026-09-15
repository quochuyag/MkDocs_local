---
title: Demo 08 — Vagrant Lab (4 VMs)
course: 06-high-availability
source: HA/Mysql/demo/08-vagrant-lab/README.md
---

# Demo 08 — Vagrant Lab (4 VMs)

Bộ kịch bản chỉ tập trung **dựng lab 4 VMs Ubuntu 22.04** đầy đủ provision baseline (hosts, swap, sysctl, NTP, SSH trust) để **chạy bất kỳ giải pháp HA** từ Demo 01-07. Không setup giải pháp HA cụ thể nào.

> Tham chiếu runbook gốc: [../../runbooks/08-vagrant-lab.md](../../runbooks/008-vagrant-lab.md)
> Topology: xem [../../scripts/common/env.sh](../../scripts/common/env.sh)

## Mục đích

Sau khi `bash run-all.sh` xong, bạn có:
- 4 VMs `running` (node1/2/3/mgmt), ping nội bộ OK.
- `/etc/hosts` chứa toàn bộ 4 hostname → IP.
- Swap off, NTP synchronized, sysctl tuned (`vm.swappiness=1`, `fs.file-max=1M`).
- SSH trust: vagrant user có shared key giữa các VMs (KHÔNG phải root SSH passwordless — đó là việc của Demo 04).
- Sẵn sàng cho bất kỳ demo `setup-*` của giải pháp HA cụ thể.

## Topology demo

| Host  | IP             | Role                    | RAM    | vCPU |
|-------|----------------|-------------------------|--------|------|
| node1 | 192.168.10.11  | DB candidate (master)   | 2 GB   | 2    |
| node2 | 192.168.10.12  | DB candidate            | 2 GB   | 2    |
| node3 | 192.168.10.13  | DB candidate            | 2 GB   | 2    |
| mgmt  | 192.168.10.20  | Manager / Proxy / Client | 1.5 GB | 1   |

## Yêu cầu host

- Vagrant ≥ 2.3, VirtualBox ≥ 7.0
- RAM host ≥ 8 GB, disk ≥ 30 GB
- Network: subnet `192.168.10.0/24` chưa bị xung đột

## Cấu trúc demo

| Bước | Shell script | Chạy ở đâu | Vai trò |
|------|--------------|------------|---------|
| 0 | [00-overview.md](000-overview.md) | (đọc) | Mục tiêu lab |
| 1 | [01-vagrant-up.sh](01-vagrant-up.sh) | Host | Spin up 4 VMs Ubuntu 22.04 |
| 2 | [02-prepare-os.sh](02-prepare-os.sh) | Host → 4 VMs | hosts/swap/sysctl/NTP (provisioner `common-prep`) |
| 3 | [03-ssh-trust.sh](03-ssh-trust.sh) | Host → 4 VMs | Copy shared SSH key giữa VMs (provisioner `ssh-trust`) |
| 4 | [04-verify.sh](04-verify.sh) | Host | Verify 4 VMs running, ping, hosts file, ssh-trust |
| 5 | [05-snapshot-clean.sh](05-snapshot-clean.sh) | Host | (Optional) `vagrant snapshot save` để rollback nhanh khi test các demo |
| 9 | [09-cleanup.sh](09-cleanup.sh) | Host | Destroy all VMs + xoá shared SSH key |

## Chạy nhanh — end-to-end

```bash
cd demo/08-vagrant-lab
bash run-all.sh      # Linux/macOS/WSL/Git Bash
.\run-all.ps1        # Windows PowerShell
```

Sau khi xong, chạy 1 trong:
```bash
bash ../01-async-semisync/run-all.sh   # Demo 01
bash ../02-innodb-cluster/run-all.sh   # Demo 02
bash ../03-group-replication/run-all.sh # Demo 03
# (Demo 06 yêu cầu KHÔNG cài MySQL community trước — Demo 06 sẽ tự cài PXC)
```

## Mapping demo

Sau khi lab bootstrap xong, các demo HA sẽ dùng đến những phần khác nhau:

| Demo | Cần install-mysql? | Cần SSH root passwordless? | Đặc biệt |
|------|--------------------|----------------------------|----------|
| 01 (async-semisync) | Có (script cài) | Không | Default flow |
| 02 (innodb-cluster) | Có (script cài) | Không | Dùng mysqlsh |
| 03 (group-replication) | Có (script cài) | Không | Dùng SQL trực tiếp |
| 04 (mha) | Có + cần `relay_log_purge=0` | **Có** (Demo 04 tự setup) | Cần Demo 01 chạy trước |
| 05 (orchestrator) | Có + mgmt cũng cần MySQL local | Không | Cần Demo 01 |
| 06 (galera) | **KHÔNG** — dùng PXC thay thế | Không | Standalone |
| 07 (proxysql) | Có | Không | Cần Demo 01 hoặc 06 |

## Output

- `results/01-vagrant-up.log` — `vagrant up` output
- `results/02-prepare-os.log` — provisioner common-prep output
- `results/03-ssh-trust.log` — provisioner ssh-trust output
- `results/04-verify.log` — checkpoint baseline
- `results/report.md` — template báo cáo demo

## Tham khảo
- Runbook gốc: [runbooks/08-vagrant-lab.md](../../runbooks/008-vagrant-lab.md)
- Vagrantfile: [vagrant/Vagrantfile](../../vagrant/Vagrantfile)


---

!!! info "Nguồn gốc"
    `HA/Mysql/demo/08-vagrant-lab/README.md`
