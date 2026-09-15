---
title: '`_frag_check/` — Bộ script kiểm tra mức độ phân mảnh toàn hệ thống Oracle'
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/labs/_frag_check/README.md
---

# `_frag_check/` — Bộ script kiểm tra mức độ phân mảnh toàn hệ thống Oracle

> Dùng chung cho mọi database (không gắn với lab nào). Chỉ đọc từ điển + `V$` là chính,
> phần "động chạm" (ANALYZE, Segment Advisor) **mặc định tắt**, phải bật có ý thức trong config.
>
> Nền tảng kiến thức: Section 26 (Disk I/O), **27 (Index Defragmentation)**,
> **28 (Row Migration & Chaining)**, **29 (Table Fragmentation)**, 17 (Automated Maintenance
> Tasks / Segment Advisor), 6-8-9-13 (Time Model, Wait Events, AWR, ASH).
> Mỗi script ghi rõ ở header: phần nào **lấy từ bài học**, phần nào là **mở rộng thực tế**.

---

## 1. Bốn tầng phân mảnh — đừng trộn lẫn

Cùng gọi là "phân mảnh" nhưng bốn thứ khác nhau, đo bằng view khác nhau, sửa bằng lệnh khác nhau:

| Tầng | Là gì | Đo ở đâu | Sửa bằng gì |
|---|---|---|---|
| **1. Bảng (HWM)** | Xoá nhiều nhưng HWM không hạ → FTS vẫn quét block rỗng | `01`, `02` | `SHRINK SPACE` / `MOVE` / `DEALLOCATE UNUSED` |
| **2. Block (bên trong block)** | Block chỉ dùng 10-20% dung lượng; row bị migrate sang block khác | `02`, `03` | `PCTFREE` + `MOVE`, `SHRINK` |
| **3. Index** | Leaf block rỗng sau purge dữ liệu cũ; index UNUSABLE; BLEVEL phình | `04`, `05` | `COALESCE` / `REBUILD ONLINE` |
| **4. Tablespace (không gian trống)** | Tổng còn nhiều GB nhưng bị cắt vụn → `ORA-01653` dù "còn trống" | `07` | Thêm datafile / `MOVE` gom mảnh |

Và một tầng **không phải phân mảnh nhưng luôn đi kèm**: **statistics** (`06`) — mọi con số
ở tầng 1, 3 đều suy ra từ `NUM_ROWS`/`AVG_ROW_LEN`/`LEAF_BLOCKS`. **Stats cũ = kết luận sai.**

---

## 2. Điều kiện chạy

| Mục | Yêu cầu |
|---|---|
| User | `system` (hoặc user có `SELECT_CATALOG_ROLE`) |
| Quyền thêm | `EXECUTE ON DBMS_SPACE`, `EXECUTE ON DBMS_ADVISOR` (script `09`), `ANALYZE ANY` (script `03` mục 3.5 và `05`) |
| Multitenant | `DBA_*` là **theo từng PDB** — connect thẳng vào PDB (`//localhost:15210/ORADB`), muốn quét CDB root thì connect root rồi chạy lại |
| License | Chỉ mục `10.3`/`10.4` (`DBA_HIST_*`) cần **Diagnostic Pack**. Không có thì bỏ qua, dùng `10.2` (`V$SEGMENT_STATISTICS`) — luôn miễn phí |
| Phiên bản | Viết cho **19c**. `DBA_INDEX_USAGE` (mục 4.5) cần 12.2+; `MOVE ONLINE` cho bảng thường cần 12.2+ EE |

Chạy từ host (PowerShell — nhớ quote chuỗi connect và `@file`):

```powershell
cd D:\Dba_project\The-Oracle-Database-Performance-Tuning-Course
sqlplus -S "system/oracle_4U@//localhost:15210/ORADB" "@labs\_frag_check\00_run_all.sql"
```

Chạy trong VM (thư mục này mount tại `/labs`):

```bash
vagrant ssh
sudo -u oracle -i
cd /labs/_frag_check
sqlplus system/oracle_4U@//localhost:1521/ORADB @00_run_all.sql
```

---

## 3. Danh sách script

| Script | Trả lời câu hỏi | Nặng/nhẹ | Nguồn bài học |
|---|---|---|---|
| `_frag_config.sql` | **Nơi duy nhất** chỉnh phạm vi quét + ngưỡng | — | — |
| `00_run_all.sql` | Chạy tất cả, ghi ra `frag_report_<ts>.txt` | nhẹ | — |
| `01_tables_hwm.sql` | Bảng nào HWM cao hơn dữ liệu thật? Partition? LOB? | nhẹ (từ điển) | S29/Practice 31 |
| `02_blocks_space_usage.sql` | Trong block có gì: FULL hay FS1 (gần rỗng)? | nhẹ (đọc bitmap) | S29 — `DBMS_SPACE.SPACE_USAGE` |
| `03_rows_migrated_chained.sql` | Row migration/chaining — và nó **có đang gây đau** không? | nhẹ; mục 3.5 nặng (tắt sẵn) | S28/Practice 30, S8 |
| `04_indexes.sql` | Index nào đáng ngờ: UNUSABLE, leaf thừa, BLEVEL, không ai dùng, trùng lặp | nhẹ | S27/Practice 29, S26 |
| `05_indexes_validate.sql` | `DEL_LF_ROWS` thật (INDEX_STATS) | **NẶNG — khoá DML**, tắt sẵn | S27 |
| `06_stats_health.sql` | Stats có đáng tin không? Auto task có chạy không? | nhẹ | S17, S28, S29 |
| `07_tablespace_free_space.sql` | Không gian trống có bị vụn? Headroom thật? Recyclebin? | nhẹ | mở rộng thực tế |
| `08_generate_fix_ddl.sql` | Sinh file lệnh sửa `frag_fix_<ts>.sql` (**không tự chạy**) | nhẹ | S27/28/29 |
| `09_segment_advisor.sql` | Oracle tự nói gì về segment này? Bảng đang phình nhanh không? | nhẹ; 9.3 vừa | S17, S29 |
| `10_impact_awr.sql` | **Phân mảnh có thật sự tốn DB time không?** | nhẹ | S6, S8, S9, S13, S26 |

---

## 4. Quy trình dùng chuẩn (đúng thứ tự tư duy của khoá học)

```
DB Time  →  Wait Event  →  SQL/Segment  →  Root cause  →  Fix  →  Đo lại
```

1. **`06` trước tiên.** Stats bẩn thì dừng lại, gather rồi mới đi tiếp.
2. **`01 → 02 → 03`** cho bảng, **`04 (→ 05)`** cho index → ra *danh sách phân mảnh*.
3. **`10`** → ra *danh sách đang tốn I/O / DB time*.
4. **Chỉ lấy phần GIAO của hai danh sách.** Bảng phân mảnh 60% mà không ai quét thì
   sửa nó = tiêu cửa sổ bảo trì + rước rủi ro, đổi lại số 0.
5. **`08`** sinh lệnh → review → chạy **từng lệnh** trong cửa sổ bảo trì.
6. **Chạy lại `00_run_all.sql`** và diff hai file báo cáo. Không có số trước/sau thì
   không gọi là tuning.

---

## 5. Cách đọc số — ngưỡng và ý nghĩa

| Chỉ số | Script | Ngưỡng đáng chú ý | Diễn giải |
|---|---|---|---|
| `WASTE_PCT` (bảng) | 01 | > 20% **và** `RECLAIM_MB` đáng kể | Block dưới HWM không mang dữ liệu |
| `ABOVE_HWM_MB` | 01, 02 | > 50 MB | Cấp rồi chưa dùng — `DEALLOCATE UNUSED`, rẻ nhất |
| `FS1 + FS2` (block) | 02 | chiếm phần lớn block | Bảng bị thổi phồng thật sự |
| `FULL` chiếm đa số | 02 | — | Bảng **chặt**, đừng động vào |
| `CONTINUED_PCT` | 03 | < 1% bình thường; > 5% đáng lo | Migration/chaining **đang** bị chạm vào |
| `CHAIN_PCT` | 03 | > 5% | Nhưng chỉ có ý nghĩa nếu `LAST_ANALYZED` còn mới |
| `AVG_ROW_LEN` vs block | 03 | ≥ block size | Là **chaining thật**, `PCTFREE` vô dụng |
| `WASTE_PCT` (index) | 04 | > 20% | Chỉ là **ứng viên**, phải xác nhận bằng 05 |
| `BLEVEL` | 04 | ≥ 4 trên index nhỏ | `COALESCE` không hạ được, chỉ `REBUILD` |
| `PCT_DEL` | 05 | ≥ 20% **và** khoá tuần tự + purge | Mới thật sự đáng defrag |
| `USED_PCT_MAX` | 07 | > 85% | Hết headroom thật (đã tính autoextend) |
| `FSFI` | 07 | < 30 | Không gian trống bị cắt vụn nghiêm trọng |
| `DML_PCT` | 06 | ≥ 10% | Stats stale theo chuẩn của Oracle |

---

## 6. Cây quyết định khi đã có số

```
Segment có phân mảnh (01/02/04)?
├── KHÔNG → dừng.
└── CÓ → Nó có xuất hiện ở 10.2/10.3/10.5/10.6 (tốn I/O) không?
    ├── KHÔNG → ghi vào sổ theo dõi, KHÔNG sửa lần này.
    └── CÓ → loại phân mảnh nào?
        ├── Chỉ ở trên HWM        → DEALLOCATE UNUSED           (rẻ, không khoá)
        ├── Block rỗng dưới HWM   → ASSM? → SHRINK SPACE COMPACT rồi SHRINK CASCADE
        │                          → MSSM? → MOVE ONLINE + REBUILD index
        ├── Row migration         → PCTFREE ↑ rồi MOVE ONLINE   (S28)
        ├── Row chaining thật     → tách cột / block size lớn hơn (PCTFREE vô ích)
        ├── Index leaf thừa       → BLEVEL thường → COALESCE (online, nhẹ)
        │                          → BLEVEL cao / cần trả space → REBUILD ONLINE
        ├── Index UNUSABLE        → REBUILD ONLINE ngay (đây là sự cố, không phải tuning)
        ├── Index không ai dùng   → INVISIBLE 1 chu kỳ nghiệp vụ → DROP (đừng rebuild)
        └── Tablespace vụn        → thêm datafile (rẻ nhất) / MOVE gom mảnh
Sau mọi thao tác → GATHER STATS lại → đo lại.
```

---

## 7. Bẫy thực tế (đúc kết, đừng dẫm lại)

- **`DBMS_STATS` không điền `CHAIN_CNT`** → thấy 0 đừng vội mừng (S28). Chỉ `ANALYZE` mới có,
  mà `ANALYZE` lại là deprecated cho optimizer stats → chạy xong **phải gather lại bằng `DBMS_STATS`**.
- **`ANALYZE INDEX ... VALIDATE STRUCTURE` khoá DML.** Bản `ONLINE` **không** điền `INDEX_STATS` —
  chạy xong thấy bảng trống rồi tưởng index sạch. Đây là lý do `05` mặc định tắt.
- **B-tree tự cân bằng** (S27): random insert/delete thì Oracle tái dùng entry đã xoá →
  `DEL_LF_ROWS` cao vẫn **không** cần defrag. Chỉ pattern *khoá tuần tự + purge dữ liệu cũ* mới đáng.
- **`SHRINK` cần ASSM + `ENABLE ROW MOVEMENT`** → ROWID đổi. Ứng dụng nào lưu ROWID sẽ hỏng.
- **`MOVE` (không `ONLINE`) làm index `UNUSABLE`** → phải `REBUILD` ngay, nếu không optimizer
  chuyển sang FTS và I/O bùng nổ (đúng kịch bản lab S26).
- **`REBUILD INDEX` không sửa được `CLUSTERING_FACTOR`** — cái đó nằm ở thứ tự row trong **bảng**.
- **Recyclebin** giữ extent thật; tablespace "đầy không hiểu vì sao" — kiểm tra `07` mục 7.4 đầu tiên.
- **Bảng đang tăng trưởng đều** (`09` mục 9.4): shrink hôm nay tuần sau như cũ →
  vấn đề là **chính sách purge/partition**, không phải thao tác shrink.
- **PDB vs CDB**: `DBA_*` chỉ thấy trong container hiện tại. Quên `ALTER SESSION SET CONTAINER`
  là bỏ sót cả nửa hệ thống.

---

## 8. Câu hỏi tự kiểm tra

1. Bảng A: `WASTE_PCT` 55%, không xuất hiện ở `10.2` lẫn `10.5`. Làm gì? Vì sao?
2. `CHAIN_CNT = 0` sau khi chạy `DBMS_STATS.GATHER_TABLE_STATS`. Kết luận được gì?
3. `DEL_LF_ROWS` = 45% trên index của cột `ORDER_DATE`, dữ liệu cũ bị purge hàng tháng.
   Chọn `COALESCE` hay `REBUILD`? Điều kiện nào làm đổi câu trả lời?
4. Tablespace báo free 20 GB nhưng `CREATE TABLE` extent 64 MB vẫn `ORA-01653`. Đọc chỉ số nào?
5. Vì sao `06_stats_health.sql` phải chạy **trước** `01`, chứ không phải sau?
6. Sau `MOVE` mà quên `REBUILD` index thì triệu chứng đầu tiên nhìn thấy ở đâu — `10.1`, `10.5`,
   hay `04.1`?

*(Đáp án nằm rải trong header từng script và mục 5-7 ở trên.)*

---

## 9. Liên hệ với lab của khoá học

| Muốn thực hành tay | Chạy lab |
|---|---|
| Tạo ra phân mảnh bảng rồi tự chẩn đoán | [`labs/section_29/`](../section_29/) |
| Tạo row migration rồi sửa bằng PCTFREE + MOVE | [`labs/section_28/`](../section_28/) |
| So sánh `REBUILD` vs `COALESCE` trên số thật | [`labs/section_27/`](../section_27/) |
| Xem index UNUSABLE làm I/O bùng nổ thế nào | [`labs/section_26/`](../section_26/) |

Bộ `_frag_check/` là **bản tổng quát hoá cho production** của đúng những kỹ thuật đó:
lab dạy *một bảng, biết trước bệnh*; bộ này quét *cả database, chưa biết bệnh ở đâu*.


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/labs/_frag_check/README.md`
