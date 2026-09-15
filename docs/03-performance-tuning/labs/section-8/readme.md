---
title: Lab Section 8 — Instance Activity Statistics & Wait Events
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/labs/section_8/README.md
---

# Lab Section 8 — Instance Activity Statistics & Wait Events

> Nguồn: Practice 3 (Ahmed Baraka) · Guide: [section_all/section_8_instance_activity_wait_events_guide.md](../../section-all/section-8-instance-activity-wait-events-guide.md)
> Chạy từ thư mục này (`labs/section_8/`). Quy ước chung: [labs/README.md](../readme.md)

**Câu hỏi lab trả lời:** 6 view thống kê (V$SYSSTAT / V$SESSTAT / V$MYSTAT / V$SYSTEM_EVENT / V$SESSION_EVENT / V$SESSION) khác nhau chỗ nào, và điều tra một session bị treo như thế nào?

## Chạy lab

```powershell
sqlplus soe/soe@//localhost:15210/ORADB          # chỉ cho bước 01
@01_setup.sql                  -- tạo LAB_EMP 200 rows (nhân vật chính: EMP_NO=104)

sqlplus system/oracle_4U@//localhost:15210/ORADB # các bước còn lại
@02_workload.sql               -- sinh tải nền 4 user × 180s, trả về NGAY
@03_diagnose.sql               -- chạy NHIỀU LẦN khi tải còn sống — xem số tăng dần
@04_usecase_hung_session.sql   -- ~2 phút, tự động: blocker giữ lock 75s + victim treo
@99_cleanup.sql
```

Khác course: 2 cửa sổ Putty thủ công → external job dựng blocker/victim tự động (`lock_demo.sh`); Swingbench → `_toolkit/workload_soe.sql`.

## Số đo thật (VM srv1, 2026-07-14)

- Tải 4 user: top wait Concurrency 52% (`cursor: pin S`, `latch: cache buffers chains`) — đặc trưng nhiều session chạy CÙNG MỘT SQL trên máy ít CPU.
- Hung session (04): victim SID 38 — `STATE=WAITING`, `WAIT_TIME=0`, `SECONDS_IN_WAIT` 12→32 (tăng dần); trong lúc treo `V$SESSION_WAIT_HISTORY` = **0 row**; sau khi blocker rollback: `V$SESSION_EVENT` ghi 1 wait 72s, wait history ghi 7202cs.

## 3 bài học phải thuộc

1. **Đọc đúng cột khi session ĐANG chờ**: `WAIT_TIME=0` + `STATE=WAITING` nghĩa là đang chờ (xem `SECONDS_IN_WAIT`); `WAIT_TIME>0` là wait ĐÃ XONG. Đọc nhầm → kết luận ngược.
2. **`V$SESSION_WAIT_HISTORY` chỉ ghi wait đã hết hạn** — đang treo thì không thấy gì trong đó.
3. **Mọi view V$SESSION\* chết theo session** — logout là mất sạch. Muốn truy vết quá khứ phải có AWR (Section 9) / ASH (Section 13).

## Bẫy build lab

- Dòng `PROMPT` kết thúc bằng `-` bị SQL*Plus hiểu là nối dòng → nuốt lệnh kế tiếp.
- **COMMIT trong PL/SQL loop được tối ưu thành batch/nowait → không sinh `log file sync`**; workload toolkit phải dùng `COMMIT WRITE IMMEDIATE WAIT` mới giống client thật.

## Câu hỏi tự kiểm tra

1. Muốn biết "hệ thống đang chờ gì nhiều nhất từ lúc startup" dùng view nào? "Session X đời nó đã chờ gì" dùng view nào? "Session X NGAY LÚC NÀY đang chờ gì"?
2. V$SESSTAT thiếu cột NAME — phải join với view nào?
3. Vì sao lúc victim đang treo, `V$SESSION_WAIT_HISTORY` chưa có `enq: TX`?
4. P1/P2/P3 của một wait event tra nghĩa ở đâu?
5. Idle wait (`SQL*Net message from client`) có đáng lo không? Khi nào có?


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/labs/section_8/README.md`
