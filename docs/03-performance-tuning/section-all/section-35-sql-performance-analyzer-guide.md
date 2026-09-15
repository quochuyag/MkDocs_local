---
title: Section 35 — SQL Performance Analyzer (SPA)
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/section_all/section_35_sql_performance_analyzer_guide.md
---

# Section 35 — SQL Performance Analyzer (SPA)

**Nguồn:** Oracle Database Performance Tuning — Ahmed Baraka (v2.3)  
**Practice:** 37  
**Ngày học:** 2026-04-20

---

## Tổng quan Section 35

**SQL Performance Analyzer (SPA)** là công cụ đánh giá tác động của một thay đổi hệ thống lên hiệu năng SQL workload **trước khi** áp dụng vào production. Thay đổi có thể là:

- Nâng cấp database (VD: 11g → 12c)
- Thay đổi optimizer parameter
- Tạo index mới, materialized view mới
- Thay đổi system statistics, schema statistics
- Cấu hình phần cứng mới

**Câu hỏi SPA trả lời:** "Nếu tôi áp dụng thay đổi X, SQL nào sẽ chạy nhanh hơn? Chậm hơn? Execution plan có thay đổi không?"

> SPA nên chạy trên **testing/staging system** — không phải production. Mặc dù kỹ thuật cho phép chạy production, best practice là chạy trên hệ thống test có configuration gần giống production nhất.

---

## Kiến trúc SPA — Luồng 3 bước

```
BƯỚC 1: CAPTURE WORKLOAD
Source DB (production) → SQL Tuning Set (STS)
  ↓
  Export STS → staging table → Data Pump export file
  ↓
  Copy dump file → Test DB

BƯỚC 2: TEST TRƯỚC THAY ĐỔI ("before")
Test DB (trạng thái hiện tại = giả lập 11g)
  ↓
  Import STS từ dump file
  ↓
  Tạo SPA task liên kết STS
  ↓
  EXECUTE_ANALYSIS_TASK (EXECUTION_TYPE='TEST EXECUTE', NAME='before')
  → Oracle thực sự chạy từng SQL trong STS, thu thập metrics

BƯỚC 3: ÁP DỤNG THAY ĐỔI VÀ TEST SAU ("after")
  Thay đổi: ALTER SYSTEM SET OPTIMIZER_FEATURES_ENABLE='12.2.0.1'
  ↓
  EXECUTE_ANALYSIS_TASK (EXECUTION_TYPE='TEST EXECUTE', NAME='after')
  → Oracle chạy lại toàn bộ SQL với setting mới
  ↓
  EXECUTE_ANALYSIS_TASK (EXECUTION_TYPE='COMPARE PERFORMANCE')
  → So sánh before vs after
  ↓
  REPORT_ANALYSIS_TASK → HTML/TEXT report
```

---

## Hai package chính

| Package | Chức năng |
|---------|-----------|
| `DBMS_SQLTUNE` | Quản lý SQL Tuning Set (STS): tạo, capture, export, import |
| `DBMS_SQLPA` | Tạo và chạy SPA task: analysis, comparison, report |

---

## Bước 1: Capture SQL Workload vào SQL Tuning Set (STS)

### STS là gì?

**SQL Tuning Set (STS)** là tập hợp SQL statements được lưu trong database, kèm theo execution context (bind variables, parsing schema, execution statistics). STS là "container" chứa workload để SPA phân tích.

### Tạo STS

```sql
-- Tạo STS mang tên 'SOE_WKLD_STS', owned by SOE
EXEC DBMS_SQLTUNE.CREATE_SQLSET(
  SQLSET_NAME  => 'SOE_WKLD_STS',
  SQLSET_OWNER => 'SOE',
  DESCRIPTION  => 'SQL to assess for upgrade'
);
```

### Capture SQL từ Cursor Cache vào STS

```sql
-- Capture SQL của schema SOE từ cursor cache trong 60 giây, mỗi 3 giây một lần
BEGIN
  DBMS_SQLTUNE.CAPTURE_CURSOR_CACHE_SQLSET(
    SQLSET_NAME    => 'SOE_WKLD_STS',
    SQLSET_OWNER   => 'SOE',
    TIME_LIMIT     => 60,          -- tổng thời gian capture (giây)
    REPEAT_INTERVAL => 3,          -- lấy cursor cache mỗi 3 giây
    BASIC_FILTER   => 'UPPER(PARSING_SCHEMA_NAME) = ''SOE''',
    CAPTURE_MODE   => DBMS_SQLTUNE.MODE_REPLACE_OLD_STATS
  );
END;
/
```

**Trong lúc capture đang chạy:** Chạy workload thực tế ở session khác để SQL xuất hiện trong cursor cache.

```sql
-- Chạy workload script từ session client
@client_wrkld.sql
```

### Xem SQL đã capture

```sql
SET LONG 1000
SELECT SQL_TEXT
FROM DBA_SQLSET_STATEMENTS
WHERE SQLSET_NAME = 'SOE_WKLD_STS';
```

---

## Bước 2: Export STS sang Testing Database

STS cần được chuyển từ production DB sang testing DB bằng staging table + Data Pump.

### Tạo staging table và pack STS vào đó

```sql
-- Tạo staging table
EXEC DBMS_SQLTUNE.CREATE_STGTAB_SQLSET('SOE_WKLD_STS_TB', 'SOE');

-- Pack STS vào staging table
EXEC DBMS_SQLTUNE.PACK_STGTAB_SQLSET(
  SQLSET_NAME       => 'SOE_WKLD_STS',
  SQLSET_OWNER      => 'SOE',
  STAGING_TABLE_NAME => 'SOE_WKLD_STS_TB',
  STAGING_SCHEMA_OWNER => 'SOE'
);
```

### Export bằng Data Pump

```bash
# Export staging table ra dump file
expdp soe/soe \
  directory=DATA_PUMP_DIR \
  dumpfile=SOE_WKLD_STS_TB.dmp \
  tables=SOE_WKLD_STS_TB
```

### Dọn dẹp trên source DB

```sql
-- Drop STS sau khi đã export
EXEC DBMS_SQLTUNE.DROP_SQLSET(
  SQLSET_NAME  => 'SOE_WKLD_STS',
  SQLSET_OWNER => 'SOE'
);
DROP TABLE SOE.SOE_WKLD_STS_TB;
```

> **Thực tế:** Copy dump file từ source DB sang test DB trước bước tiếp theo.

---

## Bước 3: Import STS vào Testing Database

```bash
# Import staging table vào test DB
impdp soe/soe \
  directory=DATA_PUMP_DIR \
  dumpfile=SOE_WKLD_STS_TB.dmp \
  tables=SOE_WKLD_STS_TB
```

```sql
-- Tạo STS trên test DB
EXEC DBMS_SQLTUNE.CREATE_SQLSET(
  SQLSET_NAME  => 'SOE_WKLD_STS',
  SQLSET_OWNER => 'SOE',
  DESCRIPTION  => 'SQL to assess for upgrade'
);

-- Unpack staging table → STS
EXEC DBMS_SQLTUNE.UNPACK_STGTAB_SQLSET(
  SQLSET_NAME          => 'SOE_WKLD_STS',
  SQLSET_OWNER         => 'SOE',
  REPLACE              => TRUE,
  STAGING_TABLE_NAME   => 'SOE_WKLD_STS_TB',
  STAGING_SCHEMA_OWNER => 'SOE'
);

-- Verify
SET LONG 1000
SELECT SQL_TEXT
FROM DBA_SQLSET_STATEMENTS
WHERE SQLSET_NAME = 'SOE_WKLD_STS';
```

---

## Bước 4: Tạo SPA Task

```sql
VARIABLE v_task VARCHAR2(64)

-- Tạo SPA task liên kết với STS
EXEC :v_task := DBMS_SQLPA.CREATE_ANALYSIS_TASK(
  SQLSET_NAME  => 'SOE_WKLD_STS',
  SQLSET_OWNER => 'SOE'
);

-- Lưu lại tên task (dùng cho các bước tiếp theo)
PRINT :v_task
-- → SYS_SQLPA_TASK_nnnn
```

---

## Bước 5: Chạy "Before" Execution

Trạng thái test DB hiện tại = giả lập trạng thái **trước thay đổi** (VD: OPTIMIZER_FEATURES_ENABLE = 11.2.0.2).

```sql
-- Simulating 11g optimizer
ALTER SYSTEM SET OPTIMIZER_FEATURES_ENABLE='11.2.0.2' SCOPE=SPFILE;
SHUTDOWN IMMEDIATE
STARTUP

-- Chạy SPA task với execution_name='before'
BEGIN
  DBMS_SQLPA.EXECUTE_ANALYSIS_TASK(
    TASK_NAME      => :v_task,
    EXECUTION_TYPE => 'TEST EXECUTE',
    EXECUTION_NAME => 'before'
  );
END;
/
```

**`TEST EXECUTE`**: Oracle thực sự **thực thi** từng SQL trong STS và thu thập:
- Execution plan
- Elapsed time
- Buffer gets, disk reads
- CPU time

### Xem report "before" (optional)

```sql
SELECT DBMS_SQLPA.REPORT_ANALYSIS_TASK(
  TASK_NAME => :v_task,
  TYPE      => 'TEXT',
  SECTION   => 'SUMMARY'
) FROM DUAL;
```

---

## Bước 6: Áp dụng thay đổi

```sql
-- Simulate upgrade: đổi sang 12c optimizer
ALTER SYSTEM SET OPTIMIZER_FEATURES_ENABLE='12.2.0.1' SCOPE=SPFILE;
SHUTDOWN IMMEDIATE
STARTUP
```

> Trong thực tế, đây là bước thực hiện thay đổi thật: nâng cấp DB, tạo index, thay đổi parameter, gather statistics mới, v.v.

---

## Bước 7: Chạy "After" Execution

```sql
BEGIN
  DBMS_SQLPA.EXECUTE_ANALYSIS_TASK(
    TASK_NAME      => :v_task,
    EXECUTION_TYPE => 'TEST EXECUTE',
    EXECUTION_NAME => 'after'
  );
END;
/
```

---

## Bước 8: So sánh Before vs After

```sql
-- Chạy comparison task (tự động so sánh 2 execution gần nhất)
EXEC DBMS_SQLPA.EXECUTE_ANALYSIS_TASK(
  TASK_NAME      => :v_task,
  EXECUTION_TYPE => 'COMPARE PERFORMANCE'
);
```

---

## Bước 9: Generate Report

```sql
-- Xuất HTML report ra file
SET LONG 10000
SET HEADING OFF
SPOOL /media/sf_extdisk/report.html

SELECT DBMS_SQLPA.REPORT_ANALYSIS_TASK(
  TASK_NAME => :v_task,
  TYPE      => 'HTML',
  SECTION   => 'ALL'
) FROM DUAL;

SPOOL OFF

-- Mở file HTML, xóa các dòng thừa đầu/cuối
host vi /media/sf_extdisk/report.html
```

**TYPE options:**

| Type | Dùng khi |
|------|---------|
| `'TEXT'` | Console/quick check |
| `'HTML'` | Báo cáo đầy đủ với formatting |
| `'ACTIVE'` | Interactive HTML (Oracle 12c+) |

**SECTION options:**

| Section | Nội dung |
|---------|---------|
| `'SUMMARY'` | Tổng quan: số SQL improved/regressed/unchanged |
| `'FINDINGS'` | Chi tiết từng SQL bị thay đổi |
| `'ALL'` | Toàn bộ report |

---

## Đọc kết quả SPA Report

**Summary section điển hình:**

```
SQL Performance Analyzer Report
Task Name: SYS_SQLPA_TASK_1234
Workload Impact Summary:

  SQL Statements: 10 total
  ┌─────────────────────────────────────────┐
  │ Improved:   6  (response time giảm)     │
  │ Regressed:  2  (response time tăng) ⚠️  │
  │ Unchanged:  2                           │
  └─────────────────────────────────────────┘
```

**Findings section — mỗi SQL được phân tích:**

```
SQL_ID: abc123xyz
Before: elapsed=0.5s, plan=INDEX RANGE SCAN
After:  elapsed=1.2s, plan=FULL TABLE SCAN  ← REGRESSED!
Impact: +140% response time
Recommendation: Consider SQL Plan Baseline or hint
```

**Các loại kết quả:**

| Kết quả | Ý nghĩa |
|---------|---------|
| `IMPROVED` | SQL nhanh hơn sau thay đổi — tốt |
| `REGRESSED` | SQL chậm hơn sau thay đổi — cần xử lý |
| `UNCHANGED` | Hiệu năng không đổi |
| `ERRORS` | SQL bị lỗi khi test execute |

---

## Dọn dẹp sau khi dùng SPA

```sql
-- Drop SPA task
EXEC DBMS_SQLPA.DROP_ANALYSIS_TASK(:v_task);

-- Drop STS
EXEC DBMS_SQLTUNE.DROP_SQLSET(
  SQLSET_NAME  => 'SOE_WKLD_STS',
  SQLSET_OWNER => 'SOE'
);

-- Drop staging table
DROP TABLE SOE.SOE_WKLD_STS_TB;

-- Xóa files
HOST rm client_wrkld.sql
HOST rm /u01/app/oracle/admin/ORADB/dpdump/SOE_WKLD_STS_TB.dmp
HOST rm /media/sf_extdisk/report.html
```

---

## Quy trình đầy đủ — Quick Reference

```
PRODUCTION DB                         TEST DB
─────────────────                     ─────────────────
1. Simulating "before":
   ALTER SYSTEM SET
   OPTIMIZER_FEATURES_ENABLE='11.2.0.2'
   RESTART

2. Capture workload:
   CREATE_SQLSET                       
   CAPTURE_CURSOR_CACHE_SQLSET         
   (chạy workload song song)           
                                       
3. Export STS:
   CREATE_STGTAB_SQLSET               
   PACK_STGTAB_SQLSET                 
   expdp → dump file ──────────────→  impdp → staging table
                                       
                                       4. Import STS:
                                          CREATE_SQLSET
                                          UNPACK_STGTAB_SQLSET
                                       
                                       5. Tạo SPA task:
                                          CREATE_ANALYSIS_TASK → :v_task
                                       
                                       6. Before execution:
                                          (DB ở trạng thái 11g)
                                          EXECUTE_ANALYSIS_TASK
                                          (TYPE='TEST EXECUTE', NAME='before')
                                       
                                       7. Apply changes:
                                          ALTER SYSTEM SET
                                          OPTIMIZER_FEATURES_ENABLE='12.2.0.1'
                                          RESTART
                                       
                                       8. After execution:
                                          EXECUTE_ANALYSIS_TASK
                                          (TYPE='TEST EXECUTE', NAME='after')
                                       
                                       9. Compare:
                                          EXECUTE_ANALYSIS_TASK
                                          (TYPE='COMPARE PERFORMANCE')
                                       
                                       10. Report:
                                           REPORT_ANALYSIS_TASK
                                           (TYPE='HTML', SECTION='ALL')
```

---

## Xử lý SQL bị REGRESSED

Khi report cho thấy có SQL regressed, có các hướng xử lý:

```sql
-- Hướng 1: Dùng SQL Plan Baseline — ghim execution plan tốt từ "before"
-- (đây là chủ đề của SQL Plan Management — Section khác)

-- Hướng 2: Thêm hint vào SQL (nếu có quyền sửa app code)
-- SELECT /*+ INDEX(t idx_col) */ ...

-- Hướng 3: Dùng SQL Profile để hướng dẫn optimizer
-- (output từ DBMS_SQLTUNE.ACCEPT_SQL_PROFILE)

-- Hướng 4: Điều chỉnh tham số optimizer cho SQL cụ thể
-- ALTER SESSION SET OPTIMIZER_FEATURES_ENABLE = ...
```

---

## Tóm tắt Commands & Views

| Command/Package/View | Dùng để |
|---------------------|---------|
| `DBMS_SQLTUNE.CREATE_SQLSET` | Tạo SQL Tuning Set |
| `DBMS_SQLTUNE.CAPTURE_CURSOR_CACHE_SQLSET` | Capture SQL từ cursor cache vào STS |
| `DBMS_SQLTUNE.CREATE_STGTAB_SQLSET` | Tạo staging table để transport STS |
| `DBMS_SQLTUNE.PACK_STGTAB_SQLSET` | Pack STS vào staging table |
| `DBMS_SQLTUNE.UNPACK_STGTAB_SQLSET` | Unpack staging table vào STS |
| `DBMS_SQLTUNE.DROP_SQLSET` | Xóa STS |
| `DBA_SQLSET_STATEMENTS` | Xem SQL trong STS |
| `DBMS_SQLPA.CREATE_ANALYSIS_TASK` | Tạo SPA task liên kết với STS |
| `DBMS_SQLPA.EXECUTE_ANALYSIS_TASK` | Chạy task (TEST EXECUTE / COMPARE PERFORMANCE) |
| `DBMS_SQLPA.REPORT_ANALYSIS_TASK` | Generate report (TEXT/HTML) |
| `DBMS_SQLPA.DROP_ANALYSIS_TASK` | Xóa SPA task |
| `expdp` / `impdp` | Export/import staging table giữa databases |
| `OPTIMIZER_FEATURES_ENABLE` | Giả lập phiên bản optimizer (11.2.0.2 / 12.2.0.1) |

---

## Câu hỏi ôn tập

1. SQL Performance Analyzer dùng để làm gì? Tại sao nên chạy trên testing system thay vì production?
2. SQL Tuning Set (STS) là gì? Nó lưu những thông tin gì ngoài SQL text?
3. `CAPTURE_CURSOR_CACHE_SQLSET` hoạt động như thế nào? Cần làm gì trong thời gian capture đang chạy?
4. Tại sao cần staging table và Data Pump để chuyển STS từ production sang test? Không thể export/import trực tiếp STS sao?
5. Sự khác biệt giữa `EXECUTION_TYPE='TEST EXECUTE'` và `EXECUTION_TYPE='COMPARE PERFORMANCE'`?
6. SPA report phân loại SQL thành những nhóm nào? Nhóm nào cần được xử lý ngay?
7. Trong practice, thay đổi được mô phỏng là gì? Dùng tham số nào để giả lập Oracle 11g và 12c?
8. Sau khi SPA report cho thấy có SQL regressed, có những phương án xử lý nào?


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/section_all/section_35_sql_performance_analyzer_guide.md`
