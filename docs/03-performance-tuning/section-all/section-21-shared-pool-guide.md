---
title: Section 21 — Shared Pool Tuning
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/section_all/section_21_shared_pool_guide.md
---

# Section 21 — Shared Pool Tuning

**Nguồn:** Oracle Database Performance Tuning — Ahmed Baraka (v2.3)  
**Practices:** 20, 21, 22  
**Ngày học:** 2026-04-20

---

## Tổng quan Section 21

Section 21 bao gồm **3 chủ đề** về tối ưu hóa Shared Pool:

| Practice | Chủ đề |
|----------|--------|
| 20 | Tuning the Shared Pool (High Parse, Library Cache Pin) |
| 21 | Caching Session Cursors |
| 22 | Managing Server Result Cache |

---

## Kiến thức nền tảng

### Shared Pool là gì?

Shared Pool là một vùng nhớ trong SGA (System Global Area) gồm hai thành phần chính:

```
SGA
└── Shared Pool
    ├── Library Cache     → lưu parsed SQL, execution plans, PL/SQL code
    └── Data Dictionary Cache → lưu metadata của objects (tables, indexes...)
```

**Tại sao Shared Pool quan trọng?**
- Mọi SQL statement trước khi thực thi đều phải qua **parse** → tốn CPU
- Nếu SQL đã parse trước đó còn trong Library Cache → **soft parse** (nhanh)
- Nếu phải parse lại từ đầu → **hard parse** (chậm, tốn tài nguyên nhiều)

### Các loại Parse

| Loại | Mô tả | Chi phí |
|------|-------|---------|
| **Hard Parse** | Parse hoàn toàn mới: syntax check, semantic check, optimizer, tạo execution plan | Rất cao (CPU, latch) |
| **Soft Parse** | Tìm thấy cursor trong Library Cache, dùng lại execution plan | Thấp hơn hard parse |
| **Soft-Soft Parse** | Tìm thấy cursor trong Session Cursor Cache | Thấp nhất |

---

## Practice 20 — Tuning the Shared Pool

### Phần 1: Phát hiện vấn đề Hard Parse

#### Mô phỏng High Hard Parse

Nguyên nhân phổ biến nhất của hard parse: **dùng literals thay vì bind variables**

```sql
-- BAD: mỗi giá trị ORDER_ID khác nhau = 1 hard parse mới
SELECT COUNT(*) FROM SOE.ORDERS WHERE ORDER_ID = 1001;
SELECT COUNT(*) FROM SOE.ORDERS WHERE ORDER_ID = 1002;
SELECT COUNT(*) FROM SOE.ORDERS WHERE ORDER_ID = 1003;
-- → 3 hard parses vì SQL text khác nhau hoàn toàn

-- GOOD: dùng bind variable = chỉ 1 hard parse, nhiều lần soft parse
SELECT COUNT(*) FROM SOE.ORDERS WHERE ORDER_ID = :B1;
-- → 1 hard parse, các lần sau là soft parse
```

Code mô phỏng từ practice (PL/SQL loop dùng literal):
```sql
DECLARE
  I NUMBER := 1;
  N NUMBER;
BEGIN
  WHILE (TRUE) LOOP
    I := I + 1;
    EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM SOE.ORDERS WHERE ORDER_ID = ' || TO_CHAR(I)
    INTO N;
  END LOOP;
END;
/
```

#### Phát hiện qua Time Model

```sql
-- Xem % thời gian parse trong tổng DB time
@time_model_pct.sql
-- Quan sát: hard parse time % tăng dần khi có vấn đề
```

#### Phát hiện qua Wait Events

```sql
-- Top wait events ở database level
SELECT EVENT, AVERAGE_WAIT,
       TO_CHAR(ROUND(TIME_WAITED/100),'999,999,999') TIME_SECONDS, WAIT_CLASS
FROM   V$SYSTEM_EVENT
WHERE  TIME_WAITED > 0 AND WAIT_CLASS <> 'Idle'
ORDER BY TIME_WAITED DESC FETCH FIRST 10 ROWS ONLY;

-- Top wait events của các session soe
SELECT E.EVENT, E.WAIT_CLASS,
       TO_CHAR(ROUND(SUM(E.TIME_WAITED)/100),'999,999,999') TIME_SECONDS
FROM V$SESSION_EVENT E, V$SESSION S
WHERE E.SID = S.SID AND ROUND(E.TIME_WAITED/100) > 0
  AND S.USERNAME = 'SOE' AND E.WAIT_CLASS <> 'Idle'
GROUP BY E.EVENT, E.WAIT_CLASS
ORDER BY TIME_SECONDS DESC FETCH FIRST 10 ROWS ONLY;
```

**Dấu hiệu nhận biết high parse:** Wait event `cursor: pin S wait on X` (mutex) xuất hiện trong top events.

#### Phát hiện qua ASH

```sql
-- CPU usage theo phút của các soe sessions
SELECT TO_CHAR(SAMPLE_TIME,'HH24:MI') SMINUTE, COUNT(1) CPU
FROM  V$ACTIVE_SESSION_HISTORY
WHERE USER_ID IN (SELECT USER_ID FROM DBA_USERS WHERE USERNAME = 'SOE')
  AND SESSION_STATE = 'ON CPU'
  AND SAMPLE_TIME > SYSTIMESTAMP - INTERVAL '10' MINUTE
GROUP BY TO_CHAR(SAMPLE_TIME,'HH24:MI')
ORDER BY 1 DESC;
```

---

### Phần 2: Xác định kích thước tối ưu Shared Pool

#### Kiểm tra cấu hình Memory Management

```sql
-- Kiểm tra Automatic Memory Management (AMM)
SHOW PARAMETER MEMORY_TARGET;
-- Nếu MEMORY_TARGET > 0 → AMM đang bật, Oracle tự quản lý toàn bộ SGA+PGA

-- Kiểm tra Automatic Shared Memory Management (ASMM)
SHOW PARAMETER SGA_TARGET;
-- Nếu SGA_TARGET > 0 → ASMM bật, Oracle tự cân bằng các component trong SGA
```

```sql
-- Xem kích thước hiện tại của các SGA components
SELECT NAME, ROUND(BYTES/1024/1024,2) MB
FROM V$SGAINFO
ORDER BY 2 DESC;
```

#### Xem Library Cache Memory Usage

```sql
-- Xem bộ nhớ Library Cache theo namespace
SELECT LC_NAMESPACE NAMES,
       LC_INUSE_MEMORY_OBJECTS  "OBJECTS",
       LC_INUSE_MEMORY_SIZE     "USED_MEM (MB)",
       LC_FREEABLE_MEMORY_SIZE  "FREEABLE MEM (MB)"
FROM V$LIBRARY_CACHE_MEMORY
ORDER BY LC_INUSE_MEMORY_OBJECTS DESC;
```

#### Shared Pool Advisory — View quan trọng nhất

```sql
-- Tìm kích thước tối ưu từ Shared Pool Advisory
SELECT SHARED_POOL_SIZE_FOR_ESTIMATE  C1,   -- Kích thước thử nghiệm (MB)
       SHARED_POOL_SIZE_FACTOR         C2,   -- Hệ số so với kích thước hiện tại
       ESTD_LC_SIZE                    C3,   -- Ước tính Library Cache size (MB)
       ESTD_LC_MEMORY_OBJECTS          C4,   -- Số objects ước tính trong LC
       ESTD_LC_TIME_SAVED              C5,   -- Thời gian tiết kiệm được (giây)
       ESTD_LC_TIME_SAVED_FACTOR       C6,   -- Hệ số tiết kiệm thời gian
       ESTD_LC_MEMORY_OBJECT_HITS      C7    -- Số object hits ước tính
FROM V$SHARED_POOL_ADVICE
ORDER BY 1;
```

**Cách đọc kết quả Advisory:**
- Tìm điểm mà `ESTD_LC_TIME_SAVED_FACTOR` bắt đầu plateau (không tăng đáng kể nữa)
- Đó là kích thước tối ưu — tăng thêm không mang lại lợi ích tương xứng
- **Lưu ý quan trọng:** Đọc advisory khi hệ thống đang chạy trong điều kiện bình thường (normal OLTP), không phải khi đang có vấn đề

**AWR Report — Shared Pool Advisory Section:**
- Trong AWR report, tìm section **"Shared Pool Advisory"**
- Report trong điều kiện bình thường (normal_oltp.html) đáng tin cậy hơn report lúc có sự cố

---

### Phần 3: Library Cache Pin

#### Library Cache Pin là gì?

Khi một session **compile lại** (ALTER ... COMPILE) một object đang được session khác **đang thực thi**, Oracle phải lấy exclusive pin lock. Session compile phải chờ → sinh ra wait event `library cache pin`.

```
Session A: đang EXECUTE function PCKORDERS (giữ shared pin)
Session B: ALTER PACKAGE PCKORDERS COMPILE (cần exclusive pin → WAIT)
→ Session B sinh ra: "library cache pin" wait event
```

#### Mô phỏng Library Cache Pin

```sql
-- Tạo package
CREATE OR REPLACE PACKAGE SOE.PCKORDERS AS
  FUNCTION GET_ORDER_TOTAL(P_ORDER_ID NUMBER) RETURN NUMBER;
END;
/

CREATE OR REPLACE PACKAGE BODY SOE.PCKORDERS AS
  FUNCTION GET_ORDER_TOTAL(P_ORDER_ID NUMBER) RETURN NUMBER AS
    N NUMBER;
  BEGIN
    SELECT ORDER_TOTAL INTO N FROM ORDERS WHERE ORDER_ID = P_ORDER_ID;
    RETURN N;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN RETURN 0;
  END GET_ORDER_TOTAL;
END;
/

-- Sessions chạy loop liên tục gọi function
DECLARE
  I NUMBER := 1;
  N NUMBER;
BEGIN
  WHILE (TRUE) LOOP
    I := I + 1;
    N := PCKORDERS.GET_ORDER_TOTAL(I);
  END LOOP;
END;
/

-- Session khác compile lại → HANG
ALTER PACKAGE PCKORDERS COMPILE;
```

#### Chẩn đoán Library Cache Pin

```sql
-- Bước 1: Tìm session đang chờ và lấy P1RAW (Handle Address)
SELECT EVENT, P1TEXT, P1, P1RAW, WAIT_TIME, STATE, WAIT_TIME_MICRO
FROM V$SESSION
WHERE SID = &V_SID;

-- Bước 2: Từ P1RAW → tìm tên object bị lock
SELECT KGLNAOWN AS OWNER, KGLNAOBJ AS OBJECT
FROM SYS.X$KGLOB
WHERE KGLHDADR = '&Enter_P1RAW';
```

**Cách giải quyết:**
- Identify session đang giữ lock → kiểm tra có thể kill không
- Lên lịch compile vào giờ thấp điểm
- Dùng `DBMS_DDL.ALTER_COMPILE` với timeout

---

## Practice 21 — Caching Session Cursors

### Session Cursor Cache là gì?

```
Hard Parse → cursor trong Library Cache (Shared Pool)
                     ↓ (sau 2-3 lần execute)
           → pointer lưu vào Session Cursor Cache
                     ↓ (lần execute tiếp theo)
           → soft-soft parse (không cần tìm Library Cache)
```

**Mục đích:** Giảm overhead soft parse bằng cách giữ pointer đến các cursor thường dùng ngay trong session.

### Tham số điều chỉnh

```sql
-- Xem giá trị hiện tại (mặc định = 50)
SHOW PARAMETER SESSION_CACHED_CURSORS;

-- Điều chỉnh
ALTER SYSTEM SET SESSION_CACHED_CURSORS = 100 SCOPE = SPFILE;

-- Bật/tắt ở session level
ALTER SESSION SET SESSION_CACHED_CURSORS = 50;  -- bật
ALTER SESSION SET SESSION_CACHED_CURSORS = 0;   -- tắt
```

### Giám sát Session Cursor Cache

#### Scripts quan trọng

```sql
-- 1. Xem loại cursor của một SQL statement
SELECT C.SQL_TEXT, CURSOR_TYPE
FROM   V$OPEN_CURSOR C, V$SESSION S
WHERE  S.USERNAME = 'SOE' AND C.SID = S.SID
  AND  C.SQL_TEXT LIKE '%/*+ MY_QUERY */%';
-- CURSOR_TYPE values:
--   OPEN            → cursor đang mở trong Shared Pool
--   DICTIONARY LOOKUP CURSOR CACHED → cursor từ Session Cursor Cache
```

```sql
-- 2. Thống kê session cursor cache
SELECT B.NAME STATISTIC, A.VALUE
FROM  V$SESSTAT A, V$STATNAME B, V$SESSION S
WHERE A.STATISTIC# = B.STATISTIC#
  AND S.SID = A.SID AND S.USERNAME = 'SOE'
  AND B.NAME IN ('session cursor cache count',
                 'session cursor cache hits',
                 'parse count (total)',
                 'parse count (hard)')
ORDER BY B.NAME;
```

```sql
-- 3. Số cursors đang cached trong mỗi session soe
SELECT A.VALUE CURR_CACHED, P.VALUE MAX_CACHE,
       S.USERNAME, S.SID, S.SERIAL#
FROM V$SESSTAT A, V$STATNAME B, V$SESSION S, V$PARAMETER2 P
WHERE A.STATISTIC# = B.STATISTIC#
  AND S.SID = A.SID AND S.USERNAME = 'SOE'
  AND P.NAME = 'session_cached_cursors'
  AND B.NAME = 'session cursor cache count'
ORDER BY A.VALUE DESC;
```

```sql
-- 4. Tỷ lệ hit của session cursor cache
SELECT C.SID, C.VALUE CACHE_HITS, PRS.VALUE ALL_PARSES,
       ROUND((C.VALUE/PRS.VALUE)*100,2) AS "% FOUND IN CACHE"
FROM  V$SESSTAT C, V$STATNAME NM1, V$SESSTAT PRS, V$STATNAME NM2
WHERE C.STATISTIC# = NM1.STATISTIC#
  AND NM1.NAME = 'session cursor cache hits'
  AND PRS.STATISTIC# = NM2.STATISTIC#
  AND NM2.NAME = 'parse count (total)'
  AND PRS.SID IN (SELECT SID FROM V$SESSION WHERE USERNAME = 'SOE')
  AND PRS.SID = C.SID;
```

### Quy trình hoạt động của Session Cursor Cache

```
Lần 1 execute SQL → Hard Parse → lưu cursor vào Library Cache (OPEN)
Lần 2 execute SQL → Soft Parse → cursor vẫn OPEN trong Library Cache
Lần 3 execute SQL → Oracle cache pointer vào Session Cursor Cache
                  → CURSOR_TYPE = 'DICTIONARY LOOKUP CURSOR CACHED'
Lần 4+ execute SQL → Soft-Soft Parse → lấy từ Session Cursor Cache (nhanh nhất)
```

### Cách xác định kích thước tối ưu SESSION_CACHED_CURSORS

**Nguyên tắc:** Nếu nhiều session đạt đến MAX_CACHE → cần tăng giá trị.

```
Quan sát CURR_CACHED vs MAX_CACHE:
- Nếu CURR_CACHED ≈ MAX_CACHE ở nhiều session → TĂNG SESSION_CACHED_CURSORS
- Nếu CURR_CACHED << MAX_CACHE → giá trị hiện tại đủ dùng

Ví dụ thực tế:
- SESSION_CACHED_CURSORS = 50, nhiều session đạt 48-50 → set lên 100
- Sau khi set 100, CURR_CACHED cao nhất là 75 → optimal ≈ 70-90
```

---

## Practice 22 — Managing Server Result Cache

### Server Result Cache là gì?

```
Client gửi query → Oracle kiểm tra Result Cache
   ├── HIT:  trả về result set ngay (không đọc blocks, không tính toán)
   └── MISS: thực thi query → lưu result set vào Result Cache → trả kết quả
```

Result Cache lưu trong **Shared Pool** (không phải Buffer Cache), block size = **1 KB** (Buffer Cache block size = 8 KB).

**Phù hợp cho:** Queries trên dữ liệu **ít thay đổi** (static/reference data), queries tốn nhiều CPU/I/O, chạy lặp đi lặp lại.

**Không phù hợp cho:** OLTP với data thay đổi liên tục (invalidation overhead).

### Các tham số cấu hình

```sql
-- Kích thước tối đa của toàn bộ Result Cache
SHOW PARAMETER RESULT_CACHE_MAX_SIZE;
-- Mặc định: ~0.25% của SGA hoặc 75% của Shared Pool (tùy Oracle version)

-- Kích thước tối đa cho một single result set (% của RESULT_CACHE_MAX_SIZE)
SHOW PARAMETER RESULT_CACHE_MAX_RESULT;
-- Mặc định: 5% của RESULT_CACHE_MAX_SIZE
```

### Cách sử dụng Result Cache trong SQL

```sql
-- Dùng hint RESULT_CACHE
SELECT /*+ RESULT_CACHE */ SALES_REP_ID, SUM(ORDER_TOTAL)
FROM ORDERS
WHERE EXTRACT(YEAR FROM ORDER_DATE) = 2017
GROUP BY SALES_REP_ID;

-- Đặt tên cho cache object (dễ theo dõi)
SELECT /*+ RESULT_CACHE(NAME=SALES_REPORT) */ SALES_REP_ID, SUM(ORDER_TOTAL)
FROM ORDERS
WHERE EXTRACT(YEAR FROM ORDER_DATE) = 2017
GROUP BY SALES_REP_ID
ORDER BY SUM(ORDER_TOTAL);
```

### Giám sát Result Cache

#### DBMS_RESULT_CACHE — Procedure quan trọng

```sql
-- Xem báo cáo bộ nhớ Result Cache
SET SERVEROUTPUT ON
EXEC DBMS_RESULT_CACHE.MEMORY_REPORT;
-- Output:
-- R e s u l t  C a c h e  M e m o r y  R e p o r t
-- [Parameters]
-- Block Size         = 1024 bytes
-- Maximum Cache Size = X bytes (100%)
-- Maximum Result Size = Y bytes (5%)
-- [Memory]
-- Total Memory = ...
-- Cache Memory = ...

-- Flush toàn bộ Result Cache
EXEC DBMS_RESULT_CACHE.FLUSH;
```

#### Views giám sát

```sql
-- 1. Thống kê Result Cache
SELECT NAME, VALUE
FROM V$RESULT_CACHE_STATISTICS
ORDER BY ID;
-- Các metric quan trọng: Create Count, Find Count, Invalidation Count, Delete Count

-- 2. Bộ nhớ blocks của từng RC object
SELECT OBJECT_ID CACHE_OBJECT, COUNT(ID) BLOCKS, FREE
FROM V$RESULT_CACHE_MEMORY
GROUP BY OBJECT_ID, FREE
ORDER BY FREE, COUNT(ID);

-- 3. Danh sách RC objects và trạng thái
SELECT NAME, TYPE, STATUS, BLOCK_COUNT, INVALIDATIONS
FROM V$RESULT_CACHE_OBJECTS
ORDER BY TYPE DESC;
-- STATUS values:
--   Published  → valid, sẵn sàng dùng
--   Invalid    → bị invalidate (data đã thay đổi hoặc quá lớn)
--   Expired    → hết hạn

-- 4. Lấy kích thước RC max từ parameters
WITH RC_MAX AS (SELECT VALUE FROM V$PARAMETER WHERE UPPER(NAME) = 'RESULT_CACHE_MAX_SIZE'),
     RC_MAX_RESULT AS (SELECT VALUE FROM V$PARAMETER WHERE UPPER(NAME) = 'RESULT_CACHE_MAX_RESULT')
SELECT A.VALUE/1024 RC_MAX_KB,
       B.VALUE * A.VALUE / 100 / 1024 MAX_RESULT_KB
FROM RC_MAX A, RC_MAX_RESULT B;
```

### Tác động của Result Cache lên Performance

#### Khi result set VỪA với max size

```
Lần 1: consistent gets = cao, physical reads = cao (cache miss → đọc từ disk/buffer)
Lần 2: consistent gets = 0,   physical reads = 0   (cache hit → từ Result Cache)
```

**Kết luận:** Result Cache loại bỏ hoàn toàn việc đọc blocks — hiệu quả cực kỳ cao với static data.

#### Khi result set QUÁ LỚN (> RESULT_CACHE_MAX_RESULT)

```sql
-- Nếu result set > MAX_RESULT_SIZE → STATUS = 'Invalid'
-- Query chạy nhưng KHÔNG cache được → không có lợi ích

-- Kiểm tra
SELECT NAME, TYPE, STATUS FROM V$RESULT_CACHE_OBJECTS;
-- STATUS = 'Invalid' → object quá lớn hoặc data đã thay đổi

-- Giải pháp: tăng RESULT_CACHE_MAX_RESULT
ALTER SYSTEM SET RESULT_CACHE_MAX_RESULT = 50;  -- 50% của RESULT_CACHE_MAX_SIZE
-- → Chạy query lại → lần 2 sẽ cache được
```

### Invalidation của Result Cache

Khi data thay đổi (INSERT/UPDATE/DELETE/COMMIT trên bảng phụ thuộc), Oracle **tự động invalidate** RC object liên quan.

```sql
-- RC object có 2 thành phần:
-- 1. Result object (chứa data)
-- 2. Dependency object (trỏ đến SOE.ORDERS)
-- → Khi ORDERS bị DML → cả 2 object bị invalidate
SELECT NAME, TYPE, STATUS, INVALIDATIONS
FROM V$RESULT_CACHE_OBJECTS;
```

---

## Tóm tắt Key Takeaways

### Shared Pool Sizing
| Nguyên tắc | Chi tiết |
|-----------|---------|
| Đọc Shared Pool Advisory khi bình thường | Đừng đọc lúc đang có sự cố |
| `V$SHARED_POOL_ADVICE` | Tìm điểm plateau của `ESTD_LC_TIME_SAVED_FACTOR` |
| AMM vs ASMM | Nếu AMM bật → Oracle tự điều chỉnh, không cần set tay |

### Parse Optimization
| Kỹ thuật | Lợi ích |
|---------|--------|
| Bind variables | Triệt tiêu hard parse |
| Session Cursor Cache | Giảm overhead soft parse |
| Result Cache | Loại bỏ hoàn toàn parse + I/O cho static queries |

### Chẩn đoán nhanh
| Triệu chứng | Nguyên nhân | View kiểm tra |
|------------|-------------|---------------|
| `cursor: pin S wait on X` tăng | Hard parse quá nhiều (dùng literals) | `V$SYSTEM_EVENT` |
| `library cache pin` tăng | Session compile object đang được execute | `V$SESSION` + `X$KGLOB` |
| CPU cao bất thường | Hard parse chiếm CPU | `V$SYS_TIME_MODEL` + ASH |

### Views quan trọng Section 21

| View | Mục đích |
|------|---------|
| `V$SGAINFO` | Kích thước các SGA components |
| `V$LIBRARY_CACHE_MEMORY` | Bộ nhớ Library Cache theo namespace |
| `V$SHARED_POOL_ADVICE` | Advisory kích thước tối ưu Shared Pool |
| `V$OPEN_CURSOR` | Trạng thái cursor (OPEN/CACHED) |
| `V$SESSTAT` + `V$STATNAME` | Thống kê session (parse counts, cache hits) |
| `V$RESULT_CACHE_STATISTICS` | Thống kê Result Cache |
| `V$RESULT_CACHE_OBJECTS` | Danh sách RC objects và trạng thái |
| `V$RESULT_CACHE_MEMORY` | Block usage của từng RC object |
| `X$KGLOB` | Internal table — tìm object bị library cache pin |

---

## Câu hỏi ôn tập

1. Sự khác nhau giữa hard parse, soft parse, và soft-soft parse là gì?
2. Wait event `cursor: pin S wait on X` xuất hiện do nguyên nhân gì?
3. Khi nào nên đọc Shared Pool Advisory để xác định kích thước tối ưu?
4. Session Cursor Cache hoạt động như thế nào? Oracle cache cursor sau bao nhiêu lần execute?
5. Result Cache phù hợp với loại workload nào? Tại sao không nên dùng với OLTP data thay đổi liên tục?
6. Nếu `V$RESULT_CACHE_OBJECTS` cho thấy STATUS = 'Invalid', nguyên nhân có thể là gì?
7. Dùng query nào để xác định kích thước tối ưu của `SESSION_CACHED_CURSORS`?


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/section_all/section_21_shared_pool_guide.md`
