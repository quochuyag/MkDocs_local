---
title: Lab Section 13 — ASH (Active Session History) & Dimension Views
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/labs/section_13/README.md
---

# Lab Section 13 — ASH (Active Session History) & Dimension Views

> Nguồn: Practice 11 + 12 (Ahmed Baraka) gộp thành 1 lab · Guide: [section_all/](../../section_all/)
> Chạy từ thư mục này (`labs/section_13/`). Quy ước chung: [labs/README.md](../readme.md)
> ⚠️ **Chưa kiểm chứng trên VM** — buổi chạy đầu tiên điền số thật vào mục "Số đo".

**Câu hỏi lab trả lời:** khi session gây sự cố ĐÃ THOÁT (V$SESSION* mất sạch — bài học section_8), ASH truy ngược được đến đâu — và cách "phân rã DB time theo bất kỳ dimension nào" bằng một mẫu GROUP BY?

## Chạy lab

```powershell
sqlplus soe/soe@//localhost:15210/ORADB          # chỉ cho bước 01
@01_setup.sql                 -- LAB_EMP 200 rows (nhân vật chính: EMP_NO=104)

sqlplus system/oracle_4U@//localhost:15210/ORADB # các bước còn lại
@02_workload.sql              -- ~2 phút: 2 phiên ACTION='PROCESS_CORDERS' block nhau rồi THOÁT
@03_diagnose.sql              -- điều tra hậu kỳ: ASH → SQL_ID → dựng ROWID → đúng row 104
@04_usecase_dimensions.sql    -- ~2.5 phút: DB time theo module/SQL/object/block
@05_ash_report.sql            -- (mở rộng) ASH report text 20 phút gần nhất
@99_cleanup.sql
```

Khác course: 2 cửa sổ Putty thủ công → `ash_lock_demo.sh` (external job, 2 phiên gắn ACTION rồi exit); Swingbench → toolkit; ashrpti.sql 14 define → `ASH_REPORT_TEXT`; obj#/file#/block#/row# gõ tay → tự nhặt từ ASH.

## Số đo (điền sau buổi chạy đầu tiên)

| Chỉ số | Kỳ vọng | Số thật |
|---|---|---|
| Số sample `enq: TX` của victim | ≈ số giây treo (~55-60) — ASH sample mỗi 1s | |
| BLOCKING_SESSION trong sample | = SID blocker | |
| Row dựng lại từ CURRENT_* + DBMS_ROWID | EMP_NO = 104 | |
| Top module trong [1] của 04 | SQL*Plus (phiên toolkit) áp đảo | |

## 3 bài học phải thuộc

1. **Đếm sample = ước lượng thời gian**: V$ASH mỗi sample ≈ 1 giây; DBA_HIST_ASH mỗi sample ≈ 10 giây (nhân 10). Không cần cột time nào khác cho phân tích thô.
2. **ASH là view "muôn dimension"**: GROUP BY module/action/sql_id/event/current_obj#/user_id... là có ngay DB time phân rã theo chiều đó — một mẫu query dùng cho mọi câu hỏi.
3. **Chuỗi truy ngược hậu kỳ**: ACTION → sample enq: TX → SQL_ID (câu lệnh) → CURRENT_OBJ#/FILE#/BLOCK#/ROW# + `DBMS_ROWID.ROWID_CREATE` → đúng ROW tranh chấp — kể cả khi session đã chết.

## Câu hỏi tự kiểm tra

1. V$ACTIVE_SESSION_HISTORY chứa session nào — mọi session hay chỉ session active? Idle session có để lại sample không?
2. Vì sao query trên DBA_HIST_ACTIVE_SESS_HISTORY phải SUM(10) thay vì COUNT(*)?
3. Sự cố kéo dài 90 giây: AWR report 60 phút có "thấy" không? Công cụ nào bắt được spike này và bằng mục nào của report?
4. TOP_LEVEL_SQL_ID khác SQL_ID nói lên điều gì?
5. Vì sao wait `db file sequential read` có thể "lọt lưới" ASH? (gợi ý: sample 1 giây vs wait vài ms)


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/labs/section_13/README.md`
