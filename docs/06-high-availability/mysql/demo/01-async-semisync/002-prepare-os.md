---
title: Bước 2 — Chuẩn bị OS trên 4 nodes
course: 06-high-availability
source: HA/Mysql/demo/01-async-semisync/02-prepare-os.md
---

# Bước 2 — Chuẩn bị OS trên 4 nodes

## Mục tiêu
Áp dụng [scripts/common/00-prepare-os.sh](../../scripts/common/00-prepare-os.sh) trên cả 4 VM:
- Inject `/etc/hosts`
- Tắt swap
- Bật NTP (chrony) — quan trọng cho replication
- Sysctl tuning cho MySQL/cluster
- `ulimit` cho service mysql
- AppArmor → permissive (lab only)

## Cách chạy

```bash
bash demo/01-async-semisync/02-prepare-os.sh
```

## Diễn giải

`vagrant provision <vm> --provision-with common-prep` gọi inline script trong Vagrantfile, mà inline đó chỉ chạy `bash /vagrant/scripts/common/00-prepare-os.sh`. Vì `/vagrant` được share đến repo gốc trên host, mọi sửa đổi script trên host được áp dụng ngay.

Trên các node thuộc cụm Galera/MySQL, chỉ cần chạy `00-prepare-os.sh` 1 lần. Việc rerun an toàn vì script idempotent (mọi append vào `/etc/hosts` được lọc bằng pattern, sysctl/limits dùng drop-in file).

## Verify

```bash
vagrant ssh node1 -c "cat /etc/hosts | grep mysql-ha -A4"
vagrant ssh node1 -c "swapon --show || echo 'swap OFF (OK)'"
vagrant ssh node1 -c "timedatectl | grep -E 'NTP|synchronized'"
vagrant ssh node1 -c "sysctl vm.swappiness fs.file-max"
```

Mong đợi:
```
# --- mysql-ha cluster ---
192.168.10.11  node1
192.168.10.12  node2
192.168.10.13  node3
192.168.10.20  mgmt
swap OFF (OK)
NTP service: active
System clock synchronized: yes
vm.swappiness = 1
fs.file-max = 2097152
```

## Lỗi thường gặp

| Lỗi | Khắc phục |
|-----|-----------|
| `apt-get update` lỗi do DNS | `vagrant ssh node1 -c "cat /etc/resolv.conf"` → đảm bảo có `8.8.8.8` |
| `timedatectl: NTP service: inactive` | `vagrant ssh node1 -c "systemctl restart chrony && timedatectl set-ntp true"` |
| AppArmor reload sau provision | `vagrant reload node1` (chỉ cần nếu lỗi khi cài MySQL) |


---

!!! info "Nguồn gốc"
    `HA/Mysql/demo/01-async-semisync/02-prepare-os.md`
