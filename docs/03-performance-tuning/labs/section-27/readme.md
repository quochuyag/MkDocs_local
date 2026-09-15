---
title: Lab Section 27 — Index Defragmentation
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/labs/section_27/README.md
---

# Lab Section 27 — Index Defragmentation

> Nguồn: Practice 29 (Ahmed Baraka) · Guide: [section_all/section_27_index_defrag_guide.md](../../section-all/section-27-index-defrag-guide.md) · Senior: [section_all_new/section_27_index_defrag_senior_guide.md](../../section-all-new/section-27-index-defrag-senior-guide.md)
> Chạy từ thư mục này (`labs/section_27/`). Quy ước chung: [labs/README.md](../readme.md)
> ⚠️ **Lab chưa kiểm chứng end-to-end trên VM** — số đo trong tài liệu là **kỳ vọng**, có thể lệch theo phiên bản/môi trường. Cần đúng **xu hướng**: DEL_LF_ROWS về 0, LF_BLKS giảm.

**🎓 Học theo buổi đầy đủ (từng bước, dự đoán + đáp án):**
👉 **[HUONG_DAN_HOC_SECTION_27.md](huong-dan-hoc-section-27.md)**

## Chạy lab chính — user `soe`

```powershell
sqlplus soe/soe@//localhost:15210/ORADB
```

```
@01_setup.sql      -- TTABLE 500k rows + index TTABLE_IDX (R_ID tuần tự) (~30-60s)
@02_workload.sql   -- DELETE 200k rows đầu -> deleted entry dồn về TRÁI; đo baseline
@03_diagnose.sql   -- có THỰC SỰ cần defrag không? (pattern tuần tự + bulk delete)
@04_fix.sql        -- so sánh COALESCE vs REBUILD, đo lại
```

**Kỳ vọng (chưa kiểm chứng VM):**

| Chỉ số INDEX_STATS | Sau DELETE (02) | Sau COALESCE | Sau REBUILD |
|---|---|---|---|
| `DEL_LF_ROWS` | ~200,000 | **0** | **0** |
| `LF_BLKS` | cao | **giảm** | **giảm** |
| `BLOCKS` (tổng size) | ~không đổi | **GIỮ NGUYÊN** | **GIẢM** |
| Cần lock? | — | Không | Có (bước cutover) |

## Mở rộng (tùy chọn)

- **REBUILD ONLINE hang khi bảng đang DML** — chạy `idx_dml_load.sh 120` từ một session khác (trong VM), rồi `ALTER INDEX ttable_idx REBUILD ONLINE` sẽ treo ở `enq: TX - row lock contention`. Theo dõi bằng `@05_shrink_and_dml.sql` (PHẦN B, user SYS).
- **SHRINK SPACE trả space** — `@05_shrink_and_dml.sql` PHẦN A: khác COALESCE, BLOCKS giảm (trả space về tablespace ASSM).

## Dọn dẹp

```
@99_cleanup.sql    -- xóa TTABLE, TTABLE_SOURCE
```

## Câu hỏi tự kiểm tra (trả lời trước khi xem 03/04)

1. Vì sao "DEL_LF_ROWS = 40%" **chưa đủ** để kết luận phải rebuild? Điều kiện nào mới khiến deleted entry **không được Oracle reuse**?
2. B-tree Oracle self-balancing — với random insert/delete, tại sao **không** cần defrag định kỳ?
3. `COALESCE` vs `REBUILD` vs `SHRINK SPACE`: cái nào trả space về tablespace? cái nào giảm BLEVEL? cái nào cần lock?
4. `REBUILD ONLINE` vẫn hang được — hang ở **bước nào** và **chờ gì**? Vì sao `COALESCE` không hang?
5. `INDEX_STATS` là view kiểu gì? Nếu ANALYZE index A rồi ANALYZE index B thì đọc `INDEX_STATS` ra của ai?


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/labs/section_27/README.md`
