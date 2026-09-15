---
title: 'Bước 8 — Smoke test: ghi qua Router :6446, đọc qua Router :6447'
course: 06-high-availability
source: HA/Mysql/demo/02-innodb-cluster/08-smoke-test.md
---

# Bước 8 — Smoke test: ghi qua Router :6446, đọc qua Router :6447

## Mục tiêu
Chứng minh **end-to-end flow qua Router**:
1. Tạo DB `smoke_db`, table `t(id, val, ts)` qua `mgmt:6446` (Router RW → primary).
2. Insert N rows qua `mgmt:6446`.
3. Trên cả 3 node (truy vấn trực tiếp): poll `SELECT COUNT(*) FROM smoke_db.t` đến khi = N hoặc timeout.
4. Đọc qua `mgmt:6447` (RO) — verify Router round-robin giữa các secondary.
5. Đối chiếu `gtid_executed` 3 node.

## Cách chạy

```bash
bash demo/02-innodb-cluster/08-smoke-test.sh
# Hoặc tuỳ chỉnh:
ROWS=500 bash demo/02-innodb-cluster/08-smoke-test.sh
```

## Diễn giải

| Pha | Endpoint | Action | Kỳ vọng |
|-----|----------|--------|---------|
| Setup | `mgmt:6446` | `CREATE DATABASE smoke_db; CREATE TABLE t(...)` | Replicate xuống 2 secondary qua GR |
| Write | `mgmt:6446` | Loop 200 INSERT | Router route hết về primary; GR consensus xác nhận trên ≥ 2 node trước khi commit |
| Read direct | node1/2/3 SQL | `SELECT COUNT(*) FROM t` | Đến 200 trong < 1s |
| Read via Router | `mgmt:6447` × 6 lần | `SELECT @@hostname, COUNT(*) FROM t` | Round-robin 2 secondaries, mỗi hit thấy đủ 200 rows |
| GTID check | direct | `SELECT @@global.gtid_executed` | 3 node bằng nhau |

> **Khác biệt với demo 01**: smoke 01 viết SQL trực tiếp vào master node1; smoke 02 đi qua **Router :6446** — đúng như app trong production. Việc này verify Router config đúng (không phải chỉ verify GR đúng).

## Output

[results/08-smoke-test.log](results/08-smoke-test.log) gồm:
- Time elapsed cho insert qua Router
- Time elapsed cho mỗi node để đạt N rows
- Phân phối hit `:6447` qua các secondary
- 3 GTID set
- Bảng kết quả `SMOKE_PASS=true/false`

## Kết quả mong đợi (lab điển hình)

```
[mgmt:6446] insert 200 rows: 0.5s
[node1] saw 200 rows after: 0.0s (primary, source)
[node2] saw 200 rows after: 0.18s
[node3] saw 200 rows after: 0.22s
[mgmt:6447] hit #1 -> node2 (count=200)
[mgmt:6447] hit #2 -> node3 (count=200)
[mgmt:6447] hit #3 -> node2 (count=200)
[mgmt:6447] hit #4 -> node3 (count=200)
gtid_executed bằng nhau giữa 3 node
SMOKE_PASS=true
```

## Cleanup (optional)

Smoke test KHÔNG drop `smoke_db` — để bước 9 (failover) tiếp tục dùng. Nếu muốn dọn:
```bash
vagrant ssh mgmt -c "mysql -uclusteradmin -p'ChangeMe!Admin#2026' -h127.0.0.1 -P6446 -e 'DROP DATABASE smoke_db;'"
```

## Lỗi thường gặp

| Hiện tượng | Nguyên nhân | Khắc phục |
|------------|-------------|-----------|
| `Router :6446 connection refused` | Service down | `vagrant ssh mgmt -c "sudo systemctl status mysqlrouter"` |
| Insert chậm bất thường (> 5s/200 rows) | GR consensus latency cao do CPU/net | `SHOW STATUS LIKE 'group_replication%'`; kiểm tra `Count_Conflicts_Detected` |
| Secondary đếm < N rows mãi | Member RECOVERING/ERROR | `SELECT * FROM PS.replication_group_member_stats\G` |
| Router :6447 đôi khi route về primary | Policy đổi sang `round-robin` (default) thay vì `round-robin-with-fallback` | `cat /var/lib/mysqlrouter/mysqlrouter.conf` — section `[routing:bootstrap_ro]` |
| `Read-only file system` khi insert | Lỡ tay nhập vào :6447 thay vì :6446 | Kiểm tra port |


---

!!! info "Nguồn gốc"
    `HA/Mysql/demo/02-innodb-cluster/08-smoke-test.md`
