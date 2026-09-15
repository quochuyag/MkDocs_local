---
title: Lab Section 12 — ADDM (Automatic Database Diagnostic Monitor)
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/labs/section_12/README.md
---

# Lab Section 12 — ADDM (Automatic Database Diagnostic Monitor)

> Nguồn: Practice 10 (Ahmed Baraka) · Guide: [section_all/](../../section_all/)
> Chạy từ thư mục này (`labs/section_12/`). Quy ước chung: [labs/README.md](../readme.md)
> ⚠️ **Chưa kiểm chứng trên VM** — buổi chạy đầu tiên điền số thật vào mục "Số đo".

**Câu hỏi lab trả lời:** ADDM tự chẩn đoán được gì từ một cặp AWR snapshot, đọc chuỗi findings → recommendations → actions thế nào, và vì sao KHÔNG được làm theo khuyến nghị một cách mù quáng?

## Chạy lab — user `system` (toàn bộ trong PDB ORADB)

```powershell
sqlplus system/oracle_4U@//localhost:15210/ORADB
```

```
@01_setup.sql            -- điều kiện ADDM + snapshot B
@02_workload.sql         -- ~3.5 phút: 8 user × 180s (CPU bão hòa) + snapshot E
@03_diagnose.sql         -- DBMS_ADDM.ANALYZE_INST + report + drill-down 3 tầng
@04_usecase_compare.sql  -- ~2.5 phút: dựng cửa sổ yên tĩnh + COMPARE_INSTANCES (HTML)
@99_cleanup.sql
```

Khác course: EM Express → SQL*Plus thuần; Swingbench + `stress --cpu` → 8 phiên toolkit (đủ bão hòa 2 vCPU, số liệu section_6); addmrpt.sql interactive → `DBMS_ADDM.ANALYZE_INST` batch; baseline OLTP_NORMAL → tự dựng cửa sổ yên tĩnh để so sánh.

## Số đo (điền sau buổi chạy đầu tiên)

| Chỉ số | Kỳ vọng | Số thật |
|---|---|---|
| Finding lớn nhất | CPU Usage (impact cao nhất) hoặc Top SQL | |
| Khuyến nghị cho CPU | "Consider adding more CPUs..." | |
| SQL Commonality trong compare report | THẤP (<80% — một bên idle, cố ý để học cách đọc) | |
| AAS cửa sổ quá tải vs yên tĩnh | chênh nhiều lần | |

## 3 bài học phải thuộc

1. **ADDM chỉ thấy triệu chứng**: "add more CPUs" nghĩa thật là "CPU không phục vụ kịp yêu cầu trong cửa sổ đo" — tín hiệu để đi điều tra (Section 25), không phải lệnh mua máy.
2. **Chuỗi 3 tầng**: findings (impact % DB time) → recommendations (benefit) → actions (việc cụ thể) — nằm trong `DBA_ADDM_FINDINGS` / `DBA_ADVISOR_RECOMMENDATIONS` / `DBA_ADVISOR_ACTIONS`, cùng bộ view của mọi advisor.
3. **Multitenant**: auto-ADDM chạy ở CDB root trên snapshot CDB; trong PDB muốn có ADDM phải tự chạy tay trên snapshot PDB-local (19c).

## Câu hỏi tự kiểm tra

1. ADDM lấy dữ liệu từ đâu — nó có tự đo gì không?
2. Task name của auto-ADDM có format gì? Vì sao trong PDB `DBA_ADDM_TASKS` trống?
3. IMPACT của finding tính theo đơn vị gì? Vì sao tổng impact các finding có thể vượt 100%?
4. Compare report cần điều kiện gì để so sánh HỢP LỆ? (gợi ý: SQL Commonality)
5. ADDM thuộc pack license nào? Hệ quả với Standard Edition?


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/labs/section_12/README.md`
