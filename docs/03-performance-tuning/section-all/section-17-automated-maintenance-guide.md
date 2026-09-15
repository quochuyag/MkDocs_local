---
title: Section 17 — Automated Maintenance Tasks
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/section_all/section_17_automated_maintenance_guide.md
---

# Section 17 — Automated Maintenance Tasks

## Tổng quan

Oracle Database tự động chạy một số maintenance tasks định kỳ trong các **Maintenance Windows** (cửa sổ bảo trì). DBA cần biết cách xem thông tin về các tasks này và điều chỉnh lịch chạy khi cần thiết.

**Practice 17 — Managing Automated Maintenance Tasks**

Mục tiêu:
- Xem thông tin về các automated maintenance tasks
- Xem các Scheduler Windows gắn với tasks
- Thay đổi thời gian và thời lượng của maintenance windows
- Xem lịch sử chạy của các tasks

---

## Kiến thức lý thuyết

### 3 Automated Maintenance Tasks mặc định

Oracle cấu hình sẵn 3 tasks:

| Task | CLIENT_NAME | Mô tả |
|------|-------------|-------|
| Auto Optimizer Stats Collection | `auto optimizer stats collection` | Thu thập statistics cho optimizer |
| Auto Space Advisor | `auto space advisor` | Phân tích và tư vấn về không gian lưu trữ |
| SQL Tuning Advisor | `sql tuning advisor` | Tự động phân tích SQL performance |

Mỗi task có **Window Group** riêng. Window Group chứa các Scheduler Windows xác định khi nào task được chạy.

### Maintenance Windows mặc định

Oracle tạo sẵn window cho mỗi ngày trong tuần:
- **Weekdays (Mon–Fri):** Mở lúc 22:00, kéo dài 4 giờ
- **Weekends (Sat–Sun):** Mở lúc 06:00, kéo dài 20 giờ

---

## Phần 1: Xem thông tin Automated Tasks

### Xem danh sách tasks và thống kê

```sql
set linesize 180
set pagesize 30
col "Auto Optimizer Stats Info." format a100

SELECT
  'CLIENT_NAME: '              || CLIENT_NAME              || CHR(10) ||
  'STATUS: '                   || STATUS                   || CHR(10) ||
  'WINDOW_GROUP: '             || WINDOW_GROUP             || CHR(10) ||
  'MEAN_JOB_DURATION: '        || MEAN_JOB_DURATION        || CHR(10) ||
  'MEAN_JOB_CPU: '             || MEAN_JOB_CPU             || CHR(10) ||
  'MAX_DURATION_LAST_7_DAYS: ' || MAX_DURATION_LAST_7_DAYS || CHR(10) ||
  'MAX_DURATION_LAST_30_DAYS: '|| MAX_DURATION_LAST_30_DAYS AS "Auto Optimizer Stats Info."
FROM DBA_AUTOTASK_CLIENT;
```

**Thông tin quan trọng:**
- `STATUS = ENABLED/DISABLED`: task có đang bật không
- `WINDOW_GROUP`: tên window group của task
- `MEAN_JOB_DURATION`: thời gian chạy trung bình
- `MAX_DURATION_LAST_30_DAYS`: thời gian chạy dài nhất trong 30 ngày → estimate xem có đủ window time không

### Xem Scheduler Windows của một task

```sql
col WINDOW_NAME       format a20
col REPEAT_INTERVAL   format a55
col DURATION          format a15

-- Xem windows của SQL Tuning Advisor (window group: ORA$AT_WGRP_SQ)
SELECT WINDOW_NAME, REPEAT_INTERVAL, DURATION, ENABLED
FROM DBA_SCHEDULER_WINDOWS
WHERE '"SYS"."' || WINDOW_NAME || '"' IN (
  SELECT MEMBER_NAME
  FROM DBA_SCHEDULER_GROUP_MEMBERS
  WHERE GROUP_NAME = 'ORA$AT_WGRP_SQ'
)
ORDER BY NEXT_START_DATE;
```

**Window Group names:**
| Task | Window Group |
|------|-------------|
| SQL Tuning Advisor | `ORA$AT_WGRP_SQ` |
| Auto Space Advisor | `ORA$AT_WGRP_SA` |
| Optimizer Stats Collection | `ORA$AT_WGRP_OS` |

---

## Phần 2: Thay đổi Maintenance Windows

Quy trình: **Disable → Set attributes → Enable**

> Bắt buộc disable window trước khi thay đổi bất kỳ attribute nào.

### Ví dụ: Thay đổi SUNDAY_WINDOW thành 22:00, kéo dài 4 giờ

```sql
BEGIN
  -- Bước 1: Disable
  DBMS_SCHEDULER.DISABLE(NAME => 'SUNDAY_WINDOW');

  -- Bước 2: Thay đổi thời lượng
  DBMS_SCHEDULER.SET_ATTRIBUTE(
    NAME      => 'SUNDAY_WINDOW',
    ATTRIBUTE => 'DURATION',
    VALUE     => NUMTODSINTERVAL(4, 'hour')
  );

  -- Bước 3: Thay đổi lịch lặp
  DBMS_SCHEDULER.SET_ATTRIBUTE(
    NAME      => 'SUNDAY_WINDOW',
    ATTRIBUTE => 'REPEAT_INTERVAL',
    VALUE     => 'freq=daily;byday=SUN;byhour=22;byminute=0;bysecond=0'
  );

  -- Bước 4: Enable lại
  DBMS_SCHEDULER.ENABLE(name => 'SUNDAY_WINDOW');
END;
/
```

### Ví dụ: Thay đổi FRIDAY_WINDOW thành 06:00, kéo dài 20 giờ

```sql
BEGIN
  DBMS_SCHEDULER.DISABLE(NAME => 'FRIDAY_WINDOW');

  DBMS_SCHEDULER.SET_ATTRIBUTE(
    NAME      => 'FRIDAY_WINDOW',
    ATTRIBUTE => 'DURATION',
    VALUE     => NUMTODSINTERVAL(20, 'hour')
  );

  DBMS_SCHEDULER.SET_ATTRIBUTE(
    NAME      => 'FRIDAY_WINDOW',
    ATTRIBUTE => 'REPEAT_INTERVAL',
    VALUE     => 'freq=daily;byday=FRI;byhour=6;byminute=0;bysecond=0'
  );

  DBMS_SCHEDULER.ENABLE(NAME => 'FRIDAY_WINDOW');
END;
/
```

### Verify sau khi thay đổi

```sql
SELECT WINDOW_NAME, REPEAT_INTERVAL, DURATION, ENABLED
FROM DBA_SCHEDULER_WINDOWS
WHERE '"SYS"."' || WINDOW_NAME || '"' IN (
  SELECT MEMBER_NAME
  FROM DBA_SCHEDULER_GROUP_MEMBERS
  WHERE GROUP_NAME = 'ORA$AT_WGRP_OS'  -- Optimizer Stats
)
ORDER BY NEXT_START_DATE;
```

---

## Phần 3: Xem Lịch sử Chạy của Tasks

```sql
col JOB_NAME  format a22
col OPERATION format a12
col STATUS    format a10

SELECT
  TO_CHAR(LOG_DATE,'DD-MM-YYYY HH24:MI:SS') AS LOG_DATE,
  JOB_NAME, OPERATION, STATUS
FROM DBA_SCHEDULER_JOB_LOG
WHERE JOB_NAME LIKE 'ORA$AT%SA%'  -- SA = Space Advisor
ORDER BY LOG_DATE DESC FETCH FIRST 10 ROWS ONLY;
```

**Pattern tên job:** `ORA$AT_<task_abbrev>_<window>_<number>`
- `SA` = Space Advisor
- `OS` = Optimizer Stats
- `SQ` = SQL Tuning Advisor

---

## Tóm tắt

| Tác vụ | Phương pháp |
|--------|------------|
| Xem danh sách tasks | `SELECT FROM DBA_AUTOTASK_CLIENT` |
| Xem windows của task | `DBA_SCHEDULER_WINDOWS` join `DBA_SCHEDULER_GROUP_MEMBERS` |
| Thay đổi window | `DBMS_SCHEDULER.DISABLE` → `SET_ATTRIBUTE` → `ENABLE` |
| Xem lịch sử chạy | `SELECT FROM DBA_SCHEDULER_JOB_LOG WHERE JOB_NAME LIKE 'ORA$AT%'` |

**Khi nào cần điều chỉnh maintenance windows?**
- Task chạy quá lâu, lấn sang giờ cao điểm
- Muốn dồn tất cả maintenance vào cuối tuần
- Server bận vào ban đêm (VD: batch jobs) → cần đổi sang buổi sáng sớm
- `MAX_DURATION_LAST_30_DAYS` lớn hơn duration của window → task chưa hoàn thành trong window → cần kéo dài window


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/section_all/section_17_automated_maintenance_guide.md`
