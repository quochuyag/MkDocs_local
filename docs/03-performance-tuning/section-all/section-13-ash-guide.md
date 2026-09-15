---
title: Section 13 — ASH (Active Session History)
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/section_all/section_13_ash_guide.md
---

# Section 13 — ASH (Active Session History)

## Tổng quan

**ASH (Active Session History)** là cơ chế Oracle lấy mẫu (sample) trạng thái của tất cả active sessions mỗi **1 giây**. Đây là công cụ mạnh nhất để phân tích **transient performance issues** — những vấn đề xảy ra trong thời gian ngắn rồi biến mất.

**Practice 11 — Using Active Session History (ASH)**
**Practice 12 — Linking ASH to Its Dimension Views**

---

## Kiến thức lý thuyết

### ASH hoạt động như thế nào?

```
Mỗi 1 giây: Oracle chụp trạng thái của tất cả active sessions
    ↓
Lưu vào buffer trong SGA (V$ACTIVE_SESSION_HISTORY)
    ↓
AWR flush định kỳ (mỗi 10 giây): lưu 1/10 samples vào disk
    ↓
DBA_HIST_ACTIVE_SESS_HISTORY (lịch sử lâu dài)
```

### Hai views chính

| View | Phạm vi | Tần suất sample | Dùng khi |
|------|---------|----------------|---------|
| `V$ACTIVE_SESSION_HISTORY` | Trong SGA, ~1 giờ gần nhất | Mỗi 1 giây | Phân tích vấn đề vừa xảy ra |
| `DBA_HIST_ACTIVE_SESS_HISTORY` | Trên disk, nhiều ngày | Mỗi 10 giây (1/10 flush) | Phân tích lịch sử xa hơn |

> **Lưu ý:** Khi query `DBA_HIST_ACTIVE_SESS_HISTORY`, nhân với 10 để tính DB Time chính xác vì chỉ 1/10 samples được lưu.

### Các cột quan trọng trong ASH

| Cột | Mô tả |
|-----|-------|
| `SAMPLE_TIME` | Thời điểm sample |
| `SESSION_ID` | SID của session |
| `SESSION_STATE` | `ON CPU` hoặc `WAITING` |
| `EVENT` | Tên wait event (khi WAITING) |
| `SQL_ID` | SQL statement đang thực thi |
| `SQL_PLAN_HASH_VALUE` | Execution plan đang dùng |
| `TOP_LEVEL_SQL_ID` | SQL cha (nếu là recursive SQL) |
| `MODULE` | Tên module (`DBMS_APPLICATION_INFO`) |
| `ACTION` | Tên action |
| `CLIENT_ID` | Client identifier |
| `BLOCKING_SESSION` | SID của session đang chặn |
| `CURRENT_OBJ#` | Object ID đang truy cập |
| `TEMP_SPACE_ALLOCATED` | Temp space dùng (bytes) |
| `XID` | Transaction ID |

---

## Practice 11: Phân tích lịch sử session

### Scenario: Session bị block, đã đóng — không còn trong V$SESSION

```sql
-- Tìm session theo ACTION đã đặt trước
set linesize 180
col EVENT format a30
col STIME format a10

SELECT TO_CHAR(SAMPLE_TIME,'HH24:MI:SS') STIME, SESSION_STATE, EVENT,
       TIME_WAITED, SQL_ID, CURRENT_OBJ# CO#, CURRENT_FILE# CF#,
       CURRENT_BLOCK# CB#, CURRENT_ROW# CR#, BLOCKING_SESSION BS#
FROM V$ACTIVE_SESSION_HISTORY
WHERE ACTION = 'PROCESS_CORDERS'
  AND SAMPLE_TIME BETWEEN
      TO_DATE(:CTIME,'DD-MM-YY HH24:MI:SS') - 5/1440
      AND
      TO_DATE(:CTIME,'DD-MM-YY HH24:MI:SS') + 5/1440
ORDER BY SESSION_ID, SAMPLE_TIME;
```

> **Mẹo đọc kết quả:** Số rows có `SESSION_STATE = 'WAITING'` xấp xỉ bằng số giây session đó chờ đợi (vì sample 1 lần/giây).

### Lấy SQL text từ SQL_ID

```sql
SELECT SQL_TEXT FROM V$SQL WHERE SQL_ID = '&Enter_SQL_ID';
```

### Từ block/file/row → tìm dữ liệu bị lock

```sql
-- Lấy ROWID từ block information
SELECT OBJECT_NAME, DBMS_ROWID.ROWID_CREATE(1, &ENTER_OBJECT_ID, &ENTER_FILE,
                                              &ENTER_BLOCK, &ENTER_ROW) ROW_ID
FROM DBA_OBJECTS
WHERE DATA_OBJECT_ID = &ENTER_OBJECT_ID;

-- Dùng ROWID để xem row bị khóa
SELECT * FROM SOE.ORDERS WHERE ROWID = '<retrieved_rowid>';
```

---

## Practice 11: Troubleshoot transient performance issue với ASH Report

### Phân tích DB Time theo module (realtime)

```sql
WITH TOTAL_DBTIME AS
  (SELECT COUNT(1)
   FROM V$ACTIVE_SESSION_HISTORY
   WHERE SESSION_TYPE = 'FOREGROUND')
SELECT MODULE,
       COUNT(1) "MODULE_DBTIME",
       (SELECT * FROM TOTAL_DBTIME) "TOTAL_DBTIME",
       ROUND((COUNT(1)/(SELECT * FROM TOTAL_DBTIME))*100,2) PCT_DBTIME
FROM V$ACTIVE_SESSION_HISTORY
WHERE SESSION_TYPE = 'FOREGROUND'
GROUP BY MODULE ORDER BY PCT_DBTIME DESC;
```

### Phân tích CPU Time theo module

```sql
WITH TOTAL_CPU AS
  (SELECT COUNT(1)
   FROM V$ACTIVE_SESSION_HISTORY
   WHERE SESSION_TYPE != 'BACKGROUND'
     AND SESSION_STATE = 'ON CPU')
SELECT MODULE,
       COUNT(1) "MODULE_CPU",
       (SELECT * FROM TOTAL_CPU) "TOTAL_CPU",
       ROUND((COUNT(1)/(SELECT * FROM TOTAL_CPU))*100,2) PCT_CPU
FROM V$ACTIVE_SESSION_HISTORY
WHERE SESSION_TYPE != 'BACKGROUND'
  AND SESSION_STATE = 'ON CPU'
GROUP BY MODULE ORDER BY PCT_CPU DESC;
```

### Sinh ASH Report (ashrpti.sql)

```sql
print :CTIME
define begin_time = '<CTIME value>'
define dbid = '';
define inst_num = '';
define report_type = 'html';
define duration = 10;          -- phút
define report_name = '/media/sf_extdisk/ash_report.html';
define slot_width = '';
define target_session_id = '';
define target_sql_id = '';
define target_wait_class = '';
define target_service_hash = '';
define target_module_name = '';
define target_action_name = '';
define target_client_id = '';
define target_plsql_entry = '';
define target_container = '';
@ $ORACLE_HOME/rdbms/admin/ashrpti.sql
```

### Phân tích từ AWR history (cho khoảng thời gian cụ thể)

```sql
-- Nhân với 10 vì DBA_HIST lưu 1/10 samples
WITH TOTAL_CPU AS
  (SELECT COUNT(1)*10
   FROM DBA_HIST_ACTIVE_SESS_HISTORY
   WHERE SNAP_ID >= :BEGIN_SNAP_ID AND SNAP_ID < :END_SNAP_ID
     AND SESSION_TYPE = 'FOREGROUND')
SELECT MODULE,
       COUNT(1)*10 "MODULE_CPU",
       (SELECT * FROM TOTAL_CPU) "TOTAL_CPU",
       ROUND((COUNT(1)*10/(SELECT * FROM TOTAL_CPU))*100,2) PCT_CPU
FROM DBA_HIST_ACTIVE_SESS_HISTORY
WHERE SNAP_ID >= :BEGIN_SNAP_ID AND SNAP_ID < :END_SNAP_ID
  AND SESSION_TYPE = 'FOREGROUND'
GROUP BY MODULE ORDER BY PCT_CPU DESC;
```

---

## Practice 12: Linking ASH to Dimension Views

### 1. Top SQL Statements theo DB Time

```sql
set linesize 180
col SQL_TEXT format a25
SELECT H.SQL_ID,
       SUBSTR(Q.SQL_TEXT,1,20) SQL_TEXT,
       H.SQL_CHILD_NUMBER,
       H.SQL_PLAN_HASH_VALUE,
       SUM(1) SQL_DBTIME
FROM V$ACTIVE_SESSION_HISTORY H, V$SQLAREA Q
WHERE H.SQL_ID IS NOT NULL
  AND H.SQL_ID = Q.SQL_ID(+)
  AND SAMPLE_TIME >= CURRENT_TIMESTAMP - INTERVAL '30' MINUTE
  AND H.USER_ID = (SELECT USER_ID FROM DBA_USERS WHERE USERNAME='SOE')
GROUP BY H.SQL_ID, SUBSTR(Q.SQL_TEXT,1,20), H.SQL_CHILD_NUMBER, H.SQL_PLAN_HASH_VALUE
ORDER BY SQL_DBTIME DESC
FETCH FIRST 5 ROWS ONLY;
```

> `V$SQLAREA` = parent cursors, `V$SQL` = child cursors. Outer join (+) vì statement có thể đã aged out khỏi library cache.

### 2. Xem Execution Plan

```sql
SELECT * FROM table(DBMS_XPLAN.DISPLAY_CURSOR('&V_SQL_ID', NULL, '+NOTE'));
-- Nếu statement đã aged out hoặc từ DBA_HIST, dùng:
SELECT * FROM table(DBMS_XPLAN.DISPLAY_AWR('&V_SQL_ID'));
```

### 3. Kiểm tra Recursive SQL

```sql
-- TOP_LEVEL_SQL_ID khác SQL_ID → là recursive SQL
SELECT DISTINCT SQL_ID, TOP_LEVEL_SQL_ID
FROM V$ACTIVE_SESSION_HISTORY H
WHERE H.SQL_ID IS NOT NULL
  AND SAMPLE_TIME >= CURRENT_TIMESTAMP - INTERVAL '30' MINUTE
  AND SQL_ID = '&V_SQL_ID';
```

### 4. SQL Performance Statistics

```sql
col "SQL Stats" format a50
SELECT
  'Elapsed Time (s): ' || ROUND(ELAPSED_TIME/1000000,3) || CHR(10) ||
  'CPU time (s): ' || ROUND(CPU_TIME/1000000,3) || CHR(10) ||
  'Buffer Gets: ' || BUFFER_GETS || CHR(10) ||
  'Disk Reads: ' || DISK_READS || CHR(10) ||
  'Rows Processed: ' || ROWS_PROCESSED || CHR(10) ||
  'Executions: ' || EXECUTIONS || CHR(10) ||
  'Parse Calls: ' || PARSE_CALLS || CHR(10) ||
  'Child Cursors: ' || VERSION_COUNT || CHR(10) ||
  'User IO Wait Time (s): ' || ROUND(USER_IO_WAIT_TIME/1000000,3) as "SQL Stats"
FROM V$SQLAREA
WHERE SQL_ID = '&V_SQL_ID';
```

### 5. SQL Performance History (từ DBA_HIST)

```sql
col SQL_TEXT format a25
SELECT
  TO_CHAR(SAMPLE_TIME,'YY-MM-DD') SAMPLE_DATE,
  H.SQL_ID,
  SUBSTR(TO_CHAR(Q.SQL_TEXT),1,20) SQL_TEXT,
  H.SQL_EXEC_ID,
  H.SQL_PLAN_HASH_VALUE,
  SUM(10) SQL_DBTIME
FROM DBA_HIST_ACTIVE_SESS_HISTORY H, DBA_HIST_SQLTEXT Q
WHERE H.SQL_ID = Q.SQL_ID(+)
  AND H.SQL_ID IS NOT NULL
  AND H.USER_ID = (SELECT USER_ID FROM DBA_USERS WHERE USERNAME='SOE')
  AND H.SQL_ID = '&V_SQL_ID'
GROUP BY TO_CHAR(SAMPLE_TIME,'YY-MM-DD'), H.SQL_ID, SUBSTR(TO_CHAR(Q.SQL_TEXT),1,20),
         H.SQL_EXEC_ID, H.SQL_PLAN_HASH_VALUE
ORDER BY TO_CHAR(SAMPLE_TIME,'YY-MM-DD') DESC;
```

### 6. Temporary Space tiêu thụ

```sql
SELECT H.SQL_ID,
       SUBSTR(Q.SQL_TEXT,1,20) SQL_TEXT,
       H.SQL_PLAN_HASH_VALUE,
       SUM(1) SQL_DBTIME,
       ROUND(MAX(TEMP_SPACE_ALLOCATED)/1024,1) TEMP_KB
FROM V$ACTIVE_SESSION_HISTORY H, V$SQLAREA Q
WHERE H.SQL_ID IS NOT NULL
  AND H.SQL_ID = Q.SQL_ID(+)
  AND SAMPLE_TIME >= CURRENT_TIMESTAMP - INTERVAL '30' MINUTE
GROUP BY H.SQL_ID, SUBSTR(Q.SQL_TEXT,1,20), H.SQL_PLAN_HASH_VALUE
ORDER BY MAX(TEMP_SPACE_ALLOCATED) DESC
FETCH FIRST 5 ROWS ONLY;
```

> Khi gặp lỗi ORA-01652 (không đủ temp space), query này giúp tìm statement nào đang dùng nhiều temp nhất.

### 7. Top Tables theo I/O Time

```sql
-- Method 1: Lọc theo event 'db file%'
col OBJECT_NAME format a20
SELECT O.OBJECT_ID, O.OBJECT_NAME, SUM(1) TOTAL_WAIT_TIME
FROM V$ACTIVE_SESSION_HISTORY H, DBA_OBJECTS O
WHERE H.SESSION_STATE = 'WAITING'
  AND SAMPLE_TIME >= CURRENT_TIMESTAMP - INTERVAL '30' MINUTE
  AND H.EVENT IS NOT NULL
  AND H.EVENT LIKE 'db file%'
  AND H.P2TEXT = 'block#'
  AND H.CURRENT_OBJ# = O.OBJECT_ID
GROUP BY O.OBJECT_ID, O.OBJECT_NAME
ORDER BY SUM(1) DESC
FETCH FIRST 10 ROWS ONLY;

-- Method 2: Lọc theo wait class 'User I/O' (generic hơn)
SELECT O.OBJECT_ID, O.OBJECT_NAME, O.OBJECT_TYPE, N.NAME EVENT_NAME, SUM(1) TOTAL_WAIT_TIME
FROM V$ACTIVE_SESSION_HISTORY H, DBA_OBJECTS O, V$EVENT_NAME N
WHERE H.SESSION_STATE = 'WAITING'
  AND SAMPLE_TIME >= CURRENT_TIMESTAMP - INTERVAL '30' MINUTE
  AND N.EVENT_ID = H.EVENT_ID
  AND N.WAIT_CLASS = 'User I/O'
  AND H.CURRENT_OBJ# = O.OBJECT_ID
GROUP BY O.OBJECT_ID, O.OBJECT_NAME, O.OBJECT_TYPE, N.NAME
ORDER BY SUM(1) DESC
FETCH FIRST 10 ROWS ONLY;
```

### 8. Top Blocks theo I/O Time

```sql
SELECT H.P1 FILE#, H.P2 BLOCK#, SUM(1) TOTAL_WAIT_TIME
FROM V$ACTIVE_SESSION_HISTORY H
WHERE H.SESSION_STATE = 'WAITING'
  AND SAMPLE_TIME >= CURRENT_TIMESTAMP - INTERVAL '30' MINUTE
  AND H.EVENT IS NOT NULL
  AND H.EVENT LIKE 'db file%'
  AND H.P2TEXT = 'block#'
GROUP BY H.P1, H.P2
ORDER BY SUM(1) DESC
FETCH FIRST 10 ROWS ONLY;

-- Từ block# và file# → tìm segment name
SELECT SEGMENT_NAME, PARTITION_NAME, SEGMENT_TYPE
FROM DBA_EXTENTS
WHERE (&blockno BETWEEN BLOCK_ID AND (BLOCK_ID + BLOCKS - 1))
  AND FILE_ID = &fileno AND ROWNUM < 2;
```

### 9. Index Usage Analysis từ ASH

```sql
-- Các index đã được dùng trong AWR history
WITH P AS (
  SELECT DISTINCT P.PLAN_HASH_VALUE, P.OBJECT#, P.OBJECT_OWNER, P.OBJECT_TYPE, P.OBJECT_NAME
  FROM DBA_HIST_SQL_PLAN P
  WHERE P.OBJECT_TYPE LIKE 'INDEX%' AND P.OBJECT_OWNER = 'SOE'
)
SELECT DISTINCT P.OBJECT# OBJECT_ID, P.OBJECT_OWNER, P.OBJECT_TYPE, P.OBJECT_NAME
FROM DBA_HIST_ACTIVE_SESS_HISTORY H, P
WHERE H.SQL_PLAN_HASH_VALUE = P.PLAN_HASH_VALUE;

-- Số lần mỗi index được dùng
WITH P AS (
  SELECT DISTINCT P.PLAN_HASH_VALUE, P.OBJECT#, P.OBJECT_TYPE, P.OBJECT_NAME
  FROM DBA_HIST_SQL_PLAN P
  WHERE P.OBJECT_TYPE LIKE 'INDEX%' AND P.OBJECT_OWNER = 'SOE'
)
SELECT P.OBJECT# OBJECT_ID, P.OBJECT_TYPE, P.OBJECT_NAME,
       COUNT(DISTINCT SQL_ID||SQL_PLAN_HASH_VALUE||SQL_EXEC_ID) SQL_EXECS
FROM DBA_HIST_ACTIVE_SESS_HISTORY H, P
WHERE H.SQL_PLAN_HASH_VALUE = P.PLAN_HASH_VALUE
GROUP BY P.OBJECT#, P.OBJECT_TYPE, P.OBJECT_NAME
ORDER BY SQL_EXECS;
```

---

## ASH Report — Các phần quan trọng

| Section | Nội dung |
|---------|---------|
| **Top Events** | Wait events chiếm nhiều DB Time nhất |
| **Top SQL with Top Events** | SQL statement + event gắn với SQL đó |
| **Top Sessions** | Session tiêu tốn nhiều DB Time nhất |
| **Top Service/Module** | Module nào đang bận nhất |
| **Activity Over Time** | Timeline của activity — giúp nhận ra spike |
| **Top Event P1/P2/P3** | Giá trị parameter của event (dùng để identify object) |

> **"Activity Over Time"** đặc biệt hữu ích để phát hiện transient spikes: nhìn thấy rõ khoảng thời gian ngắn có activity tăng đột biến.

---

## Tóm tắt

| Tình huống | Công cụ nên dùng |
|-----------|-----------------|
| Session vừa đóng, cần xem lịch sử | `V$ACTIVE_SESSION_HISTORY` |
| Vấn đề xảy ra vài ngày trước | `DBA_HIST_ACTIVE_SESS_HISTORY` |
| Phân tích nhanh nhiều chiều (SQL, session, event...) | ASH report (`ashrpti.sql`) |
| Tìm SQL đang chạy nhiều nhất | Query `V$ACTIVE_SESSION_HISTORY` GROUP BY SQL_ID |
| Tìm table/block hot nhất | Join với `DBA_OBJECTS` + filter `db file%` event |
| Xem index nào thực sự được dùng | Join `DBA_HIST_SQL_PLAN` + `DBA_HIST_ACTIVE_SESS_HISTORY` |


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/section_all/section_13_ash_guide.md`
