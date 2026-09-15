---
title: Section 15 — SQL Tracing với DBMS_MONITOR
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/section_all/section_15_sql_tracing_guide.md
---

# Section 15 — SQL Tracing với DBMS_MONITOR

## Tổng quan

SQL Tracing là kỹ thuật ghi lại toàn bộ hoạt động SQL của một session (hoặc nhiều sessions) vào trace file, sau đó dùng `tkprof` để phân tích. Đây là công cụ debug chuyên sâu nhất khi cần hiểu chi tiết tại sao một SQL chạy chậm.

**Practice 15 — Tracing SQL Statements using DBMS_MONITOR**

Mục tiêu:
- Bật trace cho một session đơn
- Bật trace cho nhiều sessions theo module
- Dùng `trcsess` để merge trace files
- Dùng `tkprof` để sinh readable report
- Xem trace file trong SQL Developer

---

## Kiến thức lý thuyết

### Trace file ở đâu?

```sql
SELECT VALUE FROM V$DIAG_INFO WHERE NAME = 'Diag Trace';
-- Ví dụ: /u01/app/oracle/diag/rdbms/oradb/ORADB/trace
```

Thực tế nên lưu path này vào biến môi trường để dùng lại:

```bash
export TRACE_DIR=/u01/app/oracle/diag/rdbms/oradb/ORADB/trace
```

### Quy trình tổng thể

```
Bật trace → Chạy workload → Tắt trace
    ↓
Dùng trcsess merge files (nếu nhiều session)
    ↓
Dùng tkprof sinh readable output
    ↓
Phân tích output
```

---

## Phần 1: Trace một Session đơn

### Bước 1: Lấy SID và SERIAL# của session cần trace

```sql
SELECT SID, SERIAL# FROM V$SESSION WHERE USERNAME = 'SOE';
```

### Bước 2: Bật trace

```sql
DEFINE v_sid = <sid_value>
DEFINE v_serial = <serial_value>

BEGIN
  DBMS_MONITOR.SESSION_TRACE_ENABLE(
    SESSION_ID => &v_sid,
    SERIAL_NUM => &v_serial,
    WAITS      => TRUE,   -- ghi lại wait events
    BINDS      => FALSE   -- không ghi bind variable values
  );
END;
/
```

**Tham số quan trọng:**
- `WAITS => TRUE`: ghi wait events vào trace — **rất quan trọng để chẩn đoán**
- `BINDS => TRUE`: ghi giá trị bind variables — hữu ích khi nghi ngờ data-specific issue, nhưng làm trace file lớn hơn nhiều

### Bước 3: Lấy tên trace file

```sql
SELECT P.TRACEFILE
FROM   V$SESSION S
JOIN   V$PROCESS P ON S.PADDR = P.ADDR
WHERE  S.SID = &V_SID;
```

> Ghi lại đường dẫn đầy đủ của trace file để dùng với tkprof.

### Bước 4: Chạy workload trong session được trace

```sql
-- Chạy trong session được trace (client window)
SELECT * FROM EMP;
```

### Bước 5: Kiểm tra trace file đang ghi

```bash
host grep EMP <trace_file_path>
-- Nếu thấy kết quả, trace đang hoạt động
```

### Bước 6: Tắt trace

```sql
BEGIN
  DBMS_MONITOR.SESSION_TRACE_DISABLE(
    SESSION_ID => &v_sid,
    SERIAL_NUM => &v_serial
  );
END;
/
```

---

## Phần 2: Trace nhiều Sessions theo Module

Usecase: Trace một tiến trình nghiệp vụ chạy song song nhiều session (VD: batch PROCESS_ORDERS).

### Bước 1: Ứng dụng đặt module name

```sql
-- Chạy trong session của ứng dụng (client)
exec DBMS_APPLICATION_INFO.SET_MODULE(
  MODULE_NAME => 'PROCESS_ORDERS',
  ACTION_NAME => NULL
);
```

### Bước 2: Đặt identifier cho trace file (tùy chọn nhưng rất hữu ích)

```sql
ALTER SESSION SET TRACEFILE_IDENTIFIER = 'PORDERS';
```

> Tất cả trace files tạo ra sẽ có chuỗi `PORDERS` trong tên → dễ phân biệt với hàng trăm trace files khác.

### Bước 3: Flush shared pool (admin), sau đó bật trace

```sql
-- Admin window
ALTER SYSTEM FLUSH SHARED_POOL;

exec DBMS_MONITOR.SERV_MOD_ACT_TRACE_ENABLE(
  SERVICE_NAME => 'ORADB.localdomain',
  MODULE_NAME  => 'PROCESS_ORDERS'
  -- ACTION_NAME không truyền = trace tất cả actions trong module
);
```

### Bước 4: Kiểm tra trace đã bật

```sql
col PRIMARY_ID format a10
col QUALIFIER_ID1 format a15

SELECT TRACE_TYPE, PRIMARY_ID, QUALIFIER_ID1, WAITS, BINDS, PLAN_STATS
FROM DBA_ENABLED_TRACES;
```

### Bước 5: Tắt trace sau khi xong

```sql
exec DBMS_MONITOR.SERV_MOD_ACT_TRACE_DISABLE(
  SERVICE_NAME => 'ORADB.localdomain',
  MODULE_NAME  => 'PROCESS_ORDERS'
);
```

---

## Phần 3: Merge Trace Files với trcsess

Khi nhiều sessions cùng chạy, mỗi session tạo một trace file riêng. Cần merge trước khi dùng tkprof.

```bash
# Xem các trace files được tạo
cd $TRACE_DIR
ls *PORDERS.trc

# Merge tất cả trace files của module PROCESS_ORDERS
trcsess output="$TRACE_DIR/PROCESS_ORDERS.trc" module="PROCESS_ORDERS"

# Kiểm tra file đã được tạo
ls -alh PROCESS_ORDERS.trc
```

> **Lưu ý:** Nếu trace session đơn → chỉ có 1 trace file → không cần dùng `trcsess`.

---

## Phần 4: Phân tích bằng tkprof

`tkprof` chuyển raw trace file thành dạng dễ đọc, tổng hợp thống kê từng SQL.

### Xem help

```bash
tkprof
```

### Chạy tkprof cơ bản

```bash
tkprof PROCESS_ORDERS.trc PROCESS_ORDERS.txt \
  SYS=no \          # bỏ qua recursive sys statements
  waits=yes \       # bao gồm wait event stats
  aggregate=yes \   # gộp các lần chạy cùng SQL
  sort="(exeela,prsela,fchela)"  # sort theo elapsed time (execute+parse+fetch)
```

**Giải thích tham số sort:**
- `exeela` = execute elapsed time
- `prsela` = parse elapsed time
- `fchela` = fetch elapsed time

→ Sort giảm dần theo tổng 3 giá trị → SQL tốn thời gian nhất lên đầu.

### Thêm tham số insert (tùy chọn)

```bash
tkprof PROCESS_ORDERS.trc PROCESS_ORDERS.txt \
  SYS=no waits=yes aggregate=yes \
  sort="(exeela,prsela,fchela)" \
  insert=porders.sql
```

> `insert` tạo script SQL chèn kết quả vào table → hữu ích khi cần so sánh nhiều lần chạy (trước/sau tuning).

---

## Phần 5: Đọc tkprof Output

Mỗi SQL statement trong output có dạng:

```
SQL ID: ...
SQL Text: SELECT ...

call     count       cpu    elapsed       disk      query    current        rows
------- ------  -------- ---------- ---------- ---------- ----------  ----------
Parse        1      0.00       0.00          0          0          0           0
Execute      1      0.50       0.85          0       5000          0           0
Fetch       10      0.10       0.12          0       1000          0         100
------- ------  -------- ---------- ---------- ---------- ----------  ----------
total       12      0.60       0.97          0       6000          0         100

Rows (1st) Rows (avg) Rows (max)  Row Source Operation
---------- ---------- ----------  ---------------------------------------------------
       100        100        100  TABLE ACCESS FULL CUSTOMERS (cr=6000 pr=0 ...)

Elapsed times include waiting on following events:
  Event waited on                             Times   Max. Wait  Total Waited
  ----------------------------------------   -----  ----------  ------------
  db file sequential read                       50        0.010         0.050
```

**Các cột quan trọng:**
| Cột | Ý nghĩa |
|-----|---------|
| `count` | Số lần parse/execute/fetch |
| `cpu` | CPU time (giây) |
| `elapsed` | Wall clock time (giây) |
| `disk` | Physical reads |
| `query` | Consistent gets (logical reads) |
| `current` | Current mode gets (DML) |
| `rows` | Số rows xử lý |

> **Phân tích:** Nếu `elapsed >> cpu` → phần lớn thời gian là wait (I/O, lock, latch...). Xem phần "Elapsed times" để biết wait event nào chiếm nhiều nhất.

---

## Phần 6: Xem trace trong SQL Developer

SQL Developer có thể đọc trực tiếp trace file (.trc):

1. Copy trace file ra `/tmp` để SQL Developer truy cập:
   ```bash
   cp PROCESS_ORDERS.trc /tmp
   ```
2. Khởi động SQL Developer
3. **File → Open** → chọn file `.trc`

SQL Developer hiển thị 4 tabs:
- **Tree View**: cấu trúc phân cấp SQL, có thể expand để xem recursive calls và bind values
- **Statistics View**: thống kê theo từng statement
- **List View**: dạng bảng tương tự tkprof output, thay Filter thành non-recursive
- **History**: lịch sử các lần xem

---

## Tóm tắt

| Tác vụ | Lệnh |
|--------|------|
| Lấy trace folder | `SELECT VALUE FROM V$DIAG_INFO WHERE NAME = 'Diag Trace'` |
| Bật trace session đơn | `DBMS_MONITOR.SESSION_TRACE_ENABLE(...)` |
| Bật trace theo module | `DBMS_MONITOR.SERV_MOD_ACT_TRACE_ENABLE(...)` |
| Tắt trace session | `DBMS_MONITOR.SESSION_TRACE_DISABLE(...)` |
| Tắt trace theo module | `DBMS_MONITOR.SERV_MOD_ACT_TRACE_DISABLE(...)` |
| Kiểm tra trace đang bật | `SELECT * FROM DBA_ENABLED_TRACES` |
| Lấy tên trace file của session | `V$PROCESS.TRACEFILE` join `V$SESSION` |
| Merge nhiều trace files | `trcsess output=... module=...` |
| Phân tích trace file | `tkprof <input>.trc <output>.txt SYS=no waits=yes ...` |

> **Workflow:** Bật trace → Chạy workload → Tắt trace → trcsess (nếu multi-session) → tkprof → Đọc output, tập trung vào SQL có elapsed cao nhất và wait events.


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/section_all/section_15_sql_tracing_guide.md`
