---
title: Runbook 08 — Vagrant Lab (4 VMs Ubuntu 22.04)
course: 06-high-availability
source: HA/mongo/runbooks/08-vagrant-lab.md
---

# Runbook 08 — Vagrant Lab (4 VMs Ubuntu 22.04)

Spin up nhanh lab 4-node trên máy local để chạy bất kỳ giải pháp HA nào trong Runbook 01-06.

## 1. Topology

| VM | IP | vCPU | RAM | Role |
|---|---|---|---|---|
| node1 | 192.168.20.11 | 2 | 2.5 GB | DB (primary thường) |
| node2 | 192.168.20.12 | 2 | 2.5 GB | DB |
| node3 | 192.168.20.13 | 2 | 2.5 GB | DB / arbiter (PSA) |
| mgmt  | 192.168.20.20 | 1 | 1.5 GB | mongos / DR secondary / backup host |

Tổng: **7 vCPU, ~9 GB RAM**. Host khuyến nghị RAM ≥ 12 GB, disk free ≥ 30 GB.

## 2. Yêu cầu host & cài đặt

### 2.1 Components

| Component | Min version | Tải từ |
|---|---|---|
| Vagrant | 2.3+ | <https://developer.hashicorp.com/vagrant/downloads> |
| VirtualBox | 7.0+ | <https://www.virtualbox.org/wiki/Downloads> (chọn "Windows hosts") |
| OpenSSL | bất kỳ | Có sẵn trên Git for Windows / WSL; hoặc <https://slproweb.com/products/Win32OpenSSL.html> |

### 2.2 Cài đặt trên Windows (PowerShell as Administrator)

```powershell
# Cách A — qua winget (Windows 11 / Windows 10 21H1+):
winget install -e --id Hashicorp.Vagrant
winget install -e --id Oracle.VirtualBox

# Cách B — qua chocolatey:
choco install vagrant virtualbox openssl -y

# Cách C — installer truyền thống: tải .msi/.exe từ link ở 2.1, double-click cài.

# Sau khi cài, đóng/mở lại PowerShell rồi verify:
vagrant --version          # >= 2.3
VBoxManage --version       # >= 7.0
```

### 2.3 BIOS / Windows requirements

- Bật **Intel VT-x / AMD-V** trong BIOS (thường mặc định đã bật trên Windows 11).
- **Tắt Hyper-V** (xung đột với VirtualBox 7.0):

  ```powershell
  bcdedit /set hypervisorlaunchtype off
  Disable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All -NoRestart
  # Reboot host
  ```

- Nếu vẫn dùng Docker Desktop / WSL2 song song → khó cùng tồn tại với VirtualBox; tham khảo `VBoxManage modifyvm --paravirtprovider none` hoặc đổi sang provider `libvirt` / `hyperv`.

### 2.4 Box Ubuntu — nguồn lấy

Box mặc định trong [Vagrantfile](../vagrant/Vagrantfile) là **`bento/ubuntu-22.04`** từ Vagrant Cloud:

- Trang catalog: <https://portal.cloud.hashicorp.com/vagrant/discover/bento/ubuntu-22.04>
- Vagrant **tự động tải lần đầu** khi `vagrant up` — không cần thao tác thủ công.
- Tải về 1 lần, cache tại: `%USERPROFILE%\.vagrant.d\boxes\bento-VAGRANTSLASH-ubuntu-22.04\<version>\virtualbox\`
- Box duy nhất, dùng chung cho cả 4 VMs (Vagrant clone từ box → từng VM).

Tải thủ công trước (tùy chọn, hữu ích khi mạng chậm):

```powershell
vagrant box add bento/ubuntu-22.04 --provider virtualbox
vagrant box list                # liệt kê box đã có local
```

Alternative boxes (sửa `config.vm.box` trong Vagrantfile nếu muốn):

- `ubuntu/jammy64` — official Ubuntu 22.04 (đôi khi update chậm hơn bento).
- `generic/ubuntu2204` — multi-provider (VirtualBox / libvirt / Hyper-V).

## 3. Đổi nơi lưu VM files sang `D:\VM VirtualBox\mongo-ha`

Mặc định VirtualBox lưu VM disk (`.vdi`) tại `C:\Users\<username>\VirtualBox VMs\` — tốn ổ C. Lab này tạo ~12-20 GB.

### 3.1 Cách A — Đổi global default machine folder (đơn giản nhất)

```powershell
# Tạo thư mục trước
New-Item -ItemType Directory -Force -Path "D:\VM VirtualBox\mongo-ha"

# Đổi default machinefolder của VirtualBox (toàn hệ thống — ảnh hưởng MỌI VM tạo sau)
VBoxManage setproperty machinefolder "D:\VM VirtualBox\mongo-ha"

# Verify
VBoxManage list systemproperties | Select-String "Default machine folder"
# kỳ vọng: Default machine folder:  D:\VM VirtualBox\mongo-ha
```

Sau bước trên, `vagrant up` sẽ tạo VM tại:

```text
D:\VM VirtualBox\mongo-ha\mongo-ha-node1\
D:\VM VirtualBox\mongo-ha\mongo-ha-node2\
D:\VM VirtualBox\mongo-ha\mongo-ha-node3\
D:\VM VirtualBox\mongo-ha\mongo-ha-mgmt\
```

(tên VM `mongo-ha-<name>` đến từ `vb.name` trong [Vagrantfile](../vagrant/Vagrantfile)).

Khôi phục default cũ khi xong (nếu muốn):

```powershell
VBoxManage setproperty machinefolder default
```

### 3.2 Cách B — Helper script tự động (đề xuất)

Repo có sẵn helper [vagrant/set-vm-path.ps1](../vagrant/set-vm-path.ps1):

```powershell
cd vagrant
.\set-vm-path.ps1                                    # mặc định D:\VM VirtualBox\mongo-ha
# Hoặc đổi target:
.\set-vm-path.ps1 -Path "E:\Labs\mongo-ha"
```

Script: tạo thư mục, set machinefolder, hiển thị verify. Chạy 1 lần trước `vagrant up` lần đầu là đủ.

### 3.3 Cách C — Đổi qua GUI

VirtualBox Manager → **File → Preferences → General → Default Machine Folder** → trỏ tới `D:\VM VirtualBox\mongo-ha`.

### 3.4 Lưu ý nếu VMs đã tồn tại ở chỗ khác

VBoxManage setproperty **CHỈ ảnh hưởng VMs tạo MỚI**. Nếu đã chạy `vagrant up` rồi đổi path:

```powershell
# B1. Destroy VMs cũ
cd vagrant
vagrant destroy -f

# B2. Đổi machinefolder
VBoxManage setproperty machinefolder "D:\VM VirtualBox\mongo-ha"

# B3. Up lại
vagrant up
```

Hoặc di chuyển VM hiện tại (phức tạp, không khuyến nghị): `VBoxManage movevm <vm-name> --type basic --folder "D:\VM VirtualBox\mongo-ha"`.

### 3.5 Phân biệt 3 nơi lưu trữ

| Lưu cái gì | Path | Đổi được? |
|---|---|---|
| VM disk + .vbox config | `D:\VM VirtualBox\mongo-ha\<vm>\` | ✅ `VBoxManage setproperty machinefolder` |
| Box (template Ubuntu) | `%USERPROFILE%\.vagrant.d\boxes\` | ✅ Set env `VAGRANT_HOME=D:\vagrant-home` |
| Per-project state | `<repo>/vagrant/.vagrant/` | Cố định — không đổi (nhỏ, chỉ metadata) |

Đổi box cache sang D: (tùy chọn, save more C: space):

```powershell
[Environment]::SetEnvironmentVariable("VAGRANT_HOME", "D:\vagrant-home", "User")
# Mở PowerShell mới để biến env có hiệu lực
```

## 4. Quick start

```bash
cd vagrant

# Pipeline đầy đủ:
make full-bootstrap
# = make ssh-keys → make keyfile → vagrant up → make prep-all → make install-mongo → make trust

# Hoặc step-by-step:
make ssh-keys       # sinh provision/cluster_id_rsa
make keyfile        # sinh provision/keyfile (MongoDB internal auth)
make up             # vagrant up (cài VMs, chỉ chạy provisioner "prep" + "banner")
make prep-all       # OS prep (THP off, swap off, ulimit, sysctl) trên 4 VMs
make install-mongo  # cài MongoDB community + firewall
make trust          # copy keyfile + SSH key vào /root/.ssh
```

## 4. Provisioner trong Vagrantfile

| Provisioner | Khi nào chạy | Mục đích |
|---|---|---|
| `prep` | auto khi `vagrant up` | /etc/hosts, link env.sh, tools cơ bản |
| `banner` | auto | MOTD khi SSH |
| `common-prep` | manual | Chạy `scripts/common/00-prepare-os.sh` |
| `install-mongo` | manual | Chạy `01-install-mongo.sh` + `02-firewall.sh` |
| `trust` | manual | Copy keyFile (/etc/mongodb/keyfile) + SSH key |

Lệnh chạy provisioner thủ công:
```bash
vagrant provision node1 --provision-with install-mongo
```

## 5. Chạy một giải pháp HA sau khi bootstrap

### A — Replica Set PSS (Runbook 01)
```bash
for N in node1 node2 node3; do
  vagrant ssh $N -c "sudo bash /vagrant/scripts/replica-set/node-config.sh"
done
vagrant ssh node1 -c "sudo bash /vagrant/scripts/replica-set/initiate.sh"
vagrant ssh node1 -c "sudo bash /vagrant/scripts/replica-set/ops.sh status"
```

### B — PSA (Runbook 02)
```bash
vagrant ssh node1 -c "sudo bash /vagrant/scripts/psa/node-config.sh data"
vagrant ssh node2 -c "sudo bash /vagrant/scripts/psa/node-config.sh data"
vagrant ssh node3 -c "sudo bash /vagrant/scripts/psa/node-config.sh arbiter"
vagrant ssh node1 -c "sudo bash /vagrant/scripts/psa/initiate-psa.sh"
```

### C — Sharded Cluster (Runbook 03)
```bash
# Config server RS
for N in node1 node2 node3; do
  vagrant ssh $N -c "sudo bash /vagrant/scripts/sharded-cluster/config-server-setup.sh"
done
vagrant ssh node1 -c "sudo bash /vagrant/scripts/sharded-cluster/config-server-setup.sh --init"

# Shard 1 RS
for N in node1 node2 node3; do
  vagrant ssh $N -c "sudo bash /vagrant/scripts/sharded-cluster/shard-setup.sh"
done
vagrant ssh node1 -c "sudo bash /vagrant/scripts/sharded-cluster/shard-setup.sh --init"

# mongos + add shard
vagrant ssh mgmt -c "sudo bash /vagrant/scripts/sharded-cluster/mongos-setup.sh"
vagrant ssh mgmt -c "sudo bash /vagrant/scripts/sharded-cluster/add-shard.sh"

# Verify từ host:
vagrant ssh mgmt -c "mongosh -u admin -p 'ChangeMe!Admin#2026' --host mgmt:27017/admin --eval 'sh.status({verbose:false})'"
```

### D — Delayed hidden member (Runbook 04, build trên A)
```bash
vagrant ssh node1 -c "sudo bash /vagrant/scripts/hidden-delayed/add-delayed-member.sh 192.168.20.13:27017 86400"
```

### E — Backup (Runbook 05, build trên A)
```bash
vagrant ssh mgmt -c "sudo bash /vagrant/scripts/backup-pitr/mongodump.sh 192.168.20.13:27017"
vagrant ssh mgmt -c "ls -la /var/backups/mongo/"
```

### F — Multi-region DR (Runbook 06, build trên A)
```bash
vagrant ssh mgmt -c "sudo bash /vagrant/scripts/common/01-install-mongo.sh"
vagrant ssh mgmt -c "sudo bash /vagrant/scripts/replica-set/node-config.sh"
vagrant ssh node1 -c "sudo bash /vagrant/scripts/multi-region/add-remote-secondary.sh 192.168.20.20:27017 0 false"
```

## 6. Vận hành VM

| Tác vụ | Lệnh |
|---|---|
| Trạng thái | `make status` |
| SSH | `vagrant ssh node1` |
| Halt | `make down` |
| Reload 1 VM | `vagrant reload node1` |
| Re-run provisioner | `vagrant provision node1 --provision-with install-mongo` |
| Destroy + clean | `make clean` |

## 7. Snapshot để rollback test destructive

```bash
# Snapshot all VMs:
for N in node1 node2 node3 mgmt; do vagrant snapshot save $N clean; done

# Restore:
for N in node1 node2 node3 mgmt; do vagrant snapshot restore $N clean; done
```

Rất hữu ích khi test failover (kill primary), network partition, force-reconfig — chạy chaos rồi rollback nhanh về clean state.

## 8. Troubleshooting

| Triệu chứng | Giải pháp |
|---|---|
| `vagrant up` báo IP conflict `192.168.20.0/24` trùng | Đổi NODES IPs trong `Vagrantfile` + `scripts/common/env.sh` |
| mongod start fail "Permissions on keyfile too open" | `chmod 400 /etc/mongodb/keyfile && chown mongodb:mongodb /etc/mongodb/keyfile` |
| `rs.initiate` báo "already initialized" | `rm -rf /var/lib/mongodb/local && systemctl restart mongod` rồi initiate lại |
| `bento/ubuntu-22.04` không tải được | `vagrant box add bento/ubuntu-22.04` thủ công, hoặc đổi `ubuntu/jammy64` |
| THP vẫn enabled sau restart | `systemctl status disable-thp.service` — phải `active (exited)` |
| Secondary stuck STARTUP2 | Thường initial sync chậm; check `db.currentOp({'desc':/repl/i})` |

## 9. Dọn dẹp hoàn toàn

```bash
make clean              # destroy + xoá SSH key + keyfile
rm -rf .vagrant/        # nếu vẫn còn
```

## 10. Lưu ý

- Mỗi VM chỉ chạy 1 mongod (default port 27017) trừ khi chạy Sharded Cluster (cộng thêm port 27018, 27019).
- Synced folder `../` → `/vagrant` ⇒ chỉnh script trên host được apply ngay trên VM (không cần copy).
- Mật khẩu mặc định trong `scripts/common/env.sh` chỉ cho lab — đổi trước khi clone topology này sang production.


---

!!! info "Nguồn gốc"
    `HA/mongo/runbooks/08-vagrant-lab.md`
