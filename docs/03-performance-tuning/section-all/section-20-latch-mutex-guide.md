---
title: Section 20 — Latch & Mutex Contention
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/section_all/section_20_latch_mutex_guide.md
---

# Section 20 — Latch & Mutex Contention

## Tổng quan

**Latch** và **Mutex** là cơ chế low-level serialization của Oracle để bảo vệ các cấu trúc dữ liệu trong memory (SGA). Khác với enqueue (user-level locking), latch/mutex là internal Oracle mechanism — không liên quan trực tiếp đến user data.

**Practice 19 — Handling Latch and Mutex Contention**

Mục tiêu:
- Xem thông tin latch tổng thể từ hệ thống
- Mô phỏng và xử lý Library Cache Latch Contention (hard parsing)
- Mô phỏng và xử lý Cache Buffer Chain (CBC) Latch Contention (hot block)
- Quan sát Cursor Mutex và Pin Waits

---

## Kiến thức lý thuyết

### Latch vs Mutex vs Enqueue

| Đặc điểm | Latch | Mutex | Enqueue |
|----------|-------|-------|---------|
| Level | Internal (Oracle engine) | Internal (Oracle engine) | User-visible |
| Scope | SGA structures | Cursor metadata | User objects |
| Thời gian giữ | Rất ngắn (micro-seconds) | Rất ngắn | Có thể lâu |
| Wait mode | Spin, rồi sleep | Spin, rồi sleep | Sleep |
| Chế độ | Exclusive hoặc Shared | Exclusive hoặc Shared | Nhiều mode |

### Các Latch/Mutex thường gặp

| Latch/Mutex | Nguyên nhân |
|-------------|------------|
| `library cache: mutex X` | Hard parsing nhiều — SQL dùng literals |
| `cache buffers chains` (CBC) | Hot block — nhiều sessions đọc cùng buffer |
| `cursor: mutex X` | Nhiều sessions execute cùng cursor |
| `cursor: pin S` | Nhiều sessions pin cùng cursor để đọc |
| `row cache lock` | Tranh chấp dictionary cache |

---

## Phần 1: Xem Thông Tin Latch Tổng Thể

### Query 1: Tỷ lệ latch wait trong tổng wait time

```sql
col WAIT_TYPE format a25

WITH SYS_EVENT AS (
  SELECT
    CASE
      WHEN (EVENT LIKE '%latch%' OR EVENT LIKE '%mutex%' OR EVENT LIKE 'cursor:%')
      THEN EVENT
      ELSE WAIT_CLASS
    END WAIT_TYPE, E.*
  FROM V$SYSTEM_EVENT E
)
SELECT WAIT_TYPE,
       SUM(TOTAL_WAITS) TOTAL_WAITS,
       ROUND(SUM(TIME_WAITED_MICRO)/1000000) TIME_WAITED_SECONDS,
       ROUND(SUM(TIME_WAITED_MICRO)*100 / SUM(SUM(TIME_WAITED_MICRO)) OVER(), 2) PCT
FROM (
  SELECT E.WAIT_TYPE, E.EVENT, E.TOTAL_WAITS, E.TIME_WAITED_MICRO
  FROM SYS_EVENT E
  UNION
  SELECT 'CPU', M.STAT_NAME, NULL, M.VALUE
  FROM V$SYS_TIME_MODEL M
  WHERE M.STAT_NAME IN ('background cpu time', 'DB CPU')
) L
WHERE WAIT_TYPE <> 'Idle'
GROUP BY WAIT_TYPE
HAVING ROUND(SUM(TIME_WAITED_MICRO)/1000000) > 0
ORDER BY 4 DESC;
```

> **Kết luận:** Nếu `latch/mutex` events chiếm % nhỏ trong tổng wait → không có vấn đề latch contention tổng thể.

### Query 2: Latch statistics từ khi startup (V$LATCH)

```sql
set pagesize 20
set linesize 180
col NAME format A20

SELECT C.NAME,
       SUM(A.GETS) GETS,
       SUM(A.MISSES) MISSES,
       SUM(A.SLEEPS) SLEEPS,
       SUM(A.IMMEDIATE_GETS) IMM_GETS,
       SUM(A.IMMEDIATE_MISSES) IMM_MISSES,
       SUM(WAIT_TIME) WAIT_TIME
FROM V$LATCH A, V$LATCHNAME C
WHERE A.LATCH# = C.LATCH#
  AND (A.GETS > 0 OR A.MISSES > 0 OR A.SLEEPS > 0 OR A.IMMEDIATE_GETS > 0 OR A.IMMEDIATE_MISSES > 0)
GROUP BY C.NAME
ORDER BY WAIT_TIME ASC;
```

**Giải thích cột:**
- `GETS/MISSES`: Willing-to-wait requests (session sẵn sàng chờ)
- `IMMEDIATE_GETS/IMMEDIATE_MISSES`: Nowait requests (không chờ, thử ngay)
- `SLEEPS`: Số lần phải sleep vì không lấy được latch
- `WAIT_TIME`: Tổng thời gian chờ (microseconds)

> **Lưu ý:** `V$LATCH` chỉ hiển thị current latches, không có lịch sử.

### Query 3: Latch wait theo session (SOE)

```sql
col EVENT    format a40
col TIME_CSEC format 999,999

SELECT E.EVENT, SUM(E.TIME_WAITED) TIME_CSEC
FROM V$SESSION_EVENT E, V$SESSION S
WHERE E.SID = S.SID
  AND S.USERNAME = 'SOE'
  AND (E.EVENT LIKE '%latch%' OR E.EVENT LIKE '%mutex%')
  AND E.TIME_WAITED <> 0
GROUP BY E.EVENT
ORDER BY SUM(TIME_WAITED) DESC;
```

### Query 4: Top sessions chờ latch nhiều nhất

```sql
col USERNAME format a10

SELECT E.SID, S.USERNAME, E.EVENT, E.TIME_WAITED TIME_CSEC
FROM V$SESSION_EVENT E, V$SESSION S
WHERE E.SID = S.SID
  AND S.USERNAME = 'SOE'
  AND (E.EVENT LIKE '%latch%' OR E.EVENT LIKE '%mutex%')
  AND E.TIME_WAITED <> 0
ORDER BY TIME_WAITED ASC;
```

### Query 5: SQL đang chạy trong các session đang chờ latch

```sql
col Info format a100

SELECT
  'SID : '           || S.SID                          || CHR(10) ||
  'Event : '         || E.EVENT                        || CHR(10) ||
  'Wait Time (CS) : '|| E.TIME_WAITED                  || CHR(10) ||
  'SQL : '           || SUBSTR(TO_CHAR(SQL_TEXT),1,100) Info
FROM V$SESSION S, V$SQLAREA Q, V$SESSION_EVENT E
WHERE S.SQL_ID  = Q.SQL_ID(+)
  AND E.SID     = S.SID
  AND S.USERNAME = 'SOE'
  AND (E.EVENT LIKE '%latch%' OR E.EVENT LIKE '%mutex%')
  AND E.TIME_WAITED > 0
ORDER BY E.TIME_WAITED ASC;
```

---

## Phần 2: Library Cache Latch Contention (Hard Parsing)

### Nguyên nhân

SQL dùng **literals** thay vì bind variables → mỗi lần chạy là một câu SQL mới → hard parse → tranh chấp `library cache: mutex X`.

### Mô phỏng — Chạy SQL với literals (client sessions)

```sql
DECLARE
  I NUMBER := 1;
  N NUMBER;
BEGIN
  -- Ấn CTL+C để dừng
  WHILE (TRUE) LOOP
    I := I + 1;
    EXECUTE IMMEDIATE
      'SELECT COUNT(*) FROM SOE.ORDERS WHERE ORDER_ID = ' || TO_CHAR(I)
    INTO N;
  END LOOP;
END;
/
```

### Phát hiện vấn đề

**Kiểm tra số lượng parent cursors:**

```sql
SELECT COUNT(*)
FROM V$SQLAREA
WHERE SQL_TEXT LIKE 'SELECT COUNT(*) FROM SOE.ORDERS WHERE ORDER_ID%';
-- Con số tăng nhanh → nhiều hard parses
```

**Kiểm tra latch contention:**

```sql
SELECT E.EVENT, SUM(E.TIME_WAITED) TIME_CSEC
FROM V$SESSION_EVENT E, V$SESSION S
WHERE E.SID = S.SID AND S.USERNAME = 'SOE'
  AND (E.EVENT LIKE '%latch%' OR E.EVENT LIKE '%mutex%')
  AND E.TIME_WAITED <> 0
GROUP BY E.EVENT
ORDER BY SUM(TIME_WAITED) DESC;
-- 'library cache: mutex X' tăng nhanh = có latch contention
```

**Xác nhận bằng FORCE_MATCHING_SIGNATURE:**

```sql
col SQL_TEXT                  format a40
col FORCE_MATCHING_SIGNATURE  format a25

SELECT TO_CHAR(FORCE_MATCHING_SIGNATURE) FORCE_MATCHING_SIGNATURE,
       SUBSTR(SQL_TEXT, 1, 40) SQL_TEXT,
       COUNT(*) MATCHES
FROM V$SQL
WHERE FORCE_MATCHING_SIGNATURE <> 0
  AND PARSING_SCHEMA_NAME <> 'SYS'
GROUP BY TO_CHAR(FORCE_MATCHING_SIGNATURE), SUBSTR(SQL_TEXT, 1, 40)
HAVING COUNT(*) > 1;
-- Nhiều cursors cùng FORCE_MATCHING_SIGNATURE = cùng SQL khác literals
```

### Giải pháp — Dùng Bind Variables

```sql
DECLARE
  I NUMBER := 1;
  N NUMBER;
BEGIN
  WHILE (TRUE) LOOP
    I := I + 1;
    EXECUTE IMMEDIATE
      'SELECT COUNT(*) FROM SOE.ORDERS WHERE ORDER_ID = :V_ORDER_ID'
    INTO N USING I;
  END LOOP;
END;
/
```

**Verify:** Sau khi chuyển sang bind variables, `library cache: mutex X` không còn tăng nhanh → latch contention được giải quyết.

> **Root cause:** Literals → nhiều SQL unique → library cache bị lấp đầy → hard parsing liên tục → tranh chấp latch để ghi vào library cache.
> **Fix:** Bind variables → tái sử dụng cursor → giảm hard parsing → giảm latch contention.

---

## Phần 3: Cache Buffer Chain (CBC) Latch Contention

### Nguyên nhân

Nhiều sessions đồng thời đọc cùng một **buffer** trong Buffer Cache → tranh chấp CBC latch (mỗi buffer chain được bảo vệ bởi một CBC latch).

### Điều kiện tiên quyết: Verify 2 rows ở cùng block

```sql
SELECT CUSTOMER_ID,
       DBMS_ROWID.ROWID_RELATIVE_FNO(ROWID) RFILE#,
       DBMS_ROWID.ROWID_BLOCK_NUMBER(ROWID) BLOCK#
FROM CUSTOMERS
WHERE CUSTOMER_ID IN (10000, 10001);
-- Cần cùng BLOCK# để tạo hot block scenario
```

### Mô phỏng: Nhiều sessions đọc cùng block (5 phút)

Script `access_block.sql`:

```sql
DECLARE
  V_TIME DATE;
  V CUSTOMERS%ROWTYPE;
BEGIN
  DBMS_APPLICATION_INFO.SET_MODULE(
    MODULE_NAME => 'CUSTOMER ACCESS',
    ACTION_NAME => 'ACCESS BLOCK'
  );
  V_TIME := SYSDATE;
  WHILE (SYSDATE <= V_TIME + INTERVAL '5' MINUTE) LOOP
    SELECT * INTO V FROM CUSTOMERS WHERE CUSTOMER_ID = 10000;
  END LOOP;
END;
/
```

Chạy song song + update transaction chưa commit (tạo dirty block):

```sql
-- Session khác: Update nhưng KHÔNG commit
UPDATE CUSTOMERS SET DOB = DOB + 0 WHERE CUSTOMER_ID = 10001;
-- KHÔNG COMMIT
```

### Phát hiện CBC Latch

```sql
set linesize 180
col EVENT      format a35
col WAIT_CLASS format a20
col TIME_CSEC  format 999,999,999

SELECT E.SID, E.EVENT, E.WAIT_CLASS, P1RAW, SUM(E.TIME_WAITED) TIME_CSEC
FROM V$SESSION_EVENT E, V$SESSION S
WHERE E.SID = S.SID AND S.ACTION = 'ACCESS BLOCK'
  AND E.WAIT_CLASS <> 'Idle'
GROUP BY E.SID, E.EVENT, E.WAIT_CLASS, P1RAW
HAVING SUM(E.TIME_WAITED) > 0
ORDER BY SUM(TIME_WAITED) DESC;
-- 'cache buffers chains' xuất hiện = CBC latch contention
```

> `P1RAW` = địa chỉ của latch đang bị tranh chấp.

### Lấy thống kê chi tiết của CBC latch

```sql
DEFINE LATCH_ADDRESS = '<latch_address_from_above>'

SELECT ADDR, LATCH#, CHILD#, LEVEL#, GETS, MISSES, SLEEPS
FROM V$LATCH_CHILDREN
WHERE ADDR = '&LATCH_ADDRESS';
-- Chạy nhiều lần: GETS/MISSES tăng = latch đang hot
-- Sau khi COMMIT: SLEEPS stable = không còn tranh chấp write
```

### Xác định object của hot block

```sql
col OWNER       for a4
col OBJECT_NAME for a20
col OBJECT_TYPE for a10

SELECT L.ADDR, OWNER, OBJECT_NAME, OBJECT_TYPE,
       COUNT(DISTINCT L.ADDR) LATCHES,
       SUM(TCH) TOUCHES
FROM V$LATCH_CHILDREN L
JOIN X$BH B ON (L.ADDR = B.HLADDR)
JOIN DBA_OBJECTS O ON (B.OBJ = O.OBJECT_ID)
WHERE L.NAME = 'cache buffers chains'
  AND OWNER = 'SOE'
  AND L.ADDR = '&LATCH_ADDRESS'
GROUP BY L.ADDR, OWNER, OBJECT_NAME, OBJECT_TYPE
ORDER BY SUM(TCH) DESC;
```

> `TCH` = Touch Count — số lần buffer được truy cập. TOUCHES cao = hot block.

**Root cause:** Nhiều sessions đọc cùng block có transaction chưa commit → cần consistent read → truy cập undo → tạo dirty buffer → tranh chấp CBC latch.
**Fix:** Giảm hot block bằng cách: phân tán dữ liệu, tăng INITRANS, partitioning, hoặc reverse-key index để phân tán insert.

---

## Phần 4: Cursor Mutex và Pin Waits

Khi 10+ sessions đồng thời execute cùng cursor và truy cập cùng block:

```sql
SELECT E.EVENT, E.WAIT_CLASS, SUM(E.TIME_WAITED) TIME_CSEC
FROM V$SESSION_EVENT E, V$SESSION S
WHERE E.SID = S.SID AND S.ACTION = 'ACCESS BLOCK'
  AND E.WAIT_CLASS <> 'Idle'
GROUP BY E.EVENT, E.WAIT_CLASS
HAVING SUM(E.TIME_WAITED) > 0
ORDER BY SUM(TIME_WAITED) ASC;
```

**Events thường thấy:**
- `cursor: mutex X` — exclusive mutex khi compile/load cursor
- `cursor: pin S` — shared pin khi execute cursor

**Root cause:** Quá nhiều sessions execute cùng cursor → tranh chấp pin để đọc cursor.
**Fix:** Giảm số sessions cùng thực thi, hoặc kiểm tra lại logic ứng dụng.

---

## Tóm tắt

| Vấn đề | Event | Root cause | Fix |
|--------|-------|-----------|-----|
| Library cache latch | `library cache: mutex X` | SQL dùng literals → nhiều hard parses | Dùng bind variables |
| CBC latch | `cache buffers chains` | Nhiều sessions đọc cùng block | Phân tán data, tăng INITRANS |
| Cursor mutex/pin | `cursor: mutex X`, `cursor: pin S` | Nhiều sessions execute cùng cursor | Giảm concurrency |

**Views quan trọng:**
| View | Mô tả |
|------|-------|
| `V$LATCH` | Latch statistics tổng thể |
| `V$LATCHNAME` | Tên của latches |
| `V$LATCH_CHILDREN` | Child latch details (CBC latch) |
| `V$SESSION_EVENT` | Wait events theo session |
| `V$SYSTEM_EVENT` | Wait events tổng thể |
| `X$BH` | Buffer Header — internal, join với V$LATCH_CHILDREN để tìm hot block |


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/section_all/section_20_latch_mutex_guide.md`
