---
title: Runbook 08 — Vagrant Lab (4 VMs Ubuntu 22.04)
course: 06-high-availability
source: HA/Mysql/runbooks/08-vagrant-lab.md
---

# Runbook 08 — Vagrant Lab (4 VMs Ubuntu 22.04)

Spin up nhanh lab 4-node trên máy local để chạy thử bất kỳ trong 7 giải pháp HA. Không cần cloud, không cần host vật lý riêng.

## 1. Topology

| VM | IP | vCPU | RAM | Role |
|---|---|---|---|---|
| node1 | 192.168.10.11 | 2 | 2 GB | DB (master / primary / writer) |
| node2 | 192.168.10.12 | 2 | 2 GB | DB |
| node3 | 192.168.10.13 | 2 | 2 GB | DB |
| mgmt  | 192.168.10.20 | 1 | 1 GB | ProxySQL / Orchestrator / MHA manager |

Tổng tài nguyên: **7 vCPU, ~7 GB RAM** trên host. Khuyến nghị host RAM ≥ 12 GB.

## 2. Yêu cầu host

| Component | Version tối thiểu | Ghi chú |
|---|---|---|
| Vagrant | 2.3+ | https://www.vagrantup.com/downloads |
| VirtualBox | 7.0+ | Hoặc libvirt — cần sửa provider trong Vagrantfile |
| Disk free | ≥ 30 GB | Mỗi VM ~ 5-8 GB sau provision |

Windows: bật virtualization trong BIOS, tắt Hyper-V (xung đột với VirtualBox).

## 3. Quick start

```bash
cd vagrant

# Cách 1 — pipeline đầy đủ:
make full-bootstrap
# = make ssh-keys → vagrant up → make prep-all → make install-mysql → make ssh-trust

# Cách 2 — bằng vagrant trực tiếp:
bash provision/generate-ssh-key.sh
vagrant up
for N in node1 node2 node3 mgmt; do vagrant provision $N --provision-with common-prep; done
for N in node1 node2 node3;        do vagrant provision $N --provision-with install-mysql; done
for N in node1 node2 node3 mgmt;   do vagrant provision $N --provision-with ssh-trust; done
```

## 4. Cấu trúc provisioner trong Vagrantfile

Vagrantfile khai báo 5 named provisioners — mặc định chỉ `prep` và `banner` chạy khi `vagrant up`. Các provisioner khác `run: "never"` → chạy tường minh bằng `vagrant provision <vm> --provision-with <name>`.

| Provisioner | Default | Mục đích |
|---|---|---|
| `prep` | auto | Set /etc/hosts, install tools cơ bản, link env.sh |
| `banner` | auto | Hiện MOTD khi SSH vào |
| `common-prep` | manual | Chạy `scripts/common/00-prepare-os.sh` |
| `install-mysql` | manual (DB only) | Chạy `01-install-mysql.sh` + `02-firewall.sh` |
| `ssh-trust` | manual | Copy shared SSH key, disable strict host check |

## 5. Sau khi bootstrap xong, chọn 1 giải pháp HA

### Ví dụ A — InnoDB Cluster
```bash
# Trên mỗi node DB:
for N in node1 node2 node3; do
  vagrant ssh $N -c "sudo bash /vagrant/scripts/innodb-cluster/node-setup.sh"
done

# Bootstrap trên node1:
vagrant ssh node1 -c "sudo bash /vagrant/scripts/innodb-cluster/cluster-bootstrap.sh"

# Router trên mgmt:
vagrant ssh mgmt -c "sudo bash /vagrant/scripts/innodb-cluster/router-setup.sh"
```
Verify từ host:
```bash
# Cài mysql client trên host, hoặc dùng VM mgmt
vagrant ssh mgmt -c "mysql -uappuser -p<APP_PWD> -h192.168.10.20 -P6446 -e 'SELECT @@hostname'"
```

### Ví dụ B — Galera (PXC)
```bash
# KHÔNG chạy install-mysql ở bước bootstrap nếu chọn Galera; thay bằng:
for N in node1 node2 node3; do
  vagrant ssh $N -c "sudo bash /vagrant/scripts/galera/install-pxc.sh"
done
vagrant ssh node1 -c "sudo bash /vagrant/scripts/galera/bootstrap-node.sh"
vagrant ssh node2 -c "sudo bash /vagrant/scripts/galera/join-node.sh"
vagrant ssh node3 -c "sudo bash /vagrant/scripts/galera/join-node.sh"
```

### Ví dụ C — Async/Semi-sync + Orchestrator
```bash
vagrant ssh node1 -c "sudo bash /vagrant/scripts/async-semisync/master-setup.sh"
vagrant ssh node2 -c "sudo bash /vagrant/scripts/async-semisync/replica-setup.sh"
vagrant ssh node3 -c "sudo bash /vagrant/scripts/async-semisync/replica-setup.sh"
vagrant ssh mgmt  -c "sudo bash /vagrant/scripts/orchestrator/orchestrator-setup.sh"
# Web UI: http://192.168.10.20:3000 từ trình duyệt host
```

## 6. Vận hành VM

| Tác vụ | Lệnh |
|---|---|
| Trạng thái | `make status` hoặc `vagrant status` |
| SSH | `vagrant ssh node1` |
| Halt giữ disk | `make down` |
| Reboot 1 VM | `vagrant reload node1` |
| Re-run provisioner | `vagrant provision node1 --provision-with install-mysql` |
| Destroy + clean | `make clean` |

## 7. Snapshot để rollback nhanh

VirtualBox snapshot rất hữu ích khi test các scenario destructive (failover, split-brain):
```bash
# Snapshot cả 4 VMs
for N in node1 node2 node3 mgmt; do vagrant snapshot save $N clean; done

# Khôi phục
for N in node1 node2 node3 mgmt; do vagrant snapshot restore $N clean; done

# Liệt kê
vagrant snapshot list
```

## 8. Troubleshooting

| Triệu chứng | Cách xử lý |
|---|---|
| `vagrant up` báo IP conflict | `192.168.10.0/24` trùng với mạng host — đổi NODES IPs trong Vagrantfile + env.sh |
| Box `bento/ubuntu-22.04` không tải được | `vagrant box add bento/ubuntu-22.04` thủ công hoặc đổi sang `ubuntu/jammy64` |
| VirtualBox báo `VT-x not available` | Bật Intel VT-x / AMD-V trong BIOS; tắt Hyper-V trên Windows: `bcdedit /set hypervisorlaunchtype off` rồi reboot |
| `synced_folder` chậm trên Windows | Đổi sang `type: "smb"` (cần SMB share) hoặc `type: "rsync"` |
| MySQL 01-install-mysql.sh fail vì repo timeout | VM thiếu DNS → `vagrant ssh node1 -c "sudo systemctl restart systemd-resolved"` |

## 9. Dọn dẹp hoàn toàn

```bash
make clean              # destroy + xoá shared SSH key
# Xoá thư mục .vagrant/ nếu vẫn còn:
rm -rf .vagrant/
```

## 10. Mapping với runbooks khác

Sau khi `make full-bootstrap` xong, bạn đã có môi trường tương đương phần "Tiền đề" của tất cả runbook 01..07. Đọc runbook tương ứng và chạy script qua `vagrant ssh <node> -c "sudo bash /vagrant/scripts/.../*.sh"`.


---

!!! info "Nguồn gốc"
    `HA/Mysql/runbooks/08-vagrant-lab.md`
