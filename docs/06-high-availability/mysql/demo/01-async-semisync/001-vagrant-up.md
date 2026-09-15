---
title: Bước 1 — Khởi tạo 4 VMs Ubuntu 22.04 bằng Vagrant
course: 06-high-availability
source: HA/Mysql/demo/01-async-semisync/01-vagrant-up.md
---

# Bước 1 — Khởi tạo 4 VMs Ubuntu 22.04 bằng Vagrant

## Mục tiêu
Spin up 4 máy ảo theo topology cluster, chưa cài MySQL.

## Tiền đề
- Đã cài Vagrant + VirtualBox.
- Cổng `22` & subnet `192.168.10.0/24` chưa bị xung đột với mạng host.
- Ở thư mục gốc của repo (chỗ có `vagrant/Vagrantfile`).

## Cách chạy

```bash
bash demo/01-async-semisync/01-vagrant-up.sh
```

Hoặc thủ công:
```bash
cd vagrant
bash provision/generate-ssh-key.sh    # sinh SSH key dùng chung cho cluster
vagrant up
```

## Diễn giải kỹ thuật

`vagrant up` đọc [vagrant/Vagrantfile](../../vagrant/Vagrantfile) và thực hiện:
1. Tải box `bento/ubuntu-22.04` (lần đầu ~600 MB).
2. Clone linked-clone 4 VM: `mysql-ha-node1`, `node2`, `node3`, `mgmt`.
3. Network: 1 NAT (internet) + 1 private host-only (`192.168.10.0/24`).
4. Provision `prep` (luôn chạy): inject `/etc/hosts`, cài curl/wget/net-tools.
5. Provision `banner`: ghi `/etc/motd` chào mừng.

Các provisioner sau đây có `run: "never"` → **không tự chạy**, đợi `vagrant provision` thủ công ở bước 2 & 3:
- `common-prep`
- `install-mysql`
- `ssh-trust`

## Verify

```bash
vagrant status                # phải thấy 4 VM "running"
vagrant ssh node1 -c "hostname && ip -4 addr show eth1 | grep inet"
vagrant ssh node1 -c "ping -c2 node2 && ping -c2 node3 && ping -c2 mgmt"
```

Kết quả mong đợi:
```
Current machine states:
node1                     running (virtualbox)
node2                     running (virtualbox)
node3                     running (virtualbox)
mgmt                      running (virtualbox)
```
và `ping` thành công sang 3 host còn lại.

## Troubleshooting

| Lỗi | Khắc phục |
|-----|-----------|
| `Vagrant cannot forward port 2222` | đổi range port hoặc tắt VM cũ đang chiếm |
| `VBoxManage: error: Could not find a controller` | cài lại VirtualBox 7.x, reboot host |
| `Host-only adapter creation failed` | trên Win10/11: chạy PowerShell as Admin, hoặc tắt `Hyper-V`/`WSL2` (đối với VirtualBox) |
| Box download chậm/đứt | `vagrant box add bento/ubuntu-22.04 --force` thử lại |


---

!!! info "Nguồn gốc"
    `HA/Mysql/demo/01-async-semisync/01-vagrant-up.md`
