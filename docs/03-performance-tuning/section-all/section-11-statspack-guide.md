---
title: Section 11 — Statspack
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/section_all/section_11_statspack_guide.md
---

# Section 11 — Statspack

## Tổng quan

**Statspack** là công cụ thu thập và phân tích hiệu năng Oracle Database, xuất hiện từ Oracle 8i. Nó là tiền thân của AWR nhưng **không yêu cầu license Diagnostics Pack**, nên được dùng khi không có Enterprise Edition license đầy đủ.

**Practice 9 — Using Statspack**

Mục tiêu:
- Cài đặt Statspack và cấu hình snapshot level
- Tạo snapshot và baseline
- Sinh báo cáo hiệu năng (instance report và SQL report)
- Quản lý snapshot (purge, clear baseline)

---

## Statspack vs AWR — So sánh

| Tiêu chí | Statspack | AWR |
|---------|-----------|-----|
| Yêu cầu license | Không (miễn phí) | Cần Diagnostics Pack |
| Tự động thu thập | Không (phải schedule thủ công) | Có (mặc định 60 phút/lần) |
| Lưu trữ | Schema PERFSTAT | SYSAUX tablespace |
| Snapshot level | 0–10 | Cố định |
| ADDM tích hợp | Không | Có |
| Khuyến nghị | Dùng khi không có AWR license | Ưu tiên dùng nếu có license |

---

## Bước 1: Cài đặt Statspack

### Chạy script spcreate.sql

```sql
-- Chạy trong SQL*Plus với quyền sysdba, ở batch mode
define default_tablespace='USERS'
define temporary_tablespace='TEMP'
define perfstat_password='oracle'
@ ?/rdbms/admin/spcreate
```

Script này tạo schema **PERFSTAT** và tất cả các bảng/views/packages cần thiết.

### Kiểm tra sau cài đặt

```sql
conn perfstat/oracle
SELECT * FROM STATS$STATSPACK_PARAMETER;
-- Kết quả ban đầu: bảng rỗng (chưa có parameter nào)
```

---

## Bước 2: Cấu hình Snapshot Level

### Các mức snapshot level

| Level | Thu thập thêm |
|-------|--------------|
| 0 | Statistics cơ bản |
| 5 | Thêm SQL statements (default) |
| 6 | Thêm SQL execution plans |
| 7 | Thêm segment statistics |
| 10 | Thêm parent/child latches — mức đầy đủ nhất |

### Đặt level 10

```sql
conn perfstat/oracle
exec STATSPACK.MODIFY_STATSPACK_PARAMETER(I_SNAP_LEVEL => 10)
```

> **Lưu ý:** Level 10 tốn nhiều disk space hơn. Chỉ dùng khi cần debug latch contention.

### Verify

```sql
SELECT SNAP_LEVEL FROM STATS$STATSPACK_PARAMETER;
```

---

## Bước 3: Tạo Snapshot

### Tạo thủ công

```sql
exec STATSPACK.SNAP
```

### Xem danh sách snapshot

```sql
ALTER SESSION SET NLS_DATE_FORMAT='DD-MM-RR HH24:MI:SS';
SELECT SNAP_ID, SNAP_LEVEL, SNAP_TIME FROM STATS$SNAPSHOT ORDER BY 1;
```

> **Thực tế:** Cần tạo **ít nhất 2 snapshot** để sinh report (cần khoảng đầu và cuối).
> Trong thực tế triển khai, tạo job chạy tự động mỗi 30-60 phút.

---

## Bước 4: Tạo Baseline

Baseline trong Statspack chỉ là **flag** trên snapshot, không có tên như AWR baseline.

```sql
-- Đánh dấu snapshot 1 và 2 là baseline
exec STATSPACK.MAKE_BASELINE(I_BEGIN_SNAP => 1, I_END_SNAP => 2)

-- Verify baseline flag
SELECT SNAP_ID, SNAP_LEVEL, SNAP_TIME, BASELINE FROM STATS$SNAPSHOT ORDER BY 1;
-- BASELINE column: 'Y' = đã baseline, 'N' = chưa
```

---

## Bước 5: Thu thập thống kê optimizer cho PERFSTAT

```sql
exec DBMS_STATS.GATHER_SCHEMA_STATS(OWNNAME => 'PERFSTAT', CASCADE => TRUE)
```

> Best practice: Gather stats trước khi sinh report để optimizer chọn đúng execution plan.

---

## Bước 6: Sinh báo cáo Statspack

### Instance Report (spreport.sql)

```sql
@ ?/rdbms/admin/spreport
-- Script hỏi: begin snap, end snap, tên file output
-- File được tạo dạng .lst trong thư mục hiện tại
```

### SQL Report trên specific statement (sprepsql.sql)

```sql
-- Chạy batch mode (không cần interactive)
define begin_snap = 1
define end_snap = 2
define hash_value = <HASH_VALUE>  -- lấy từ spreport dưới mục "SQL ordered by CPU"
define report_name = batch_sql_run
@ ?/rdbms/admin/sprepsql
-- Output: batch_sql_run.lst
```

> **Cách lấy hash value:** Mở report bằng vi editor, tìm section "SQL ordered by CPU":
> ```
> host vi sp_1_2.lst
> -- Trong vi: ESC -> : -> /SQL ordered by CPU
> ```

---

## Bước 7: Quản lý Snapshot

### Purge snapshot (xóa không-baseline)

```sql
-- Thử purge tất cả từ snap 1 đến 3
exec STATSPACK.PURGE(I_BEGIN_SNAP => 1, I_END_SNAP => 3)

-- Verify: chỉ snapshot không có baseline mới bị xóa
SELECT SNAP_ID, SNAP_LEVEL, SNAP_TIME, BASELINE FROM STATS$SNAPSHOT ORDER BY 1;
```

> **Quan trọng:** `PURGE` chỉ xóa snapshot **không có baseline flag**. Snapshot đã baseline được bảo vệ.

### Clear baseline flag

```sql
-- Bỏ flag baseline (snapshot vẫn còn, chỉ bỏ flag)
exec STATSPACK.CLEAR_BASELINE(
  I_BEGIN_SNAP => 1,
  I_END_SNAP   => 2,
  I_SNAP_RANGE => TRUE
)

-- Verify: BASELINE column trở về 'N'
SELECT SNAP_ID, SNAP_LEVEL, SNAP_TIME, BASELINE FROM STATS$SNAPSHOT ORDER BY 1;
```

---

## Bước 8: Gỡ cài đặt Statspack

```sql
connect / as sysdba
@ ?/rdbms/admin/spdrop
```

---

## Cấu trúc Statspack Report

Statspack report có cấu trúc tương tự AWR report:

```
1. Report Summary
   - DB Time, Elapsed Time, DB CPU
2. Top 10 Foreground Events by Total Wait Time
3. Host CPU & Memory Statistics
4. Instance Activity Statistics
5. SQL Statistics
   - SQL ordered by Elapsed Time
   - SQL ordered by CPU Time
   - SQL ordered by Gets (logical reads)
   - SQL ordered by Reads (physical reads)
6. Latch Statistics (nếu level >= 10)
```

---

## Tóm tắt

| Tác vụ | Lệnh / Script |
|--------|--------------|
| Cài đặt | `@ ?/rdbms/admin/spcreate` |
| Tạo snapshot | `exec STATSPACK.SNAP` |
| Đặt snapshot level | `exec STATSPACK.MODIFY_STATSPACK_PARAMETER(I_SNAP_LEVEL=>10)` |
| Baseline | `exec STATSPACK.MAKE_BASELINE(I_BEGIN_SNAP=>N, I_END_SNAP=>M)` |
| Sinh instance report | `@ ?/rdbms/admin/spreport` |
| Sinh SQL report | `@ ?/rdbms/admin/sprepsql` |
| Purge snapshot | `exec STATSPACK.PURGE(I_BEGIN_SNAP=>N, I_END_SNAP=>M)` |
| Clear baseline | `exec STATSPACK.CLEAR_BASELINE(I_BEGIN_SNAP=>N, I_END_SNAP=>M, I_SNAP_RANGE=>TRUE)` |
| Gỡ cài đặt | `@ ?/rdbms/admin/spdrop` |
| Tài liệu | `$ORACLE_HOME/rdbms/admin/spdoc.txt` |

> **Khuyến nghị thực tế:** Nếu có AWR license, ưu tiên dùng AWR + ADDM thay vì Statspack. Statspack hữu ích nhất khi triển khai trên Standard Edition hoặc môi trường không có Diagnostics Pack license.


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/section_all/section_11_statspack_guide.md`
