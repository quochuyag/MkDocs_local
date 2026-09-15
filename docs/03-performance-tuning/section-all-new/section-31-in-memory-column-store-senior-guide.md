---
title: 'Section 31 — In-Memory Column Store: Senior DBA Guide'
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/section_all_new/section_31_in_memory_column_store_senior_guide.md
---

# Section 31 — In-Memory Column Store: Senior DBA Guide

**Nguồn:** Practice 33 (PDF gốc) + section_all guide + Oracle internals
**Cập nhật:** 2026-07-16
**Level:** Senior DBA / Production

---

# LECTURE NOTES

## 1. Mental Model

Database In-Memory (IM) **không phải một cache bạn query riêng** — nó là kiến trúc **dual-format**: cùng một bảng tồn tại đồng thời ở HAI định dạng, được giữ nhất quán giao dịch với nhau:

```
                 ┌─────────────────────┐   ┌──────────────────────────┐
   DISK  ──────► │  Buffer Cache        │   │  In-Memory Column Store  │
  (row     nạp   │  (ROW format)        │   │  (COLUMNAR format)       │
   format)       │  → OLTP: lookup,     │   │  → Analytics: scan,      │
                 │    single-row DML    │   │    aggregate, filter     │
                 └─────────────────────┘   └──────────────────────────┘
                          ▲                            ▲
                          └──── Optimizer chọn ───────┘
                               format phù hợp/query
```

Điểm mấu chốt senior phải nắm: **optimizer tự chọn** format. Bạn không viết query khác đi. Query analytic (quét nhiều row, ít cột, aggregate) → optimizer chọn `TABLE ACCESS INMEMORY FULL`; query OLTP lookup 1 row qua PK → vẫn dùng row store/index. IM **tăng tốc scan/aggregate, không tăng tốc single-row lookup**. Dùng IM cho một bảng OLTP thuần lookup PK là lãng phí license.

IM là **transient**: dữ liệu columnar được dựng lại từ đĩa (row format) và giữ trong SGA; **không persist** — restart DB là mất, phải populate lại.

---

## 2. Internals & Mechanics

### IMCU và SMU — hai đơn vị cốt lõi

- **IMCU (In-Memory Compression Unit):** dữ liệu columnar lưu theo IMCU, mỗi IMCU phủ một dải row, chứa **một cột** ở dạng nén columnar. Scan chỉ đọc IMCU của các cột cần → bỏ qua cột không dùng (khác row format phải đọc cả row).
- **SMU (Snapshot Metadata Unit):** đi kèm mỗi IMCU, theo dõi tính nhất quán. Khi có DML, SMU ghi vào **transaction journal** rằng row nào trong IMCU đã cũ. Query đọc IMCU + đối chiếu journal để lấy phiên bản đúng, cho tới khi IMCU được **repopulate** (nền).

### 4 cơ chế tăng tốc (vì sao IM nhanh)

1. **Columnar scan:** chỉ đọc cột cần → giảm khối lượng đọc.
2. **SIMD vector processing:** một lệnh CPU xử lý nhiều giá trị cột cùng lúc → quét hàng tỷ row/giây.
3. **In-Memory Storage Index:** mỗi IMCU lưu min/max của cột → predicate lọc có thể **prune** cả IMCU không đọc (giống partition pruning nhưng ở mức IMCU).
4. **Vector aggregation + Bloom filter join:** GROUP BY / join tăng tốc bằng vector group-by và bloom filter.

### Populate là bất đồng bộ

Đánh dấu bảng INMEMORY **không** nạp ngay. Background worker `Wnnn` (kiểm soát bởi `INMEMORY_MAX_POPULATE_SERVERS`) populate segment. Thứ tự do **PRIORITY**:

| PRIORITY | Khi nào populate |
|---|---|
| `NONE` (mặc định) | Lần đầu segment bị **quét** mới trigger populate |
| `LOW→CRITICAL` | Populate ngay sau startup, theo độ ưu tiên, không cần query |

Đây là lý do Practice 33 thấy: query lần 1 (plan đã là INMEMORY FULL nhưng consistent gets/physical reads còn cao — đang populate hoặc đọc từ đĩa), lần 2 giảm nửa, lần 3 trở đi `physical reads = 0` (populate xong hoàn toàn). `V$IM_SEGMENTS.POPULATE_STATUS = COMPLETED` là mốc xác nhận.

### Compression levels — trade CPU/scan-speed vs footprint

```
MEMCOMPRESS FOR DML          — ít nén nhất, DML nhanh
             FOR QUERY LOW   — mặc định khi INMEMORY: cân bằng, scan nhanh nhất
             FOR QUERY HIGH
             FOR CAPACITY LOW
             FOR CAPACITY HIGH — nén mạnh nhất, tiết kiệm RAM, scan chậm hơn
```

Nén IM khác nén trên đĩa (Section 30): mục tiêu là **scan nhanh trên định dạng nén** (SIMD chạy thẳng trên dữ liệu nén), không chỉ tiết kiệm chỗ. Footprint IM thường **nhỏ hơn nhiều** kích thước segment trên đĩa (Practice 33: `INMEMORY_SIZE` << `SEGMENT_SIZE`).

### Dual-format nhất quán như thế nào

DML cập nhật row store (buffer cache) **ngay** như bình thường → OLTP không chờ IM. Song song, thay đổi được ghi vào transaction journal của SMU; row bị đổi trong IMCU bị đánh dấu stale. Query analytic đọc IMCU + journal (row stale lấy từ buffer cache) → luôn nhất quán. Nền, IMCU được repopulate để dọn journal. **Hệ quả:** DML nặng → journal phình → query IM phải reconcile nhiều → hiệu năng IM giảm cho tới khi repopulate.

---

## 3. Production Realities

### License — Database In-Memory Option

`INMEMORY_SIZE > 0` kích hoạt **Database In-Memory Option — tính phí riêng, rất đắt**. Chỉ cần đặt `INMEMORY_SIZE` là feature usage được ghi nhận. Kiểm `DBA_FEATURE_USAGE_STATISTICS` (feature "In-Memory Column Store"). Đừng bao giờ bật thử trên production không có license — đây là một trong những option bị audit gắt nhất.

### INMEMORY_SIZE lấy từ SGA và không co lại dễ

`INMEMORY_SIZE` là một pool **tách riêng trong SGA**, tối thiểu 100MB. Bật nó phải **tăng SGA_TARGET/SGA_MAX_SIZE** tương ứng (Practice 33: nâng SGA lên 2.5GB trước khi cấp 300MB cho IM). `INMEMORY_SIZE` **không nằm trong** vùng auto-tune của ASMM/AMM — nó là pool cố định. Tăng được động (12.2+) nhưng **giảm** thì cần restart. `INMEMORY_SIZE` yêu cầu restart để bật lần đầu.

### Không persist — cold sau restart

Sau mỗi restart, IMCS rỗng và populate lại từ đĩa. Bảng PRIORITY NONE chỉ populate khi bị quét lần đầu → **query analytic đầu tiên sau restart chậm** (đọc đĩa + populate). Muốn tránh: `PRIORITY CRITICAL/HIGH` để pre-populate lúc startup — đổi lại startup lâu hơn và tốn I/O đầu giờ.

### DML overhead — IM không "miễn phí" cho bảng ghi nặng

Bảng INMEMORY chịu DML nặng: mỗi thay đổi ghi journal + đánh dấu IMCU stale + repopulate nền tốn CPU/RAM. Trên bảng OLTP write-heavy, overhead này có thể vượt lợi ích. Chiến lược: chỉ đưa vào IM các bảng/partition **read-mostly** (ví dụ partition tháng cũ), hoặc chỉ **các cột** dùng cho analytics (`INMEMORY` cột chọn lọc, `NO INMEMORY` cột còn lại).

### IM thay thế analytic index → DML nhanh hơn

Lợi ích gián tiếp lớn: sau khi bật IM cho bảng, có thể **drop các index chỉ phục vụ báo cáo** (IM scan thay chúng). Ít index hơn → INSERT/UPDATE/DELETE nhanh hơn, bảng nhỏ hơn. Đây là lập luận ROI mạnh nhất cho IM trong mixed workload: không phải "query nhanh hơn" mà "bỏ được cả tá index analytic".

### RAC — distribute vs duplicate

Trên RAC: `INMEMORY_DISTRIBUTE` chia IMCU across node (mỗi node giữ một phần) hoặc `DUPLICATE` (nhân bản, chỉ Engineered Systems). Phân bố sai → query phải fetch IMCU qua interconnect → chậm. Cần cân nhắc affinity khi thiết kế.

---

## 4. Decision Framework

**Bật IM cho một bảng/cột khi:**
- Query analytic quét lớn + aggregate/filter trên ít cột (star schema fact, reporting table)
- Mixed workload: cùng bảng vừa OLTP vừa real-time analytics → IM bỏ được analytic index
- Có license Database In-Memory (xác nhận trước!)
- Bảng/partition read-mostly (hoặc chọn cột read-mostly)

**KHÔNG bật IM khi:**
- Bảng chỉ truy cập single-row lookup qua PK/index (IM không tăng tốc lookup)
- Bảng write-heavy toàn phần (journal churn > lợi ích)
- Không có license
- SGA không đủ để cấp INMEMORY_SIZE mà không bóp buffer cache/shared pool

**Chọn compression level:**
- Bảng có DML → `MEMCOMPRESS FOR DML`
- Analytics thuần, ưu tiên tốc độ → `FOR QUERY LOW` (mặc định)
- RAM chật, chấp nhận scan chậm hơn → `FOR CAPACITY HIGH`

**Chọn PRIORITY:**
- Cần sẵn sàng ngay sau restart → `CRITICAL/HIGH`
- Chấp nhận populate khi query đầu tiên → `NONE`

**Anti-patterns:**
- Bật INMEMORY_SIZE "để thử" trên production không license → rủi ro audit
- Đưa cả bảng OLTP write-heavy vào IM → OLTP chậm đi vì journal churn
- Kỳ vọng IM tăng tốc PK lookup → nhầm bản chất (IM cho scan/aggregate)
- Không tăng SGA khi bật IM → bóp buffer cache → OLTP degrade
- Đo lợi ích ở query lần 1 (chưa populate xong) rồi kết luận IM "không nhanh"

---

## 5. Key SQL / Commands

```sql
-- 5.1 Cau hinh (SYS, CDB root) — INMEMORY_SIZE lay tu SGA, can restart lan dau
ALTER SYSTEM SET sga_target      = 2684354560 SCOPE=SPFILE;   -- 2.5G
ALTER SYSTEM SET sga_max_size    = 2684354560 SCOPE=SPFILE;
ALTER SYSTEM SET inmemory_size   = 314572800  SCOPE=SPFILE;   -- 300M
SHUTDOWN IMMEDIATE
STARTUP

-- 5.2 Bat IM cho bang + muc nen + priority
ALTER TABLE soe.orders2 INMEMORY;                          -- mac dinh QUERY LOW, PRIORITY NONE
ALTER TABLE soe.orders2 INMEMORY MEMCOMPRESS FOR CAPACITY HIGH PRIORITY CRITICAL;
ALTER TABLE soe.orders2 INMEMORY NO INMEMORY (note1, note2);  -- loai cot khoi IM
ALTER TABLE soe.orders2 NO INMEMORY;                       -- tat IM cho bang

-- 5.3 Thuoc tinh IM cua bang
SELECT table_name, inmemory, inmemory_priority, inmemory_distribute,
       inmemory_compression, inmemory_duplicate
FROM   user_tables WHERE table_name = 'ORDERS2';

-- 5.4 Vung IM tong the (cap phat / da dung / trang thai populate)
SELECT pool, alloc_bytes/1024/1024 alloc_mb,
       used_bytes/1024/1024 used_mb, populate_status
FROM   v$inmemory_area;

-- 5.5 Segment nao da populate + footprint IM so voi segment tren dia
SELECT segment_name,
       inmemory_size/1024/1024 im_mb,
       bytes/1024/1024        segment_mb,
       ROUND(bytes/NULLIF(inmemory_size,0),1) compress_x,
       populate_status, inmemory_priority
FROM   v$im_segments;

-- 5.6 Xac nhan plan dung IM (TABLE ACCESS INMEMORY FULL)
EXPLAIN PLAN FOR
  SELECT SUM(order_total), TO_CHAR(order_date,'YYYY-MM')
  FROM   orders2 GROUP BY TO_CHAR(order_date,'YYYY-MM');
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY(NULL,NULL,'BASIC'));

-- 5.7 Kiem tra license usage TRUOC audit
SELECT name, detected_usages, currently_used, last_usage_date
FROM   dba_feature_usage_statistics
WHERE  name LIKE '%In-Memory%';
```

---

## 6. Senior Checklist

1. **Xác nhận license Database In-Memory:** `INMEMORY_SIZE>0` = phát sinh nghĩa vụ; kiểm `DBA_FEATURE_USAGE_STATISTICS` + hợp đồng; đây là option bị audit gắt
2. **Tăng SGA trước khi cấp INMEMORY_SIZE:** IM pool tách riêng, không auto-tune; bật mà không nâng SGA → bóp buffer cache/shared pool → OLTP degrade
3. **Chỉ IM cái đáng IM:** bảng/partition/cột read-mostly phục vụ analytics; đừng đưa cả bảng OLTP write-heavy vào IM (journal churn)
4. **Xác nhận đã populate trước khi đo:** `V$IM_SEGMENTS.POPULATE_STATUS=COMPLETED`; đo ở query lần đầu (đang populate) sẽ underestimate lợi ích
5. **Kiểm plan thật sự dùng IM:** `TABLE ACCESS INMEMORY FULL` trong plan; nếu vẫn `TABLE ACCESS FULL` thường → chưa populate / query không phù hợp IM / optimizer chọn khác
6. **Lường cold-start:** IM không persist; sau restart PRIORITY NONE chỉ populate khi query đầu → chậm; dùng PRIORITY cao nếu cần sẵn sàng ngay
7. **Tận dụng bỏ analytic index:** sau khi IM ổn định, drop các index chỉ phục vụ báo cáo → DML nhanh hơn (đây thường là ROI lớn nhất, không phải bản thân query)

---

# LAB EXERCISES

## Exercise 1 — Cấu hình IM và chứng minh chuyển đổi format cho query analytic

**Scenario:** Một query báo cáo doanh thu theo tháng (`SUM(order_total) GROUP BY month`) trên bảng 2M row chạy FTS từ buffer cache, chậm. Bạn được yêu cầu đánh giá Database In-Memory (đã có license thử nghiệm) xem có cải thiện không.

**Tasks:**
1. (SYS, VM, **snapshot trước**) Nâng SGA lên 2.5GB, đặt `INMEMORY_SIZE=300M` trong spfile, restart; xác nhận `V$INMEMORY_AREA` có pool.
2. (soe) Tạo `ORDERS2` ~2M row với `ORDER_DATE`, `ORDER_TOTAL`; đo baseline query analytic (plan + `consistent gets`/`physical reads`) — kỳ vọng `TABLE ACCESS FULL` từ buffer cache.
3. `ALTER TABLE ORDERS2 INMEMORY PRIORITY CRITICAL`; chờ `V$IM_SEGMENTS.POPULATE_STATUS=COMPLETED`.
4. Chạy lại query nhiều lần; ghi lại plan (`TABLE ACCESS INMEMORY FULL`) và stats qua 3 lần chạy.

**Expected Findings:**
- Baseline: `TABLE ACCESS FULL`, consistent gets/physical reads cao.
- Sau IM: plan thành `TABLE ACCESS INMEMORY FULL`; lần 1 stats còn cao (populate/đĩa), lần 2 giảm ~nửa, lần 3+ `physical reads=0`, consistent gets rất thấp.
- `V$IM_SEGMENTS`: `INMEMORY_SIZE` << `SEGMENT_SIZE` (nén columnar).

**Debrief Questions:**
- Vì sao query lần 1 sau khi bật IM chưa nhanh, lần 3 mới nhanh?
- IM lấy RAM từ đâu? Nếu không tăng SGA thì cái gì bị bóp?
- IM có tăng tốc `SELECT * FROM orders2 WHERE order_id = :x` không? Vì sao?

---

## Exercise 2 — Compression Level, Column Subset, và IM thay thế Index

**Scenario:** RAM cho IM có hạn (300MB). Bảng `ORDERS2` có cột `NOTE` lớn ít dùng cho báo cáo. Bạn cần fit bảng vào IM một cách tiết kiệm và đánh giá việc bỏ analytic index.

**Tasks:**
1. So `INMEMORY_SIZE` của bảng với `MEMCOMPRESS FOR QUERY LOW` vs `FOR CAPACITY HIGH` (dùng `V$IM_SEGMENTS`).
2. Loại cột lớn khỏi IM: `ALTER TABLE ORDERS2 INMEMORY NO INMEMORY (note...)`; đo lại footprint.
3. Tạo một index analytic trên `ORDER_DATE`; chạy query aggregate, xem optimizer chọn index hay IM.
4. Lập luận: sau khi IM phục vụ query này, có nên drop index đó không? Đo tác động lên tốc độ INSERT.

**Expected Findings:**
- `CAPACITY HIGH` nén mạnh hơn (footprint nhỏ hơn) nhưng scan tốn CPU hơn.
- Loại cột lớn khỏi IM → footprint giảm rõ; query analytic không cần cột đó vẫn nhanh.
- Với IM populated, optimizer thường chọn INMEMORY FULL thay vì index range scan cho aggregate → index analytic trở nên thừa.

**Debrief Questions:**
- Đánh đổi giữa `QUERY LOW` và `CAPACITY HIGH` là gì? Khi nào chọn cái nào?
- Vì sao "bỏ được analytic index" thường là ROI lớn hơn cả tốc độ query?
- Loại cột khỏi IM có ảnh hưởng gì nếu sau này báo cáo cần cột đó?

---

## Exercise 3 — Troubleshooting Scenario (Expert Level)

**Incident Brief:**
Sau khi bật Database In-Memory cho `SALES_FACT` (partition theo tháng) tuần trước, team báo: (a) dashboard analytic buổi sáng **chậm hơn trước** trong ~15 phút đầu mỗi ngày rồi mới nhanh; (b) job ETL đêm ghi vào partition tháng hiện tại **chậm đi 25%**; (c) thỉnh thoảng cùng một dashboard query lúc nhanh lúc chậm trong ngày. DBA đã bật IM với `PRIORITY NONE` cho toàn bộ bảng, `MEMCOMPRESS FOR QUERY LOW`, và giữ nguyên tất cả index cũ.

**Evidence Provided:**

`V$IM_SEGMENTS` (sáng, sau restart hằng đêm lúc 02:00):
```
SEGMENT_NAME       PARTITION      POPULATE_STATUS   INMEMORY_PRIORITY  IM_MB   SEG_MB
-----------------  -------------  ----------------  -----------------  ------  ------
SALES_FACT         SALES_2026_01  COMPLETED         NONE                 120     980
SALES_FACT         SALES_2026_06  STARTED           NONE                  40     990   ← dang populate
SALES_FACT         SALES_2026_07  INMEMORY (partial) NONE                 12     995   ← thang hien tai
```

`V$INMEMORY_AREA`:
```
POOL           ALLOC_MB   USED_MB   POPULATE_STATUS
1MB POOL          256        250     POPULATING
64KB POOL          44         30     DONE
```

AWR Top Timed Events (ETL window, sau khi bật IM):
```
Event                        Time(s)   %DB Time
IM populate                     412      18%
db file sequential read         180       8%
DB CPU                          620      27%
```

`USER_INDEXES` trên SALES_FACT: 6 index, trong đó 3 index chỉ xuất hiện trong query báo cáo (không dùng bởi OLTP/ETL).

**Your Mission:**
1. Triệu chứng (a) — dashboard chậm 15 phút đầu ngày. Nguyên nhân gốc? Liên hệ `PRIORITY NONE` + restart 02:00 + `POPULATE_STATUS`.
2. Triệu chứng (b) — ETL chậm 25%. IM có liên quan không? Đọc AWR + việc IM cho **partition hiện tại đang bị ghi**.
3. Triệu chứng (c) — cùng query lúc nhanh lúc chậm. Giải thích qua populate trạng thái + journal DML.
4. `USED_MB=250/256` — vùng IM gần đầy. Điều này gây rủi ro gì cho các partition chưa populate?
5. Đề xuất cấu hình lại toàn diện: PRIORITY, phạm vi partition đưa vào IM, compression, và xử lý 3 index báo cáo.

**Evaluation Criteria:**
- (a) `PRIORITY NONE` nghĩa là partition chỉ populate khi bị **quét lần đầu** sau restart 02:00; dashboard sáng là scan đầu tiên → phải chờ populate (thấy `STARTED`/`partial`) → chậm 15 phút cho tới `COMPLETED`. Fix: `PRIORITY HIGH/CRITICAL` cho partition tháng gần để pre-populate lúc startup.
- (b) ETL ghi vào `SALES_2026_07` **đang trong IM** → mỗi DML sinh journal + đánh dấu IMCU stale + repopulate nền (`IM populate 18%` trong AWR) → CPU/I/O tăng → ETL chậm. Fix: **KHÔNG** đưa partition tháng hiện tại (write-heavy) vào IM; chỉ IM các partition tháng cũ read-mostly.
- (c) Query trúng partition đang populate (`STARTED`) hoặc partition có nhiều journal DML chưa repopulate → phải reconcile từ buffer cache → chậm; khi populate/repopulate xong → nhanh. Tính "lúc nhanh lúc chậm" phản ánh trạng thái populate/journal biến động.
- (d) `USED 250/256MB` gần đầy → partition mới (2026_06 đang STARTED) có thể **không đủ chỗ** → populate dừng ở partial, hoặc Oracle evict theo priority → các partition không bao giờ populate đủ → query không ổn định. Cần tăng `INMEMORY_SIZE` hoặc giảm phạm vi/nén mạnh hơn.
- Cấu hình lại: (1) chỉ INMEMORY các partition tháng cũ (read-mostly) với `PRIORITY HIGH`; loại partition tháng hiện tại; (2) partition rất cũ ít query → `MEMCOMPRESS FOR CAPACITY HIGH` tiết kiệm RAM; (3) tăng `INMEMORY_SIZE` nếu cần fit; (4) **drop 3 index báo cáo** (IM thay thế) → ETL/OLTP nhanh hơn — giải quyết một phần triệu chứng (b) ngay cả khi chưa đụng IM.
- **Bonus:** chỉ ra IM không persist → mọi restart lặp lại vấn đề cold-start → PRIORITY là bắt buộc, không optional; và cảnh báo license Database In-Memory phải có cho production.


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/section_all_new/section_31_in_memory_column_store_senior_guide.md`
