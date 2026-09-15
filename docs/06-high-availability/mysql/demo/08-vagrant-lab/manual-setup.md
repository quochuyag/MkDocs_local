---
title: Hướng dẫn setup THỦ CÔNG — Demo 08 Vagrant Lab (4 VMs Ubuntu 22.04)
course: 06-high-availability
source: HA/Mysql/demo/08-vagrant-lab/MANUAL-SETUP.md
---

# Hướng dẫn setup THỦ CÔNG — Demo 08 Vagrant Lab (4 VMs Ubuntu 22.04)

> Tài liệu này ghi lại **TỪNG CÂU LỆNH** để dựng lab 4 VMs (3 DB + 1 mgmt) làm baseline cho mọi giải pháp HA của Demo 01–07, **không cần** `run-all.sh` / `run-all.ps1`.
>
> Copy-paste theo thứ tự từ trên xuống. Mỗi bước nêu rõ:
> - 🖥️ **Where**: chạy ở đâu (HOST / node1 / node2 / node3 / mgmt)
> - 💻 **Command**: lệnh CLI hoặc SQL
> - 📝 **File**: cấu hình cần ghi (nếu có)
> - ✅ **Verify**: cách kiểm tra step OK
>
> Mục tiêu sau khi xong: **4 VMs `running`**, ping nội bộ OK, `/etc/hosts` chứa 4 entries, swap off, NTP synced, sysctl tuned, `vagrant` user SSH passwordless giữa các VMs, snapshot `clean` để rollback nhanh.

## 0. Topology & biến môi trường

| Host  | IP              | Vai trò                          | vCPU | RAM    |
|-------|-----------------|----------------------------------|------|--------|
| node1 | 192.168.10.11   | DB candidate (master / primary)  | 2    | 2 GB   |
| node2 | 192.168.10.12   | DB candidate                     | 2    | 2 GB   |
| node3 | 192.168.10.13   | DB candidate                     | 2    | 2 GB   |
| mgmt  | 192.168.10.20   | Manager / Proxy / Client         | 1    | 1.5 GB |

Tổng tài nguyên trên host: **7 vCPU, ~7.5 GB RAM**. Khuyến nghị host RAM ≥ 12 GB, disk ≥ 30 GB.

Biến cấu hình lấy từ [scripts/common/env.sh](../../scripts/common/env.sh) — không cần đổi cho demo 08 (chỉ cần đổi nếu subnet `192.168.10.0/24` trùng với mạng host).

---

## B0 · Prerequisites trên HOST

🖥️ **Where**: HOST (Windows / macOS / Linux)

### B0.1 — Cài Vagrant + VirtualBox

```bash
# Linux/macOS — cài qua package manager
sudo apt install virtualbox vagrant      # Ubuntu/Debian
brew install --cask virtualbox vagrant   # macOS

# Windows — tải installer:
#   https://www.virtualbox.org/wiki/Downloads     (≥ 7.0)
#   https://www.vagrantup.com/downloads           (≥ 2.3)
#   https://git-scm.com/download/win              (Git Bash để chạy .sh)
```

> ⚠ **Windows pitfall**: tắt Hyper-V trước khi cài VirtualBox (xung đột hypervisor):
> ```powershell
> bcdedit /set hypervisorlaunchtype off
> # Restart Windows
> ```
> Và bật Intel VT-x / AMD-V trong BIOS.

✅ **Verify**:
```bash
vagrant --version       # 2.3+
VBoxManage --version    # 7.0+    (Windows Git Bash: /c/Program\ Files/Oracle/VirtualBox/VBoxManage.exe)
```

### B0.2 — Free RAM/disk check

```bash
# Linux/macOS
free -h                            # ≥ 8 GB free
df -h .                            # ≥ 30 GB free trên thư mục chứa repo
```
```powershell
# Windows
Get-CimInstance Win32_OperatingSystem | Select FreePhysicalMemory
Get-PSDrive C | Select Used,Free
```

### B0.3 — Subnet conflict check

```bash
# Nếu host đã có route cho 192.168.10.0/24 thì phải đổi IP plan
ip route | grep 192.168.10       # Linux/macOS
```
```powershell
route print -4 | findstr 192.168.10   # Windows
```

Nếu trùng — sửa cả 2 file:
- `vagrant/Vagrantfile` — block `NODES = { ... }`
- `scripts/common/env.sh` — `NODE*_IP`, `MGMT_IP`, `VIP`

---

## B1 · Bring up 4 VMs (HOST)

🖥️ **Where**: HOST, ở thư mục `vagrant/`

### B1.1 — Sinh SSH key dùng chung cho cluster (chỉ 1 lần)

💻 **Command**:
```bash
cd vagrant
bash provision/generate-ssh-key.sh
# tạo provision/cluster_id_rsa + cluster_id_rsa.pub
```

📝 **File output** — `vagrant/provision/cluster_id_rsa` (private key, 4096-bit RSA, không passphrase).

Script source: [vagrant/provision/generate-ssh-key.sh](../../vagrant/provision/generate-ssh-key.sh):
```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
if [[ -f cluster_id_rsa ]]; then
  echo "cluster_id_rsa đã tồn tại. Xoá nếu muốn regenerate."
  exit 0
fi
ssh-keygen -t rsa -b 4096 -N '' -C 'mysql-ha-cluster' -f cluster_id_rsa
chmod 600 cluster_id_rsa
chmod 644 cluster_id_rsa.pub
```

✅ **Verify**:
```bash
ls -la provision/cluster_id_rsa*
# -rw-------  1 user  staff  3.4K  cluster_id_rsa
# -rw-r--r--  1 user  staff   742  cluster_id_rsa.pub
```

### B1.2 — Spin up 4 VMs

💻 **Command**:
```bash
# Linux/macOS:
export VAGRANT_DEFAULT_PROVIDER=virtualbox
# Windows PowerShell:
# $env:VAGRANT_DEFAULT_PROVIDER='virtualbox'

vagrant up node1 --provider=virtualbox --no-destroy-on-error
vagrant up node2 --provider=virtualbox --no-destroy-on-error
vagrant up node3 --provider=virtualbox --no-destroy-on-error
vagrant up mgmt  --provider=virtualbox --no-destroy-on-error
```

Lần đầu mất 10–15 phút (tải box `bento/ubuntu-22.04` ~600 MB). Vagrantfile đã set `boot_timeout = 1200` để tránh timeout trên host yếu.

> ⚠ **Common errors**:
>
> | Lỗi | Cách xử lý |
> |---|---|
> | `VERR_ALREADY_EXISTS` (D:\VM VirtualBox\mysql-ha-nodeX đã tồn tại) | Xem [B1.3](#b13--troubleshooting-orphan-vm-cleanup) |
> | `VERR_INTNET_FLT_IF_NOT_FOUND` adapter not found | Adapter NDIS bị ghost-bind — chạy `vagrant/fix-vbox-hostonly.ps1` (Method A) hoặc tạo Host-Only Adapter mới |
> | `Vagrant could not detect VirtualBox` | Cài VirtualBox 7.0+ trước Vagrant; reboot |
> | `box bento/ubuntu-22.04 not found` | `vagrant box add bento/ubuntu-22.04` thủ công |
> | Box tải chậm | Đổi mirror trong `~/.vagrant.d/data/vagrant_login_token` |

### B1.3 — Troubleshooting orphan VM cleanup

Nếu `vagrant up` báo VM đã tồn tại:
```powershell
# Windows
VBoxManage list vms                                      # nếu thấy "<inaccessible>"
VBoxManage unregistervm <UUID>                            # nếu cần
Remove-Item -Recurse -Force "D:\VM VirtualBox\mysql-ha-node1"
Remove-Item -Recurse -Force "D:\VM VirtualBox\temp_clone_*"
```

Hoặc dùng helper:
```bash
bash vagrant/cleanup.sh --all --dry-run    # xem
bash vagrant/cleanup.sh --all --yes        # thực hiện
```

✅ **Verify**:
```bash
vagrant status
# Output:
# node1                     running (virtualbox)
# node2                     running (virtualbox)
# node3                     running (virtualbox)
# mgmt                      running (virtualbox)

# Test connectivity giữa các node
for N in node1 node2 node3 mgmt; do
  echo "=== $N ==="
  vagrant ssh "$N" -c "for T in node1 node2 node3 mgmt; do \
    [ \"\$T\" = \"\$(hostname)\" ] && continue; \
    ping -c1 -W2 \$T >/dev/null && echo \"\$(hostname) -> \$T OK\" || echo \"FAIL\"; \
  done"
done
```

Mong đợi: 12 dòng `... -> ... OK` (4 × 3 pairs).

---

## B2 · Prepare OS — chạy provisioner `common-prep` trên 4 VMs

🖥️ **Where**: HOST, ở thư mục `vagrant/` — provisioner sẽ tự SSH vào từng VM và chạy `/vagrant/scripts/common/00-prepare-os.sh` với quyền root.

### B2.1 — Trigger provisioner trên từng VM

💻 **Command**:
```bash
for N in node1 node2 node3 mgmt; do
  echo "==> prepare-os $N"
  vagrant provision "$N" --provision-with common-prep
done
```

Script được chạy: [scripts/common/00-prepare-os.sh](../../scripts/common/00-prepare-os.sh) — làm các việc:

| Tác vụ | Chi tiết |
|---|---|
| `/etc/hosts` | Inject block với marker `>>> mysql-ha cluster >>>` (idempotent) |
| Swap off | `swapoff -a` + comment dòng swap trong `/etc/fstab` |
| NTP | `apt install chrony` + `systemctl enable --now chrony` + `timedatectl set-ntp true` |
| sysctl | Ghi `/etc/sysctl.d/99-mysql-ha.conf` (xem B2.4) + `sysctl --system` |
| ulimit | Ghi `/etc/systemd/system/mysql.service.d/limits.conf` + `mysqld.service.d/` (xem B2.5) |
| AppArmor | `systemctl disable --now apparmor` (cho lab) |
| Repo MySQL cũ | Dọn `/etc/apt/sources.list.d/mysql.list*` nếu B3 fail trước đó |

### B2.2 — `/etc/hosts` (nội dung block được inject)

📝 **File** — `/etc/hosts` trên mỗi VM (append nếu chưa có):
```
# >>> mysql-ha cluster >>>
192.168.10.11  node1
192.168.10.12  node2
192.168.10.13  node3
192.168.10.20  mgmt
# <<< mysql-ha cluster <<<
```

> Ghi chú: Vagrantfile provisioner `prep` (chạy tự động khi `vagrant up`) cũng inject một block tương đương với marker `# --- mysql-ha cluster ---`. Sau B2 sẽ có 2 block — đó là bình thường, idempotent.

### B2.3 — Swap

💻 **Tương đương thủ công nếu muốn chạy bằng tay** (SSH vào từng VM, `sudo -i`):
```bash
swapoff -a
sed -i.bak -E '/^[^#].*\sswap\s/s/^/#/' /etc/fstab
```

### B2.4 — sysctl tuning

📝 **File** — `/etc/sysctl.d/99-mysql-ha.conf` (được script tạo):
```ini
vm.swappiness = 1
net.core.somaxconn = 65535
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_keepalive_time = 60
net.ipv4.tcp_keepalive_intvl = 10
net.ipv4.tcp_keepalive_probes = 6
fs.aio-max-nr = 1048576
fs.file-max = 2097152
```

```bash
sysctl --system
```

> ⚠ **Bento box quirk**: `net.ipv4.conf.all.accept_source_route` và `promote_secondaries` có thể báo `Invalid argument` trên bento/ubuntu-22.04 — bỏ qua, không có trong config trên.

### B2.5 — ulimit / systemd limits

📝 **File** — `/etc/systemd/system/mysql.service.d/limits.conf` (và copy sang `mysqld.service.d/`):
```ini
[Service]
LimitNOFILE=1048576
LimitNPROC=65535
```
```bash
systemctl daemon-reload
```

### B2.6 — NTP

```bash
DEBIAN_FRONTEND=noninteractive apt-get update
apt-get install -y chrony
systemctl enable --now chrony
timedatectl set-ntp true
```

### B2.7 — AppArmor (Ubuntu)

```bash
systemctl disable --now apparmor
```

✅ **Verify** (chạy trên HOST sau khi xong cả 4 VMs):
```bash
for N in node1 node2 node3 mgmt; do
  echo "--- $N ---"
  vagrant ssh "$N" -c "
    grep -A4 'mysql-ha cluster' /etc/hosts | head -5
    echo 'swap:'; swapon --show || echo '  swap OFF'
    timedatectl | grep -E 'NTP|synchron'
    sysctl vm.swappiness fs.file-max
  "
done
```

Mong đợi mỗi VM:
- `/etc/hosts` chứa block `mysql-ha cluster`
- `swap OFF` (output rỗng)
- `System clock synchronized: yes`, `NTP service: active`
- `vm.swappiness = 1`, `fs.file-max = 2097152`

---

## B3 · SSH trust giữa `vagrant` user trên 4 VMs

🖥️ **Where**: HOST — chạy provisioner `ssh-trust` (Vagrantfile sẽ inject cùng cặp `cluster_id_rsa` vào cả `/root/.ssh/` và `/home/vagrant/.ssh/`).

> Mục đích: cho phép `vagrant ssh nodeA -c "ssh nodeB hostname"` chạy không cần password. Demo 04 (MHA) cần passwordless cho **root** — đã được set sẵn ở provisioner này. Các demo còn lại chỉ cần qua `vagrant` user.

### B3.1 — Trigger provisioner

💻 **Command**:
```bash
cd vagrant
for N in node1 node2 node3 mgmt; do
  echo "==> ssh-trust $N"
  vagrant provision "$N" --provision-with ssh-trust
done
```

### B3.2 — Provisioner nội dung (đã trong Vagrantfile)

📝 **File** — đoạn shell inline trong [vagrant/Vagrantfile](../../vagrant/Vagrantfile) provisioner `ssh-trust`:
```bash
SRC=/vagrant/vagrant/provision/cluster_id_rsa
SSH_CONF='Host node1 node2 node3 mgmt 192.168.10.*
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null
  LogLevel ERROR'

# --- root ---
mkdir -p /root/.ssh && chmod 700 /root/.ssh
cp  ${SRC}     /root/.ssh/id_rsa
cp  ${SRC}.pub /root/.ssh/id_rsa.pub
grep -qxF "$(cat ${SRC}.pub)" /root/.ssh/authorized_keys 2>/dev/null \
  || cat ${SRC}.pub >> /root/.ssh/authorized_keys
chmod 600 /root/.ssh/id_rsa /root/.ssh/authorized_keys
chmod 644 /root/.ssh/id_rsa.pub
echo "$SSH_CONF" >/root/.ssh/config
chmod 600 /root/.ssh/config

# --- vagrant ---
install -d -o vagrant -g vagrant -m 700 /home/vagrant/.ssh
cp  ${SRC}     /home/vagrant/.ssh/id_rsa
cp  ${SRC}.pub /home/vagrant/.ssh/id_rsa.pub
grep -qxF "$(cat ${SRC}.pub)" /home/vagrant/.ssh/authorized_keys 2>/dev/null \
  || cat ${SRC}.pub >> /home/vagrant/.ssh/authorized_keys
echo "$SSH_CONF" >/home/vagrant/.ssh/config
chown -R vagrant:vagrant /home/vagrant/.ssh
chmod 600 /home/vagrant/.ssh/id_rsa /home/vagrant/.ssh/authorized_keys /home/vagrant/.ssh/config
chmod 644 /home/vagrant/.ssh/id_rsa.pub
```

> 🐛 **Bug đã fix khi viết tài liệu này**: phiên bản cũ chỉ copy vào `/root/.ssh/` → step verify (`vagrant ssh ...` = vagrant user) bị treo đợi password. Sau fix cả root + vagrant đều có key + ssh config.

### B3.3 — Tương đương thủ công nếu không dùng provisioner

Nếu muốn làm bằng tay (mỗi VM, login `vagrant` user):
```bash
# Trên HOST (chỉ 1 lần):
cd vagrant
bash provision/generate-ssh-key.sh

# Trên mỗi VM (SSH vào: vagrant ssh node1, rồi node2, node3, mgmt):
sudo -i

SRC=/vagrant/vagrant/provision/cluster_id_rsa
SSH_CONF='Host node1 node2 node3 mgmt 192.168.10.*
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null
  LogLevel ERROR'

# root
mkdir -p /root/.ssh && chmod 700 /root/.ssh
cp ${SRC} /root/.ssh/id_rsa
cp ${SRC}.pub /root/.ssh/id_rsa.pub
cat ${SRC}.pub >> /root/.ssh/authorized_keys
echo "$SSH_CONF" >/root/.ssh/config
chmod 600 /root/.ssh/id_rsa /root/.ssh/authorized_keys /root/.ssh/config

# vagrant
install -d -o vagrant -g vagrant -m 700 /home/vagrant/.ssh
cp ${SRC} /home/vagrant/.ssh/id_rsa
cp ${SRC}.pub /home/vagrant/.ssh/id_rsa.pub
cat ${SRC}.pub >> /home/vagrant/.ssh/authorized_keys
echo "$SSH_CONF" >/home/vagrant/.ssh/config
chown -R vagrant:vagrant /home/vagrant/.ssh
chmod 600 /home/vagrant/.ssh/id_rsa /home/vagrant/.ssh/authorized_keys /home/vagrant/.ssh/config
```

✅ **Verify**:
```bash
# Trên HOST — 12 cross-SSH (4 nodes × 3 peers):
for N in node1 node2 node3 mgmt; do
  for T in node1 node2 node3 mgmt; do
    [[ "$N" == "$T" ]] && continue
    R=$(vagrant ssh "$N" -c "ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 ${T} hostname 2>/dev/null" | tr -d '\r' | tail -n1)
    [[ "$R" == "$T" ]] && echo "[$N -> $T] OK" || echo "[$N -> $T] FAIL ($R)"
  done
done
```

Mong đợi: **12 dòng `OK`**.

---

## B4 · Verify lab baseline

🖥️ **Where**: HOST — read-only kiểm tra 7 tiêu chí thành công.

### B4.1 — VM state

```bash
for N in node1 node2 node3 mgmt; do
  STATE=$(vagrant status "$N" --machine-readable | awk -F, -v n="$N" '$2==n && $3=="state"{print $4; exit}')
  echo "[$N] state=$STATE"
done
```
Mong đợi: 4 dòng `state=running`.

### B4.2 — Ping nội bộ

```bash
for N in node1 node2 node3 mgmt; do
  for T in node1 node2 node3 mgmt; do
    [[ "$N" == "$T" ]] && continue
    R=$(vagrant ssh "$N" -c "ping -c1 -W2 $T >/dev/null 2>&1 && echo OK || echo FAIL" | tr -d '\r' | tail -n1)
    echo "[$N -> $T] $R"
  done
done
```
Mong đợi: 12 dòng `OK`.

### B4.3 — `/etc/hosts` entries

```bash
for N in node1 node2 node3 mgmt; do
  CNT=$(vagrant ssh "$N" -c "grep -E 'node1|node2|node3|mgmt' /etc/hosts | wc -l" | tr -d '\r' | tail -n1)
  echo "[$N] entries=$CNT"
done
```
Mong đợi: `entries ≥ 4` mỗi VM.

### B4.4 — Swap off

```bash
for N in node1 node2 node3 mgmt; do
  SWAP=$(vagrant ssh "$N" -c "swapon --show 2>/dev/null | wc -l" | tr -d '\r' | tail -n1)
  echo "[$N] swap_lines=$SWAP"
done
```
Mong đợi: `swap_lines=0`.

### B4.5 — NTP

```bash
for N in node1 node2 node3 mgmt; do
  S=$(vagrant ssh "$N" -c "timedatectl 2>/dev/null | awk -F': ' '/synchron/{print \$2}' | tr -d ' \r'" | tail -n1)
  echo "[$N] NTP=$S"
done
```
Mong đợi: `NTP=yes`.

### B4.6 — sysctl

```bash
for N in node1 node2 node3 mgmt; do
  SW=$(vagrant ssh "$N" -c "sysctl -n vm.swappiness" | tr -d '\r' | tail -n1)
  FM=$(vagrant ssh "$N" -c "sysctl -n fs.file-max" | tr -d '\r' | tail -n1)
  echo "[$N] vm.swappiness=$SW  fs.file-max=$FM"
done
```
Mong đợi: `vm.swappiness=1`, `fs.file-max=2097152`.

### B4.7 — SSH cross-trust

```bash
for N in node1 node2 node3 mgmt; do
  for T in node1 node2 node3 mgmt; do
    [[ "$N" == "$T" ]] && continue
    R=$(vagrant ssh "$N" -c "ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 $T hostname 2>/dev/null" | tr -d '\r' | tail -n1)
    [[ "$R" == "$T" ]] && echo "[$N -> $T] OK" || echo "[$N -> $T] FAIL ($R)"
  done
done
```
Mong đợi: 12 dòng `OK`.

---

## B5 · Snapshot `clean` (optional nhưng khuyến nghị)

🖥️ **Where**: HOST.

Mục đích: chụp state "lab ready" để rollback nhanh khi test các demo HA destructive (failover, split-brain, force-shutdown).

### B5.1 — Save snapshot cho 4 VMs

💻 **Command**:
```bash
cd vagrant
for N in node1 node2 node3 mgmt; do
  # Xoá snapshot trùng tên (nếu có)
  if vagrant snapshot list "$N" 2>/dev/null | grep -qx clean; then
    vagrant snapshot delete "$N" clean
  fi
  vagrant snapshot save "$N" clean
done
```

Mất ~1–2 phút (mỗi VM ~30s).

✅ **Verify**:
```bash
for N in node1 node2 node3 mgmt; do
  echo "--- $N ---"
  vagrant snapshot list "$N"
done
# Mỗi VM in ra: clean
```

### B5.2 — Restore snapshot khi cần

```bash
for N in node1 node2 node3 mgmt; do
  vagrant snapshot restore "$N" clean
done
```

> ⚠ Sau restore, các block IP/route có thể cần khởi tạo lại — chạy lại `vagrant reload` hoặc `vagrant ssh nodeX -c "sudo systemctl restart networking"` nếu mất kết nối.

### B5.3 — Xoá snapshot

```bash
for N in node1 node2 node3 mgmt; do
  vagrant snapshot delete "$N" clean
done
```

---

## B6 · Bước tiếp theo

Sau khi xong B1–B5, bạn có lab baseline. Chọn 1 trong các demo HA:

| Demo | Script chạy | Cần MySQL community? |
|------|-------------|----------------------|
| 01 Async/Semi-sync | `bash demo/01-async-semisync/run-all.sh` | ✅ (script tự cài) |
| 02 InnoDB Cluster | `bash demo/02-innodb-cluster/run-all.sh` | ✅ (script tự cài) |
| 03 Group Replication | `bash demo/03-group-replication/run-all.sh` | ✅ (script tự cài) |
| 04 MHA | `bash demo/04-mha/run-all.sh` | ✅ + root SSH passwordless (demo tự setup) — cần demo 01 chạy trước |
| 05 Orchestrator | `bash demo/05-orchestrator/run-all.sh` | ✅ + MySQL trên mgmt — cần demo 01 chạy trước |
| 06 Galera (PXC) | `bash demo/06-galera/run-all.sh` | ❌ — dùng PXC thay thế, **không chạy 01-install-mysql.sh** |
| 07 ProxySQL | `bash demo/07-proxysql/run-all.sh` | ✅ — cần demo 01 hoặc 06 chạy trước |

> ⚠ Các demo 01/02/03 đều có B1 + B2 tương đương demo 08 — sẽ skip nhanh do VMs đã `running` và `/etc/hosts` đã có block.

---

## B7 · Cleanup (destructive)

🖥️ **Where**: HOST.

### B7.1 — Halt (giữ disk + snapshot)

```bash
cd vagrant
vagrant halt
```

### B7.2 — Destroy hoàn toàn

```bash
cd vagrant
vagrant destroy -f
rm -f provision/cluster_id_rsa provision/cluster_id_rsa.pub
rm -rf .vagrant/
```

Hoặc dùng helper interactive:
```bash
bash vagrant/cleanup.sh --all --dry-run    # xem
bash vagrant/cleanup.sh --all --yes        # thực hiện không hỏi
```

Demo 08 cleanup wrapper:
```bash
bash demo/08-vagrant-lab/09-cleanup.sh --all --yes
```

---

## Appendix A · Trouble-shooting tổng hợp

| Triệu chứng | Nguyên nhân | Fix |
|---|---|---|
| `vagrant up` báo IP conflict | Subnet `192.168.10.0/24` trùng host | Đổi NODES IPs trong Vagrantfile + env.sh |
| Box `bento/ubuntu-22.04` không tải | Network / mirror | `vagrant box add bento/ubuntu-22.04` thủ công; hoặc đổi sang `ubuntu/jammy64` |
| `VT-x not available` | Hyper-V đang chiếm | Windows: `bcdedit /set hypervisorlaunchtype off` + reboot; BIOS bật VT-x |
| Provisioner timeout | RAM/IO host thấp | Tăng `config.vm.boot_timeout` trong Vagrantfile; chạy `vagrant up` tuần tự |
| `synced_folder` chậm trên Windows | virtualbox shared folder | Đổi sang `type: "smb"` (cần SMB share) hoặc `type: "rsync"` |
| MySQL repo install fail trong B2 | Key A8D3785C expired | Script đã tự dọn — chạy lại |
| UFW chặn SSH | `02-firewall.sh` đã allow 22 sẵn | Nếu vẫn chặn: `vagrant ssh nodeX -c "sudo ufw allow 22/tcp"` (lưu trong memory: bug_ufw_blocks_ssh.md) |
| Host-Only adapter NDIS ghost-bind | `VERR_INTNET_FLT_IF_NOT_FOUND` adapter #N | Chạy `vagrant/fix-vbox-hostonly.ps1` Method A (memory: bug_vbox_hostonly_ndis_filter.md) |
| `ssh node2 hostname` từ vagrant user treo | Provisioner `ssh-trust` cũ chỉ set root | Đã fix trong B3 — re-run `vagrant provision $N --provision-with ssh-trust` |
| `vagrant halt --force` rồi PXC seqno=-1 | Crash recovery cần | `sudo -u mysql mysqld --wsrep-recover` (memory: bug_pxc_halt_seqno_minus_1_recovery.md) |

## Appendix B · Cấu trúc thư mục liên quan

```
HA/Mysql/
├── vagrant/
│   ├── Vagrantfile                  # 4 VMs definition + 5 provisioners
│   ├── Makefile                     # full-bootstrap = ssh-keys + up + prep-all + install-mysql + ssh-trust
│   ├── cleanup.sh / cleanup.ps1     # destructive cleanup
│   └── provision/
│       ├── generate-ssh-key.sh      # B1.1
│       ├── cluster_id_rsa           # sinh local (gitignored)
│       └── cluster_id_rsa.pub
├── scripts/
│   └── common/
│       ├── env.sh                   # single source of truth: IPs, ports, creds
│       ├── 00-prepare-os.sh         # chạy bởi B2 provisioner `common-prep`
│       ├── 01-install-mysql.sh      # demo 01-05/07 (KHÔNG cho Galera)
│       └── 02-firewall.sh           # UFW rules
├── demo/08-vagrant-lab/
│   ├── 00-overview.md
│   ├── 01-vagrant-up.sh             # B1
│   ├── 02-prepare-os.sh             # B2 (wrapper provisioner common-prep)
│   ├── 03-ssh-trust.sh              # B3 (wrapper provisioner ssh-trust)
│   ├── 04-verify.sh                 # B4
│   ├── 05-snapshot-clean.sh         # B5
│   ├── 09-cleanup.sh                # B7
│   ├── run-all.sh / run-all.ps1     # B1→B4 pipeline
│   ├── MANUAL-SETUP.md              # tài liệu này
│   └── results/                     # logs sau khi chạy
└── runbooks/
    └── 08-vagrant-lab.md             # runbook tham chiếu gốc
```

## Appendix C · Mapping bước → script gốc

| Bước manual | Script demo 08 | Provisioner Vagrantfile | Script trong VM |
|---|---|---|---|
| B0 | — | — | — |
| B1 | `01-vagrant-up.sh` | `prep` (auto) + `banner` (auto) | — |
| B2 | `02-prepare-os.sh` | `common-prep` | `scripts/common/00-prepare-os.sh` |
| B3 | `03-ssh-trust.sh` | `ssh-trust` | (inline shell trong Vagrantfile) |
| B4 | `04-verify.sh` | — | — (chạy `ssh ... hostname` cross VMs) |
| B5 | `05-snapshot-clean.sh` | — | — (chạy `vagrant snapshot save`) |
| B7 | `09-cleanup.sh` | — | — (chạy `vagrant destroy -f` + xoá keys) |

---

**Tham chiếu**:
- Runbook gốc: [runbooks/08-vagrant-lab.md](../../runbooks/008-vagrant-lab.md)
- Vagrantfile: [vagrant/Vagrantfile](../../vagrant/Vagrantfile)
- Env shared: [scripts/common/env.sh](../../scripts/common/env.sh)
- Prepare-OS script: [scripts/common/00-prepare-os.sh](../../scripts/common/00-prepare-os.sh)


---

!!! info "Nguồn gốc"
    `HA/Mysql/demo/08-vagrant-lab/MANUAL-SETUP.md`
