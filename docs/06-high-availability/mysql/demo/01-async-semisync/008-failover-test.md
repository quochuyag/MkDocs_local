---
title: Bước 8 — Failover thủ công khi master chết
course: 06-high-availability
source: HA/Mysql/demo/01-async-semisync/08-failover-test.md
---

# Bước 8 — Failover thủ công khi master chết

## Mục tiêu
Mô phỏng node1 (master) chết bằng `vagrant halt`. Promote node2 thành master mới. Reconfigure node3 trỏ về node2. Verify ghi/đọc trên cluster sau khi failover.

> **Cảnh báo**: bước này **phá vỡ replication** ban đầu. Sau khi xong, phải chạy [09-rollback.sh](09-rollback.sh) để dọn hoặc demo lại từ đầu.

## Cách chạy

```bash
bash demo/01-async-semisync/08-failover-test.sh
```

## Kịch bản

| Step | Action | Verify |
|------|--------|--------|
| 1 | Insert "tail row" lên node1 (sentinel) | Cả 2 replica nhận được trước khi halt |
| 2 | `vagrant halt --force node1` | `vagrant status node1 = poweroff` |
| 3 | Chờ node2 IO thread fail | `Last_IO_Error: error connecting to source 'repl@node1'` |
| 4 | Trên node2: chạy `manual-failover.sh` với `NEW_MASTER_IP=192.168.10.12` | `super_read_only=0`, replica reset |
| 5 | Trên node3: `CHANGE REPLICATION SOURCE TO SOURCE_HOST='node2'...` | replica running, lag=0 |
| 6 | Write 50 row mới lên node2 (master mới) | node3 đếm = 50 trong < 1s |
| 7 | Khởi động lại node1, làm clean replica của node2 | (manual) |

> **Vì sao chọn node2 làm master mới?** Trong demo, cả 2 replica đều nhận đủ GTID. Production: chọn replica có `gtid_executed` lớn nhất.

## Output

[results/08-failover.log](results/08-failover.log) gồm:
- Trạng thái node trước khi halt
- Last_IO_Error trên replicas sau khi halt
- Promote process trên node2
- Reconfigure node3
- Verify ghi trên master mới
- Bảng kết quả `FAILOVER_PASS=true/false`

## Kết quả mong đợi

```
[node1] sentinel row id=201 inserted
[node2] sentinel row id=201 visible
[node3] sentinel row id=201 visible
[host]  halt node1...
[node2] IO_Error detected (poll < 30s): error connecting to source
[node2] promote: STOP REPLICA; RESET REPLICA ALL; super_read_only=0
[node3] CHANGE REPLICATION SOURCE TO 'node2'; START REPLICA
[node3] IO/SQL = Yes, Source_Host=node2, lag=0
[node2] INSERT 50 rows... 0.2s
[node3] saw 50 rows after 0.15s
FAILOVER_PASS=true (RTO ~ 10-20s manual)
```

## Khôi phục node1 thành replica (post-failover)

Khi node1 sống lại, **không được tự ý cho lại làm master** — nó có thể có binlog đã ghi mà 2 node kia chưa nhận → split-brain. Cách an toàn:

```bash
# 1) start node1 trở lại
vagrant up node1

# 2) trên node1: RESET MASTER (xoá binlog cũ) + CHANGE REPLICATION SOURCE -> node2
vagrant ssh node1 -c "mysql -uroot -p'ChangeMe!Root#2026' -e \"
  STOP REPLICA;
  RESET REPLICA ALL;
  RESET MASTER;       -- chỉ làm khi chắc chắn không cần binlog cũ
  CHANGE REPLICATION SOURCE TO
    SOURCE_HOST='node2', SOURCE_PORT=3306,
    SOURCE_USER='repl', SOURCE_PASSWORD='ChangeMe!Repl#2026',
    SOURCE_AUTO_POSITION=1,
    SOURCE_SSL=1, GET_SOURCE_PUBLIC_KEY=1;
  START REPLICA;
  SET GLOBAL read_only=ON;
  SET GLOBAL super_read_only=ON;
\""
```

> Production: bước này nên dùng **clone plugin** hoặc **xtrabackup** để rebuild data, không chỉ `RESET MASTER`.

## Lỗi thường gặp

| Hiện tượng | Nguyên nhân | Khắc phục |
|------------|-------------|-----------|
| `manual-failover.sh` không thoát vòng `until` | SQL thread đang xử lý long-running stmt | Tăng timeout / kill query / kiểm tra `SHOW PROCESSLIST` |
| node3 không reconfigure được | DNS cache `node1` cũ | Dùng IP 192.168.10.12 thay vì hostname |
| Write vào node2 báo `--read-only` | Quên reset super_read_only | `SET GLOBAL super_read_only=0; SET GLOBAL read_only=0;` |


---

!!! info "Nguồn gốc"
    `HA/Mysql/demo/01-async-semisync/08-failover-test.md`
