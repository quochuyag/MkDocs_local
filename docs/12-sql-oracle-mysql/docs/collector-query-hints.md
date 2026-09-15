---
title: Collector Query Hints
course: 12-sql-oracle-mysql
source: sql_oracle_mysqll/docs/COLLECTOR_QUERY_HINTS.md
---

# Collector Query Hints

Tài liệu này cung cấp gợi ý nguồn dữ liệu hệ thống cho từng engine.
Mục tiêu là lấy dữ liệu và map về canonical model trong docs/DATA_MODEL.md.

## SQL Server

### Databases
- sys.databases

### Users
- sys.server_principals
- sys.database_principals
- sys.server_role_members

### Size
- sys.master_files
- FILEPROPERTY, DBCC SQLPERF(LOGSPACE)

### Files/Path
- sys.master_files (physical_name, size, growth, type_desc)

### Processes
- sys.dm_exec_sessions
- sys.dm_exec_requests
- sys.dm_exec_sql_text(sql_handle)

## Oracle

### Databases / PDB
- v$database
- v$instance
- cdb_pdbs hoặc dba_pdbs (nếu CDB)

### Users
- dba_users
- dba_role_privs

### Size
- dba_data_files
- dba_temp_files
- v$log
- dba_segments (nếu cần thống kê used size)

### Files/Path
- dba_data_files (file_name)
- v$logfile (member)

### Processes/Sessions
- v$session
- v$sql
- v$process
- gv$session, gv$sql (RAC)

## MySQL

### Databases
- information_schema.schemata

### Users
- mysql.user
- information_schema.user_privileges

### Size
- information_schema.tables (data_length, index_length)

### Files/Path
- information_schema.files (tùy engine/version)
- SHOW VARIABLES LIKE 'datadir'

### Processes
- information_schema.processlist
- performance_schema.events_statements_current

## Chuẩn hóa dữ liệu
- process_uid:
  - SQL Server: session_id hoặc session_id:request_id
  - Oracle: sid:serial#
  - MySQL: processlist.id
- database_name cần map về server_database.id trước khi ghi snapshot.
- collected_at dùng UTC để đồng bộ đa server.


---

!!! info "Nguồn gốc"
    `sql_oracle_mysqll/docs/COLLECTOR_QUERY_HINTS.md`
