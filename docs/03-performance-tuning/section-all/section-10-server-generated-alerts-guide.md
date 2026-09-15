---
title: Section 10 — Server-generated Alerts
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/section_all/section_10_server_generated_alerts_guide.md
---

# Section 10 — Server-generated Alerts

## Tổng quan

Oracle có thể tự động phát cảnh báo khi các metric hiệu năng vượt ngưỡng đã cấu hình. Tính năng này giúp DBA **chủ động** phát hiện vấn đề trước khi người dùng báo cáo.

**Practice 8 — Using Server-generated Alerts**

Mục tiêu:
- Đo giá trị bình thường của "Database Wait Time %" khi hệ thống hoạt động ổn định
- Cấu hình ngưỡng cảnh báo (warning/critical)
- Kiểm tra alert khi tải tăng cao

---

## Kiến thức lý thuyết

### Database Wait Time % là gì?

Công thức:
```
DB Wait Time % = 100% - DB CPU %
             = (DB Time - DB CPU Time) / DB Time * 100
```

- **DB Time** = tổng thời gian foreground sessions tiêu tốn (CPU + waiting)
- **DB CPU Time** = phần CPU time trong DB Time
- **DB Wait Time %** = tỷ lệ thời gian chờ đợi so với tổng DB Time

Ý nghĩa: metric này càng cao → sessions càng chờ nhiều → hệ thống có vấn đề.

### Các views liên quan

| View | Mô tả |
|------|-------|
| `V$METRICNAME` | Danh sách tên tất cả các metric và ID của chúng |
| `V$SYSMETRIC_HISTORY` | Lịch sử metric hệ thống theo time slice (5 phút/1 phút) |
| `V$SYSMETRIC` | Giá trị metric hiện tại |
| `V$SYS_TIME_MODEL` | Time model statistics toàn hệ thống |
| `DBA_THRESHOLDS` | Ngưỡng cảnh báo đã cấu hình |
| `DBA_OUTSTANDING_ALERTS` | Cảnh báo đang active (chưa clear) |
| `DBA_ALERT_HISTORY` | Lịch sử tất cả cảnh báo (kể cả đã clear) |

---

## Bước 1: Xác định Metric ID của DATABASE_WAIT_TIME%

```sql
set linesize 180
col GROUP_NAME format a40
col metric_name format a30

SELECT GROUP_NAME, METRIC_NAME, METRIC_ID
FROM V$METRICNAME
WHERE UPPER(METRIC_NAME) LIKE 'DATABASE_WAIT_TIME%';
```

> Kết quả có 2 dòng:
> - METRIC_ID = **2107** → dùng cho non-CDB database
> - METRIC_ID khác → dùng cho PDB (multitenant)

---

## Bước 2: Lấy giá trị Wait Time % hiện tại

### Cách nhanh nhất — V$SYSMETRIC

```sql
SELECT METRIC_NAME, VALUE
FROM V$SYSMETRIC
WHERE METRIC_NAME IN ('Database CPU Time Ratio', 'Database Wait Time Ratio')
  AND INTSIZE_CSEC = (SELECT MAX(INTSIZE_CSEC) FROM V$SYSMETRIC);
```

### Từ lịch sử theo thời gian — V$SYSMETRIC_HISTORY

```sql
-- Lưu thời điểm bắt đầu quan sát
VARIABLE START_TIME VARCHAR2(20)
exec :START_TIME := TO_CHAR(SYSDATE, 'DD-MM-YY HH24:MI:SS')
print :START_TIME

-- Xem time slice chi tiết trong 10 phút
ALTER SESSION SET NLS_DATE_FORMAT='DD-MON-RR HH24:MI:SS';
SELECT BEGIN_TIME, END_TIME, ROUND(VALUE,4) WAIT_TIME_PCT
FROM V$SYSMETRIC_HISTORY
WHERE METRIC_ID = 2107
  AND BEGIN_TIME BETWEEN TO_DATE(:START_TIME,'DD-MM-YY HH24:MI:SS')
                     AND TO_DATE(:START_TIME,'DD-MM-YY HH24:MI:SS') + (10/24/60);
```

```sql
-- Tính giá trị trung bình trong khoảng thời gian quan sát
SELECT AVG(WAIT_TIME_PCT)
FROM (
  SELECT BEGIN_TIME, END_TIME, ROUND(VALUE,4) WAIT_TIME_PCT
  FROM V$SYSMETRIC_HISTORY
  WHERE METRIC_ID = 2107
    AND BEGIN_TIME BETWEEN TO_DATE(:START_TIME,'DD-MM-YY HH24:MI:SS')
                       AND TO_DATE(:START_TIME,'DD-MM-YY HH24:MI:SS') + (10/24/60)
);
```

### Từ Time Model View — V$SYS_TIME_MODEL

```sql
SELECT
  ROUND(VALUE/(SELECT VALUE FROM V$SYS_TIME_MODEL WHERE STAT_NAME='DB time')*100,2) DB_CPU_PCT,
  100 - ROUND(VALUE/(SELECT VALUE FROM V$SYS_TIME_MODEL WHERE STAT_NAME='DB time')*100,2) TOTAL_WAIT_PCT
FROM V$SYS_TIME_MODEL
WHERE STAT_NAME = 'DB CPU';
```

> **So sánh 3 nguồn:**
> - `V$SYS_TIME_MODEL`: tính từ khi instance startup → không phản ánh trạng thái hiện tại
> - `V$SYSMETRIC_HISTORY`: time slice ngắn (5 phút) → chính xác hơn cho hiện tại
> - AWR report: đại diện cho một khoảng thời gian cụ thể → dùng khi cần phân tích lịch sử

---

## Bước 3: Cấu hình Alert Threshold

### Đặt ngưỡng cảnh báo bằng DBMS_SERVER_ALERT

```sql
begin
  DBMS_SERVER_ALERT.SET_THRESHOLD(
    METRICS_ID            => DBMS_SERVER_ALERT.DATABASE_WAIT_TIME,
    WARNING_OPERATOR      => DBMS_SERVER_ALERT.OPERATOR_GE,   -- Greater or Equal
    WARNING_VALUE         => '70',    -- Cảnh báo khi Wait Time % >= 70%
    CRITICAL_OPERATOR     => DBMS_SERVER_ALERT.OPERATOR_GE,
    CRITICAL_VALUE        => '90',    -- Critical khi Wait Time % >= 90%
    OBSERVATION_PERIOD    => 1,       -- Quan sát trong 1 phút
    CONSECUTIVE_OCCURRENCES => 1,     -- Xảy ra 1 lần liên tiếp thì báo
    INSTANCE_NAME         => NULL,
    OBJECT_TYPE           => DBMS_SERVER_ALERT.OBJECT_TYPE_SYSTEM,
    OBJECT_NAME           => NULL
  );
end;
/
```

> **Lưu ý:** Giá trị ngưỡng là phần trăm (0-100), không phải tỷ lệ (0-1).

### Kiểm tra cấu hình qua DBA_THRESHOLDS

```sql
SELECT
  'METRICS_NAME: ' || METRICS_NAME || CHR(10) ||
  'WARNING_VALUE: ' || WARNING_VALUE || CHR(10) ||
  'CRITICAL_VALUE: ' || CRITICAL_VALUE || CHR(10) ||
  'OBSERVATION_PERIOD: ' || OBSERVATION_PERIOD || CHR(10) ||
  'CONSECUTIVE_OCCURRENCES: ' || CONSECUTIVE_OCCURRENCES || CHR(10) ||
  'STATUS: ' || STATUS AS INFO
FROM DBA_THRESHOLDS
WHERE METRICS_NAME = 'Database Wait Time Ratio';
```

---

## Bước 4: Kiểm tra Alert khi tải cao

### Theo dõi metric realtime

```sql
-- Chạy lặp lại để theo dõi
SELECT ROUND(VALUE,4) WAIT_TIME_PCT
FROM V$SYSMETRIC_HISTORY
WHERE METRIC_ID = 2107
ORDER BY BEGIN_TIME DESC FETCH FIRST 1 ROWS ONLY;
```

### Kiểm tra alert đang active

```sql
SELECT
  'SEQUENCE_ID: ' || SEQUENCE_ID || CHR(10) ||
  'REASON: ' || REASON || CHR(10) ||
  'TIME_SUGGESTED: ' || TIME_SUGGESTED || CHR(10) ||
  'CREATION_TIME: ' || CREATION_TIME || CHR(10) ||
  'SUGGESTED_ACTION: ' || SUGGESTED_ACTION || CHR(10) ||
  'METRIC_VALUE: ' || METRIC_VALUE || CHR(10) ||
  'MESSAGE_TYPE: ' || MESSAGE_TYPE AS INFO
FROM DBA_OUTSTANDING_ALERTS
ORDER BY SEQUENCE_ID;
```

> **Cột quan trọng:**
> - `REASON`: mô tả lý do cảnh báo
> - `SUGGESTED_ACTION`: Oracle gợi ý hành động xử lý
> - `MESSAGE_TYPE`: WARNING hoặc CRITICAL

### Đếm alert đang active

```sql
SELECT COUNT(*) FROM DBA_OUTSTANDING_ALERTS ORDER BY SEQUENCE_ID;
```

### Xem alert đã cleared trong lịch sử

```sql
SELECT
  'REASON: ' || REASON || CHR(10) ||
  'CREATION_TIME: ' || CREATION_TIME || CHR(10) ||
  'METRIC_VALUE: ' || METRIC_VALUE || CHR(10) ||
  'RESOLUTION: ' || RESOLUTION || CHR(10) ||
  'MESSAGE_TYPE: ' || MESSAGE_TYPE AS INFO
FROM DBA_ALERT_HISTORY
ORDER BY SEQUENCE_ID DESC FETCH FIRST 1 ROWS ONLY;
```

> `RESOLUTION = 'cleared'` → alert tự động cleared khi metric trở về bình thường.

---

## Quy trình thực hành đầy đủ

```
1. Chạy workload bình thường → Đo giá trị Wait Time % cơ sở (baseline)
2. Ghi lại giá trị trung bình → Ví dụ: 20%
3. Đặt ngưỡng: WARNING = baseline × 3 (60%), CRITICAL = 90%
4. Tăng tải → Theo dõi V$SYSMETRIC_HISTORY
5. Verify: DBA_OUTSTANDING_ALERTS có alert xuất hiện không
6. Giảm tải → Verify: alert tự cleared, xem DBA_ALERT_HISTORY
```

---

## Tóm tắt

| Khái niệm | Chi tiết |
|-----------|---------|
| Mục đích | Phát hiện sớm vấn đề hiệu năng thông qua metric tự động |
| Metric chính | `Database Wait Time Ratio` (METRIC_ID = 2107) |
| Package cấu hình | `DBMS_SERVER_ALERT` |
| Alert views | `DBA_OUTSTANDING_ALERTS`, `DBA_ALERT_HISTORY` |
| Yêu cầu | Phải biết giá trị baseline trước khi đặt ngưỡng |
| Alert lifecycle | WARNING → CRITICAL → cleared (tự động khi metric giảm) |

> **Nguyên tắc quan trọng:** Đặt ngưỡng cố định (static threshold) chỉ hiệu quả khi hệ thống có workload tương đối ổn định. Nếu workload biến động lớn theo giờ/ngày, cần tính toán ngưỡng riêng cho từng khung giờ.


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/section_all/section_10_server_generated_alerts_guide.md`
