---
title: Section 9 — AWR (Automatic Workload Repository)
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/section_all/section_9_awr_guide.md
---

# Section 9 — AWR (Automatic Workload Repository)

## Mục tiêu

Nắm vững công cụ chẩn đoán hiệu năng mạnh nhất của Oracle:

- Quản lý AWR settings và snapshots (Practice 4)
- Tạo và đọc AWR Reports để phát hiện performance issue (Practice 5)
- Phân tích SQL statement cụ thể với AWR SQL Reports (Practice 6)
- Bảo toàn snapshots quan trọng bằng AWR Baselines (Practice 7)

---

## Khái niệm nền tảng

### AWR là gì?

**AWR (Automatic Workload Repository)** là kho lưu trữ dữ liệu hiệu năng tự động của Oracle. Cứ mỗi chu kỳ (mặc định 60 phút), Oracle chụp ảnh (snapshot) toàn bộ trạng thái hiệu năng của database và lưu vào tablespace **SYSAUX**.

```
                    ┌──────────────┐
  Mỗi 60 phút      │ AWR Snapshot │ ← dữ liệu từ V$SYS_TIME_MODEL,
  ─────────────────►│   (SYSAUX)   │   V$SYSTEM_EVENT, V$SQL, v.v.
                    └──────────────┘
                          │
                          ▼
              DBA_HIST_* views (lịch sử)
```

**Tại sao AWR tốt hơn V$ views?**
- V$ views: dữ liệu real-time, mất khi instance restart
- AWR: lưu lịch sử dài hạn, so sánh được giữa các thời điểm

### Điều kiện kích hoạt AWR

```sql
-- STATISTICS_LEVEL phải là TYPICAL hoặc ALL
SHOW PARAMETER STATISTICS_LEVEL;

-- Đặt thành ALL để thu thập thêm OS stats và plan execution stats
ALTER SYSTEM SET STATISTICS_LEVEL = ALL SCOPE = BOTH;
```

---

## Practice 4 — Quản lý AWR Settings & Snapshots

### AWR Settings

```sql
-- Xem cấu hình hiện tại
SELECT SNAP_INTERVAL, RETENTION, TOPNSQL FROM DBA_HIST_WR_CONTROL;
-- Mặc định: INTERVAL=60 phút, RETENTION=8 ngày
```

```sql
-- Đổi interval thành 30 phút (khuyến nghị cho production)
BEGIN
  DBMS_WORKLOAD_REPOSITORY.MODIFY_SNAPSHOT_SETTINGS(INTERVAL => 30);
END;
/
```

> **Thực tế:** Nên giảm interval xuống 15–30 phút để phân tích chính xác hơn. Tuy nhiên, disk space trong SYSAUX sẽ tăng.

### Quản lý Snapshots

```sql
-- Xem danh sách snapshots
SELECT SNAP_ID, BEGIN_INTERVAL_TIME, END_INTERVAL_TIME, SNAP_LEVEL
FROM DBA_HIST_SNAPSHOT
ORDER BY SNAP_ID;
```

```sql
-- Tạo snapshot thủ công (heavyweight, LEVEL=2)
EXEC DBMS_WORKLOAD_REPOSITORY.CREATE_SNAPSHOT(FLUSH_LEVEL => 'ALL');
```

```sql
-- Xóa một dải snapshots
BEGIN
  DBMS_WORKLOAD_REPOSITORY.DROP_SNAPSHOT_RANGE(
    LOW_SNAP_ID  => &begin_snap,
    HIGH_SNAP_ID => &end_snap);
END;
/
```

### Quản lý Space của AWR

```sql
-- Xem dung lượng AWR trong SYSAUX
SELECT OCCUPANT_NAME, SPACE_USAGE_KBYTES/1024 MB, MOVE_PROCEDURE
FROM V$SYSAUX_OCCUPANTS
WHERE OCCUPANT_NAME = 'SM/AWR';

-- Báo cáo chi tiết
@ ?/rdbms/admin/awrinfo.sql
```

**Giảm dung lượng SYSAUX:** Rút ngắn thời gian lưu Optimizer Statistics (mặc định 31 ngày, thực tế chỉ cần 7 ngày):

```sql
-- Xem retention hiện tại
SELECT DBMS_STATS.GET_STATS_HISTORY_RETENTION FROM DUAL;

-- Giảm xuống 7 ngày
EXEC DBMS_STATS.ALTER_STATS_HISTORY_RETENTION(7);

-- Purge dữ liệu cũ (CẢNH BÁO: không chạy trên production nếu data đang ở GB)
EXEC DBMS_STATS.PURGE_STATS(NULL);
```

---

## Practice 5 — Sử dụng AWR Reports

### Tạo AWR Report

```sql
-- Report HTML (khuyến nghị)
@ ?/rdbms/admin/awrrpt.sql
-- Nhập: format (html/text), begin_snap_id, end_snap_id, report_name
```

```sql
-- Report so sánh 2 khoảng thời gian (AWR Diff/Compare Report)
@ ?/rdbms/admin/awrddrpt.sql
```

### Cách đọc AWR Report — Header sections quan trọng

#### 1. DB Time vs Elapsed Time
```
Elapsed:               10.00 (mins)
DB Time:               45.23 (mins)
```
- `DB Time > Elapsed Time` → hoàn toàn bình thường khi có nhiều concurrent sessions
- `DB Time per Second = DB Time / Elapsed Time` → đo mức độ bận của database

#### 2. Load Profile
| Metric | Ý nghĩa |
|--------|---------|
| `DB time(s): per second` | Workload tổng thể mỗi giây |
| `Logical reads: per second` | Số blocks đọc từ buffer cache |
| `Hard parses: per second` | Hard parse cao → shared pool issue |
| `Executes: per second` | Throughput SQL |

#### 3. Instance Efficiency Percentages
| Chỉ số | Giá trị tốt | Vấn đề khi |
|--------|-----------|-----------|
| `Buffer Cache Hit %` | > 95% | < 90% → cần tăng buffer cache |
| `Library Cache Hit %` | > 99% | Thấp → hard parse nhiều |
| `Soft Parse %` | > 95% | Thấp → ứng dụng không dùng bind variables |
| `Parse CPU to Parse Elapsed %` | Không cố định | Thấp nhưng hard parse ít = không sao |

#### 4. Top 10 Foreground Events by Total Wait Time
Phần quan trọng nhất — hiển thị wait events chiếm nhiều thời gian nhất.

```
Event                           Waits    Time(s)   Avg wait   % DB time  Wait Class
log file sync                   45,231    234.5      5.2ms       8.6%     Commit
db file sequential read         12,453    189.2      15.2ms      6.9%     User I/O
```

> **Chiến lược đọc:** Tập trung vào top 2–3 events. `log file sync` cao → vấn đề Commit/Redo. `db file sequential read` cao → I/O bottleneck.

### Chiến lược Troubleshoot bằng AWR

```
Normal AWR Report          Issue AWR Report
(baseline period)    VS    (problem period)
       │                          │
       └──────────┬───────────────┘
                  ▼
         So sánh header sections:
         1. DB Time tăng bao nhiêu?
         2. Top wait events có thay đổi?
         3. Load Profile có số nào nhảy vọt?
         4. Instance Efficiency có số nào giảm mạnh?
                  │
                  ▼
         Thu hẹp nguyên nhân
         → xem detail sections tương ứng
```

**Best practices:**
- Lưu AWR report của **thời kỳ bình thường** để làm reference
- Khi có sự cố, so sánh với report bình thường
- Hai report cần có **cùng elapsed time** và **cùng workload pattern**

---

## Practice 6 — AWR SQL Reports

### Mục đích

Phân tích lịch sử performance của **một SQL statement cụ thể** — bao gồm nhiều execution plans khác nhau theo thời gian.

### Tạo AWR SQL Report

```sql
-- Lấy SQL_ID của câu query cần phân tích
SELECT SQL_ID FROM V$SQL
WHERE SQL_TEXT LIKE 'SELECT ORDER_ID, ORDER_TOTAL FROM ORDERS2%';
-- Kết quả ví dụ: '0rzpfnnv95pv1'

-- Tạo AWR SQL Report
@ ?/rdbms/admin/awrsqrpt.sql
-- Nhập: format, begin_snap, end_snap, sql_id, report_name
```

### Thông tin trong AWR SQL Report

- **Execution Plans History**: tất cả execution plans đã dùng trong khoảng snapshot
- **Plan thay đổi theo thời gian**: phát hiện khi optimizer chọn plan khác (tốt hơn hoặc tệ hơn)
- **Số lần execute** mỗi plan
- **Performance so sánh** giữa các plans (elapsed time, buffer gets, rows processed)

### Ví dụ phân tích

```sql
-- Tạo bảng test
CREATE TABLE ORDERS2 NOLOGGING AS
SELECT * FROM ORDERS WHERE ORDER_ID <= 150000;
ANALYZE TABLE ORDERS2 COMPUTE STATISTICS;

-- Snapshot 1: chạy query (full table scan vì chưa có index)
EXEC DBMS_WORKLOAD_REPOSITORY.CREATE_SNAPSHOT(FLUSH_LEVEL => 'ALL');

-- Tạo index
CREATE INDEX I2 ON ORDERS2(ORDER_ID) NOLOGGING;
ANALYZE INDEX I2 COMPUTE STATISTICS;

-- Chạy lại query (index range scan)
EXEC DBMS_WORKLOAD_REPOSITORY.CREATE_SNAPSHOT(FLUSH_LEVEL => 'ALL');

-- AWR SQL Report sẽ thấy 2 execution plans với performance khác nhau
@ ?/rdbms/admin/awrsqrpt.sql
```

**View liên quan:**
```sql
-- Lấy thông tin tương đương từ view (không cần AWR report)
SELECT SQL_ID, PLAN_HASH_VALUE, EXECUTIONS, ELAPSED_TIME_TOTAL/1000000 ELAPSED_SEC
FROM DBA_HIST_SQLSTAT
WHERE SQL_ID = '0rzpfnnv95pv1'
ORDER BY SNAP_ID;
```

---

## Practice 7 — AWR Baselines

### Baseline là gì?

**AWR Baseline** = tập snapshots được đánh dấu quan trọng → **không bị tự động xóa** theo retention policy.

```
Thông thường:                    Sau khi tạo baseline:
┌──────────────┐                ┌──────────────┐
│  Snapshot A  │ ─── tự xóa    │  Snapshot A  │ ─── được bảo vệ
│  Snapshot B  │ ─── tự xóa    │  Snapshot B  │ ─── được bảo vệ
│  Snapshot C  │                │  Snapshot C  │
└──────────────┘                └──────────────┘
  (sau RETENTION days)            (đến EXPIRATION date)
```

### Tạo và quản lý Baseline

```sql
-- Tạo baseline từ snapshot IDs (ví dụ: snapshots của thời kỳ bình thường)
BEGIN
  DBMS_WORKLOAD_REPOSITORY.CREATE_BASELINE(
    START_SNAP_ID => &begin_snap,
    END_SNAP_ID   => &end_snap,
    BASELINE_NAME => 'OLTP_NORMAL',
    EXPIRATION    => 365);  -- giữ 365 ngày
END;
/
```

```sql
-- Xem danh sách baselines
SELECT BASELINE_NAME, START_SNAP_ID, END_SNAP_ID,
       START_SNAP_TIME, END_SNAP_TIME, EXPIRATION
FROM DBA_HIST_BASELINE;
-- SYSTEM_MOVING_WINDOW: baseline tự động, dùng cho Adaptive Threshold
```

```sql
-- Xem chi tiết một baseline
SELECT 'START: ' || START_SNAP_ID || CHR(10) ||
       'END: '   || END_SNAP_ID   || CHR(10) ||
       'PCT: '   || PCT_TOTAL_TIME  AS INFO
FROM TABLE(DBMS_WORKLOAD_REPOSITORY.SELECT_BASELINE_DETAILS(&baseline_id));
```

```sql
-- Xóa baseline
EXEC DBMS_WORKLOAD_REPOSITORY.DROP_BASELINE(BASELINE_NAME => 'OLTP_NORMAL');
```

### Baseline Templates — Tự động tạo Baseline

```sql
-- Tạo Single Baseline Template (tạo 1 baseline cho 1 khoảng thời gian)
BEGIN
  DBMS_WORKLOAD_REPOSITORY.CREATE_BASELINE_TEMPLATE(
    START_TIME    => SYSDATE + (3/24/60),   -- 3 phút từ bây giờ
    END_TIME      => SYSDATE + (18/24/60),  -- 18 phút từ bây giờ
    BASELINE_NAME => 'BATCHING_BS',
    TEMPLATE_NAME => 'BATCHING_BT',
    EXPIRATION    => NULL);
  COMMIT;  -- bắt buộc!
END;
/
```

> **Lưu ý thực tế:** Baseline templates **không đáng tin cậy** — có thể mất vài ngày mới tạo baseline. Thay vào đó, dùng **Oracle Scheduler Job** để tự động tạo baseline đúng giờ.

```sql
-- Xóa template
EXEC DBMS_WORKLOAD_REPOSITORY.DROP_BASELINE_TEMPLATE('BATCHING_BT');
```

---

## Tổng hợp — Views & Packages AWR

| Đối tượng | Mô tả |
|-----------|-------|
| `DBA_HIST_WR_CONTROL` | AWR settings (interval, retention, topnsql) |
| `DBA_HIST_SNAPSHOT` | Danh sách snapshots |
| `DBA_HIST_BASELINE` | Danh sách baselines |
| `DBA_HIST_SQLSTAT` | Lịch sử performance của SQL statements |
| `DBA_HIST_ACTIVE_SESS_HISTORY` | Lịch sử ASH (Active Session History) |
| `DBA_HIST_SYS_TIME_MODEL` | Lịch sử time model statistics |
| `DBA_HIST_SYSTEM_EVENT` | Lịch sử wait events |
| `V$SYSAUX_OCCUPANTS` | Dung lượng từng component trong SYSAUX |
| `DBMS_WORKLOAD_REPOSITORY` | Package quản lý AWR |

---

## Quy trình AWR trong thực tế

```
Hàng ngày:
1. AWR tự động snapshot mỗi 30 phút (sau khi đã chỉnh interval)
2. DBA review AWR report của giờ bận nhất

Khi hệ thống bình thường:
3. Tạo AWR report → đọc và ghi nhớ "normal baseline"
4. Tạo AWR Baseline để bảo vệ snapshots đó

Khi có performance issue:
5. Tạo snapshot ngay trước và sau thời điểm sự cố
6. Generate AWR report cho khoảng đó
7. So sánh với "normal baseline" report
8. Nếu cần: dùng AWR Compare Report (awrddrpt.sql)
9. Drill down vào SQL cụ thể với AWR SQL Report (awrsqrpt.sql)
```

---

## Câu hỏi Ôn tập

1. Tại sao `DB Time` trong AWR report có thể lớn hơn `Elapsed Time`?
2. AWR lưu dữ liệu ở đâu? Tại sao DBA cần theo dõi dung lượng của nó?
3. Sự khác biệt giữa AWR Snapshot Level 1 (TYPICAL) và Level 2 (ALL) là gì?
4. Khi nào cần tạo AWR Baseline? Tại sao không để AWR tự xóa snapshots đó?
5. AWR SQL Report cung cấp thông tin gì mà AWR Report thông thường không có?
6. `SYSTEM_MOVING_WINDOW` baseline là gì và dùng để làm gì?

<details>
<summary>Gợi ý trả lời</summary>

1. DB Time = tổng thời gian CPU + wait của **tất cả foreground sessions**. Nếu có 10 sessions cùng chạy trong 1 phút, DB Time ≈ 10 phút trong khi Elapsed Time = 1 phút. DB Time > Elapsed Time là bình thường với concurrent workload.

2. AWR lưu trong tablespace **SYSAUX**. DBA cần theo dõi vì SYSAUX đầy có thể gây lỗi AWR collection, thậm chí ảnh hưởng database operations. Kiểm tra qua `V$SYSAUX_OCCUPANTS` và `awrinfo.sql`.

3. Level 1 (TYPICAL): thu thập statistics chuẩn. Level 2 (ALL): thu thập thêm **timed OS statistics** và **plan execution statistics** (row source execution stats). Level 2 được tạo khi dùng `FLUSH_LEVEL=>'ALL'` hoặc khi `STATISTICS_LEVEL=ALL`.

4. Tạo Baseline khi muốn **bảo tồn snapshots đại diện cho workload bình thường** để dùng làm reference trong tương lai. Nếu không tạo baseline, AWR sẽ tự xóa sau N ngày theo retention policy và mất đi dữ liệu reference quý giá.

5. AWR SQL Report cung cấp: lịch sử **tất cả execution plans** của 1 SQL cụ thể theo thời gian, performance của từng plan (rows, buffer gets, elapsed time), và phát hiện khi optimizer thay đổi plan — không có trong AWR Report thông thường.

6. `SYSTEM_MOVING_WINDOW` là baseline tự động của Oracle, luôn đại diện cho khoảng thời gian bằng `RETENTION` của AWR (di chuyển theo thời gian). Dùng cho tính năng **Adaptive Threshold** — Oracle tự động xác định ngưỡng cảnh báo dựa trên lịch sử thống kê trong cửa sổ di động này.

</details>


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/section_all/section_9_awr_guide.md`
