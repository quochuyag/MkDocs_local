---
title: 'Section 29 — Table Fragmentation: Senior DBA Guide'
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/section_all_new/section_29_table_fragmentation_senior_guide.md
---

# Section 29 — Table Fragmentation: Senior DBA Guide

**Nguồn:** Practice 31 (PDF gốc) + section_all guide + Oracle internals
**Cập nhật:** 2026-07-16
**Level:** Senior DBA / Production

---

# LECTURE NOTES

## 1. Mental Model

Table fragmentation là bài toán về **High Water Mark (HWM)**, không phải về "block rỗng". Nhiều DBA nghĩ fragmentation nghĩa là "block có nhiều holes sau DELETE" — đúng một nửa. Vấn đề thật sự trên production là: **Full Table Scan luôn đọc tới HWM**, bất kể block đó còn row hay đã rỗng sạch.

```
Segment:  [====== rows ======][ block rỗng ][ rỗng ][ rỗng ]│ HWM
                                                            ▲
FTS đọc từ block đầu đến ĐÂY ────────────────────────────────┘
          (dù nửa sau không còn 1 row nào)
```

Khi bạn DELETE 50% rows rải khắp bảng, HWM **không tự hạ**. FTS vẫn quét đúng số block như lúc bảng đầy → `session logical reads` không đổi dù bảng chỉ còn nửa dữ liệu. Đây là lý do fragmentation **chỉ phạt FTS**, gần như không phạt index unique lookup (index đi thẳng tới rowid, không quét khoảng rỗng).

Câu hỏi đúng khi nghi fragmentation: **"Có bao nhiêu block dưới HWM thực sự còn chứa row?"** — không phải "AVG_SPACE có cao không?".

---

## 2. Internals & Mechanics

### High Water Mark và hai loại của nó (ASSM)

HWM là ranh giới "block cao nhất đã từng được dùng" của segment. Trong tablespace **ASSM** (Automatic Segment Space Management — mặc định từ 10g) có hai mốc:

- **LHWM (Low HWM):** dưới mốc này *mọi* block đã được format và từng chứa data.
- **HHWM (High HWM):** trên mốc này chưa block nào được dùng.
- Giữa LHWM và HHWM: vùng "xám" — một số block đã format, một số chưa.

FTS quét tới HHWM. DELETE giải phóng row nhưng **không kéo HWM xuống**. Chỉ ba thao tác hạ được HWM: `TRUNCATE`, `ALTER TABLE MOVE`, và `ALTER TABLE SHRINK SPACE`.

### SHRINK SPACE — ba pha thực chất

```
ALTER TABLE t SHRINK SPACE CASCADE;
```

1. **Compact (pha 1):** Oracle đọc row từ các block cuối segment, chèn lại vào block trống phía đầu (dưới LHWM), xóa row ở vị trí cũ. Đây là chuỗi INSERT+DELETE nội bộ → **sinh undo/redo**, và vì row đổi chỗ nên **ROWID đổi** → bắt buộc `ENABLE ROW MOVEMENT`. Pha này **online**, chỉ khóa từng row đang di chuyển (row-level).
2. **HWM adjustment (pha 2):** hạ HWM xuống, trả các extent trống về tablespace. Cần một **exclusive lock rất ngắn** trên segment ở cuối pha.
3. **CASCADE:** áp dụng shrink cho các dependent object (chủ yếu index) trong cùng lệnh. Không có CASCADE thì index vẫn valid (shrink maintain index tự động, khác `MOVE`) nhưng không được compact.

### Vì sao index KHÔNG UNUSABLE sau SHRINK (khác MOVE)

`ALTER TABLE MOVE` viết lại toàn bộ segment một lần → mọi ROWID đổi đồng loạt → Oracle bỏ mark global index thành UNUSABLE. `SHRINK SPACE` di chuyển row **từng phần và maintain index đồng thời** trong pha compact → index luôn ở trạng thái valid. Đây là khác biệt kiến trúc quyết định vì sao SHRINK là lựa chọn online, MOVE thì không.

### AVG_SPACE và cái bẫy của ANALYZE

`USER_TABLES.AVG_SPACE` = trung bình byte trống mỗi block, **chỉ populate bởi `ANALYZE TABLE ... COMPUTE/ESTIMATE STATISTICS`** — không phải `DBMS_STATS`. Giống Section 27/28: `DBMS_STATS` (chuẩn cho optimizer) để `AVG_SPACE` = NULL. Nên trên production, muốn đo fragmentation bằng AVG_SPACE bạn buộc phải ANALYZE (deprecated cho optimizer stats) rồi gather lại bằng DBMS_STATS ngay sau đó.

Cách hiện đại hơn (không đụng optimizer stats, không lock): so sánh **số block thực sự chứa row** với **số block dưới HWM**:

```
actual_blocks = ceil(num_rows * avg_row_len / usable_block_space)
hwm_blocks    = DBA_SEGMENTS.blocks (hoặc USER_TABLES.blocks sau gather)
frag% ≈ (1 - actual_blocks / hwm_blocks) * 100
```

Hoặc dùng `DBMS_SPACE.SPACE_USAGE` (ASSM) để lấy phân bố block theo mức đầy (FS1/FS2/FS3/FS4/FULL) — không cần ANALYZE.

### ENABLE ROW MOVEMENT thất bại khi bảng đang DML

`ALTER TABLE ... ENABLE ROW MOVEMENT` là DDL → cần lock **exclusive DDL** ngắn trên bảng, phải chờ mọi transaction đang mở đóng lại. Một vòng lặp UPDATE liên tục (commit thưa) giữ transaction mở gần như liên tục → DDL không lấy được lock → `ORA-00054: resource busy`. Đây chính xác là điều Practice 31 minh họa (bước 12: lệnh lỗi khi `update_cust` đang chạy).

---

## 3. Production Realities

### Fragmentation là triệu chứng, không phải bệnh

Bảng bị fragment vì một **pattern DML**: bulk delete định kỳ (purge dữ liệu cũ), hoặc UPDATE làm row co lại (set cột lớn về NULL). SHRINK dọn hậu quả, nhưng nếu pattern lặp lại thì tuần sau bảng lại fragment. Senior phải hỏi: *pattern này có tái diễn không?* Nếu có → cân nhắc partitioning (drop partition thay vì delete + shrink), hoặc lịch shrink định kỳ, thay vì shrink một lần rồi quên.

### SHRINK sinh redo/undo — không "miễn phí"

Vì pha compact là chuỗi INSERT+DELETE nội bộ, shrink một bảng lớn có thể sinh **redo bằng cỡ dữ liệu di chuyển**. Trên Data Guard, lượng redo này phải truyền sang standby. Shrink bảng 50GB lúc cao điểm có thể làm nghẽn redo transport. Lên lịch off-peak và cân nhắc tách hai pha:

```sql
ALTER TABLE t SHRINK SPACE COMPACT;   -- pha 1, online, chạy giờ cao điểm
-- ... off-peak:
ALTER TABLE t SHRINK SPACE;           -- pha 2, hạ HWM (lock ngắn)
```

### CASCADE không đụng index bị vô hiệu hóa bởi lý do khác

`SHRINK SPACE CASCADE` maintain index của chính bảng, nhưng nếu có function-based index, domain index (Text/Spatial), hay bitmap join index, hành vi có thể khác — `[⚠️ verify with MOS]` cho từng loại trước khi chạy production. Ngoài ra CASCADE **không** shrink LOB segment; LOB cần `SHRINK SPACE` riêng trên cột LOB.

### Bảng có LONG, hoặc bảng trong cluster → không shrink được

`SHRINK SPACE` yêu cầu segment nằm trong tablespace ASSM và không thuộc các loại bị loại trừ: bảng có cột `LONG`, bảng cluster, bảng có materialized view log dạng ROWID, IOT overflow trong vài trường hợp. Với các bảng này, phương án là `ALTER TABLE MOVE` (cần window) hoặc online redefinition.

### Đo bằng logical reads, không bằng thời gian

Practice đo `session logical reads` trước/sau — đây là metric đúng vì nó không phụ thuộc cache nóng/lạnh. Nếu bạn đo bằng wall-clock, lần chạy sau (cache đã ấm) luôn nhanh hơn *bất kể* shrink có tác dụng hay không → dễ kết luận sai. Luôn so logical reads.

---

## 4. Decision Framework

**Khi nào SHRINK SPACE:**
- Tablespace ASSM, bảng không nằm trong danh sách loại trừ
- FTS là access path chính của bảng (fragmentation phạt FTS)
- Fragmentation xác nhận (frag% > ~25-30%, nhiều block dưới HWM rỗng)
- Cần giữ online (bảng 24x7) → SHRINK thắng MOVE

**Khi nào ALTER TABLE MOVE:**
- Có maintenance window
- Cần đổi tablespace / storage attribute cùng lúc
- Bảng có LONG / không shrink được
- Chấp nhận rebuild index sau (hoặc dùng `MOVE ONLINE` 12.2+)

**Khi nào TRUNCATE:**
- Xóa toàn bộ và nạp lại (staging/ETL table) → HWM về 0 tức thì, không undo

**Khi nào KHÔNG làm gì:**
- Bảng chủ yếu truy cập qua index unique lookup → fragmentation gần như không phạt
- Bảng sẽ được INSERT đầy lại ngay (space rỗng sẽ tái dùng — HWM không phải vấn đề)

**Anti-patterns:**
- Shrink định kỳ mọi bảng không có bằng chứng FTS/fragmentation — tốn redo, vô ích
- Dùng wall-clock để "chứng minh" shrink có tác dụng — cache làm nhiễu; dùng logical reads
- Quên gather lại DBMS_STATS sau khi ANALYZE để đo AVG_SPACE → optimizer dùng stats cũ do ANALYZE
- Chạy `ENABLE ROW MOVEMENT` rồi để đó — row movement bật vĩnh viễn cho phép Oracle di chuyển row (ví dụ partition update) ngoài ý muốn; cân nhắc tắt lại nếu không cần

---

## 5. Key SQL / Commands

```sql
-- 5.1 Fragmentation qua ANALYZE (AVG_SPACE) — cách của course
ANALYZE TABLE soe.cust COMPUTE STATISTICS;
SELECT blocks,
       blocks * 8192 / 1024                    total_kb,
       avg_space,
       ROUND(blocks * avg_space / 1024, 2)     free_kb,
       ROUND(blocks * avg_space / (blocks*8192) * 100, 1) frag_pct
FROM   user_tables WHERE table_name = 'CUST';
-- Nho: gather lai bang DBMS_STATS sau do de tra optimizer stats chuan

-- 5.2 Fragmentation KHONG can ANALYZE (DBMS_SPACE.SPACE_USAGE, ASSM)
SET SERVEROUTPUT ON
DECLARE
  v_unf NUMBER; v_unfb NUMBER; v_fs1 NUMBER; v_fs1b NUMBER;
  v_fs2 NUMBER; v_fs2b NUMBER; v_fs3 NUMBER; v_fs3b NUMBER;
  v_fs4 NUMBER; v_fs4b NUMBER; v_full NUMBER; v_fullb NUMBER;
BEGIN
  DBMS_SPACE.SPACE_USAGE('SOE','CUST','TABLE',
    v_unf,v_unfb, v_fs1,v_fs1b, v_fs2,v_fs2b,
    v_fs3,v_fs3b, v_fs4,v_fs4b, v_full,v_fullb);
  DBMS_OUTPUT.PUT_LINE('FULL blocks (75-100%% used): '||v_full);
  DBMS_OUTPUT.PUT_LINE('FS1  blocks (0-25%% used)  : '||v_fs1);
  DBMS_OUTPUT.PUT_LINE('Unformatted              : '||v_unf);
END;
/

-- 5.3 So sanh actual_blocks vs HWM blocks
SELECT t.table_name, t.num_rows, t.avg_row_len,
       t.blocks                                              hwm_blocks,
       CEIL(t.num_rows * t.avg_row_len / (8192*0.9))         est_actual_blocks,
       ROUND((1 - CEIL(t.num_rows*t.avg_row_len/(8192*0.9))
              / NULLIF(t.blocks,0)) * 100, 1)                frag_pct
FROM   user_tables t WHERE table_name = 'CUST';

-- 5.4 Shrink online (3 pha)
ALTER TABLE soe.cust ENABLE ROW MOVEMENT;
ALTER TABLE soe.cust SHRINK SPACE CASCADE;      -- compact + HWM + indexes
-- Tach 2 pha khi can:
-- ALTER TABLE soe.cust SHRINK SPACE COMPACT;    -- pha 1 (online, gio cao diem)
-- ALTER TABLE soe.cust SHRINK SPACE;            -- pha 2 (ha HWM, lock ngan)

-- 5.5 Do impact FTS truoc/sau (logical reads — khong dung wall-clock)
-- (lab dung _toolkit/before_after.sql; day la ban rut gon)
SELECT value FROM v$mystat s JOIN v$statname n ON n.statistic#=s.statistic#
WHERE  n.name = 'session logical reads';

-- 5.6 Ai dang giu transaction mo khien ENABLE ROW MOVEMENT loi ORA-00054
SELECT s.sid, s.serial#, s.username, s.module, t.status, t.used_ublk
FROM   v$transaction t JOIN v$session s ON s.taddr = t.addr;
```

---

## 6. Senior Checklist

1. **Xác nhận fragmentation phạt FTS thật:** access path chính của bảng có phải FTS/scan không? Nếu chỉ index unique lookup → shrink gần như vô ích
2. **Đo bằng logical reads, không wall-clock:** cache nóng/lạnh làm nhiễu thời gian; `session logical reads` là bằng chứng khách quan trước/sau
3. **AVG_SPACE cần ANALYZE, không DBMS_STATS:** nếu dùng ANALYZE để đo → gather lại DBMS_STATS ngay sau để không bỏ optimizer stats kiểu cũ trên bảng
4. **Kiểm tra bảng có shrink được không:** tablespace ASSM? có cột LONG / cluster / loại bị loại trừ? nếu không → MOVE hoặc redefinition
5. **Lường trước redo:** shrink = INSERT+DELETE nội bộ, sinh redo cỡ dữ liệu di chuyển; bảng lớn → off-peak, cân nhắc tách COMPACT/HWM, chú ý Data Guard
6. **Xử lý concurrent DML:** `ENABLE ROW MOVEMENT` và pha HWM cần DDL lock ngắn → ORA-00054 nếu bảng đang DML liên tục; có kế hoạch quiesce ngắn hoặc chọn cửa sổ ít DML
7. **Truy nguồn gốc pattern:** DELETE/UPDATE gì gây fragment? có tái diễn? nếu purge định kỳ → cân nhắc partitioning (drop partition) thay vì shrink lặp lại

---

# LAB EXERCISES

## Exercise 1 — Chứng minh Fragmentation chỉ phạt FTS, không phạt Index Lookup

**Scenario:** Một bảng `CUST` bị DELETE ~33% và UPDATE co row ~50% qua nhiều tháng. Team app phàn nàn "report chạy chậm" (report dùng FTS) nhưng "màn hình tra cứu khách theo ID vẫn nhanh" (index unique lookup). Bạn cần chứng minh bằng số vì sao hai access path phản ứng khác nhau với cùng một bảng fragment.

**Tasks:**
1. Tạo `CUST` fragment (INSERT 100k, UPDATE chẵn co row, DELETE bội-3) như Practice 31; giữ cả index unique trên `CUSTOMER_NO`.
2. Đo `session logical reads` cho một workload **FTS** (query trên cột không index) 1000 lần.
3. Đo `session logical reads` cho một workload **index unique lookup** (query trên `CUSTOMER_NO` có index) 1000 lần.
4. SHRINK SPACE CASCADE, rồi lặp lại cả hai phép đo.

**Expected Findings:**
- Trước shrink: FTS đọc rất nhiều block (tới HWM); index lookup đọc ~vài block/query bất kể fragment.
- Sau shrink: FTS logical reads **giảm mạnh** (HWM hạ); index lookup **gần như không đổi**.
- Kết luận: fragmentation là bài toán HWM → chỉ phạt access path quét (FTS).

**Debrief Questions:**
- Vì sao index unique lookup miễn nhiễm với HWM cao?
- Nếu bảng chỉ được truy cập qua index, con số nào biện minh cho việc **không** shrink?
- `session logical reads` hay wall-clock — cái nào là bằng chứng đúng, và vì sao?

---

## Exercise 2 — SHRINK Online dưới tải DML: xử lý ORA-00054

**Scenario:** Bảng `CUST` 24x7 đang bị một batch UPDATE liên tục (commit mỗi vài update). Bạn phải shrink nó mà không dừng batch — nhưng `ENABLE ROW MOVEMENT` cứ báo `ORA-00054: resource busy`.

**Tasks:**
1. Từ session 2, chạy vòng lặp UPDATE liên tục lên `CUST` (mô phỏng batch).
2. Từ session 1, thử `ALTER TABLE CUST ENABLE ROW MOVEMENT` → quan sát ORA-00054.
3. Dùng `V$TRANSACTION` + `V$SESSION` tìm session đang giữ transaction mở.
4. Thử hai cách: (a) `ALTER TABLE ... ENABLE ROW MOVEMENT` với `DDL_LOCK_TIMEOUT` đặt trước; (b) tạm dừng batch để lấy lock, rồi bật row movement và `SHRINK SPACE COMPACT` (pha 1 online) trong khi batch chạy lại.
5. Chứng minh pha COMPACT chạy song song với DML; pha HWM (`SHRINK SPACE`) mới cần lock ngắn.

**Expected Findings:**
- `ENABLE ROW MOVEMENT` (DDL) không lấy được lock khi transaction mở → ORA-00054.
- Đặt `ALTER SESSION SET DDL_LOCK_TIMEOUT = 30` khiến DDL **chờ** thay vì fail ngay.
- `SHRINK SPACE COMPACT` tiến triển cùng lúc batch UPDATE chạy (row-level lock).
- Pha hạ HWM cần một khoảnh khắc exclusive → có thể vẫn vướng nếu DML quá dày.

**Debrief Questions:**
- `DDL_LOCK_TIMEOUT` giải quyết gốc rễ hay chỉ hoãn vấn đề?
- Vì sao COMPACT online được nhưng hạ HWM thì không hoàn toàn online?
- Trên bảng thật sự 24x7 không thể dừng DML, chiến lược nào an toàn hơn shrink?

---

## Exercise 3 — Troubleshooting Scenario (Expert Level)

**Incident Brief:**
Thứ Hai 08:30. Report tài chính `MONTHLY_REVENUE` (FTS trên `SALES_ARCHIVE`) sáng nay chạy 22 phút, tháng trước chạy 6 phút. Không có thay đổi code, không có tăng trưởng dữ liệu — thực tế `SALES_ARCHIVE` **giảm** số row tháng này vì team vừa purge 40% dữ liệu 2019 cuối tuần. On-call DBA đề xuất "gather stats lại rồi chạy lại". Bạn được gọi cho ý kiến hai.

**Evidence Provided:**

AWR SQL ordered by Physical Reads (report window):
```
SQL_ID        Reads      Execs  Reads/Exec  Module
------------- ---------- -----  ----------  ----------------
7xk2p9mnza01  4,812,006     1   4,812,006   MONTHLY_REVENUE
```

Segment/space snapshot của SALES_ARCHIVE:
```
NUM_ROWS (sau purge)      : 3,100,000   (thang truoc: 5,150,000)
BLOCKS (USER_TABLES/HWM)  : 61,400      (thang truoc: 61,400)  ← khong doi
AVG_ROW_LEN               : 118
Tablespace segment mgmt   : AUTO (ASSM)
Cot LONG?                 : khong
```

DBMS_SPACE.SPACE_USAGE trên SALES_ARCHIVE:
```
FULL blocks       : 22,900
FS1 (0-25% used)  : 31,800   ← rat nhieu block gan rong
FS2/FS3/FS4       : 6,100
Unformatted       : 600
```

`ANALYZE ... COMPUTE` (chạy ngoài giờ):
```
AVG_SPACE : 5,980   (block 8192)  → ~73% moi block la free
```

**Your Mission:**
1. On-call muốn gather stats. Điều đó có sửa được thời gian report không? Vì sao có/không?
2. Đọc bằng chứng: xác định chính xác nguyên nhân report chậm gấp ~3.6 lần dù dữ liệu **giảm**.
3. `BLOCKS` không đổi (61,400) dù purge 40% — điều này nói lên cơ chế gì? Liên hệ FTS.
4. Đề xuất fix cụ thể + thứ tự thực hiện; ước lượng report sẽ đọc bao nhiêu block sau fix.
5. Purge 40% là thao tác định kỳ hàng năm. Đề xuất thay đổi kiến trúc để năm sau không tái diễn.

**Evaluation Criteria:**
- Nhận ra gather stats **không** sửa được: fragmentation là vấn đề HWM/space, không phải bad plan; FTS vẫn quét 61,400 block dù stats mới; gather chỉ giúp CBO chọn plan, mà report đã là FTS đúng bản chất.
- Xác định root cause: purge để lại HWM ở 61,400 block, 31,800 block giờ ở FS1 (gần rỗng) → FTS vẫn đọc đủ 61,400 block cho chỉ 3.1M row → logical/physical reads cao → chậm.
- Giải thích BLOCKS không đổi: DELETE không hạ HWM; chỉ TRUNCATE/MOVE/SHRINK mới hạ → đây là bằng chứng cốt lõi rằng cần shrink.
- Fix đúng: `ENABLE ROW MOVEMENT` + `SHRINK SPACE CASCADE` (off-peak, lường redo), sau đó gather DBMS_STATS; ước lượng sau shrink actual_blocks ≈ CEIL(3.1M×118/(8192×0.9)) ≈ 49,600 → thực tế ~ số FULL blocks + phần gộp, giảm rõ; FTS đọc ~ nửa số block cũ.
- Kiến trúc: `SALES_ARCHIVE` nên **range-partition theo năm** → purge = `DROP/TRUNCATE PARTITION` (hạ space tức thì, không undo, không cần shrink); hoặc lịch shrink ngay sau purge hàng năm.
- **Bonus:** chỉ ra rủi ro redo/Data Guard khi shrink 60k block một lần; đề xuất `SHRINK SPACE COMPACT` trước (giờ làm việc) rồi hạ HWM off-peak; và cảnh báo ROW MOVEMENT bật vĩnh viễn nên đánh giá tác động.


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/section_all_new/section_29_table_fragmentation_senior_guide.md`
