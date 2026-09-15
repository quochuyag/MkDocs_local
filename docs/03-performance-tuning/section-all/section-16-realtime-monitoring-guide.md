---
title: Section 16 — Real-time Database Operation Monitoring
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/section_all/section_16_realtime_monitoring_guide.md
---

# Section 16 — Real-time Database Operation Monitoring

## Tổng quan

Oracle cho phép monitor tiến trình thực thi của SQL queries và composite database operations theo thời gian thực, không cần trace file. Đây là công cụ hữu ích khi cần theo dõi một query đang chạy dài hoặc một nghiệp vụ phức tạp gồm nhiều SQL.

**Practice 16 — Monitoring Database Operations in Real-time**

Mục tiêu:
- Monitor một simple operation (query đơn) qua `V$SQL_MONITOR`
- Monitor một composite database operation gồm nhiều queries
- Xem real-time execution plan progress qua `V$SQL_PLAN_MONITOR`
- Dùng EM Express để xem monitoring report

---

## Kiến thức lý thuyết

### Điều kiện để SQL được monitor tự động

Oracle tự động monitor một SQL khi:
1. SQL chạy **trên 5 giây** (CPU hoặc I/O time)
2. Hoặc SQL chạy song song (parallel execution)

**Yêu cầu prerequisites:**
- `STATISTICS_LEVEL = TYPICAL` hoặc `ALL` (mặc định là TYPICAL)
- `CONTROL_MANAGEMENT_PACK_ACCESS = DIAGNOSTIC+TUNING` (cần license)

```sql
SHOW PARAMETER STATISTICS_LEVEL
SHOW PARAMETER CONTROL_MANAGEMENT_PACK_ACCESS
```

### Các views chính

| View | Mô tả |
|------|-------|
| `V$SQL_MONITOR` | Thống kê real-time của queries và operations đang/đã monitor |
| `V$SQL_PLAN_MONITOR` | Chi tiết tiến trình thực thi từng bước trong execution plan |

### Hai loại monitoring

| Loại | Mô tả |
|------|-------|
| **Simple monitoring** | Oracle tự động monitor SQL > 5 giây |
| **Composite operation monitoring** | DBA chủ động định nghĩa một "operation" gồm nhiều SQL, dùng `DBMS_SQL_MONITOR` |

---

## Phần 1: Monitor Simple Operation

### Ví dụ: Query tiêu tốn CPU

```sql
-- Tạo function tiêu thụ CPU (client window)
CREATE OR REPLACE FUNCTION SOE.CONSUME_CPU(N NUMBER) RETURN NUMBER IS
  V TIMESTAMP;
  X NUMBER;
  SECONDS NUMBER;
BEGIN
  V := SYSTIMESTAMP;
  SECONDS := 0;
  WHILE SECONDS < N LOOP
    SECONDS := (EXTRACT(MINUTE FROM SYSTIMESTAMP - V)*60)
               + EXTRACT(SECOND FROM SYSTIMESTAMP - V);
    X := SQRT(DBMS_RANDOM.VALUE(1,10000));
  END LOOP;
  RETURN SECONDS;
END;
/

-- Chạy query tốn 80 giây (client window)
SELECT /* MY QUERY 1 */ CONSUME_CPU(80) FROM DUAL;
```

### Xem monitoring status (admin window — chạy nhiều lần)

```sql
SELECT
  'REPORT_ID: ' || REPORT_ID || CHR(10) ||
  'STATUS: '    || STATUS    || CHR(10) ||
  'USERNAME: '  || USERNAME  || CHR(10) ||
  'SQL_TEXT: '  || SQL_TEXT  || CHR(10) ||
  'CPU_TIME: '  || CPU_TIME  || CHR(10) ||
  'DISK_READS: '|| DISK_READS AS "Monitoring Tasks"
FROM V$SQL_MONITOR
WHERE USERNAME='SOE' AND SQL_TEXT LIKE '%MY QUERY 1%';
```

**Quan sát:** `CPU_TIME` tăng dần qua mỗi lần query, `DISK_READS = 0` → query chỉ tốn CPU, không đọc disk.

> **Tại sao Oracle tự monitor query này?** Vì elapsed time > 5 giây — Oracle tự động kích hoạt monitoring.

---

## Phần 2: Monitor Composite Database Operation

Composite operation = một nghiệp vụ gồm nhiều SQL, được đặt tên để theo dõi tổng thể.

### Bước 1: Lấy SID và SERIAL# của client session

```sql
-- Chạy trong client session
SELECT SID, SERIAL# FROM V$SESSION WHERE AUDSID = SYS_CONTEXT('USERENV', 'SESSIONID');
```

### Bước 2: Bắt đầu monitoring operation (admin window)

```sql
VARIABLE OP_ID NUMBER;

BEGIN
  :OP_ID := DBMS_SQL_MONITOR.BEGIN_OPERATION(
    DBOP_NAME      => 'ORA.SOE.TOPCUSTOMERS',
    SESSION_ID     => &Enter_SID,
    SESSION_SERIAL => &Enter_Serial,
    FORCED_TRACKING => 'Y'  -- buộc monitor ngay cả khi < 5 giây
  );
END;
/

print :OP_ID
```

> `FORCED_TRACKING => 'Y'` = track kể cả các SQL chạy dưới 5 giây trong operation này.

### Bước 3: Verify operation đã được khởi tạo

```sql
set linesize 180
col STATUS   format a20
col USERNAME format a20
col MODULE   format a20
col ACTION   format a20

SELECT DBOP_EXEC_ID, STATUS, USERNAME, MODULE, ACTION
FROM V$SQL_MONITOR
WHERE (DBOP_NAME='ORA.SOE.TOPCUSTOMERS' OR IN_DBOP_NAME='ORA.SOE.TOPCUSTOMERS')
  AND DBOP_EXEC_ID = :OP_ID;
```

**Phân biệt rows trong V$SQL_MONITOR:**
- Row có giá trị `DBOP_NAME` = operation tổng thể
- Row có giá trị `IN_DBOP_NAME` = SQL task thuộc operation đó

### Bước 4: Chạy workload trong client session

```sql
-- Query 1: query nhanh — KHÔNG xuất hiện trong V$SQL_MONITOR
SELECT SYSDATE FROM DUAL;

-- Query 2: query phức tạp, nhiều row
SELECT CUSTOMERS.CUSTOMER_ID,
       InitCap(CUST_FIRST_NAME) FIRST_NAME,
       InitCap(CUST_LAST_NAME)  LAST_NAME,
       ENAME ACCOUNT_MANAGER,
       ROUND(MONTHS_BETWEEN(SYSDATE,CUSTOMER_SINCE)/12,1) CUSTOMER_YEARS,
       TO_CHAR(SUM(ORDER_TOTAL),'999,999,999') TOTAL
FROM ORDERS, CUSTOMERS, EMP
WHERE CUSTOMERS.CUSTOMER_ID = ORDERS.CUSTOMER_ID AND EMP_NO = ACCOUNT_MGR_ID
GROUP BY CUSTOMERS.CUSTOMER_ID, InitCap(CUST_FIRST_NAME), InitCap(CUST_LAST_NAME),
         ENAME, ROUND(MONTHS_BETWEEN(SYSDATE,CUSTOMER_SINCE)/12,1)
ORDER BY SUM(ORDER_TOTAL) DESC;

-- Query 3: PL/SQL block
BEGIN
  FOR R IN (SELECT * FROM CUSTOMERS) LOOP NULL; END LOOP;
END;
/

-- Query 4: query cực nặng để demo real-time plan
SET TIMING ON
SELECT /*+ USE_NL(A B) NO_PARALLEL */ COUNT(*) FROM CUSTOMERS A, CUSTOMERS B
WHERE A.CUSTOMER_ID < 13000 AND B.CUSTOMER_ID < 13000;
```

> **Lưu ý thực tế:** Chỉ Query 4 (chạy > 5 giây) mới xuất hiện trong V$SQL_MONITOR. Đây là hạn chế của công cụ — short queries bị bỏ qua.

### Bước 5: Xem tasks của operation

```sql
SELECT
  'DBOP_NAME: '    || DBOP_NAME    || CHR(10) ||
  'IN_DBOP_NAME: ' || IN_DBOP_NAME || CHR(10) ||
  'SQL_ID: '       || SQL_ID       || CHR(10) ||
  'SQL_TEXT: '     || SQL_TEXT AS "Operation Tasks"
FROM V$SQL_MONITOR
WHERE (DBOP_NAME='ORA.SOE.TOPCUSTOMERS' OR IN_DBOP_NAME='ORA.SOE.TOPCUSTOMERS')
ORDER BY DBOP_NAME;
```

### Bước 6: Xem real-time execution plan progress

```sql
DEFINE v_sql_id = '<sql_id_của_query_4>'

COL ID        FORMAT 999
COL OPERATION FORMAT A20
COL OBJECT    FORMAT A18
COL STATUS    FORMAT A8
SET COLSEP '|'
SET LINES 100

SELECT P.ID,
       RPAD(' ', P.DEPTH*2, ' ') || P.OPERATION OPERATION,
       P.OBJECT_NAME OBJECT,
       P.CARDINALITY CARD,
       P.COST COST,
       SUBSTR(M.STATUS, 1, 4) STATUS,
       M.OUTPUT_ROWS
FROM V$SQL_PLAN P, V$SQL_PLAN_MONITOR M
WHERE P.SQL_ID              = M.SQL_ID
  AND P.CHILD_ADDRESS       = M.SQL_CHILD_ADDRESS
  AND P.PLAN_HASH_VALUE     = M.SQL_PLAN_HASH_VALUE
  AND P.ID                  = M.PLAN_LINE_ID
  AND M.SQL_ID              = '&V_SQL_ID'
ORDER BY P.ID;
```

**Quan sát:** Chạy query này nhiều lần → `OUTPUT_ROWS` tăng dần → theo dõi từng bước của execution plan đang thực thi.

### Bước 7: Kết thúc operation

```sql
BEGIN
  DBMS_SQL_MONITOR.END_OPERATION(
    DBOP_NAME => 'ORA.SOE.TOPCUSTOMERS',
    DBOP_EID  => :OP_ID
  );
END;
/
```

### Bước 8: Verify status

```sql
-- Admin window
col STATUS format a20
SELECT STATUS FROM V$SQL_MONITOR WHERE DBOP_NAME='ORA.SOE.TOPCUSTOMERS';
-- Kết quả: STATUS = EXECUTING (vì client session chưa cập nhật)

-- Client window: chạy query bất kỳ để trigger round-trip
SELECT SYSDATE FROM DUAL;

-- Admin window: verify lại
SELECT STATUS FROM V$SQL_MONITOR WHERE DBOP_NAME='ORA.SOE.TOPCUSTOMERS';
-- Kết quả: STATUS = DONE
```

> **Giải thích:** `END_OPERATION` đánh dấu operation đã kết thúc trong admin, nhưng status trong `V$SQL_MONITOR` chỉ cập nhật khi client session thực hiện một round-trip đến database.

---

## Phần 3: Monitor qua EM Express

1. Login EM Express: `https://<srv1_IP>:5500/em` với tài khoản `sys`
2. **Performance → Performance Hub → Monitored SQL** tab
3. Thấy 2 entries: một cho database operation, một cho monitored query
4. Click vào **Query ID link** → xem detailed performance metrics
5. Click vào **Operation ID link** → xem tổng thể performance của toàn bộ operation
6. Click **Save** để lưu report (HTML) để xem lại sau

---

## Tóm tắt

| Khái niệm | Mô tả |
|-----------|-------|
| Auto monitoring trigger | SQL > 5 giây CPU/I/O, hoặc parallel execution |
| View thống kê realtime | `V$SQL_MONITOR` |
| View execution plan progress | `V$SQL_PLAN_MONITOR` |
| Bắt đầu composite operation | `DBMS_SQL_MONITOR.BEGIN_OPERATION(...)` |
| Kết thúc composite operation | `DBMS_SQL_MONITOR.END_OPERATION(...)` |
| Xem trong EM Express | Performance Hub → Monitored SQL tab |

**Hạn chế cần biết:**
- Chỉ SQL > 5 giây mới tự động được monitor → short queries bị bỏ qua ngay cả khi chúng thuộc composite operation
- Cần license `DIAGNOSTIC+TUNING` để dùng tính năng này
- Dùng `FORCED_TRACKING => 'Y'` để buộc monitor composite operation bất kể thời gian chạy


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/section_all/section_16_realtime_monitoring_guide.md`
