---
title: Section 14 — Database Service Performance Statistics & Module/Action/Client ID
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/section_all/section_14_database_service_statistics_guide.md
---

# Section 14 — Database Service Performance Statistics & Module/Action/Client ID

## Tổng quan

Oracle cho phép thu thập thống kê hiệu năng theo các chiều khác nhau:
- **Service level**: theo tên service kết nối (VD: ORADB, BATCH_SVC)
- **Module/Action level**: theo tên module/action do ứng dụng đặt
- **Client Identifier level**: theo định danh client do ứng dụng đặt

**Practice 13 — Using Database Service Performance Statistics**
**Practice 14 — Using Module, Action, and Client Identifier Attributes**

---

## Practice 13: Database Service Statistics

### Service là gì?

**Database Service** là một alias để client kết nối đến database. Một database có thể có nhiều service, mỗi service phục vụ một ứng dụng khác nhau. Khi có nhiều service, DBA có thể theo dõi hiệu năng theo từng service.

### Các views chính

| View | Mô tả |
|------|-------|
| `DBA_SERVICES` | Danh sách services đã đăng ký trong database |
| `V$SERVICES` | Services đang active |
| `V$SERVICE_STATS` | Thống kê tổng từ khi instance startup |
| `DBA_HIST_SERVICE_STAT` | Lịch sử của V$SERVICE_STATS (lưu trong AWR) |
| `V$SERVICE_EVENT` | Wait events theo service |
| `V$SERVICEMETRIC` | Metrics theo service (5 giây và 1 phút gần nhất) |
| `V$SERVICEMETRIC_HISTORY` | Lịch sử metric trong 1 giờ qua |

---

### 1. Xem danh sách Services

```sql
set linesize 180
col NAME format a20

SELECT SERVICE_ID, NAME, NAME_HASH FROM DBA_SERVICES;

-- Kiểm tra service đã đăng ký với listener chưa
host lsnrctl services
```

> `NAME_HASH` là giá trị dùng trong các views khác để identify service.

### 2. Sessions hiện tại theo Service

```sql
col SERVICE_NAME format a30
SELECT SERVICE_NAME, COUNT(SID) CNT
FROM V$SESSION
WHERE CLIENT_INFO LIKE 'Swingbench%'
GROUP BY SERVICE_NAME;
```

### 3. Số kết nối trong 30 phút qua (từ ASH)

```sql
SELECT S.NAME, V.CNT
FROM V$SERVICES S,
  (SELECT SERVICE_HASH, COUNT(DISTINCT SESSION_ID) CNT
   FROM V$ACTIVE_SESSION_HISTORY
   WHERE SAMPLE_TIME >= CURRENT_TIMESTAMP - INTERVAL '30' MINUTE
   GROUP BY SERVICE_HASH) V
WHERE S.NAME_HASH = V.SERVICE_HASH;
```

> Muốn lấy thống kê tuần trước → thay `V$ACTIVE_SESSION_HISTORY` bằng `DBA_HIST_ACTIVE_SESS_HISTORY`.

---

### 4. Service-level Performance Statistics

#### Xem statistics từ khi instance startup

```sql
col STAT_NAME format a35
SELECT STAT_NAME, VALUE
FROM V$SERVICE_STATS
WHERE SERVICE_NAME_HASH = (SELECT NAME_HASH FROM DBA_SERVICES WHERE NAME = 'ORADB.localdomain')
ORDER BY 1;
```

> `DB time` và `CPU time` trong view này tính bằng **microseconds**.

#### Tính Wait Time từ V$SERVICE_STATS

```sql
-- Wait Time = DB Time - DB CPU Time (đổi ra phút)
SELECT
  (SELECT ROUND(VALUE/1000000/60,3)
   FROM V$SERVICE_STATS
   WHERE SERVICE_NAME_HASH = (SELECT NAME_HASH FROM DBA_SERVICES WHERE NAME = 'ORADB.localdomain')
     AND STAT_NAME = 'DB time')
  -
  (SELECT ROUND(VALUE/1000000/60,3)
   FROM V$SERVICE_STATS
   WHERE SERVICE_NAME_HASH = (SELECT NAME_HASH FROM DBA_SERVICES WHERE NAME = 'ORADB.localdomain')
     AND STAT_NAME = 'DB CPU')
  AS SERVICE_WAIT_TIME
FROM DUAL;
```

#### Xem statistics theo AWR snapshot (lịch sử)

```sql
SELECT S.SNAP_ID, V.NAME, S.STAT_NAME, S.VALUE
FROM DBA_HIST_SERVICE_STAT S, DBA_HIST_SNAPSHOT N, DBA_SERVICES V
WHERE S.SNAP_ID = N.SNAP_ID
  AND S.SERVICE_NAME_HASH = V.NAME_HASH
  AND V.NAME = 'ORADB.localdomain'
  AND N.BEGIN_INTERVAL_TIME BETWEEN SYSDATE-1.03 AND SYSDATE-1.01
ORDER BY 1,2,3;
```

> `DBA_HIST_SERVICE_STAT` không có cột thời gian nên phải join với `DBA_HIST_SNAPSHOT`.

---

### 5. Service-level Wait Events

```sql
col EVENT format a50
SELECT EVENT, TIME_WAITED, AVERAGE_WAIT, MAX_WAIT
FROM V$SERVICE_EVENT E, V$EVENT_NAME N
WHERE E.EVENT_ID = N.EVENT_ID
  AND N.WAIT_CLASS <> 'Idle'
  AND TIME_WAITED <> 0
  AND SERVICE_NAME_HASH = (SELECT NAME_HASH FROM DBA_SERVICES WHERE NAME = 'ORADB.localdomain')
ORDER BY TIME_WAITED DESC FETCH FIRST 10 ROWS ONLY;

-- Tổng wait time của service (centi-seconds → phút)
SELECT ROUND(SUM(TIME_WAITED/100/60),3) "Total Service Wait Time in Minutes"
FROM V$SERVICE_EVENT E, V$EVENT_NAME N
WHERE E.EVENT_ID = N.EVENT_ID
  AND N.WAIT_CLASS <> 'Idle'
  AND TIME_WAITED <> 0
  AND SERVICE_NAME_HASH = (SELECT NAME_HASH FROM DBA_SERVICES WHERE NAME = 'ORADB.localdomain');
```

> **Lưu ý:** `V$SERVICE_EVENT` không được flush vào AWR. `DBA_HIST_SERVICE_WAIT_CLASS` lưu lịch sử theo wait class (không chi tiết theo từng event).

---

### 6. Service-level Metrics

```sql
ALTER SESSION SET NLS_DATE_FORMAT = 'DD-MON-YY HH24:MI:SS';

-- Metrics 5 giây và 1 phút gần nhất
SELECT BEGIN_TIME, END_TIME, ROUND(INTSIZE_CSEC/100) INTERVAL_S,
       ROUND(DBTIMEPERSEC) DBTIMEPERSEC, ROUND(DBTIMEPERCALL) DBTIMEPERCALL,
       ROUND(CALLSPERSEC) CALLSPERSEC, ROUND(ELAPSEDPERCALL) ELAPSEDPERCALL,
       ROUND(CPUPERCALL) CPUPERCALL
FROM V$SERVICEMETRIC
WHERE SERVICE_NAME_HASH = (SELECT NAME_HASH FROM DBA_SERVICES WHERE NAME = 'ORADB.localdomain')
ORDER BY BEGIN_TIME ASC;

-- Metrics trong 1 giờ qua (lịch sử)
SELECT BEGIN_TIME, END_TIME, ROUND(INTSIZE_CSEC/100) INTERVAL_S,
       ROUND(DBTIMEPERSEC) DBTIMEPERSEC, ROUND(DBTIMEPERCALL) DBTIMEPERCALL,
       ROUND(CALLSPERSEC) CALLSPERSEC, ROUND(ELAPSEDPERCALL) ELAPSEDPERCALL,
       ROUND(CPUPERCALL) CPUPERCALL
FROM V$SERVICEMETRIC_HISTORY
WHERE SERVICE_NAME_HASH = (SELECT NAME_HASH FROM DBA_SERVICES WHERE NAME = 'ORADB.localdomain')
ORDER BY BEGIN_TIME ASC;
```

**Giải thích các cột metrics:**

| Cột | Ý nghĩa |
|-----|---------|
| `DBTIMEPERSEC` | DB Time microseconds/giây |
| `DBTIMEPERCALL` | DB Time microseconds/call |
| `CALLSPERSEC` | Số calls/giây |
| `ELAPSEDPERCALL` | Elapsed time microseconds/call |
| `CPUPERCALL` | CPU time microseconds/call |

---

## Practice 14: Module, Action, và Client Identifier

### Khái niệm

Ứng dụng dùng `DBMS_APPLICATION_INFO` để đặt context:

| Attribute | Package | Tối đa |
|-----------|---------|--------|
| **Module** | `DBMS_APPLICATION_INFO.SET_MODULE` | 48 bytes |
| **Action** | `DBMS_APPLICATION_INFO.SET_ACTION` | 32 bytes |
| **Client Info** | `DBMS_APPLICATION_INFO.SET_CLIENT_INFO` | 64 bytes |
| **Client ID** | `DBMS_SESSION.SET_IDENTIFIER` | 64 bytes |

---

### Module/Action Statistics từ Dictionary Views

#### Sessions hiện tại với module/action

```sql
col MODULE format a25
col ACTION format a15
col CLIENT_INFO format a25
set linesize 180

SELECT MODULE, ACTION, CLIENT_INFO, COUNT(*) CNT
FROM V$SESSION
WHERE SERVICE_NAME = 'ORADB.localdomain'
GROUP BY MODULE, ACTION, CLIENT_INFO;
```

#### Module/Action trong 30 phút qua (từ ASH)

```sql
col ACTION format a30
col CLIENT_ID format a20

SELECT DISTINCT MODULE, ACTION, CLIENT_ID
FROM V$ACTIVE_SESSION_HISTORY
WHERE SAMPLE_TIME >= CURRENT_TIMESTAMP - INTERVAL '30' MINUTE
  AND SERVICE_HASH = (SELECT NAME_HASH FROM DBA_SERVICES WHERE NAME = 'ORADB.localdomain')
ORDER BY 1,2;
```

> `CLIENT_INFO` không có trong ASH view. Dùng `CLIENT_ID` thay thế.

#### Top Module theo DB Time

```sql
WITH TOTAL_DBTIME AS
  (SELECT COUNT(1) FROM V$ACTIVE_SESSION_HISTORY WHERE SESSION_TYPE = 'FOREGROUND')
SELECT MODULE,
       COUNT(1) "MODULE_DBTIME",
       (SELECT * FROM TOTAL_DBTIME) "TOTAL_DBTIME",
       ROUND((COUNT(1)/(SELECT * FROM TOTAL_DBTIME))*100,2) PCT_DBTIME
FROM V$ACTIVE_SESSION_HISTORY
WHERE SAMPLE_TIME >= CURRENT_TIMESTAMP - INTERVAL '30' MINUTE
  AND SESSION_TYPE = 'FOREGROUND'
  AND SERVICE_HASH = (SELECT NAME_HASH FROM DBA_SERVICES WHERE NAME = 'ORADB.localdomain')
GROUP BY MODULE
ORDER BY PCT_DBTIME DESC;
```

#### Top Module/Action theo DB Time

```sql
WITH TOTAL_DBTIME AS
  (SELECT COUNT(1) FROM V$ACTIVE_SESSION_HISTORY WHERE SESSION_TYPE = 'FOREGROUND')
SELECT MODULE, ACTION,
       COUNT(1) "ACTION_DBTIME",
       (SELECT * FROM TOTAL_DBTIME) "TOTAL_DBTIME",
       ROUND((COUNT(1)/(SELECT * FROM TOTAL_DBTIME))*100,2) PCT_DBTIME
FROM V$ACTIVE_SESSION_HISTORY
WHERE SAMPLE_TIME >= CURRENT_TIMESTAMP - INTERVAL '30' MINUTE
  AND SESSION_TYPE = 'FOREGROUND'
  AND SERVICE_HASH = (SELECT NAME_HASH FROM DBA_SERVICES WHERE NAME = 'ORADB.localdomain')
GROUP BY MODULE, ACTION
ORDER BY PCT_DBTIME DESC FETCH FIRST 10 ROWS ONLY;
```

---

### Enable Module/Action Statistics Aggregation

#### Bật aggregation cho module cụ thể

```sql
begin
  DBMS_MONITOR.SERV_MOD_ACT_STAT_ENABLE(
    SERVICE_NAME => 'ORADB.localdomain',
    MODULE_NAME  => 'Top Customers Report',
    ACTION_NAME  => NULL   -- NULL = áp dụng cho tất cả actions trong module
  );
end;
/
```

#### Kiểm tra aggregation đã bật

```sql
col AGGREGATION_TYPE format a21;
col PRIMARY_ID format a20;
col QUALIFIER_ID1 format a20;
col QUALIFIER_ID2 format a20;
SELECT AGGREGATION_TYPE, PRIMARY_ID, QUALIFIER_ID1, QUALIFIER_ID2
FROM DBA_ENABLED_AGGREGATIONS;
```

> `AGGREGATION_TYPE = 'SERVICE_MODULE_ACTION'` khi ACTION_NAME = NULL.

#### Xem statistics của module đang được aggregate

```sql
SELECT AGGREGATION_TYPE, MODULE, ACTION, STAT_NAME, VALUE
FROM V$SERV_MOD_ACT_STATS
WHERE SERVICE_NAME = 'ORADB.localdomain'
ORDER BY VALUE;
```

#### Tắt aggregation

```sql
begin
  DBMS_MONITOR.SERV_MOD_ACT_STAT_DISABLE(
    SERVICE_NAME => 'ORADB.localdomain',
    MODULE_NAME  => 'Top Customers Report',
    ACTION_NAME  => NULL
  );
end;
/
```

---

### Enable Client Identifier Aggregation

**Usecase:** Nhiều session chạy cùng một loại tác vụ, muốn theo dõi tổng thể tác vụ đó.

#### Đặt Client Identifier trong session (phía ứng dụng)

```sql
begin
  DBMS_SESSION.SET_IDENTIFIER('ETL Load Orders');
end;
/
```

#### Bật aggregation cho client identifier

```sql
exec DBMS_MONITOR.CLIENT_ID_STAT_ENABLE('ETL Load Orders');
```

#### Xem statistics của client identifier

```sql
col CLIENT_IDENTIFIER format a20
col STAT_NAME format a45
col VALUE format 9999999999999
SELECT CLIENT_IDENTIFIER, STAT_NAME, VALUE FROM V$CLIENT_STATS ORDER BY VALUE;
```

#### Tắt và bật lại để reset statistics

```sql
exec DBMS_MONITOR.CLIENT_ID_STAT_DISABLE('ETL Load Orders');
exec DBMS_MONITOR.CLIENT_ID_STAT_ENABLE('ETL Load Orders');
```

---

### Case Study: Phát hiện vấn đề qua Client ID Aggregation

**Kịch bản:** 20 sessions song song chạy script `INSERT /*+ APPEND */` vào cùng một bảng.

**Triệu chứng từ V$CLIENT_STATS:**
- Wait time chiếm % lớn trong DB Time → có vấn đề
- Wait class = Application → application-level lock

**Điều tra tiếp bằng ASH report:**
```sql
define target_client_id = 'ETL Load Orders';
define begin_time = '-30'
define duration = 30;
@ $ORACLE_HOME/rdbms/admin/ashrpti.sql
```

**Phát hiện trong ASH report:**
- Top event: `enq: TM - contention` → Table Mode lock
- Section "Top Event P1/P2/P3": P2 = object_id → xác định table
- Section "Top SQL with Top Events": INSERT có `APPEND` hint

**Root cause:** `INSERT /*+ APPEND */` dùng Direct Path Load → yêu cầu TM exclusive lock → các session song song bị serialize.

**Giải pháp:** Bỏ `APPEND` hint → INSERT thông thường → không cần exclusive lock → 20 sessions chạy song song được.

**Verify sau fix:**
- `sql execute elapsed time` chiếm % cao trong DB Time → tốt
- `application wait time` gần bằng 0 → không còn TM contention

---

## Tóm tắt

| Chiều phân tích | View xem realtime | View xem lịch sử |
|----------------|------------------|-----------------|
| Service | `V$SERVICE_STATS`, `V$SERVICE_EVENT`, `V$SERVICEMETRIC` | `DBA_HIST_SERVICE_STAT` |
| Module/Action | `V$SERV_MOD_ACT_STATS` | ASH views |
| Client ID | `V$CLIENT_STATS` | ASH views |
| Tất cả chiều | `V$ACTIVE_SESSION_HISTORY` | `DBA_HIST_ACTIVE_SESS_HISTORY` |

| Package | Chức năng |
|---------|----------|
| `DBMS_APPLICATION_INFO` | Đặt module/action/client_info từ ứng dụng |
| `DBMS_SESSION` | Đặt client identifier |
| `DBMS_MONITOR` | Bật/tắt aggregation cho service/module/client_id |


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/section_all/section_14_database_service_statistics_guide.md`
