---
title: Section 22 — Buffer Cache & Smart Flash Cache Tuning
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/section_all/section_22_buffer_cache_flash_cache_guide.md
---

# Section 22 — Buffer Cache & Smart Flash Cache Tuning

**Nguồn:** Oracle Database Performance Tuning — Ahmed Baraka (v2.3)  
**Practices:** 23, 24  
**Ngày học:** 2026-04-20

---

## Tổng quan Section 22

| Practice | Chủ đề |
|----------|--------|
| 23 | Tuning the Buffer Cache (Advisory + KEEP Pool) |
| 24 | Using Smart Flash Cache (cấu hình + giám sát) |

---

## Kiến thức nền tảng

### Buffer Cache là gì?

Buffer Cache là thành phần **lớn nhất trong SGA**, lưu trữ các data blocks đọc từ disk vào RAM để tái sử dụng.

```
Disk I/O read → Block vào Buffer Cache → Session đọc từ RAM
                       ↑
              Nếu block đã có trong Cache → "logical read" (không cần disk)
              Nếu block chưa có → "physical read" (đọc từ disk) → tốn thời gian
```

**Metric quan trọng nhất: Buffer Cache Hit Ratio**
```
Hit% = (Logical Reads - Physical Reads) / Logical Reads × 100
→ Mục tiêu: ≥ 95% trong OLTP thông thường
→ < 95% là dấu hiệu buffer cache không đủ lớn
```

### Các vùng nhớ trong Buffer Cache

| Pool | Mục đích | Tham số |
|------|---------|---------|
| **DEFAULT Pool** | Pool chính, tất cả objects dùng mặc định | `DB_CACHE_SIZE` |
| **KEEP Pool** | Giữ các objects nhỏ hay truy cập thường xuyên — không bị aging out | `DB_KEEP_CACHE_SIZE` |
| **RECYCLE Pool** | Cho objects lớn FTS — tránh đẩy blocks khác ra khỏi cache | `DB_RECYCLE_CACHE_SIZE` |

---

## Practice 23 — Tuning the Buffer Cache

### Phần 1: Xác định vấn đề Buffer Cache qua AWR

Khi buffer cache không đủ, AWR report sẽ hiển thị các dấu hiệu sau:

#### Các section cần kiểm tra trong AWR Report

| AWR Section | Dấu hiệu bất thường |
|-------------|---------------------|
| **Load Profile** | Physical reads/sec ≈ Logical reads/sec (bình thường: logical >> physical) |
| **Instance Efficiency** | Buffer Hit % thấp (< 95%) |
| **Top 10 Foreground Events** | Wait events như `db file sequential read`, `db file scattered read`, `buffer busy waits` chiếm top |
| **Cache Sizes** | Buffer cache size rất nhỏ so với workload |
| **Latch Statistics → Latch Sleep Breakdown** | **CBC latch** (Cache Buffer Chain) đứng top |
| **Buffer Pool Advisory** | Advisory chỉ hiển thị tối đa 200% kích thước hiện tại |

#### ADDM Finding liên quan Buffer Cache

```sql
-- Lấy thông tin ADDM finding về buffer cache
SELECT
  'FINDING_ID: ' || FINDING_ID || CHR(10) ||
  'FINDING_NAME: ' || FINDING_NAME || CHR(10) ||
  'TYPE: ' || TYPE || CHR(10) ||
  'IMPACT_TYPE: ' || IMPACT_TYPE || CHR(10) ||
  'IMPACT: ' || IMPACT || CHR(10) ||
  'MESSAGE: ' || MESSAGE FINDING
FROM DBA_ADDM_FINDINGS F
WHERE TASK_NAME = '&V_TNAME' AND FINDING_NAME = '&V_FNAME';

-- Lấy action recommendations từ ADDM
SELECT ACTION_ID, MESSAGE
FROM DBA_ADVISOR_ACTIONS
WHERE (TASK_NAME, REC_ID) IN (
  SELECT TASK_NAME, REC_ID FROM DBA_ADVISOR_RECOMMENDATIONS
  WHERE TASK_NAME = '&V_TNAME'
    AND FINDING_ID IN (
      SELECT FINDING_ID FROM DBA_ADDM_FINDINGS
      WHERE TASK_NAME = '&V_TNAME' AND FINDING_NAME = '&V_FNAME'
    )
)
ORDER BY ACTION_ID;
```

---

### Phần 2: Buffer Pool Advisory — Xác định kích thước tối ưu

#### View V$DB_CACHE_ADVICE

```sql
-- Buffer Pool Advisory: ước tính physical reads ở các kích thước khác nhau
SELECT SIZE_FOR_ESTIMATE          "Cache Size (MB)",
       SIZE_FACTOR                "Size Factor",
       ESTD_PHYSICAL_READ_FACTOR  "Phys Read Factor",
       ESTD_PHYSICAL_READS        "Est Phys Reads"
FROM V$DB_CACHE_ADVICE
WHERE NAME = 'DEFAULT'
ORDER BY SIZE_FOR_ESTIMATE;
```

**Cách đọc kết quả:**
```
Cache Size (MB) | Size Factor | Phys Read Factor | Est Phys Reads
         50     |    0.25     |      8.00        |   8,000,000   ← quá nhỏ
        100     |    0.50     |      4.00        |   4,000,000
        200     |    1.00     |      1.00        |   1,000,000   ← hiện tại
        300     |    1.50     |      0.60        |     600,000
        400     |    2.00     |      0.30        |     300,000   ← plateau bắt đầu
        500     |    2.50     |      0.28        |     280,000   ← không giảm nhiều
```
→ Tìm điểm **Phys Read Factor plateau** (không giảm đáng kể) → đó là kích thước tối ưu

**Lưu ý quan trọng:**
- Advisory chỉ hiển thị tối đa **200% kích thước hiện tại**
- Nếu 200% vẫn chưa đủ → cần tăng mạnh hơn và đọc lại Advisory
- Đọc Advisory khi hệ thống chạy trong điều kiện bình thường

#### Kiểm tra cấu hình Memory Management trước khi điều chỉnh

```sql
-- Kiểm tra AMM (Automatic Memory Management)
SHOW PARAMETER MEMORY_TARGET;   -- > 0 → AMM bật

-- Kiểm tra ASMM (Automatic Shared Memory Management)
SHOW PARAMETER SGA_TARGET;      -- > 0 → ASMM bật

-- Xem kích thước hiện tại các components
SHOW PARAMETER DB_CACHE_SIZE;
SHOW PARAMETER SHARED_POOL_SIZE;
SHOW PARAMETER LARGE_POOL_SIZE;
SHOW PARAMETER JAVA_POOL_SIZE;

-- Xem kích thước thực tế đang dùng (khi AMM/ASMM tự điều chỉnh)
SELECT COMPONENT, CURRENT_SIZE/1024/1024 MB
FROM V$MEMORY_DYNAMIC_COMPONENTS
WHERE COMPONENT IN ('DEFAULT buffer cache', 'shared pool', 'large pool', 'java pool');
```

#### Chuyển sang Manual Memory Management để test

```sql
-- Tắt AMM và ASMM
ALTER SYSTEM SET MEMORY_TARGET = 0 SCOPE = SPFILE;
ALTER SYSTEM SET SGA_TARGET = 0 SCOPE = SPFILE;

-- Set kích thước thủ công
ALTER SYSTEM SET DB_CACHE_SIZE    = 10485760 SCOPE = SPFILE;  -- 10 MB (test undersized)
ALTER SYSTEM SET SHARED_POOL_SIZE = &enter_size SCOPE = SPFILE;
ALTER SYSTEM SET LARGE_POOL_SIZE  = &enter_size SCOPE = SPFILE;
ALTER SYSTEM SET JAVA_POOL_SIZE   = &enter_size SCOPE = SPFILE;

SHUTDOWN IMMEDIATE
STARTUP
```

#### Quy trình tuning theo từng bước (iterative)

```
Bước 1: Buffer cache = 10 MB → AWR → Hit% = 5%  (rất tệ)
Bước 2: Buffer cache = 280 MB → AWR → Hit% = 60% (cải thiện nhưng chưa đủ)
Bước 3: Buffer cache = 460 MB → AWR → Hit% = 95% (đạt mục tiêu)
                                                    ↑
                                          Đây là kích thước tối ưu
```

**Quy tắc khi so sánh nhiều AWR reports:**
> Chỉ so sánh các metrics đã **normalize** (per second, per transaction, % DB time) — không so sánh giá trị tuyệt đối vì period length khác nhau.

---

### Phần 3: KEEP Pool — Giữ hot objects luôn trong bộ nhớ

#### KEEP Pool là gì và khi nào dùng?

**Dùng KEEP Pool khi:**
- Bảng nhỏ (lookup tables, reference data) được truy cập **rất thường xuyên**
- Blocks của bảng bị aging out khỏi DEFAULT pool do cạnh tranh với objects khác
- Muốn đảm bảo bảng luôn nằm trong memory, không bị evict

**Cơ chế:** Blocks trong KEEP pool không bị aging out bởi LRU algorithm thông thường.

#### Cấu hình KEEP Pool

```sql
-- Tạo KEEP pool (10 MB) và giảm DEFAULT pool tương ứng
ALTER SYSTEM SET DB_CACHE_SIZE      = 40M SCOPE = SPFILE;
ALTER SYSTEM SET DB_KEEP_CACHE_SIZE = 10M SCOPE = SPFILE;

SHUTDOWN IMMEDIATE
STARTUP

-- Verify
SHOW PARAMETER DB_KEEP_CACHE_SIZE;
```

#### Gán Object vào KEEP Pool

```sql
-- Gán table vào KEEP pool
ALTER TABLE SOE.EMP  STORAGE(BUFFER_POOL KEEP);
ALTER TABLE SOE.DEPT STORAGE(BUFFER_POOL KEEP);
ALTER TABLE SOE.JOBS STORAGE(BUFFER_POOL KEEP);

-- Gán index vào KEEP pool
ALTER INDEX SOE.EMP_PK STORAGE(BUFFER_POOL KEEP);

-- Đưa object về DEFAULT pool
ALTER TABLE SOE.EMP STORAGE(BUFFER_POOL DEFAULT);
```

#### Giám sát physical I/O của sessions

```sql
-- Physical read statistics của các SOE sessions đang chạy
SELECT T.NAME, SUM(S.VALUE) VALUE
FROM V$SESSTAT S, V$STATNAME T, V$SESSION H
WHERE S.STATISTIC# = T.STATISTIC#
  AND S.SID = H.SID
  AND H.USERNAME = 'SOE'
  AND H.ACTION = 'ID 1'
  AND S.VALUE <> 0
  AND T.NAME IN ('physical reads',
                 'physical reads cache',
                 'physical read bytes',
                 'physical read IO requests',
                 'physical reads cache prefetch',
                 'file io service time',
                 'file io wait time')
GROUP BY T.NAME
ORDER BY T.NAME;
```

**Kết quả kỳ vọng sau khi dùng KEEP Pool:**
```
Trước KEEP Pool: physical reads = 50,000 blocks
Sau KEEP Pool:   physical reads = 5,000 blocks  (giảm 90%)
→ Cải thiện đáng kể dù không tăng tổng bộ nhớ buffer cache
```

---

## Practice 24 — Smart Flash Cache

### Smart Flash Cache là gì?

Smart Flash Cache (Database Smart Flash Cache) mở rộng Buffer Cache ra **SSD/Flash storage** — tạo ra một tầng bộ nhớ trung gian giữa RAM và HDD.

```
Tầng 1: Buffer Cache (RAM)     — nhanh nhất, đắt nhất
Tầng 2: Smart Flash Cache (SSD) — nhanh hơn HDD nhiều lần
Tầng 3: Disk (HDD)              — chậm nhất, rẻ nhất

Luồng đọc:
Buffer Cache MISS → kiểm tra Flash Cache
   ├── Flash Cache HIT → đọc từ SSD (nhanh)
   └── Flash Cache MISS → đọc từ HDD (chậm)
```

**Lưu ý:** Chỉ available trên **Oracle Database Enterprise Edition** chạy trên **Oracle Solaris** hoặc **Oracle Linux** với SSD. Không có trên Windows.

### Cấu hình Smart Flash Cache

#### Bước 1: Tạo flash disk files (môi trường lab — giả lập SSD)

```bash
# Chạy với quyền root
dd if=/dev/zero of=/mnt/vdisk1 bs=1024 count=1024000  # 1 GB
dd if=/dev/zero of=/mnt/vdisk2 bs=1024 count=1024000
dd if=/dev/zero of=/mnt/vdisk3 bs=1024 count=1024000

chown oracle:oinstall /mnt/vdisk1
chown oracle:oinstall /mnt/vdisk2
chown oracle:oinstall /mnt/vdisk3
```

#### Bước 2: Cấu hình trong Oracle

```sql
-- Chỉ định các file/device của Flash Cache
ALTER SYSTEM SET DB_FLASH_CACHE_FILE = '/mnt/vdisk1', '/mnt/vdisk2', '/mnt/vdisk3'
SCOPE = SPFILE;

-- Chỉ định kích thước tương ứng (không có dấu nháy đơn)
ALTER SYSTEM SET DB_FLASH_CACHE_SIZE = 1G, 1G, 1G SCOPE = SPFILE;

SHUTDOWN IMMEDIATE
STARTUP
```

**Sizing guideline:** Flash Cache nên lớn hơn Buffer Cache (thường 2-3x) để có giá trị. Ví dụ: Buffer Cache = 1.2 GB → Flash Cache = 3 GB.

### Điều khiển việc Cache Object vào Flash Cache

```sql
-- KEEP: blocks của object được ghi vào Flash Cache (ưu tiên giữ lại)
ALTER TABLE SOE.ORDERS STORAGE (FLASH_CACHE KEEP);

-- NONE: blocks của object KHÔNG được ghi vào Flash Cache
ALTER TABLE SOE.ORDERS STORAGE (FLASH_CACHE NONE);

-- DEFAULT: Oracle tự quyết định
ALTER TABLE SOE.ORDERS STORAGE (FLASH_CACHE DEFAULT);

-- Để ORDERS table cache blocks vào Buffer Cache khi FTS
ALTER TABLE SOE.ORDERS CACHE;
```

### Giám sát Smart Flash Cache

#### Views quan trọng

```sql
-- 1. Thống kê cơ bản Flash Cache
SELECT NAME "Disk Name",
       BYTES/1024/1024 "Disk Size (MB)",
       SINGLEBLKRDS "Reads#",
       SINGLEBLKRDTIM_MICRO "Disk Latency (us)"
FROM V$FLASHFILESTAT;

-- 2. Wait events liên quan Flash Cache
SELECT EVENT, AVERAGE_WAIT,
       TO_CHAR(TIME_WAITED,'999,999,999') TIME_CS
FROM V$SYSTEM_EVENT
WHERE EVENT LIKE '%flash cache%';

-- 3. Blocks của ORDERS table trong Buffer Cache (và Flash Cache)
SELECT BH.STATUS, COUNT(*) BLOCKS
FROM V$BH BH, DBA_OBJECTS O
WHERE O.OBJECT_ID = BH.OBJD
  AND O.OBJECT_NAME = 'ORDERS' AND O.OWNER = 'SOE'
GROUP BY BH.STATUS;
-- STATUS values:
--   xcur  → current version block
--   scur  → shared current
--   cr    → consistent read clone
--   free  → free buffer
--   flash → block is in Flash Cache (not in Buffer Cache RAM)
```

---

## Views Tổng hợp Section 22

| View / Tool | Mục đích |
|-------------|---------|
| `V$DB_CACHE_ADVICE` | Buffer Pool Advisory — ước tính physical reads ở các sizes |
| `V$SGAINFO` | Kích thước thực tế các SGA components |
| `V$MEMORY_DYNAMIC_COMPONENTS` | Kích thước hiện tại khi AMM/ASMM bật |
| `V$SESSTAT` + `V$STATNAME` | Physical read statistics của sessions |
| `V$BH` | Buffer headers — trạng thái từng block trong buffer cache |
| `V$FLASHFILESTAT` | Thống kê Flash Cache theo file/disk |
| `V$SYSTEM_EVENT` | Wait events kể cả flash cache events |
| `DBA_ADDM_FINDINGS` | ADDM findings (kể cả buffer cache issues) |
| `DBA_ADVISOR_ACTIONS` | Actions được ADDM đề xuất |

---

## So sánh các kỹ thuật tuning Buffer Cache

| Kỹ thuật | Khi nào dùng | Tác động |
|---------|-------------|---------|
| **Tăng DB_CACHE_SIZE** | Buffer Hit% thấp, Advisory chỉ 200% vẫn chưa đủ | Tăng trực tiếp RAM cache |
| **KEEP Pool** | Bảng nhỏ hay dùng bị evict khỏi DEFAULT pool | Đảm bảo hot objects luôn trong RAM |
| **RECYCLE Pool** | Bảng lớn FTS không cần cache | Bảo vệ DEFAULT pool khỏi bị lấp đầy bởi large scans |
| **Smart Flash Cache** | Có SSD, muốn mở rộng cache giá rẻ hơn RAM | Thêm tầng cache SSD giữa RAM và HDD |

---

## Các tham số quan trọng

| Tham số | Mô tả | Mặc định |
|---------|-------|---------|
| `DB_CACHE_SIZE` | Kích thước DEFAULT buffer pool | 0 (Oracle tự tính khi AMM/ASMM) |
| `DB_KEEP_CACHE_SIZE` | Kích thước KEEP pool | 0 (không cấu hình) |
| `DB_RECYCLE_CACHE_SIZE` | Kích thước RECYCLE pool | 0 (không cấu hình) |
| `DB_FLASH_CACHE_FILE` | Path đến flash disk files | — |
| `DB_FLASH_CACHE_SIZE` | Kích thước từng flash disk | — |

---

## Tóm tắt Key Takeaways

1. **Buffer Hit% < 95%** là dấu hiệu đầu tiên của buffer cache undersized — kiểm tra trong AWR → Instance Efficiency section
2. **CBC Latch** trong top latch contention → buffer cache quá nhỏ, nhiều sessions tranh giành cùng lúc
3. **Buffer Pool Advisory** chỉ hiển thị đến 200% kích thước hiện tại → nếu vẫn chưa đủ, tăng mạnh rồi đọc lại Advisory
4. **KEEP Pool** không cần tăng tổng RAM — chỉ phân bổ lại: giảm DEFAULT, tăng KEEP — nhưng vẫn cải thiện performance cho hot small objects
5. **Smart Flash Cache** là giải pháp cost-effective khi RAM đắt: SSD rẻ hơn nhiều nhưng nhanh hơn HDD gấp 10-100x
6. Chỉ so sánh AWR reports bằng **normalized metrics** (per second, per transaction)

---

## Câu hỏi ôn tập

1. Buffer Cache Hit Ratio bình thường nên đạt bao nhiêu %? Tính như thế nào?
2. Sự khác biệt giữa DEFAULT Pool, KEEP Pool, và RECYCLE Pool là gì? Khi nào dùng từng loại?
3. View `V$DB_CACHE_ADVICE` dùng để làm gì? Cột nào quan trọng nhất khi đọc kết quả?
4. Tại sao không nên so sánh giá trị tuyệt đối giữa hai AWR reports có period length khác nhau?
5. Smart Flash Cache hoạt động ở tầng nào trong memory hierarchy? Lợi thế so với tăng RAM là gì?
6. Dùng câu lệnh SQL nào để gán table `SOE.ORDERS` vào KEEP pool? Và vào Flash Cache?
7. Khi `V$BH.STATUS = 'flash'`, block đó đang nằm ở đâu?


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/section_all/section_22_buffer_cache_flash_cache_guide.md`
