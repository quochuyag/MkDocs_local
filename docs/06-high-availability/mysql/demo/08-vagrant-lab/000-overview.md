---
title: 00 — Tổng quan bài demo
course: 06-high-availability
source: HA/Mysql/demo/08-vagrant-lab/00-overview.md
---

# 00 — Tổng quan bài demo

## Mục tiêu

Chỉ dựng **lab Vagrant 4 VMs** với baseline provisioning (OS prep + SSH trust giữa các VMs). Không cài MySQL, không setup HA. Mục đích:
1. Cho người mới tập làm quen với Vagrant + VirtualBox.
2. Snapshot "clean" để rollback nhanh khi test các demo HA destructive.
3. Validate host machine đủ tài nguyên (RAM, disk, network).

## Sự khác biệt vs các demo khác

| Demo khác | Demo 08 |
|-----------|---------|
| Tự dựng lab + cài MySQL + cài giải pháp HA | Chỉ dựng lab thuần, dừng ở mức "VMs ready" |
| Có B7/B8 failover destructive | Không destructive — không có gì để break |
| Cuối cùng là demo report PASS/FAIL của HA | Cuối cùng là "lab ready" |

## Phạm vi

| Có | Không |
|----|-------|
| Vagrant up 4 VMs Ubuntu 22.04 | Cài MySQL hoặc bất kỳ DB engine nào |
| OS prep: hosts, swap, NTP, sysctl | Setup replication / cluster |
| SSH trust giữa VMs (shared key) | SSH passwordless root (đặc thù MHA) |
| VirtualBox snapshot để rollback | Backup / DR |

## Tiêu chí thành công

| # | Tiêu chí | Cách kiểm tra |
|---|----------|---------------|
| 1 | 4 VMs running | `vagrant status` |
| 2 | Ping nội bộ (node1 ↔ node2 ↔ node3 ↔ mgmt) | ICMP test |
| 3 | `/etc/hosts` chứa 4 entries trên mọi VM | `grep mysql-ha /etc/hosts` |
| 4 | `swapon --show` empty | swap đã off |
| 5 | `timedatectl` báo `synchronized: yes` | NTP OK |
| 6 | `vm.swappiness=1`, `fs.file-max≥1048576` | sysctl |
| 7 | vagrant user SSH sang VM khác không cần password | `vagrant ssh node1 -c "ssh node2 hostname"` |

## Thời gian ước tính

| Pha | Thời gian |
|-----|-----------|
| `vagrant up` lần đầu (tải box ~600 MB) | 10–15 phút |
| Prepare OS | 1–2 phút |
| SSH trust | 30s |
| Verify | 30s |
| Snapshot clean (optional) | 1–2 phút |
| **Tổng** | **~15–20 phút** |

## Cuối cùng

Sau khi xong, bạn có thể:
- Chạy `bash demo/01-async-semisync/run-all.sh` (skip B1+B2 vì đã làm)
- `bash demo/02-innodb-cluster/run-all.sh` (B1+B2 sẽ skip nhanh do VMs đã running)
- Hoặc làm `for N in node1 node2 node3 mgmt; do vagrant snapshot save $N clean; done` để có baseline rollback.


---

!!! info "Nguồn gốc"
    `HA/Mysql/demo/08-vagrant-lab/00-overview.md`
