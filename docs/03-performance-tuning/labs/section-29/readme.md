---
title: Lab Section 29 — Table Fragmentation
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/labs/section_29/README.md
---

# Lab Section 29 — Table Fragmentation

> Nguồn: Practice 31 (Ahmed Baraka) · Guide: [section_all/section_29_table_fragmentation_guide.md](../../section-all/section-29-table-fragmentation-guide.md) · Senior: [section_all_new/section_29_table_fragmentation_senior_guide.md](../../section-all-new/section-29-table-fragmentation-senior-guide.md)
> Chạy từ thư mục này (`labs/section_29/`). Quy ước chung: [labs/README.md](../readme.md)
> ⚠️ **Lab chưa kiểm chứng end-to-end trên VM** — số đo là **kỳ vọng**. Cần đúng **xu hướng**: FTS logical reads giảm mạnh sau shrink, index lookup ~không đổi.

**🎓 Học theo buổi đầy đủ:** 👉 **[HUONG_DAN_HOC_SECTION_29.md](huong-dan-hoc-section-29.md)**

## Ý tưởng lab

Table fragmentation là bài toán **High Water Mark**: DELETE/UPDATE để lại block gần rỗng nhưng **HWM không tự hạ** → **FTS vẫn quét tới HWM** (đọc thừa). Chỉ `TRUNCATE`/`MOVE`/`SHRINK SPACE` mới hạ HWM. Fragmentation **chỉ phạt FTS**, gần như không phạt index unique lookup.

## Chạy lab chính — user `soe`

⚠️ Cần grant một lần (bằng **SYS**) cho `before_after.sql`: `GRANT SELECT ON sys.v_$session_event TO soe;`

```powershell
sqlplus soe/soe@//localhost:15210/ORADB
```
```
@01_setup.sql        -- CUST 100k, UPDATE co row + DELETE bội-3 → fragment (~1-2 phút)
@02_workload.sql 1000 -- đo baseline 2 workload: A=FTS, B=index lookup
@03_diagnose.sql     -- 3 góc đo fragmentation: AVG_SPACE / DBMS_SPACE / actual-vs-HWM
@04_fix.sql 1000     -- ENABLE ROW MOVEMENT + SHRINK SPACE CASCADE, đo lại
```

**Kỳ vọng (chưa kiểm chứng VM):**

| | Trước shrink | Sau shrink |
|---|---|---|
| `BLOCKS` (HWM) | cao | **giảm mạnh** |
| `AVG_SPACE` (free/block) | ~40-50% | thấp |
| WORKLOAD A (FTS) logical reads | rất cao | **giảm rõ rệt** |
| WORKLOAD B (index) logical reads | thấp | ~không đổi |
| Index status | VALID | **VALID** (CASCADE maintain, khác MOVE) |

## Mở rộng (tùy chọn)

- **SHRINK dưới tải DML + ORA-00054** — trong VM: `./cust_update.sh 120` từ session khác, rồi thử `ALTER TABLE cust ENABLE ROW MOVEMENT` (→ ORA-00054). Xem `@05_shrink_dml.sql`.

## Dọn dẹp

```
@99_cleanup.sql      -- xóa CUST
```

## Câu hỏi tự kiểm tra

1. Fragmentation phạt FTS hay index lookup nhiều hơn? Vì sao (liên hệ HWM)?
2. Vì sao DELETE không làm giảm số block FTS phải đọc? Lệnh nào mới hạ HWM?
3. `AVG_SPACE` populate bởi lệnh gì? Tại sao **không** phải `DBMS_STATS`?
4. 3 pha của `SHRINK SPACE` là gì? Pha nào online, pha nào cần lock?
5. Vì sao index **không** UNUSABLE sau `SHRINK SPACE CASCADE` nhưng UNUSABLE sau `ALTER TABLE MOVE`?
6. Vì sao `ENABLE ROW MOVEMENT` báo ORA-00054 khi bảng đang UPDATE?


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/labs/section_29/README.md`
