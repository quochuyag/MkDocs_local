---
title: Lab Section 16 — Real-time Database Operation Monitoring
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/labs/section_16/README.md
---

# Lab Section 16 — Real-time Database Operation Monitoring

> Nguồn: Practice 16 (Ahmed Baraka) · Guide: [section_all/](../../section_all/)
> Chạy từ thư mục này (`labs/section_16/`). Quy ước chung: [labs/README.md](../readme.md)
> ⚠️ **Chưa kiểm chứng trên VM** — buổi chạy đầu tiên điền số thật vào mục "Số đo".

**Câu hỏi lab trả lời:** câu SQL/nghiệp vụ ĐANG CHẠY "tới đâu rồi" — xem bằng gì mà không cần trace, và gom nhiều câu lệnh thành một operation có tên để theo dõi như một khối thế nào?

## Chạy lab — user `system`

```powershell
sqlplus system/oracle_4U@//localhost:15210/ORADB
```

```
@01_setup.sql          -- điều kiện (TUNING pack) + hàm soe.lab_consume_cpu
@02_workload.sql       -- ~1.5 phút: V$SQL_MONITOR tự bắt query >5s (CPU tăng, DISK đứng)
@03_diagnose.sql       -- ~4.5 phút: composite op BEGIN/END_OPERATION + plan real-time
@04_usecase_report.sql -- REPORT_SQL_MONITOR text → /tmp/lab16_sqlmon_report.txt
@99_cleanup.sql
```

File phụ trợ: `monitor_client.sh` (client 2 kịch bản simple/dbop).
Khác course: 2 cửa sổ → external job với timeline tự động; EM Express → `REPORT_SQL_MONITOR` (cùng dữ liệu, dạng text); query nặng 13000×13000 → 8000×8000 (VM 2 vCPU).

## Số đo (điền sau buổi chạy đầu tiên)

| Chỉ số | Kỳ vọng | Số thật |
|---|---|---|
| MY QUERY 1 xuất hiện trong V$SQL_MONITOR sau | ~5-6 giây (ngưỡng 5s CPU) | |
| CPU_TIME giữa 2 lần đo | tăng; DISK_READS = 0 không đổi | |
| Tasks của operation | chỉ query NẶNG hiện IN_DBOP_NAME; SELECT SYSDATE không | |
| OUTPUT_ROWS giữa 2 lần đo plan | tăng (query đang chạy) | |
| STATUS sau END_OPERATION | EXECUTING → DONE (sau roundtrip của client) | |

## 3 bài học phải thuộc

1. **Tự động, không cần bật**: mọi câu chạy song song hoặc >5 giây CPU/IO được monitor tự động (điều kiện: `CONTROL_MANAGEMENT_PACK_ACCESS=DIAGNOSTIC+TUNING` — đây là **Tuning Pack**). Nhược điểm lớn nhất theo tác giả course: câu <5s không được bắt.
2. **Composite operation**: `DBMS_SQL_MONITOR.BEGIN_OPERATION(dbop_name, sid, serial#, forced_tracking=>'Y')` đặt tên cho cả nghiệp vụ; row có `DBOP_NAME` = operation, row có `IN_DBOP_NAME` = từng câu thuộc nó; STATUS chỉ cập nhật sau roundtrip kế tiếp của client.
3. **V$SQL_PLAN_MONITOR** = execution plan SỐNG: OUTPUT_ROWS từng step nhảy theo thời gian thực — trả lời "kẹt ở step nào" khi câu chưa chạy xong (khác DBMS_XPLAN chỉ xem plan tĩnh).

## Câu hỏi tự kiểm tra

1. Điều kiện license nào để dùng SQL Monitoring? Khác gì điều kiện của AWR/ASH?
2. Vì sao SELECT SYSDATE không xuất hiện thành task dù operation có FORCED_TRACKING='Y'?
3. Sau END_OPERATION status vẫn EXECUTING — vì sao, và khi nào nó đổi?
4. Khi nào dùng SQL Monitor thay vì trace (lab 15)? Khi nào ngược lại?
5. Muốn xem report SQL Monitor của một câu chạy HÔM QUA thì lấy ở đâu (19c)?


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/labs/section_16/README.md`
