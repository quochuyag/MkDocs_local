---
title: 'Section 30 — Table Compression: Senior DBA Guide'
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/section_all_new/section_30_table_compression_senior_guide.md
---

# Section 30 — Table Compression: Senior DBA Guide

**Nguồn:** Practice 32 (PDF gốc) + section_all guide + Oracle internals
**Cập nhật:** 2026-07-16
**Level:** Senior DBA / Production

---

# LECTURE NOTES

## 1. Mental Model

Table compression của Oracle là **de-duplication ở cấp block**, không phải nén kiểu zip toàn bảng. Mỗi data block tự chứa một **symbol table** (bảng ký hiệu) ở đầu block: các giá trị lặp lại trong block được lưu một lần trong symbol table, còn mỗi row chỉ giữ con trỏ ngắn tới ký hiệu đó. Hệ quả kéo theo mọi quyết định:

- Compression ratio phụ thuộc **độ lặp của dữ liệu TRONG cùng một block** — không phải trong toàn bảng. Dữ liệu ngẫu nhiên/unique → gần như không nén được. Dữ liệu lặp nhiều → nén tốt.
- Sắp xếp dữ liệu để gom giá trị giống nhau vào cùng block **làm tăng ratio** (load kèm `ORDER BY` cột lặp nhiều).
- Nén xảy ra **khi block đầy tới ngưỡng**, không phải từng row — nên cơ chế nạp dữ liệu quyết định có nén hay không.

Hai câu hỏi senior phải trả lời trước khi bật compression: (1) *Dữ liệu có lặp đủ để nén không?* (2) *Bảng được nạp/sửa bằng cách nào — direct path hay conventional DML?* Câu 2 quyết định giữa Basic (miễn phí) và Advanced (có phí license).

---

## 2. Internals & Mechanics

### Symbol Table cấp block

```
Data block (compressed):
┌─────────────────────────────────────┐
│ Block header                        │
│ Symbol table: [0]="XXXXXX" [1]="CA" │  ← giá trị lặp lưu 1 lần
│ Row1: cust=1  note1→[0]  state→[1]  │  ← row tham chiếu ký hiệu
│ Row2: cust=2  note1→[0]  state→[1]  │
│ ...                                  │
└─────────────────────────────────────┘
```

Vì symbol table nằm **trong** block, giải nén không cần đọc block khác — mỗi block tự đủ. FTS trên bảng nén đọc **ít block hơn** (dữ liệu dày hơn) nhưng tốn thêm CPU giải nén. Với workload scan-heavy, tiết kiệm I/O thường thắng chi phí CPU.

### Basic vs Advanced — khác biệt cốt lõi: khi nào block được nén

| | ROW STORE COMPRESS BASIC | ROW STORE COMPRESS ADVANCED (OLTP) |
|---|---|---|
| Nén khi conventional INSERT | **KHÔNG** | **CÓ** (batched) |
| Nén khi direct-path load (APPEND/CTAS/SQL*Loader direct) | CÓ | CÓ |
| Nén khi UPDATE | không (row thành uncompressed) | có (batched, khi block đầy lại) |
| PCTFREE mặc định | 0 | 10 |
| License | Miễn phí (kèm EE) | **Advanced Compression Option — có phí riêng** |

**Basic** chỉ nén ở thời điểm bulk load: block được xây đầy một lần rồi nén. Conventional INSERT chèn từng row → block không bao giờ qua bước nén → dữ liệu nằm **uncompressed** dù bảng khai báo COMPRESS BASIC. Đây là bẫy lớn nhất: khai báo compress không có nghĩa dữ liệu được nén.

**Advanced (OLTP)** dùng cơ chế nén **batched, amortized**: block nạp uncompressed qua conventional DML cho tới khi đầy tới ngưỡng, lúc đó Oracle nén cả block một lần (chi phí nén chia đều cho nhiều row → không phạt từng INSERT). Vì vậy Advanced nén được cả dữ liệu vào bằng INSERT thường.

### Direct-path load nhanh HƠN trên bảng nén (nghịch lý)

Practice đo: nạp T3 (APPEND + compress) **nhanh hơn ~70%** so với T1 (nocompress) và T2 (compress + conventional). Lý do: direct-path ghi thẳng block đầy phía trên HWM, không qua buffer cache, không sinh nhiều undo; block nén chứa nhiều row hơn → **ít block phải ghi ra đĩa hơn** → I/O ghi ít hơn. Chi phí CPU nén nhỏ hơn chi phí I/O tiết kiệm được. Nghịch lý "nén mà lại nhanh hơn" chỉ đúng với direct-path; conventional INSERT trên bảng nén (T2) không có lợi thế này.

### UPDATE làm hỏng compression theo thời gian

Row nén khi bị UPDATE lớn hơn có thể không vừa symbol table cũ → Oracle lưu row ở dạng uncompressed hoặc migrate (Section 28). Bảng nén basic chịu nhiều UPDATE sẽ **phình dần** và mất tỷ lệ nén. Advanced xử lý tốt hơn (re-compress block khi đầy) nhưng vẫn suy giảm. Đây là lý do compression hợp với bảng **read-mostly / append-mostly**, không hợp bảng OLTP update nặng (trừ khi có Advanced và chấp nhận overhead).

### HCC — ranh giới phần cứng

Hybrid Columnar Compression (COMPRESS FOR QUERY/ARCHIVE) đạt ratio 10-50x nhưng **chỉ chạy trên Exadata, ZFS Storage Appliance, hoặc Pillar Axiom** — không có trên VM/storage thường. Đừng nhầm HCC với Advanced (OLTP) compression. Trên môi trường non-Exadata, khai báo HCC sẽ báo lỗi hoặc bị bỏ qua.

---

## 3. Production Realities

### Bẫy license Advanced Compression

`ROW STORE COMPRESS ADVANCED` **chạy được** trên EE mà không bị phần mềm chặn — nhưng nó thuộc **Advanced Compression Option, tính phí riêng**. Một DBA vô tình bật nó trên production → audit license của Oracle phát hiện → phạt phí hồi tố. Luôn kiểm tra `DBA_FEATURE_USAGE_STATISTICS` (feature "Advanced Compression") trước khi khai báo ADVANCED, và xác nhận hợp đồng license. Basic compression **miễn phí** với EE — an toàn về license.

### "Bật compress" không có nghĩa dữ liệu đã nén

`ALTER TABLE t COMPRESS` chỉ đặt thuộc tính cho **dữ liệu tương lai nạp bằng direct-path** (với basic). Dữ liệu đang có **không** được nén cho tới khi bạn `ALTER TABLE t MOVE` (rewrite) hoặc reload. Kiểm tra `DBA_TABLES.COMPRESSION='ENABLED'` chỉ cho biết thuộc tính, không cho biết dữ liệu thực sự nén. Muốn biết dữ liệu đã nén chưa, so sánh BLOCKS trước/sau hoặc dùng `DBMS_COMPRESSION.GET_COMPRESSION_RATIO`.

### Ước lượng ratio TRƯỚC khi commit tài nguyên

`DBMS_COMPRESSION.GET_COMPRESSION_RATIO` lấy mẫu bảng và ước lượng ratio cho từng kiểu compression **mà không cần** nén thật cả bảng. Chạy nó trước để quyết định có đáng nén không — tránh `ALTER TABLE MOVE COMPRESS` một bảng 500GB rồi phát hiện ratio chỉ 1.1x (dữ liệu unique).

### Compression tương tác với các tính năng khác

- `MOVE ... COMPRESS` làm index UNUSABLE (như Section 26/27) → cần rebuild hoặc `MOVE ONLINE`.
- Bảng nén + partitioning: có thể nén per-partition (nén partition cũ archive, để partition hiện tại nocompress) — chiến lược ILM (Information Lifecycle Management) kinh điển.
- Bảng nén không tương thích một số thao tác: thêm cột có default trên basic-compressed table (phiên bản cũ), một số kiểu DDL — `[⚠️ verify with MOS]` theo phiên bản.

### CPU vs I/O trade-off phải đo, không đoán

Compression đổi I/O lấy CPU. Trên hệ thống **I/O-bound** (scan nhiều, đĩa chậm) → nén thắng lớn. Trên hệ thống **CPU-bound** đã sát trần → thêm chi phí giải nén có thể làm chậm. Đo cả hai phía (logical/physical reads GIẢM vs CPU used TĂNG) trước khi kết luận nén "cải thiện hiệu năng".

---

## 4. Decision Framework

**Dùng Basic Compression khi:**
- Bảng read-mostly / archive, nạp bằng bulk (ETL, CTAS, SQL*Loader direct)
- Dữ liệu có độ lặp cao trong cột
- Muốn tiết kiệm license (Basic miễn phí)
- Chấp nhận: dữ liệu vào bằng conventional INSERT sẽ KHÔNG nén

**Dùng Advanced (OLTP) Compression khi:**
- Bảng có DML liên tục (conventional INSERT/UPDATE) nhưng vẫn muốn nén
- ĐÃ có Advanced Compression Option license (xác nhận trước!)
- Chấp nhận overhead CPU cho re-compress

**Dùng direct-path load (APPEND) khi:**
- Nạp khối lượng lớn vào bảng nén → vừa nén được vừa nạp nhanh hơn
- Chấp nhận: APPEND khóa bảng (exclusive) + row đi trên HWM

**KHÔNG nén khi:**
- Dữ liệu unique/ngẫu nhiên (ratio ~1x, tốn CPU vô ích)
- Bảng OLTP update nặng + chỉ có Basic (dữ liệu vào không nén, còn phình do update)
- Hệ thống đã CPU-bound

**Anti-patterns:**
- Khai báo `COMPRESS ADVANCED` mà chưa xác nhận license → rủi ro phạt phí
- Tưởng `ALTER TABLE COMPRESS` nén ngay dữ liệu cũ (không — cần MOVE/reload)
- Nén bảng rồi conventional INSERT vào bảng Basic, tưởng đang nén (không nén)
- Kết luận "nén nhanh hơn" từ một lần chạy cache nóng — đo logical reads + CPU riêng

---

## 5. Key SQL / Commands

```sql
-- 5.1 Tao 3 kieu bang
CREATE TABLE cust_source     (...) NOLOGGING PCTFREE 0 TABLESPACE soetbs;
CREATE TABLE cust_bcompressed(...) ROW STORE COMPRESS BASIC NOLOGGING TABLESPACE soetbs;
CREATE TABLE cust_acompressed(...) ROW STORE COMPRESS ADVANCED NOLOGGING PCTFREE 0 TABLESPACE soetbs;

-- 5.2 Trang thai compression + kich thuoc
SELECT table_name, blocks*8 size_kb, compression, compress_for, pct_free
FROM   user_tables
WHERE  table_name IN ('CUST_SOURCE','CUST_BCOMPRESSED','CUST_ACOMPRESSED');

-- 5.3 Conventional vs direct-path (basic chi nen o direct-path)
INSERT INTO cust_bcompressed SELECT * FROM cust_source;            -- KHONG nen (basic)
TRUNCATE TABLE cust_bcompressed;
INSERT /*+ APPEND */ INTO cust_bcompressed SELECT * FROM cust_source;  -- nen (basic)
COMMIT;

-- 5.4 Uoc luong ratio TRUOC khi nen that (khong nen ca bang)
SET SERVEROUTPUT ON
DECLARE
  v_blkcmp NUMBER; v_blkuncmp NUMBER; v_rowcmp NUMBER; v_rowuncmp NUMBER;
  v_cmpratio NUMBER; v_comptype VARCHAR2(4000);
BEGIN
  DBMS_COMPRESSION.GET_COMPRESSION_RATIO(
    scratchtbsname => 'SOETBS', ownname => USER, objname => 'CUST_SOURCE',
    subobjname => NULL, comptype => DBMS_COMPRESSION.COMP_ADVANCED,
    blkcnt_cmp => v_blkcmp, blkcnt_uncmp => v_blkuncmp,
    row_cmp => v_rowcmp, row_uncmp => v_rowuncmp,
    cmp_ratio => v_cmpratio, comptype_str => v_comptype);
  DBMS_OUTPUT.PUT_LINE('Uoc luong ratio = ' || v_cmpratio || 'x');
END;
/

-- 5.5 Nen du lieu DANG CO (thuoc tinh COMPRESS khong nen du lieu cu)
ALTER TABLE cust_bcompressed MOVE ROW STORE COMPRESS BASIC ONLINE;  -- rewrite + nen
-- (ONLINE giu index valid; khong ONLINE thi index UNUSABLE -> rebuild)

-- 5.6 Kiem tra su dung feature Advanced Compression (truoc audit license)
SELECT name, detected_usages, currently_used, last_usage_date
FROM   dba_feature_usage_statistics
WHERE  name LIKE '%Advanced%Compression%' OR name LIKE '%OLTP Compression%';

-- 5.7 Do query benefit (autotrace: consistent gets, physical reads)
SET AUTOTRACE TRACE STATISTICS
SELECT COUNT(*) FROM cust_bcompressed;   -- so consistent gets voi ban nocompress
SET AUTOTRACE OFF
```

---

## 6. Senior Checklist

1. **Xác nhận license trước khi ADVANCED:** `DBA_FEATURE_USAGE_STATISTICS` + hợp đồng; Basic miễn phí, Advanced tính phí — nhầm là phạt hồi tố
2. **Kiểm tra dữ liệu có lặp không:** `GET_COMPRESSION_RATIO` ước lượng trước; dữ liệu unique → ratio ~1x → đừng nén
3. **Khớp phương pháp nạp với loại nén:** Basic chỉ nén direct-path (APPEND/CTAS/SQL*Loader direct); conventional INSERT vào Basic = KHÔNG nén; cần nén conventional DML → Advanced
4. **"Bật compress" ≠ dữ liệu đã nén:** thuộc tính chỉ áp cho dữ liệu tương lai; nén dữ liệu cũ cần `MOVE`/reload; kiểm bằng BLOCKS trước/sau
5. **Lường UPDATE làm suy giảm nén:** bảng update nặng mất ratio dần; compression hợp read-mostly/append-mostly; cân nhắc re-move định kỳ
6. **Đo trade-off CPU vs I/O:** logical/physical reads giảm nhưng CPU giải nén tăng; hệ CPU-bound có thể chậm đi — đo cả hai phía
7. **MOVE COMPRESS làm index UNUSABLE:** dùng `MOVE ... ONLINE` hoặc rebuild index sau; lường redo khi rewrite bảng lớn

---

# LAB EXERCISES

## Exercise 1 — Basic vs Advanced: Điều kiện nén thực sự có hiệu lực

**Scenario:** Team đề xuất "bật compression cho bảng `ORDERS` để tiết kiệm đĩa". Bảng này nhận dữ liệu chủ yếu qua conventional INSERT từ app. Bạn cần chứng minh Basic compression sẽ **không** nén gì trong tình huống này, và giải thích cần điều kiện gì.

**Tasks:**
1. Tạo `CUST_SOURCE` (nocompress), `CUST_BCOMPRESSED` (basic), `CUST_ACOMPRESSED` (advanced); populate source bằng dữ liệu **ngẫu nhiên** (ít lặp).
2. Nạp `CUST_BCOMPRESSED` bằng **conventional INSERT** → so kích thước với source.
3. TRUNCATE, nạp lại bằng **direct-path** (`INSERT /*+ APPEND */`) → so lại.
4. Nạp `CUST_ACOMPRESSED` bằng conventional INSERT → so.
5. Lập bảng đối chiếu: (loại nén × phương pháp nạp) → có nén / không nén.

**Expected Findings:**
- Basic + conventional INSERT: kích thước = source (KHÔNG nén).
- Basic + direct-path: nhỏ hơn chút (dữ liệu random, ratio thấp).
- Advanced + conventional: nhỏ hơn source (Advanced nén cả conventional).
- Kết luận: với dữ liệu vào bằng INSERT thường, chỉ Advanced nén được — nhưng cần license.

**Debrief Questions:**
- Vì sao Basic bỏ qua conventional INSERT? Cơ chế "nén khi block đầy" liên quan thế nào?
- Nếu chỉ có Basic license, cách nào để nén được dữ liệu nạp qua app?
- `DBA_TABLES.COMPRESSION='ENABLED'` chứng minh dữ liệu đã nén chưa?

---

## Exercise 2 — Ratio phụ thuộc độ lặp; Query benefit của bảng nén

**Scenario:** Bạn phải quyết định có nén `SALES_ARCHIVE` (read-mostly, bulk load) không. Cần chứng minh ratio phụ thuộc dữ liệu, và đo lợi ích query thực tế.

**Tasks:**
1. Populate source với dữ liệu **lặp nhiều** (`NOTE1='XXXXXX'`, `NOTE2='YYYYYY'`), nạp `CUST_BCOMPRESSED` bằng direct-path → so kích thước (kỳ vọng nhỏ hơn NHIỀU so với Exercise 1 dữ liệu random).
2. Tạo T1 (nocompress), T2 (basic + conventional), T3 (basic + direct-path); nạp cùng khối dữ liệu lớn; đo **thời gian nạp** từng bảng.
3. Flush cache; chạy `SELECT COUNT(*)` từng bảng với `AUTOTRACE STATISTICS`; ghi `consistent gets`, `physical reads`.
4. So sánh và giải thích nghịch lý "T3 nạp nhanh hơn dù phải nén".

**Expected Findings:**
- Dữ liệu lặp nhiều → Basic + direct-path nén rất tốt (nhỏ hơn nhiều).
- T3 (append + compress) nạp **nhanh nhất** (~70% ít thời gian hơn T1 theo course).
- T3 query: `consistent gets`/`physical reads` **ít nhất** (ít block hơn); T2 tốt hơn T1 chút.

**Debrief Questions:**
- Vì sao direct-path load trên bảng nén lại nhanh hơn cả nạp bảng không nén?
- Nếu load kèm `ORDER BY note1` thì ratio thay đổi thế nào? Vì sao (symbol table cấp block)?
- Query nhanh hơn nhờ ít I/O — khi nào lợi ích này biến mất (hệ thống kiểu gì)?

---

## Exercise 3 — Troubleshooting Scenario (Expert Level)

**Incident Brief:**
Kiểm toán license Oracle sắp diễn ra trong 2 tuần. Manager hỏi: "Chúng ta có dùng tính năng nào tính phí mà không có license không?" Bạn rà soát và phát hiện 6 tháng trước một DBA đã chạy script "tối ưu dung lượng" nén hàng loạt bảng. Đồng thời, một bảng ETL `STAGE_TXN` được nén nhưng job nạp hàng đêm (conventional INSERT) gần đây chậm dần và đĩa vẫn đầy.

**Evidence Provided:**

`DBA_FEATURE_USAGE_STATISTICS`:
```
NAME                              DETECTED_USAGES  CURRENTLY_USED  LAST_USAGE
--------------------------------  ---------------  --------------  ----------
Advanced Compression                          142  TRUE            2026-07-15
HW (Heap segment compression)                  30  TRUE            2026-07-15
```

`DBA_TABLES` (trích):
```
TABLE_NAME       COMPRESSION  COMPRESS_FOR       NUM_ROWS    BLOCKS
---------------  -----------  -----------------  ----------  ---------
SALES_ARCHIVE    ENABLED      ADVANCED           88,000,000  1,240,000
STAGE_TXN        ENABLED      BASIC              12,400,000  410,000
CUST_MASTER      ENABLED      ADVANCED               45,000     1,180
```

`GET_COMPRESSION_RATIO` chạy thử trên STAGE_TXN (dữ liệu hiện tại):
```
COMP_BASIC   ratio uoc luong: 3.4x
Thuc te BLOCKS hien tai vs uoc luong neu nen: gap ~3x
```

Job nạp STAGE_TXN hàng đêm: `INSERT INTO stage_txn SELECT ... FROM ext_feed;` (conventional).

**Your Mission:**
1. Về license: bảng nào đang tạo rủi ro phí? `SALES_ARCHIVE` và `CUST_MASTER` dùng ADVANCED — cả hai có cần license không? Phân biệt vai trò của chúng.
2. Vì sao `STAGE_TXN` (COMPRESS BASIC) vẫn tốn đĩa gấp ~3x so với ước lượng nén, dù `COMPRESSION=ENABLED`? Chỉ ra bằng chứng.
3. Job nạp STAGE_TXN chậm dần — có liên quan compression không? Giải thích.
4. Đề xuất hành động cho từng bảng: `SALES_ARCHIVE`, `STAGE_TXN`, `CUST_MASTER` — trước kỳ audit.
5. `HW (Heap segment compression)` xuất hiện — nó là gì, có tính phí không?

**Evaluation Criteria:**
- License: `Advanced Compression` currently_used=TRUE ⇒ đang phát sinh nghĩa vụ license; cả `SALES_ARCHIVE` và `CUST_MASTER` (COMPRESS_FOR ADVANCED) đều cần Advanced Compression Option. Nếu không có license → phải chuyển sang BASIC (`MOVE ... COMPRESS BASIC`) hoặc mua license trước audit.
- STAGE_TXN: `COMPRESSION=ENABLED` chỉ là **thuộc tính**, không đảm bảo dữ liệu nén. Bảng BASIC nạp bằng **conventional INSERT** (job hàng đêm) → dữ liệu vào **KHÔNG nén** → BLOCKS lớn dù thuộc tính bật; bằng chứng: 410k block cho 12.4M row so với ước lượng nén 3.4x.
- Job chậm dần: một phần vì đĩa đầy (dữ liệu không nén tích tụ) → nhiều block để scan/ghi; compression không giúp vì conventional INSERT không kích hoạt nén basic — nghĩ nhầm "đã nén" nên không xử lý.
- Hành động: (a) `SALES_ARCHIVE` read-mostly → chuyển BASIC (miễn phí) bằng `MOVE ... COMPRESS BASIC ONLINE`, mất chút ratio nhưng bỏ nghĩa vụ license; (b) `STAGE_TXN` → hoặc đổi job nạp sang `INSERT /*+ APPEND */` để BASIC nén thực sự, hoặc bỏ compression nếu staging ngắn hạn; (c) `CUST_MASTER` nhỏ (1180 block) → lợi ích nén không đáng nghĩa vụ license → chuyển nocompress/BASIC.
- `HW` là internal heap segment compression (nén block khi bulk load), **không tính phí riêng** — không phải rủi ro license; đừng nhầm với Advanced Compression.
- **Bonus:** chỉ ra `MOVE ... COMPRESS` làm index UNUSABLE → dùng ONLINE hoặc rebuild; và lường redo/Data Guard khi re-move 1.24M block của SALES_ARCHIVE.


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/section_all_new/section_30_table_compression_senior_guide.md`
