---
title: Bước 2 — Chuẩn bị OS trên 4 nodes
course: 06-high-availability
source: HA/Mysql/demo/02-innodb-cluster/02-prepare-os.md
---

# Bước 2 — Chuẩn bị OS trên 4 nodes

## Mục tiêu
Áp dụng [scripts/common/00-prepare-os.sh](../../scripts/common/00-prepare-os.sh) trên cả 4 VM:
- Inject `/etc/hosts`
- Tắt swap
- Bật NTP (chrony) — **bắt buộc** với Group Replication
- Sysctl tuning cho MySQL/cluster
- `ulimit` cho service mysql
- AppArmor → permissive (lab only)

> Bước này **giống hệt** demo 01.

## Cách chạy

```bash
bash demo/02-innodb-cluster/02-prepare-os.sh
```

## Vì sao NTP quan trọng với GR

Group Replication dùng **certifier** để giải quyết xung đột transaction giữa các node trong multi-primary (và để track GTID trong single-primary). Certifier so sánh dấu thời gian của các binlog entry. Nếu đồng hồ giữa các node lệch nhiều giây → certifier sẽ flag "transaction conflict" giả → node bị **expel** (loại khỏi group). Bật `chrony` đảm bảo skew ≤ 50ms.

## Verify

```bash
vagrant ssh node1 -c "cat /etc/hosts | grep mysql-ha -A4"
vagrant ssh node1 -c "swapon --show || echo 'swap OFF (OK)'"
vagrant ssh node1 -c "timedatectl | grep -E 'NTP|synchronized'"
vagrant ssh node1 -c "sysctl vm.swappiness fs.file-max"
```

Kỳ vọng:
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
| `apt-get update` lỗi DNS | `vagrant ssh nodeX -c "cat /etc/resolv.conf"` → đảm bảo có `8.8.8.8` |
| `timedatectl: NTP service: inactive` | `vagrant ssh nodeX -c "systemctl restart chrony && timedatectl set-ntp true"` |
| AppArmor block sau provision | `vagrant reload nodeX` |


---

!!! info "Nguồn gốc"
    `HA/Mysql/demo/02-innodb-cluster/02-prepare-os.md`
