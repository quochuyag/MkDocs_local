---
title: Lab Section 31 — In-Memory Column Store
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/labs/section_31/README.md
---

# Lab Section 31 — In-Memory Column Store

> Nguồn: Practice 33 (Ahmed Baraka) · Guide: [section_all/section_31_in_memory_column_store_guide.md](../../section-all/section-31-in-memory-column-store-guide.md) · Senior: [section_all_new/section_31_in_memory_column_store_senior_guide.md](../../section-all-new/section-31-in-memory-column-store-senior-guide.md)
> Chạy **TRONG VM** (cấu hình instance + restart). Quy ước chung: [labs/README.md](../readme.md)
> ⚠️ **Lab chưa kiểm chứng end-to-end trên VM** — số đo là **kỳ vọng**.
> ⚠️⚠️ **SNAPSHOT BẮT BUỘC** trước khi chạy (thay đổi SGA + INMEMORY_SIZE + restart): `vagrant snapshot save pre_inmemory`
> ⚠️⚠️ **LICENSE:** `INMEMORY_SIZE>0` kích hoạt **Database In-Memory Option (tính phí riêng, bị audit gắt)**. Chạy được trên 19c EE nhưng production **phải có license**.

**🎓 Học theo buổi đầy đủ:** 👉 **[HUONG_DAN_HOC_SECTION_31.md](huong-dan-hoc-section-31.md)**

## Ý tưởng lab

Database In-Memory = kiến trúc **dual-format**: cùng bảng tồn tại ở **row format** (buffer cache, cho OLTP) VÀ **columnar format** (IMCS, cho analytics), nhất quán giao dịch. Optimizer **tự chọn** format. Query analytic (scan + aggregate) → `TABLE ACCESS INMEMORY FULL` → nhanh nhờ columnar + SIMD + storage index. IM **không** tăng tốc single-row lookup.

## Chạy lab — TRONG VM

**Bước cấu hình (SYS):**
```bash
vagrant snapshot save pre_inmemory   # trên host, BẮT BUỘC
vagrant ssh → sudo -u oracle -i → sqlplus / as sysdba
```
```
@01_setup.sql    -- bỏ comment BƯỚC 2 → set SGA 2.5G + INMEMORY_SIZE 300M + restart
```

**Bước thực nghiệm (soe, trong VM):**
```
sqlplus soe/soe@//localhost:1521/ORADB
@02_workload.sql              -- tạo ORDERS2 2M, baseline FTS, bật INMEMORY, đo lại
@03_diagnose.sql             -- V$INMEMORY_AREA + V$IM_SEGMENTS (IM footprint << segment)
@04_usecase_compress_col.sql -- MEMCOMPRESS levels + loại cột + IM thay index (tùy chọn)
```

**Kỳ vọng (chưa kiểm chứng VM):**

| Lần chạy query | Plan | logical reads / physical reads |
|---|---|---|
| Baseline (chưa IM) | `TABLE ACCESS FULL` | cao |
| IM lần 1 (đang populate) | `TABLE ACCESS INMEMORY FULL` | còn cao |
| IM lần 2 | INMEMORY FULL | giảm ~nửa |
| IM lần 3+ (COMPLETED) | INMEMORY FULL | rất thấp, physical reads = **0** |

`V$IM_SEGMENTS`: `INMEMORY_SIZE` << `SEGMENT_SIZE` (nén columnar).

## Dọn dẹp

```
@99_cleanup.sql              -- drop ORDERS2, NO INMEMORY
vagrant snapshot restore pre_inmemory   # trả SGA/INMEMORY_SIZE/restart về trước lab
```

## Câu hỏi tự kiểm tra

1. IM là "cache query riêng" hay kiến trúc dual-format? Ai chọn dùng IM cho một query?
2. Vì sao query lần 1 sau khi bật IM chưa nhanh, lần 3 mới nhanh?
3. IM lấy RAM từ đâu? Không tăng SGA thì cái gì bị bóp?
4. IM có tăng tốc `WHERE order_id = :x` không? Vì sao?
5. `PRIORITY NONE` vs `CRITICAL` khác gì về thời điểm populate? Liên quan cold-start sau restart thế nào?
6. Vì sao "bỏ được analytic index" thường là ROI lớn hơn cả tốc độ query?


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/labs/section_31/README.md`
