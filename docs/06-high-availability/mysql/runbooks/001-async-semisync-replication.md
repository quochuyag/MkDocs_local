---
title: Runbook 01 — Async / Semi-Synchronous Replication
course: 06-high-availability
source: HA/Mysql/runbooks/01-async-semisync-replication.md
---

# Runbook 01 — Async / Semi-Synchronous Replication

## 1. Khi nào dùng

| Tiêu chí | Async | Semi-Sync |
|---|---|---|
| Độ trễ commit | Nhanh nhất | Chờ ≥1 replica ack (≤ vài ms) |
| Mất dữ liệu khi master chết | Có thể mất | Gần như không (nếu replica còn sống) |
| Setup phức tạp | Thấp | Thấp (chỉ thêm plugin) |
| Failover | Thủ công hoặc dùng MHA/Orchestrator | Thủ công hoặc dùng MHA/Orchestrator |

Khuyến nghị: bật **semi-sync** mặc định, kết hợp Orchestrator hoặc MHA để có auto-failover.

## 2. Tiền đề

- 3 nodes Linux đã chạy `scripts/common/00-prepare-os.sh` + `01-install-mysql.sh` + `02-firewall.sh`.
- MySQL 8.0 đã có `gtid_mode=ON`, `log_bin=ON`, `binlog_format=ROW` (script common đã set).
- Connectivity 3306 giữa 3 nodes.

## 3. Các bước

### B1. Master (node1)
```bash
bash scripts/async-semisync/master-setup.sh
```
Script này: cài plugin `semisync_source`, set `rpl_semi_sync_source_enabled=1`, tạo user `repl`, ghi config vĩnh viễn vào `/etc/mysql/mysql.conf.d/zz-semisync.cnf`.

### B2. Replicas (node2, node3)
```bash
bash scripts/async-semisync/replica-setup.sh
```
Cài plugin `semisync_replica`, `CHANGE REPLICATION SOURCE ... SOURCE_AUTO_POSITION=1`, `START REPLICA`, set `super_read_only=ON` để chống ghi.

### B3. Verify
Trên master:
```sql
SHOW STATUS LIKE 'Rpl_semi_sync_source_status';     -- ON
SHOW STATUS LIKE 'Rpl_semi_sync_source_clients';    -- 2
SHOW STATUS LIKE 'Rpl_semi_sync_source_yes_tx';     -- tăng dần theo write
```
Trên replica:
```sql
SHOW REPLICA STATUS\G   -- Replica_IO_Running / Replica_SQL_Running = Yes, Seconds_Behind_Source = 0
SHOW STATUS LIKE 'Rpl_semi_sync_replica_status';    -- ON
```

### B4. Smoke test
```sql
-- trên master
CREATE DATABASE smoke; USE smoke;
CREATE TABLE t(id INT PRIMARY KEY, val VARCHAR(64));
INSERT INTO t VALUES (1, 'hello');

-- trên replica (sau ~ms)
SELECT * FROM smoke.t;   -- thấy row
```

## 4. Vận hành thường gặp

### 4.1 Replica bị lag
```sql
SHOW REPLICA STATUS\G
-- Tăng đa luồng SQL:
STOP REPLICA SQL_THREAD;
SET GLOBAL replica_parallel_workers = 8;
SET GLOBAL replica_parallel_type = 'LOGICAL_CLOCK';
SET GLOBAL replica_preserve_commit_order = ON;
START REPLICA SQL_THREAD;
```

### 4.2 Replica báo lỗi GTID inconsistency
- Tìm GTID lỗi trong `SHOW REPLICA STATUS\G` → `Last_SQL_Error`.
- Skip transaction:
```sql
STOP REPLICA;
SET GTID_NEXT='<uuid:N>'; BEGIN; COMMIT; SET GTID_NEXT='AUTOMATIC';
START REPLICA;
```
- Hoặc rebuild replica bằng clone plugin / xtrabackup.

### 4.3 Failover thủ công khi master chết
```bash
# Trên replica có dữ liệu mới nhất (xem GTID Executed lớn nhất)
NEW_MASTER_IP=192.168.10.12 bash scripts/async-semisync/manual-failover.sh
```
Sau đó cập nhật app/DNS/ProxySQL trỏ về master mới.

## 4bis. Idempotency & rerun an toàn

Mọi script trong solution 01 được thiết kế để **chạy lại nhiều lần không gây hại**. Bảng dưới ghi rõ hành vi khi rerun:

| Script | Hành vi khi rerun | Mechanism |
|---|---|---|
| `scripts/common/00-prepare-os.sh` | Không duplicate /etc/hosts | Marker block `# >>> mysql-ha cluster >>>` … `# <<<`, xoá-rồi-append |
| `scripts/common/00-prepare-os.sh` | Không chồng `#` lên `/etc/fstab` swap | Regex `^[^#]` chỉ match dòng chưa comment |
| `scripts/common/01-install-mysql.sh` | Skip toàn bộ nếu MySQL chạy & root auth OK | Block idempotency check ở đầu script |
| `scripts/common/01-install-mysql.sh` | mysql-tools repo luôn enable | `dpkg-reconfigure` + failsafe ghi `mysql.list` thủ công |
| `scripts/async-semisync/master-setup.sh` | INSTALL PLUGIN chỉ chạy 1 lần | Prepared SQL: `IF (count=0, "INSTALL …", "DO 0")` |
| `scripts/async-semisync/master-setup.sh` | User repl không trùng / không lỗi | `CREATE USER IF NOT EXISTS` + `ALTER USER` để reset password |
| `scripts/async-semisync/replica-setup.sh` | Replica đang OK → skip `CHANGE REPLICATION SOURCE` | Pre-check `performance_schema.replication_*` (IO=ON, SQL=ON, HOST khớp, AUTO_POSITION=1) |
| `scripts/async-semisync/replica-setup.sh` | INSTALL PLUGIN replica chỉ chạy 1 lần | Prepared SQL conditional |
| `demo/.../run-all.sh` | Tự resume từ step OK cuối cùng | State file `results/.last_ok_step`, flag `--resume` / `--from=BN` / `--fresh` |

### Lệnh rerun thông dụng

```bash
# Chạy lại từ đầu (mọi script idempotent nên an toàn)
bash demo/01-async-semisync/run-all.sh

# Fail ở B3 → fix xong rerun từ B3 (resume tự động)
bash demo/01-async-semisync/run-all.sh --resume

# Force bắt đầu từ step cụ thể
bash demo/01-async-semisync/run-all.sh --from=B4

# Bỏ state, chạy lại sạch sẽ (vẫn idempotent với VMs đang up)
bash demo/01-async-semisync/run-all.sh --fresh
```

PowerShell (Windows):
```powershell
.\demo\01-async-semisync\run-all.ps1                    # B1..B7
.\demo\01-async-semisync\run-all.ps1 -Resume            # tiếp từ step OK cuối
.\demo\01-async-semisync\run-all.ps1 -From B4           # từ step B4
.\demo\01-async-semisync\run-all.ps1 -Fresh             # reset state
```

### Mỗi step ghi log riêng

```
demo/01-async-semisync/results/
  ├── 01-vagrant-up.log
  ├── 02-prepare-os.log
  ├── 03-install-mysql.log
  ├── 04-master-setup.log
  ├── 05-replica-setup.log
  ├── 06-verify.log
  ├── 07-smoke-test.log
  ├── run-all.summary      # tổng hợp start/end/duration mỗi step
  └── .last_ok_step        # state cho --resume
```

`run-all.summary` mẫu sau khi pass:
```
========== RUN-ALL DEMO 01 ASYNC/SEMI-SYNC ==========
Started: 2026-05-17 22:55:17

B1 vagrant-up             OK    2026-05-17 22:55:17 -> 2026-05-17 22:58:42  (205s)
B2 prepare-os             OK    2026-05-17 22:58:43 -> 2026-05-17 22:59:11  (28s)
B3 install-mysql          OK    2026-05-17 22:59:12 -> 2026-05-17 23:03:55  (283s)
B4 master-setup           OK    2026-05-17 23:03:56 -> 2026-05-17 23:04:08  (12s)
B5 replica-setup          OK    2026-05-17 23:04:09 -> 2026-05-17 23:04:38  (29s)
B6 verify                 OK    2026-05-17 23:04:39 -> 2026-05-17 23:04:51  (12s)
B7 smoke-test             OK    2026-05-17 23:04:52 -> 2026-05-17 23:05:07  (15s)

Finished: 2026-05-17 23:05:07
```

## 5. Rollback / tháo

```sql
-- Trên replica
STOP REPLICA; RESET REPLICA ALL;
SET GLOBAL read_only = OFF; SET GLOBAL super_read_only = OFF;
UNINSTALL PLUGIN rpl_semi_sync_replica;

-- Trên master
SET GLOBAL rpl_semi_sync_source_enabled = 0;
UNINSTALL PLUGIN rpl_semi_sync_source;
```
Xoá các config file `zz-semisync.cnf`.

## 6. Tham khảo
- https://dev.mysql.com/doc/refman/8.0/en/replication-semisync.html
- https://dev.mysql.com/doc/refman/8.0/en/replication-gtids.html


---

!!! info "Nguồn gốc"
    `HA/Mysql/runbooks/01-async-semisync-replication.md`
