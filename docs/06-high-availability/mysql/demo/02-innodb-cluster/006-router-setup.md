---
title: Bước 6 — Cài + Bootstrap MySQL Router trên mgmt
course: 06-high-availability
source: HA/Mysql/demo/02-innodb-cluster/06-router-setup.md
---

# Bước 6 — Cài + Bootstrap MySQL Router trên mgmt

## Mục tiêu
Trên `mgmt`:
1. Cài package `mysql-router` + `mysql-shell` + `mysql-client` từ APT repo Oracle (mgmt không có `mysql-server`).
2. `mysqlrouter --bootstrap` để Router đọc metadata cluster từ node1 và sinh config tự động.
3. Khởi động Router service, expose `:6446` (RW → primary) và `:6447` (RO → secondaries round-robin).
4. Mở firewall 6446 + 6447.

## Cách chạy

```bash
bash demo/02-innodb-cluster/06-router-setup.sh
```

## Diễn giải

Script chạy 2 phần trên mgmt:

### Phần 1 — Cài Router (lần đầu)
```bash
# Trong mgmt:
wget /tmp/mysql-apt.deb https://dev.mysql.com/get/mysql-apt-config_0.8.29-1_all.deb
dpkg -i /tmp/mysql-apt.deb
apt-get update
apt-get install -y mysql-router mysql-shell mysql-client
```

### Phần 2 — Bootstrap + start service
Gọi [scripts/innodb-cluster/router-setup.sh](../../scripts/innodb-cluster/router-setup.sh):
```bash
mysqlrouter --bootstrap clusteradmin:...@192.168.10.11:3306 \
            --directory /var/lib/mysqlrouter \
            --conf-use-sockets \
            --conf-bind-address 0.0.0.0 \
            --user mysqlrouter \
            --force
```

Bootstrap thực hiện:
1. Connect tới node1 với `clusteradmin`.
2. Đọc `mysql_innodb_cluster_metadata.*` để lấy danh sách member.
3. Tạo user dedicate `mysql_router1_xxx@%` cho Router (mật khẩu random, lưu trong `/var/lib/mysqlrouter/mysqlrouter.conf`).
4. Sinh `/var/lib/mysqlrouter/mysqlrouter.conf` với 4 listener:
   - `:6446` — Classic RW (luôn route đến PRIMARY).
   - `:6447` — Classic RO (round-robin các SECONDARY).
   - `:64460` — X-Protocol RW.
   - `:64470` — X-Protocol RO.
5. Tạo `start.sh` / `stop.sh` + systemd unit `mysqlrouter.service`.

### Vì sao Router đặt trên mgmt, không phải db nodes?

- **Tách concern**: nếu Router ở chung node DB và node đó chết, app mất luôn cả Router → mất truy cập cluster (dù còn 2 node sống). Đặt Router ở host độc lập tránh single point ở data plane.
- **Trong production**: nên có **2 Router instances** (active-active behind a load balancer / Anycast / haproxy). Lab demo chỉ chạy 1 instance trên mgmt.
- **Pattern phổ biến khác**: Router on each app server — gần app nhất, tránh thêm 1 hop network. Phù hợp khi có 5-10 app servers, không phù hợp khi 1000+.

## Verify

```bash
# Trên host:
vagrant ssh mgmt -c "sudo systemctl status mysqlrouter --no-pager"
vagrant ssh mgmt -c "sudo ss -tlnp | egrep ':6446 |:6447 '"

# Test routing: 6446 phải ra primary, 6447 round-robin secondaries
vagrant ssh mgmt -c "for i in 1 2 3; do \
  mysql -uclusteradmin -p'ChangeMe!Admin#2026' -h127.0.0.1 -P6446 -N -e 'SELECT @@hostname'; done"
vagrant ssh mgmt -c "for i in 1 2 3; do \
  mysql -uclusteradmin -p'ChangeMe!Admin#2026' -h127.0.0.1 -P6447 -N -e 'SELECT @@hostname'; done"
```

Kỳ vọng:
```
# mysqlrouter.service: active (running)
# 6446 → tcp LISTEN 0 0.0.0.0:6446
# 6447 → tcp LISTEN 0 0.0.0.0:6447
# :6446 (RW) — 3 lần đều ra node1 (vì node1 là primary):
node1
node1
node1
# :6447 (RO) — round-robin giữa node2 + node3:
node2
node3
node2
```

## Lỗi thường gặp

| Lỗi | Khắc phục |
|-----|-----------|
| `mysqlrouter: command not found` trên mgmt | Quên cài; chạy lại phần install trong `06-router-setup.sh` |
| `Bootstrap failed: This account already exists` | Bootstrap rerun → thêm `--account-host <ip>` hoặc dùng `--force` (đã set) |
| `:6446 connection refused` từ ngoài mgmt | UFW chặn — `sudo ufw allow 6446 && sudo ufw allow 6447` |
| `Error: HTTP errors at REST API` | Cluster status xấu — kiểm tra B5 lại |
| `MySQL Error 2002 Can't connect via UNIX socket` | Router config dùng TCP, không cần socket; check `mysqlrouter.conf` |
| `Cluster not available` khi connect Router | Router cache metadata 5s, đợi và retry. Xem `/var/lib/mysqlrouter/log/mysqlrouter.log` |

## Cấu trúc thư mục Router sau bootstrap

```
/var/lib/mysqlrouter/
├── data/                       # state files
├── log/mysqlrouter.log         # main log
├── run/                        # pid + socket files
├── mysqlrouter.conf            # main config (port, user, cluster URI)
├── start.sh / stop.sh          # wrapper scripts
└── README.md
```


---

!!! info "Nguồn gốc"
    `HA/Mysql/demo/02-innodb-cluster/06-router-setup.md`
