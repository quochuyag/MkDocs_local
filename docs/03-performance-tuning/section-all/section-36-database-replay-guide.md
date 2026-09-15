---
title: Section 36 — Database Replay
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/section_all/section_36_database_replay_guide.md
---

# Section 36 — Database Replay

**Nguồn:** Oracle Database Performance Tuning — Ahmed Baraka (v2.3)  
**Practice:** 38  
**Ngày học:** 2026-04-20

---

## Tổng quan Section 36

**Database Replay** (còn gọi là Workload Replay) là tính năng tái hiện **production workload thực tế** trong môi trường testing để đánh giá tác động của thay đổi hệ thống. Khác với SPA chỉ test từng SQL statement, Database Replay tái hiện toàn bộ **client sessions** — bao gồm timing, concurrency, think time, và transaction dependencies.

> **License:** Database Replay yêu cầu **Oracle Real Application Testing license** riêng.

---

## Database Replay vs SQL Performance Analyzer

| Tiêu chí | SQL Performance Analyzer | Database Replay |
|---------|--------------------------|-----------------|
| **Đơn vị test** | SQL statements (từ STS) | Toàn bộ client sessions (real workload) |
| **Concurrency** | Không — test tuần tự từng SQL | Có — replay concurrent connections |
| **Timing/Think time** | Không | Có — mô phỏng user delays |
| **DML/Transactions** | Không replay DML | Replay cả DML và transactions |
| **Độ phức tạp** | Đơn giản hơn | Phức tạp hơn — cần RMAN backup |
| **Phù hợp** | Đánh giá query plan changes | Kiểm tra toàn diện impact trên workload |

---

## 5 Phases của Database Replay

```
PHASE 1: WORKLOAD CAPTURE (Production DB)
  Thu thập toàn bộ external client requests
  → Lưu vào capture files trong WORKLOAD_DIR
        ↓
PHASE 2: WORKLOAD PREPROCESSING (Test DB)
  Convert capture files → replay files
  → Tạo metadata cho replay process
        ↓
PHASE 3: APPLY CHANGES (Test DB)
  Thực hiện thay đổi cần test:
  - Nâng cấp DB (OPTIMIZER_FEATURES_ENABLE)
  - Tạo index, thay đổi parameter, v.v.
        ↓
PHASE 4: WORKLOAD REPLAY (Test DB)
  Khởi động wrc (Workload Replay Client)
  → Replay lại workload đã capture
        ↓
PHASE 5: ANALYSIS & REPORTING
  So sánh performance: capture vs replay
  → HTML/TEXT/XML report
```

---

## Phase 1: Workload Capture — Chuẩn bị

### Yêu cầu bắt buộc

1. **ARCHIVELOG mode** phải được bật trên production DB
2. **RMAN backup** tại thời điểm capture (để restore test DB về cùng trạng thái)
3. **Ghi lại SCN** tại thời điểm bắt đầu capture (dùng cho RMAN recover)

### Bật ARCHIVELOG mode

```sql
SHUTDOWN IMMEDIATE
STARTUP MOUNT

-- Verify current mode
ARCHIVE LOG LIST

-- Set archive destination
ALTER SYSTEM SET LOG_ARCHIVE_DEST_1='LOCATION=USE_DB_RECOVERY_FILE_DEST' SCOPE=SPFILE;

-- Enable ARCHIVELOG
ALTER DATABASE ARCHIVELOG;

-- Restart
SHUTDOWN IMMEDIATE
STARTUP OPEN

-- Verify
ARCHIVE LOG LIST

-- Force log switch và kiểm tra
ALTER SYSTEM SWITCH LOGFILE;
SELECT NAME FROM V$ARCHIVED_LOG;
```

### Backup bằng RMAN

```bash
rman target "'/ as SYSBACKUP'"
BACKUP DATABASE FORMAT '/media/sf_extdisk/DB%U.bck';
```

> Backup này dùng để restore test DB về cùng trạng thái với production tại thời điểm capture.

### Tạo Directory Object cho capture files

```bash
mkdir /home/oracle/workload
```

```sql
CREATE DIRECTORY WORKLOAD_DIR AS '/home/oracle/workload';
```

### Thêm Filter (tùy chọn)

```sql
-- Chỉ capture sessions của user SOE (INCLUDE filter)
BEGIN
  DBMS_WORKLOAD_CAPTURE.ADD_FILTER(
    FNAME      => 'INCLUDE_SOE',
    FATTRIBUTE => 'USER',
    FVALUE     => 'SOE'
  );
END;
/

-- Verify filters
SELECT NAME, ATTRIBUTE, VALUE FROM DBA_WORKLOAD_FILTERS;
```

**Filter attributes có thể dùng:** `USER`, `MODULE`, `ACTION`, `PROGRAM`, `SERVICE`, `INSTANCE_NUMBER`, `PDB_NAME`

**DEFAULT_ACTION trong START_CAPTURE:**
- `'EXCLUDE'` → filter được coi là **inclusion** (chỉ capture những gì match filter)
- `'INCLUDE'` → filter được coi là **exclusion** (capture tất cả trừ những gì match filter)

---

## Phase 1: Workload Capture — Thực hiện

### Lấy SCN trước khi bắt đầu capture

```sql
SELECT CURRENT_SCN FROM V$DATABASE;
-- Ghi lại SCN này để dùng khi restore test DB
```

### Bắt đầu capture (khuyến nghị: STARTUP RESTRICT trước)

```sql
-- Restart restricted để tránh in-flight transactions
SHUTDOWN IMMEDIATE
STARTUP RESTRICT

-- Bắt đầu capture (database tự động về UNRESTRICTED sau khi capture start)
BEGIN
  DBMS_WORKLOAD_CAPTURE.START_CAPTURE(
    NAME           => 'SOE_CAPTURE',
    DIR            => 'WORKLOAD_DIR',  -- phải uppercase
    DEFAULT_ACTION => 'EXCLUDE',       -- treat filter as inclusion
    DURATION       => 300              -- 5 phút (giây); NULL = capture đến khi stop thủ công
  );
END;
/
```

**Trong lúc capture đang chạy:** Khởi động workload (Swingbench) để có traffic thực.

### Dừng capture thủ công (nếu không set DURATION)

```sql
EXEC DBMS_WORKLOAD_CAPTURE.FINISH_CAPTURE();
```

### Kiểm tra trạng thái capture

```sql
ALTER SESSION SET NLS_DATE_FORMAT='HH24:MI';

SELECT ID, NAME, STATUS, START_TIME, END_TIME, CONNECTS, USER_CALLS
FROM DBA_WORKLOAD_CAPTURES
WHERE ID = (SELECT MAX(ID) FROM DBA_WORKLOAD_CAPTURES);
-- STATUS: RUNNING → COMPLETED
```

### Xem files được tạo ra

```bash
ls -alh /home/oracle/workload
```

### AWR snapshots của capture

```sql
-- Database Replay tự động tạo AWR snapshots trong suốt quá trình capture
SELECT ID, AWR_BEGIN_SNAP, AWR_END_SNAP
FROM DBA_WORKLOAD_CAPTURES
ORDER BY ID;
```

### Generate Capture Report

```sql
SET PAGESIZE 0 LONG 30000000 LONGCHUNKSIZE 1000 LINESIZE 200
SPOOL /media/sf_extdisk/capture.html

SELECT DBMS_WORKLOAD_CAPTURE.REPORT(&Enter_ID, 'HTML') FROM DUAL;
-- TYPE: 'HTML', 'TEXT', 'XML'

SPOOL OFF
```

---

## Chuẩn bị Test Database

Trước khi replay, test DB cần được restore về cùng trạng thái với production tại thời điểm capture bắt đầu.

### Restore DB bằng RMAN đến SCN đã ghi

```bash
rman target "'/ as SYSBACKUP'"
```

```sql
SHUTDOWN IMMEDIATE
STARTUP MOUNT
RESTORE DATABASE;
RECOVER DATABASE UNTIL SCN <enter_scn_noted_earlier>;
ALTER DATABASE OPEN RESETLOGS;
```

### Đồng bộ thời gian (quan trọng!)

Test DB phải có **system time = thời điểm capture bắt đầu** để các SQL dùng `SYSDATE` hoạt động chính xác.

```bash
# Đặt time về thời điểm capture bắt đầu
sudo date +%T -s "HH:MM:SS"

# Verify
date
```

> **VirtualBox:** Mặc định VM tự đồng bộ time với host PC. Phải disable tính năng này trước khi set time thủ công bằng lệnh `VBoxManage setextradata`.

---

## Phase 2: Workload Preprocessing

Trên test DB, convert capture files thành replay files (thêm metadata cho replay process).

```sql
EXEC DBMS_WORKLOAD_REPLAY.PROCESS_CAPTURE('WORKLOAD_DIR');
-- Directory object WORKLOAD_DIR phải trỏ đến thư mục chứa capture files
```

```bash
# Kiểm tra files mới được tạo
ls -altr /home/oracle/workload
```

---

## Phase 3: Apply Changes

```sql
-- Ví dụ: Simulate upgrade lên 12c
ALTER SYSTEM SET OPTIMIZER_FEATURES_ENABLE='12.2.0.1' SCOPE=SPFILE;
SHUTDOWN IMMEDIATE
STARTUP
```

---

## Phase 4: Workload Replay

### Bước 1: Initialize Replay

```sql
BEGIN
  DBMS_WORKLOAD_REPLAY.INITIALIZE_REPLAY(
    REPLAY_NAME => 'SOE_CAPTURE',
    REPLAY_DIR  => 'WORKLOAD_DIR'
  );
END;
/
-- Oracle đọc metadata từ capture files vào tables
```

### Bước 2: Kiểm tra và remap connections (nếu cần)

```sql
-- Xem connection mapping
SELECT REPLAY_ID, CONN_ID, CAPTURE_CONN, REPLAY_CONN
FROM DBA_WORKLOAD_CONNECTION_MAP
ORDER BY 1, 2;

-- Remap nếu test DB ở host/port khác
-- EXEC DBMS_WORKLOAD_REPLAY.REMAP_CONNECTION(
--   CONNECTION_ID      => 1,
--   REPLAY_CONNECTION  => 'srv1:1521/ORADB'
-- );
```

### Bước 3: Prepare Replay

```sql
EXEC DBMS_WORKLOAD_REPLAY.PREPARE_REPLAY(
  SYNCHRONIZATION       => 'SCN',   -- sync method: SCN | TIME | OFF
  CONNECT_TIME_SCALE    => 100,     -- 100 = same connect speed as capture
  THINK_TIME_SCALE      => 100,     -- 100 = same think time as capture
  THINK_TIME_AUTO_CORRECT => TRUE   -- auto adjust think time nếu replay chậm hơn
);
```

**SYNCHRONIZATION options:**

| Giá trị | Ý nghĩa |
|---------|---------|
| `'SCN'` | Đồng bộ theo SCN — đảm bảo transaction dependencies |
| `'TIME'` | Đồng bộ theo thời gian |
| `'OFF'` | Không đồng bộ — replay nhanh nhất nhưng kém chính xác |

### Bước 4: Calibrate — xác định số wrc clients cần thiết

```bash
# Chạy từ OS shell (exit SQL*Plus trước)
wrc replaydir='/home/oracle/workload' mode=calibrate
# → Output: số replay clients cần thiết, số streams
```

### Bước 5: Đặt time về thời điểm capture bắt đầu

```bash
sudo date +%T -s "HH:MM:SS"    # thời điểm capture đã ghi
date                             # verify
```

### Bước 6: Khởi động Workload Replay Clients (wrc)

```bash
# Chạy từ OS shell, để cửa sổ này mở
wrc system/oracle@ORADB replaydir=/home/oracle/workload
# → "Wait for the replay to start" — wrc đang chờ lệnh START_REPLAY
```

> `wrc` không tự start replay — chỉ đăng ký và chờ. Lệnh start thực sự từ SQL*Plus.

### Bước 7: Start Replay (từ SQL*Plus khác)

```sql
EXEC DBMS_WORKLOAD_REPLAY.START_REPLAY();
```

### Monitoring trong khi replay

```sql
-- Theo dõi trạng thái replay
ALTER SESSION SET NLS_DATE_FORMAT='DD-MON-YY HH24:MI:SS';

SELECT
  'ID: '               || ID               || CHR(10) ||
  'STATUS: '           || STATUS            || CHR(10) ||
  'START_TIME: '       || START_TIME        || CHR(10) ||
  'END_TIME: '         || END_TIME          || CHR(10) ||
  'DURATION_SECS: '    || DURATION_SECS     || CHR(10) ||
  'NUM_CLIENTS: '      || NUM_CLIENTS       || CHR(10) ||
  'USER_CALLS: '       || USER_CALLS        || CHR(10) ||
  'DBTIME: '           || DBTIME            || CHR(10) ||
  'ELAPSED_TIME_DIFF: '|| ELAPSED_TIME_DIFF || CHR(10) ||
  'AWR_BEGIN_SNAP: '   || AWR_BEGIN_SNAP    || CHR(10) ||
  'AWR_END_SNAP: '     || AWR_END_SNAP      || CHR(10) ||
  'ERROR_CODE: '       || ERROR_CODE        || CHR(10) ||
  'ERROR_MESSAGE: '    || ERROR_MESSAGE     AS INFO
FROM DBA_WORKLOAD_REPLAYS
ORDER BY ID;
```

```sql
-- Xem workload sessions đang replay
SELECT LOGON_USER, WRC_ID, COUNT(*)
FROM V$WORKLOAD_REPLAY_THREAD
GROUP BY LOGON_USER, WRC_ID
ORDER BY LOGON_USER, WRC_ID;
```

### Hủy replay (nếu cần)

```sql
EXEC DBMS_WORKLOAD_REPLAY.CANCEL_REPLAY();
```

---

## Phase 5: Analysis & Reporting

### Generate Replay Report

```sql
SET PAGESIZE 0 LONG 30000000 LONGCHUNKSIZE 1000

VARIABLE v_rpt CLOB;

DECLARE
  v_cap_id NUMBER;
  v_rep_id NUMBER;
BEGIN
  -- Lấy capture ID từ thư mục
  v_cap_id := DBMS_WORKLOAD_REPLAY.GET_REPLAY_INFO(REPLAY_DIR => 'WORKLOAD_DIR');

  -- Lấy replay ID gần nhất
  SELECT MAX(ID) INTO v_rep_id
  FROM DBA_WORKLOAD_REPLAYS
  WHERE CAPTURE_ID = v_cap_id;

  -- Generate report
  :v_rpt := DBMS_WORKLOAD_REPLAY.REPORT(
    REPLAY_ID => v_rep_id,
    FORMAT    => DBMS_WORKLOAD_REPLAY.TYPE_HTML  -- hoặc TYPE_TEXT, TYPE_XML
  );
END;
/

SPOOL /media/sf_extdisk/replay_report.html
PRINT :v_rpt
SPOOL OFF
```

### AWR Report của Replay

```sql
-- Lấy AWR snapshot IDs của replay để tạo AWR report
SELECT ID, AWR_BEGIN_SNAP, AWR_END_SNAP
FROM DBA_WORKLOAD_REPLAYS
ORDER BY ID;

-- Sau đó dùng DBMS_WORKLOAD_REPOSITORY.AWR_REPORT_HTML với các snap ID trên
```

---

## Đọc Replay Report

**Nội dung chính của report:**

```
Database Replay Report
Replay Name: SOE_CAPTURE

Workload Profile:
  Capture Duration:    300 sec
  Replay Duration:     312 sec  ← nếu > capture → hệ thống chậm hơn
  User Calls:         15,234 (capture) vs 15,234 (replay)
  DB Time:             145 sec (capture) vs 198 sec (replay)  ← tăng 37%!
  Avg Active Sessions:  2.9 (capture) vs 4.0 (replay)

Divergence:
  Total Errors:         12 (replay có errors không có trong capture)
  DML Divergence:       5% (DML results khác nhau)
```

**Các chỉ số quan trọng:**

| Chỉ số | Ý nghĩa |
|--------|---------|
| `ELAPSED_TIME_DIFF` | Chênh lệch thời gian: replay lâu hơn/nhanh hơn capture |
| `DBTIME` | Total DB time — tăng → thay đổi gây overhead |
| `USER_CALLS` | Số calls — nên bằng giữa capture và replay |
| Error count | Errors mới xuất hiện khi replay → thay đổi gây lỗi |
| DML divergence | Kết quả DML khác → transaction behavior thay đổi |

---

## Dọn dẹp

```sql
-- Xóa capture info (không xóa files vật lý)
EXEC DBMS_WORKLOAD_CAPTURE.DELETE_CAPTURE_INFO(CAPTURE_ID => <id>);

-- Xóa replay info
EXEC DBMS_WORKLOAD_REPLAY.DELETE_REPLAY_INFO(REPLAY_ID => <id>);
```

```bash
# Xóa file backup
rm /media/sf_extdisk/DB*.bck
rm /media/sf_extdisk/replay_report.html
rm /media/sf_extdisk/capture.html
```

---

## Quy trình đầy đủ — Quick Reference

```
PRODUCTION DB                      TEST DB
─────────────────                  ─────────────────
Chuẩn bị:
  Bật ARCHIVELOG mode
  RMAN backup
  Ghi SCN hiện tại
  CREATE DIRECTORY WORKLOAD_DIR
  ADD_FILTER (tùy chọn)

Capture:
  STARTUP RESTRICT
  START_CAPTURE(NAME, DIR, DURATION)
  [Chạy workload]
  → STATUS = COMPLETED
  REPORT(ID, 'HTML')            →  Copy capture files sang test DB
                                   ↓
                                   RMAN restore đến SCN đã ghi
                                   ALTER DATABASE OPEN RESETLOGS
                                   ↓
                                   Apply changes:
                                   OPTIMIZER_FEATURES_ENABLE='12.2.0.1'
                                   RESTART
                                   ↓
                                   Preprocessing:
                                   PROCESS_CAPTURE('WORKLOAD_DIR')
                                   ↓
                                   Replay prep:
                                   INITIALIZE_REPLAY(NAME, DIR)
                                   [Check DBA_WORKLOAD_CONNECTION_MAP]
                                   PREPARE_REPLAY(SYNCHRONIZATION='SCN')
                                   wrc mode=calibrate
                                   ↓
                                   Set system time = capture start time
                                   ↓
                                   wrc system/oracle@ORADB replaydir=...
                                   [Chờ "Wait for the replay to start"]
                                   ↓
                                   START_REPLAY()
                                   [Monitor DBA_WORKLOAD_REPLAYS]
                                   ↓
                                   GET_REPLAY_INFO + REPORT(HTML)
                                   Set time về hiện tại
```

---

## Tóm tắt Commands, Packages & Views

| Command/Package/View | Dùng để |
|---------------------|---------|
| `DBMS_WORKLOAD_CAPTURE.ADD_FILTER` | Thêm filter để include/exclude sessions |
| `DBMS_WORKLOAD_CAPTURE.START_CAPTURE` | Bắt đầu capture workload |
| `DBMS_WORKLOAD_CAPTURE.FINISH_CAPTURE` | Dừng capture thủ công |
| `DBMS_WORKLOAD_CAPTURE.REPORT` | Generate capture report |
| `DBMS_WORKLOAD_CAPTURE.DELETE_CAPTURE_INFO` | Xóa capture metadata (giữ files) |
| `DBA_WORKLOAD_CAPTURES` | Thông tin các capture đã thực hiện |
| `DBA_WORKLOAD_FILTERS` | Xem các filters đã định nghĩa |
| `DBMS_WORKLOAD_REPLAY.PROCESS_CAPTURE` | Preprocessing: convert capture → replay files |
| `DBMS_WORKLOAD_REPLAY.INITIALIZE_REPLAY` | Load metadata từ replay files vào tables |
| `DBMS_WORKLOAD_REPLAY.PREPARE_REPLAY` | Chuẩn bị replay với timing/sync settings |
| `DBMS_WORKLOAD_REPLAY.START_REPLAY` | Bắt đầu replay (sau khi wrc đã connect) |
| `DBMS_WORKLOAD_REPLAY.CANCEL_REPLAY` | Hủy replay đang chạy |
| `DBMS_WORKLOAD_REPLAY.GET_REPLAY_INFO` | Lấy capture ID từ replay directory |
| `DBMS_WORKLOAD_REPLAY.REPORT` | Generate replay report (HTML/TEXT/XML) |
| `DBMS_WORKLOAD_REPLAY.DELETE_REPLAY_INFO` | Xóa replay metadata |
| `DBA_WORKLOAD_REPLAYS` | Thông tin, status, metrics của các replay |
| `DBA_WORKLOAD_CONNECTION_MAP` | Connection mapping cho replay |
| `V$WORKLOAD_REPLAY_THREAD` | Sessions đang replay (theo dõi real-time) |
| `wrc mode=calibrate` | Ước tính số replay clients cần thiết |
| `wrc system/oracle@DB replaydir=...` | Khởi động Workload Replay Client |

---

## Câu hỏi ôn tập

1. Database Replay khác với SQL Performance Analyzer ở điểm gì quan trọng nhất? Khi nào dùng Database Replay thay vì SPA?
2. Tại sao phải bật ARCHIVELOG mode và thực hiện RMAN backup trước khi bắt đầu capture?
3. `DEFAULT_ACTION => 'EXCLUDE'` trong `START_CAPTURE` có nghĩa là gì khi đã định nghĩa một filter USER='SOE'?
4. Tại sao nên khởi động DB ở RESTRICT mode trước khi bắt đầu capture?
5. `PROCESS_CAPTURE` làm gì? Tại sao cần bước này trước khi replay?
6. `wrc mode=calibrate` dùng để làm gì? Tại sao cần calibrate trước khi chạy replay?
7. Tại sao phải đồng bộ system time của test DB về thời điểm capture bắt đầu? Điều gì sẽ xảy ra nếu không làm bước này?
8. Trong `PREPARE_REPLAY`, `SYNCHRONIZATION='SCN'` có ý nghĩa gì? So sánh với `TIME` và `OFF`.
9. Khi replay report cho thấy `DBTIME` tăng 37% so với capture, điều đó có nghĩa là gì?
10. `ELAPSED_TIME_DIFF` trong `DBA_WORKLOAD_REPLAYS` đo lường gì?


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/section_all/section_36_database_replay_guide.md`
