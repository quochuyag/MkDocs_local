---
title: Lab Section 17 — Automated Maintenance Tasks
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/labs/section_17/README.md
---

# Lab Section 17 — Automated Maintenance Tasks

> Nguồn: Practice 17 (Ahmed Baraka) · Guide: [section_all/](../../section_all/)
> Chạy từ thư mục này (`labs/section_17/`). Quy ước chung: [labs/README.md](../readme.md)
> ⚠️ **Chưa kiểm chứng trên VM** — buổi chạy đầu tiên điền số thật vào mục "Số đo".

**Câu hỏi lab trả lời:** Oracle tự chạy 3 việc bảo trì nào, vào lúc nào, và DBA điều khiển chúng (đổi giờ, tắt/bật) ra sao để chúng không giẫm lên giờ cao điểm?

## Chạy lab — user `system` (lab cấu hình, không cần sinh tải)

```powershell
sqlplus system/oracle_4U@//localhost:15210/ORADB
```

```
@01_setup.sql            -- 3 auto tasks + 7 window + GHI LẠI config gốc
@02_workload.sql         -- bài tập course: hoán đổi lịch SUNDAY ↔ FRIDAY
@03_diagnose.sql         -- xác minh + log lịch sử job ORA$AT% + client history
@04_usecase_task_onoff.sql -- tắt/bật sql tuning advisor (DBMS_AUTO_TASK_ADMIN)
@99_cleanup.sql          -- khôi phục lịch mặc định 2 window
```

Khác course: chạy bằng system trong PDB (thay vì sysdba); bổ sung 04 (tắt/bật task — use case license phổ biến).

## Số đo (điền sau buổi chạy đầu tiên)

| Chỉ số | Kỳ vọng | Số thật |
|---|---|---|
| Số task trong DBA_AUTOTASK_CLIENT | 3, đều ENABLED | |
| Window ngày thường / cuối tuần | 22:00+4h / 06:00+20h | |
| Log ORA$AT% trên VM lab | thưa thớt (VM tắt ban đêm — window không kịp mở) | |
| Sau 02: SUNDAY / FRIDAY | 22:00+4h / 06:00+20h (đã hoán đổi) | |

## 3 bài học phải thuộc

1. **3 task mặc định**: auto optimizer stats (gần như không bao giờ tắt), auto space advisor, sql tuning advisor (shop không mua Tuning Pack **phải** tắt — vấn đề license, không phải hiệu năng).
2. **Muốn sửa window phải DISABLE → SET_ATTRIBUTE → ENABLE** — sửa window đang enabled bị chặn.
3. Job của auto task (`ORA$AT_...`) được **tạo tại chỗ** khi window mở — xem lịch sử ở `DBA_SCHEDULER_JOB_LOG` + `DBA_AUTOTASK_CLIENT_HISTORY`; đổi giờ window = đổi giờ mọi task trong window group đó.

## Câu hỏi tự kiểm tra

1. Ba automated tasks là gì, task nào nguy hiểm nhất nếu TẮT, task nào nguy hiểm nhất nếu ĐỂ BẬT (ngữ cảnh license)?
2. Muốn auto stats không chạy vào đêm thứ Hai (có batch nặng) nhưng vẫn chạy các đêm khác — làm thế nào?
3. Window mở nhưng công việc chưa xong khi window đóng — chuyện gì xảy ra với job stats đang chạy dở?
4. `MEAN_JOB_DURATION` trong DBA_AUTOTASK_CLIENT dùng để làm gì khi quy hoạch window?
5. Trên hệ thống 24x7 tải đều, lịch mặc định (22:00 weekday) có hợp lý không? Cân nhắc gì khi dời?


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/labs/section_17/README.md`
