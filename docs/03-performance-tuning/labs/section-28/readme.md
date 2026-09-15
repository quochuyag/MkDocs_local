---
title: Lab Section 28 — Row Migration & Row Chaining
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/labs/section_28/README.md
---

# Lab Section 28 — Row Migration & Row Chaining

> Nguồn: Practice 30 (Ahmed Baraka) · Guide: [section_all/section_28_row_migration_chaining_guide.md](../../section-all/section-28-row-migration-chaining-guide.md)
> Chạy từ thư mục này (`labs/section_28/`). Quy ước chung: [labs/README.md](../readme.md)

**🎓 Học theo buổi đầy đủ (SSH vào VM, từng bước, có dự đoán + đáp án + output thật):**
👉 **[HUONG_DAN_HOC_SECTION_28.md](huong-dan-hoc-section-28.md)** — đã kiểm chứng end-to-end trong VM 2026-07-14

## Chạy lab chính (row MIGRATION) — user `soe`

```powershell
sqlplus soe/soe@//localhost:15210/ORADB
```

```
@01_setup.sql            -- tạo CUST 200k rows, ~33% migrated (~1-2 phút)
@02_workload.sql 100000  -- đo BASELINE: ghi lại logical reads / continued row / CPU
@03_diagnose.sql         -- chứng minh nguyên nhân (ANALYZE vs DBMS_STATS)
@04_fix.sql 100000       -- PCTFREE 20 + MOVE ONLINE, tự đo lại và so sánh
```

**Kỳ vọng** (số đo thật trên VM srv1, 2026-07-14, loop 100000 ≈ 66,666 queries):

| Chỉ số session | Trước fix | Sau fix |
|---|---|---|
| `table fetch continued row` | ~30,600 | **0** |
| `session logical reads` | ~231,700 | ~200,400 (giảm ≈ đúng số continued row) |
| `CPU used by this session` | ~103 cs | ~93 cs |
| `BLOCKS` của CUST | 13,036 (PCTFREE 10) | 15,451 (PCTFREE 20 — giá phải trả) |

Chẩn đoán (03): ANALYZE đếm được 61,267 rows migrate (30.63%) — đúng 100% quy luật `MOD(customer_id,3)=0`; DBMS_STATS báo CHAIN_CNT = 0 (số 0 giả!).

## Mở rộng (tùy chọn) — user `SYS` qua **CDB root** (bắt buộc: `db_32k_cache_size` là tham số instance, ORA-65040 nếu set trong PDB)

```powershell
sqlplus "sys/oracle_4U@//localhost:15210/ORCLCDB as sysdba"
```

```
@05_row_chaining_32k.sql -- row CHAINING thật (row 8KB > block 8K), giải bằng tablespace 32K
```

## Dọn dẹp — cùng user SYS ở trên (system@ORADB cũng được, trừ reset cache 32K)

```
@99_cleanup.sql          -- xóa bảng lab, tablespace TBS32K, cache 32K
```

## Câu hỏi tự kiểm tra (trả lời trước khi xem 03/04)

1. `CHAIN_CNT` do lệnh nào tạo ra — `DBMS_STATS` hay `ANALYZE`? Vì sao production vẫn phải gather lại bằng `DBMS_STATS` sau khi `ANALYZE`?
2. Nhìn `AVG_ROW_LEN` = 450 và block 8K — đây là migration hay chaining? Cách fix khác nhau thế nào?
3. Vì sao chỉ `ALTER TABLE ... PCTFREE 20` mà không `MOVE` thì migration cũ vẫn còn nguyên?
4. `MOVE` vs `MOVE ONLINE` vs `DBMS_REDEFINITION` — chọn cái nào cho bảng 24x7? Trade-off?
5. Thống kê nào trong `V$MYSTAT` là bằng chứng trực tiếp của migration/chaining khi đọc dữ liệu?


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/labs/section_28/README.md`
