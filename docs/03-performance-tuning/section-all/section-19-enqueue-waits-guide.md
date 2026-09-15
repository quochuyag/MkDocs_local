---
title: Section 19 — Handling Enqueue Waits
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/section_all/section_19_enqueue_waits_guide.md
---

# Section 19 — Handling Enqueue Waits

## Tổng quan

**Enqueue** là cơ chế locking của Oracle để serialize truy cập vào các tài nguyên được chia sẻ (rows, tables, transactions...). Khi một session phải chờ một enqueue đang bị giữ bởi session khác, một **enqueue wait event** xảy ra.

**Practice 18 — Handling Enqueue Waits**

Mục tiêu:
- Mô phỏng enqueue wait (`enq: TX - row lock contention`)
- Chẩn đoán enqueue đang xảy ra (current)
- Chẩn đoán enqueue gần đây (từ ASH/V$ views)
- Chẩn đoán enqueue trong quá khứ (từ AWR)

---

## Kiến thức lý thuyết

### Các loại Enqueue phổ biến

| Enqueue | Tên đầy đủ | Nguyên nhân thường gặp |
|---------|-----------|----------------------|
| `enq: TX - row lock contention` | Transaction enqueue | Session A giữ lock, session B chờ cùng row |
| `enq: TM - contention` | Table Mode lock | Direct Path INSERT (`APPEND` hint) trên cùng bảng |
| `enq: HW - contention` | High Water Mark | Nhiều sessions extend segment đồng thời |
| `enq: ST - contention` | Space Transaction | Tranh chấp space management |

### Thông tin P1/P2/P3 trong enqueue events

Trong `V$SESSION`:
- `P1`: Lock type (2 bytes) + Lock mode (2 bytes) — encode dưới dạng hex
- `P2`: Object ID (với TX lock = transaction ID)
- `P3`: Row number hoặc info khác

---

## Phần 1: Mô phỏng Enqueue Wait

### Session A (Client 1): Cập nhật row nhưng KHÔNG commit

```sql
SELECT TO_CHAR(SYSDATE, 'MM/DD/YY HH24:MI:SS') ctime FROM DUAL;

VAR V_CUSTOMER_ID NUMBER
EXEC :V_CUSTOMER_ID := 100

UPDATE CUSTOMERS
SET CUST_EMAIL = CUST_EMAIL || ''
WHERE CUSTOMER_ID = :V_CUSTOMER_ID;
-- KHÔNG chạy COMMIT — giữ lock
```

### Session B (Client 2): Update cùng row → bị block

```sql
UPDATE CUSTOMERS SET CUST_EMAIL = CUST_EMAIL || '' WHERE CUSTOMER_ID = 100;
-- Lệnh này HANG — đang chờ session A release lock
```

---

## Phần 2: Chẩn đoán Enqueue Đang Xảy Ra

### Query 1: Xác định Holder và Waiter

```sql
col SESSIONS format A20

SELECT DECODE(REQUEST, 0, 'Holder SID: ', 'Waiter SID: ') || SID SESSIONS,
       ID1, ID2, LMODE, REQUEST, TYPE
FROM V$LOCK
WHERE (ID1, ID2, TYPE) IN (
  SELECT ID1, ID2, TYPE FROM V$LOCK WHERE REQUEST > 0
)
ORDER BY ID1, REQUEST;
```

**Giải thích:**
- `REQUEST = 0` → session đang **giữ** lock (Holder)
- `REQUEST > 0` → session đang **chờ** lock (Waiter)
- `LMODE`: lock mode đang giữ (0=none, 1=null, 2=RS, 3=RX, 4=S, 5=SRX, 6=X)
- `TYPE = TX` → Transaction lock; `TYPE = TM` → Table lock

### Query 2: Thông tin chi tiết về Waiter

```sql
set pagesize 20
col INFO for a200

SELECT
  'SID: '               || S.SID              || CHR(10) ||
  'USERNAME: '          || S.USERNAME          || CHR(10) ||
  'EVENT: '             || S.EVENT             || CHR(10) ||
  'DESCRIPTION: '       || T.DESCRIPTION       || CHR(10) ||
  'CURRENT STATEMENT: ' || Q.SQL_TEXT          || CHR(10) ||
  'WAITING TIME (s): '  || S.SECONDS_IN_WAIT   || CHR(10) ||
  'P1TEXT: '            || S.P1TEXT            || CHR(10) ||
  'P1: '                || S.P1                || CHR(10) ||
  'P2TEXT: '            || S.P2TEXT            || CHR(10) ||
  'P2: '                || S.P2                || CHR(10) ||
  'P3TEXT: '            || S.P3TEXT            || CHR(10) ||
  'P3: '                || S.P3 AS INFO
FROM V$SESSION S, V$LOCK L, V$LOCK_TYPE T, V$SQL Q
WHERE S.SID   = L.SID
  AND T.TYPE  = L.TYPE
  AND S.SQL_ID = Q.SQL_ID
  AND L.REQUEST > 0;
```

### Query 3: Xây dựng query để xem row bị lock

```sql
-- Lấy SID của waiter từ query trên → thay vào &V_WSID
SELECT
  'SELECT * FROM "' || O.OWNER || '"."' || O.OBJECT_NAME || '"' || CHR(10) ||
  'WHERE ROWID = DBMS_ROWID.ROWID_CREATE(1, ' ||
  S.ROW_WAIT_OBJ#  || ', ' ||
  S.ROW_WAIT_FILE# || ', ' ||
  ROW_WAIT_BLOCK#  || ', ' ||
  ROW_WAIT_ROW#    || ');'
FROM DBA_OBJECTS O, V$SESSION S
WHERE S.ROW_WAIT_OBJ# = O.OBJECT_ID
  AND S.SID = &V_WSID;
```

> Copy kết quả query trên và chạy để xem nội dung row đang bị lock.

---

## Phần 3: Chẩn đoán Enqueue Gần Đây (Sau Khi Release)

Khi lock đã được release nhưng thông tin còn trong bộ nhớ (V$ views chưa bị flush):

### Release lock và verify

```sql
-- Session A (holder): release lock
ROLLBACK;

-- Verify không còn lock
SELECT DECODE(REQUEST, 0, 'Holder SID: ', 'Waiter SID: ') || SID SESSIONS,
       ID1, ID2, LMODE, REQUEST, TYPE
FROM V$LOCK
WHERE (ID1, ID2, TYPE) IN (
  SELECT ID1, ID2, TYPE FROM V$LOCK WHERE REQUEST > 0
)
ORDER BY ID1, REQUEST;
-- Kết quả: no rows → lock đã release
```

### Sinh ASH Report cho khoảng thời gian xảy ra lock

```sql
define dbid         = '';
define inst_num     = '';
define report_type  = 'html';
define begin_time   = '-10';    -- 10 phút trước
define duration     = 10;       -- kéo dài 10 phút
define report_name  = '/media/sf_extdisk/ash_enqtx.html';
define slot_width   = '';
define target_session_id   = '';
define target_sql_id       = '';
define target_wait_class   = '';
define target_service_hash = '';
define target_module_name  = '';
define target_action_name  = '';
define target_client_id    = '';
define target_plsql_entry  = '';
define target_container    = '';

@ $ORACLE_HOME/rdbms/admin/ashrpti.sql
```

**Đọc ASH report:**
- **Top Events**: `enq: TX - row lock contention` xuất hiện → confirm locking issue
- **Top SQL with Top Events**: Xác định SQL nào gây ra locking
- **Top Event P1/P2/P3**: P2 = object_id → xác định table/row bị lock

---

## Phần 4: Proactive Monitoring — Phát Hiện Enqueue Thường Xuyên

Không phải lúc nào user cũng báo cáo. DBA cần proactively check.

### Query 1: Tổng enqueue waits từ khi instance startup

```sql
col EVENT       format a40
col WAIT_CLASS  format a11

SELECT EVENT,
       AVERAGE_WAIT,
       TO_CHAR(ROUND(TIME_WAITED/100),'999,999,999') TIME_SECONDS,
       WAIT_CLASS
FROM V$SYSTEM_EVENT
WHERE EVENT LIKE 'enq%'
ORDER BY TIME_WAITED;
```

### Query 2: Objects bị lock nhiều nhất

```sql
col OBJECT_NAME for a10
col STATS       for a20

SELECT OBJECT_NAME, SUBSTR(STATISTIC_NAME, 1, 30) STATS, VALUE
FROM V$SEGMENT_STATISTICS
WHERE STATISTIC_NAME IN ('ITL waits', 'row lock waits')
  AND VALUE > 0
  AND OBJECT_NAME NOT LIKE 'BIN$%'
ORDER BY VALUE DESC;
```

> `ITL waits` = Interested Transaction List waits → nhiều sessions cùng insert vào block (INITRANS quá nhỏ)
> `row lock waits` = row-level lock waits

### Query 3: SQL chờ Application waits nhiều nhất

```sql
col SQL_TEXT for a30

SELECT ROUND(APPLICATION_WAIT_TIME / 1000000) WAIT_TIME_S,
       SQL_ID,
       SUBSTR(SQL_TEXT, 1, 30) SQL_TEXT
FROM V$SQLSTATS
WHERE APPLICATION_WAIT_TIME > 0
ORDER BY APPLICATION_WAIT_TIME DESC
FETCH FIRST 10 ROW ONLY;
```

> `APPLICATION_WAIT_TIME` thường tương ứng với TX enqueue waits.

---

## Phần 5: Chẩn đoán Enqueue Trong Quá Khứ (Từ AWR)

Khi V$ views đã không còn thông tin (instance restart hoặc quá lâu):

```sql
-- Tạo AWR snapshot bao phủ khoảng thời gian xảy ra incident
exec DBMS_WORKLOAD_REPOSITORY.CREATE_SNAPSHOT;

-- Sinh AWR report cho khoảng thời gian đó
@ ?/rdbms/admin/awrrpt.sql
-- Chọn begin_snap và end_snap bao quanh thời điểm incident
-- Đặt tên report: awr_enq_tx.html

-- Di chuyển report ra thư mục staging
host mv awr_enq_tx.html /media/sf_extdisk/
```

**Đọc AWR report:**
- **Top 10 Foreground Events**: `enq: TX - row lock contention` ở đầu danh sách → confirm
- **Enqueue Activity**: chi tiết enqueue requests và waits
- **SQL Statistics**: SQL có `APPLICATION_WAIT_TIME` cao nhất

---

## Tóm tắt — 3 Tình huống Chẩn đoán

| Tình huống | Công cụ | Views/Scripts |
|-----------|---------|---------------|
| **Đang xảy ra** | V$ views | `V$LOCK`, `V$SESSION`, `V$LOCK_TYPE`, `V$SQL` |
| **Vừa xảy ra** (< 1 giờ) | ASH | `ashrpti.sql`, `V$ACTIVE_SESSION_HISTORY` |
| **Proactive monitoring** | V$ stats | `V$SYSTEM_EVENT`, `V$SEGMENT_STATISTICS`, `V$SQLSTATS` |
| **Trong quá khứ** | AWR | `awrrpt.sql`, `DBA_HIST_ACTIVE_SESS_HISTORY` |

**Nguyên tắc xử lý TX Row Lock Contention:**
1. Xác định holder và SQL đang giữ lock
2. Xác định waiter và SQL đang bị block
3. Tìm nguyên nhân: transaction chưa commit quá lâu, thiếu index → full scan → lock nhiều rows hơn cần thiết
4. Giải pháp: commit sớm, thêm index để giảm scope lock, giảm transaction size


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/section_all/section_19_enqueue_waits_guide.md`
