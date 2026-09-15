---
title: Lab Section 30 — Table Compression
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/labs/section_30/README.md
---

# Lab Section 30 — Table Compression

> Nguồn: Practice 32 (Ahmed Baraka) · Guide: [section_all/section_30_table_compression_guide.md](../../section-all/section-30-table-compression-guide.md) · Senior: [section_all_new/section_30_table_compression_senior_guide.md](../../section-all-new/section-30-table-compression-senior-guide.md)
> Chạy từ thư mục này (`labs/section_30/`). Quy ước chung: [labs/README.md](../readme.md)
> ⚠️ **Lab chưa kiểm chứng end-to-end trên VM** — số đo là **kỳ vọng**.
> ⚠️⚠️ **LICENSE:** `ROW STORE COMPRESS ADVANCED` thuộc **Advanced Compression Option (tính phí riêng)**. Chạy được trên 19c EE nhưng production **phải có license**. Basic compression **miễn phí** (kèm EE).

**🎓 Học theo buổi đầy đủ:** 👉 **[HUONG_DAN_HOC_SECTION_30.md](huong-dan-hoc-section-30.md)**

## Ý tưởng lab

Compression của Oracle = **de-duplication cấp block** (symbol table trong mỗi block). Ratio phụ thuộc **độ lặp dữ liệu trong block**, và **cách nạp dữ liệu** quyết định có nén hay không:

| loại nén \ nạp | conventional INSERT | direct-path (APPEND/CTAS) |
|---|---|---|
| **BASIC** (free) | ❌ KHÔNG nén | ✅ nén |
| **ADVANCED** (license) | ✅ nén | ✅ nén |

## Chạy lab — user `soe`

⚠️ Cần grant một lần (SYS) cho `before_after.sql` ở bước 04: `GRANT SELECT ON sys.v_$session_event TO soe;`

```powershell
sqlplus soe/soe@//localhost:15210/ORADB
```
```
@01_setup.sql              -- 3 bảng (nocompress/basic/advanced) + source RANDOM (~1 phút)
@02_workload.sql           -- conventional vs direct-path, basic vs advanced (đo SIZE_KB)
@03_diagnose.sql           -- ratio phụ thuộc độ lặp (data lặp nhiều) + GET_COMPRESSION_RATIO
@04_usecase_query_perf.sql -- T1/T2/T3: thời gian nạp + logical reads khi query
```

**Kỳ vọng (chưa kiểm chứng VM):**
- Basic + conventional → **= source** (không nén); Basic + direct-path → nhỏ hơn.
- Advanced + conventional → **nhỏ hơn source** (nén cả conventional).
- Data lặp nhiều → Basic direct-path nén **rất tốt** (khác data random).
- T3 (append+compress): **nạp nhanh nhất** + query **ít logical reads nhất**.

## Dọn dẹp

```
@99_cleanup.sql            -- xóa CUST_*, T1/T2/T3, T_SRC
```

## Câu hỏi tự kiểm tra

1. Vì sao Basic compression **không** nén dữ liệu vào bằng conventional INSERT?
2. `DBA_TABLES.COMPRESSION='ENABLED'` có chứng minh dữ liệu đã nén không?
3. Compression ratio phụ thuộc gì? Vì sao load kèm `ORDER BY` cột lặp nhiều làm tăng ratio?
4. Nghịch lý: vì sao direct-path load trên bảng nén **nhanh hơn** cả nạp bảng không nén?
5. Basic vs Advanced khác nhau cốt lõi ở điểm nào? Cái nào cần license?
6. Khi nào compression **không** đáng làm (dù đĩa đầy)?


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/labs/section_30/README.md`
