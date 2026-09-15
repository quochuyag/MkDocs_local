---
title: Data Model (Canonical)
course: 12-sql-oracle-mysql
source: sql_oracle_mysqll/docs/DATA_MODEL.md
---

# Data Model (Canonical)

## Thực thể chính
- managed_server: thông tin server nguồn.
- server_database: danh sách database/schema quản lý.
- db_user_account: user account theo server.
- db_file_snapshot: snapshot file/path/size.
- db_size_snapshot: snapshot dung lượng theo database.
- db_process_snapshot: snapshot process/session đang chạy.
- collection_job_run: lịch sử lần thu thập.

## Quan hệ
- managed_server 1-n server_database
- managed_server 1-n db_user_account
- managed_server 1-n collection_job_run
- server_database 1-n db_size_snapshot
- server_database 1-n db_file_snapshot
- server_database 1-n db_process_snapshot

## Khóa logic
- managed_server: (engine, host, port, instance_name)
- server_database: (server_id, database_name)
- db_user_account: (server_id, username)

## Mở rộng theo engine
- Các trường riêng engine được lưu trong cột extension_json.
- Ví dụ:
  - SQL Server: filegroup, recovery_model
  - Oracle: tablespace, pdb/cdb
  - MySQL: engine, row_format


---

!!! info "Nguồn gốc"
    `sql_oracle_mysqll/docs/DATA_MODEL.md`
