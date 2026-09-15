---
title: Bước 1 — Khởi tạo 4 VMs Ubuntu 22.04 bằng Vagrant
course: 06-high-availability
source: HA/Mysql/demo/02-innodb-cluster/01-vagrant-up.md
---

# Bước 1 — Khởi tạo 4 VMs Ubuntu 22.04 bằng Vagrant

## Mục tiêu
Spin up 4 máy ảo theo topology cluster, chưa cài MySQL.

> Bước này **giống hệt** demo 01 — dùng chung Vagrantfile [`vagrant/Vagrantfile`](../../vagrant/Vagrantfile).
> Nếu bạn vừa chạy demo 01 và VMs vẫn `running`, có thể bỏ qua bước này.

## Tiền đề
- Đã cài Vagrant + VirtualBox.
- Cổng `22` & subnet `192.168.10.0/24` chưa bị xung đột với mạng host.
- Ở thư mục gốc của repo (chỗ có `vagrant/Vagrantfile`).

## Cách chạy

```bash
bash demo/02-innodb-cluster/01-vagrant-up.sh
```

Hoặc thủ công:
```bash
cd vagrant
bash provision/generate-ssh-key.sh
vagrant up
```

## Diễn giải kỹ thuật

`vagrant up` đọc [vagrant/Vagrantfile](../../vagrant/Vagrantfile) và thực hiện:
1. Tải box `bento/ubuntu-22.04` (lần đầu ~600 MB).
2. Clone linked-clone 4 VM: `mysql-ha-node1`, `node2`, `node3`, `mgmt`.
3. Network: 1 NAT (internet) + 1 private host-only (`192.168.10.0/24`).
4. Provision `prep` (luôn chạy): inject `/etc/hosts`, cài curl/wget/net-tools.

Các provisioner sau có `run: "never"` → đợi gọi thủ công ở B2/B3:
- `common-prep`
- `install-mysql`
- `ssh-trust`

## Verify

```bash
vagrant status                # 4 VM "running"
vagrant ssh node1 -c "hostname && ip -4 addr show eth1 | grep inet"
vagrant ssh node1 -c "ping -c2 node2 && ping -c2 node3 && ping -c2 mgmt"
```

Kỳ vọng: cả 4 VM `running` và ping thành công.

## Troubleshooting

Xem [demo/01-async-semisync/01-vagrant-up.md](../01-async-semisync/001-vagrant-up.md) — bảng lỗi giống nhau (port forwarding, host-only adapter, VirtualBox controller).


---

!!! info "Nguồn gốc"
    `HA/Mysql/demo/02-innodb-cluster/01-vagrant-up.md`
