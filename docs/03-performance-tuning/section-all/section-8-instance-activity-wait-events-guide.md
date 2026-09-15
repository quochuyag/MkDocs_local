---
title: Section 8 — Instance Activity & Wait Events
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/section_all/section_8_instance_activity_wait_events_guide.md
---

# Section 8 — Instance Activity & Wait Events

## Mục tiêu

Hiểu cách đọc thống kê hoạt động instance và wait events để:

- Xem activity statistics toàn instance và theo từng session
- Phân tích wait events theo class, event, và session
- Điều tra session bị treo (hung) hoặc chạy rất chậm

---

## Khái niệm nền tảng

### Instance Activity Statistics là gì?

Là các bộ đếm tích lũy từ lúc instance khởi động, đo lường **số lần** các hoạt động xảy ra trong database (full table scan, index scan, parse, redo writes...).

- **Thường không hữu ích khi xem riêng lẻ** — cần so sánh 2 thời điểm (baseline vs issue period)
- **AWR/Statspack** là công cụ tốt nhất để so sánh theo thời gian
- Một số thống kê non-time-based hữu ích khi xem trực tiếp (ví dụ: số lần full table scan)

### Wait Events là gì?

Khi một Oracle process không thể tiếp tục vì đang chờ tài nguyên, nó ghi lại một **wait event**. Ví dụ:

| Wait Event | Ý nghĩa |
|-----------|---------|
| `log file sync` | Session chờ LGWR ghi redo log (xảy ra khi COMMIT) |
| `db file sequential read` | Chờ đọc 1 block từ disk (index scan) |
| `db file scattered read` | Chờ đọc nhiều block từ disk (full table scan) |
| `enq: TX - row lock contention` | Session chờ vì row đang bị lock bởi session khác |
| `latch: shared pool` | Tranh chấp latch trên shared pool |

**Wait Classes** — nhóm các wait events liên quan:

| Class | Ví dụ |
|-------|-------|
| `Commit` | `log file sync` |
| `User I/O` | `db file sequential read` |
| `Concurrency` | `latch contention` |
| `Application` | `enq: TX - row lock` |
| `Idle` | `SQL*Net message from client` — bỏ qua khi phân tích |

---

## Các Views chính

### Activity Statistics

| View | Mô tả |
|------|-------|
| `V$SYSSTAT` | Thống kê activity toàn instance (tích lũy) |
| `V$SESSTAT` | Thống kê activity từng session (join với `V$STATNAME`) |
| `V$MYSTAT` | Thống kê của **session hiện tại** (không cần biết SID) |
| `V$STATNAME` | Tên và class của từng thống kê |

### Wait Events

| View | Mô tả |
|------|-------|
| `V$SYSTEM_EVENT` | Wait events toàn instance (tích lũy từ startup) |
| `V$SYSTEM_WAIT_CLASS` | Wait events nhóm theo class |
| `V$SESSION_EVENT` | Wait events tích lũy của từng session hiện tại |
| `V$SESSION` | Session hiện tại — bao gồm wait event đang xảy ra |
| `V$SESSION_WAIT` | Chi tiết wait event đang xảy ra của từng session |
| `V$SESSION_WAIT_HISTORY` | 10 wait events gần nhất đã kết thúc của từng session |

---

## Scripts thực hành (Practice 3)

### Xem Activity Statistics toàn instance

```sql
-- Hiển thị tất cả activity statistics, phân loại theo CLASS
SELECT NAME,
  DECODE(TO_CHAR(CLASS),
    '1',  'User',
    '2',  'Redo',
    '4',  'Enqueue',
    '8',  'Cache',
    '16', 'OS',
    '32', 'RAC',
    '64', 'SQL',
    '128','Debug',
    TO_CHAR(CLASS)
  ) CLASS,
  VALUE
FROM V$SYSSTAT
ORDER BY CLASS, NAME;
```

```sql
-- Lấy thống kê cụ thể: full table scan và index scan
SELECT NAME, VALUE
FROM V$SYSSTAT
WHERE (NAME LIKE 'table%' OR NAME LIKE 'index%')
  AND VALUE <> 0
ORDER BY NAME;
```

### Xem Top Sessions theo một thống kê cụ thể

```sql
-- Top sessions theo "parse time cpu"
SELECT s.SID, h.USERNAME, t.NAME, s.VALUE
FROM V$SESSTAT s
JOIN V$STATNAME t ON s.STATISTIC# = t.STATISTIC#
JOIN V$SESSION  h ON s.SID = h.SID
WHERE t.NAME = 'parse time cpu'
  AND h.USERNAME IS NOT NULL
ORDER BY s.VALUE DESC;
```

```sql
-- Kèm theo SQL text đang chạy
SELECT s.SID, h.USERNAME, t.NAME, s.VALUE,
       SUBSTR(q.SQL_TEXT, 1, 25) SQL_TEXT
FROM V$SESSTAT  s
JOIN V$STATNAME t ON s.STATISTIC# = t.STATISTIC#
JOIN V$SESSION  h ON s.SID = h.SID
LEFT JOIN V$SQL q ON h.SQL_ID = q.SQL_ID
WHERE t.NAME = 'parse time cpu'
  AND h.USERNAME IS NOT NULL
ORDER BY s.VALUE DESC;
```

```sql
-- Chỉ xem thống kê của session hiện tại (dùng V$MYSTAT)
SELECT s.SID, h.USERNAME, t.NAME, s.VALUE
FROM V$MYSTAT  s
JOIN V$STATNAME t ON s.STATISTIC# = t.STATISTIC#
JOIN V$SESSION  h ON s.SID = h.SID
WHERE t.NAME = 'parse time cpu';
```

> `V$MYSTAT` hữu ích khi troubleshoot session của chính mình — không cần biết SID.

### Xem Wait Events toàn instance

```sql
-- Non-idle wait events, sắp xếp theo thời gian chờ tích lũy
SELECT EVENT,
       AVERAGE_WAIT,
       TO_CHAR(ROUND(TIME_WAITED/100), '999,999,999') TIME_SECONDS,
       WAIT_CLASS
FROM V$SYSTEM_EVENT
WHERE TIME_WAITED > 0
  AND WAIT_CLASS <> 'Idle'
ORDER BY TIME_WAITED;
```

```sql
-- Tổng wait time theo class
SELECT WAIT_CLASS,
       TO_CHAR(ROUND(TIME_WAITED/100), '999,999,999') TIME_SECONDS
FROM V$SYSTEM_WAIT_CLASS
WHERE TIME_WAITED > 0
  AND WAIT_CLASS <> 'Idle'
ORDER BY TIME_WAITED;

-- Thêm % từng class
SELECT WAIT_CLASS,
       TO_CHAR(ROUND(TIME_WAITED/100), '999,999,999') TIME_SECONDS,
       '%' || ROUND(RATIO_TO_REPORT(TIME_WAITED) OVER () * 100) PCT
FROM V$SYSTEM_WAIT_CLASS
WHERE TIME_WAITED > 0
  AND WAIT_CLASS <> 'Idle'
ORDER BY TIME_SECONDS;
```

### Xem Wait Events theo Session

```sql
-- Wait time tích lũy của từng SOE session cho event 'log file sync'
SELECT e.SID, s.USERNAME, e.EVENT,
       TO_CHAR(ROUND(e.TIME_WAITED/100), '999,999,999') TIME_SECONDS,
       e.WAIT_CLASS
FROM V$SESSION_EVENT e
JOIN V$SESSION s ON e.SID = s.SID
WHERE s.USERNAME = 'SOE'
  AND e.EVENT = 'log file sync'
ORDER BY e.TIME_WAITED;
```

```sql
-- Session đang CHỜ event 'log file sync' tại thời điểm hiện tại
SELECT SID, USERNAME, EVENT, WAIT_TIME, WAIT_CLASS
FROM V$SESSION
WHERE USERNAME = 'SOE'
  AND EVENT = 'log file sync'
ORDER BY WAIT_TIME;
```

---

## Use Case: Điều tra Session Bị Treo

### Tình huống

Hai session cùng chạy:
```sql
UPDATE EMP SET SALARY = SALARY WHERE EMP_NO = 104;
```
Session thứ 2 bị treo vì session thứ 1 đang giữ row lock chưa commit.

### Bước 1 — Tìm session bị treo

```sql
-- Session đang WAITING và không phải Idle
SELECT SID, EVENT
FROM V$SESSION
WHERE STATE = 'WAITING'
  AND USERNAME = 'SOE'
  AND WAIT_CLASS <> 'Idle';
```

### Bước 2 — Xem chi tiết wait event

```sql
-- Chi tiết đầy đủ từ V$SESSION
SELECT 'SID: '           || SID             || CHR(10) ||
       'USERNAME: '      || USERNAME         || CHR(10) ||
       'STATE: '         || STATE            || CHR(10) ||
       'EVENT: '         || EVENT            || CHR(10) ||
       'WAIT_TIME: '     || WAIT_TIME        || CHR(10) ||
       'SECONDS_IN_WAIT:'|| SECONDS_IN_WAIT  || CHR(10) ||
       'WAIT_CLASS: '    || WAIT_CLASS       || CHR(10) ||
       'P1TEXT: '        || P1TEXT           || CHR(10) ||
       'P1: '            || P1               || CHR(10) ||
       'P2TEXT: '        || P2TEXT           || CHR(10) ||
       'P2: '            || P2               || CHR(10) ||
       'P3TEXT: '        || P3TEXT           || CHR(10) ||
       'P3: '            || P3               AS SESSION_WAITS
FROM V$SESSION
WHERE USERNAME = 'SOE'
  AND EVENT LIKE 'enq: TX%';
```

> **Giải thích các cột:**
> - `STATE = 'WAITING'` → session đang chờ, `WAIT_TIME = 0`
> - `SECONDS_IN_WAIT` → số giây đã chờ tính đến hiện tại
> - `P1, P2, P3` → tham số của wait event (ý nghĩa tra trong Oracle docs, Appendix C)

### Bước 3 — Kiểm tra V$SESSION_WAIT_HISTORY

```sql
-- Wait events đã kết thúc (tối đa 10 gần nhất)
-- Lưu ý: event đang chờ (chưa kết thúc) KHÔNG xuất hiện ở đây
SELECT COUNT(*) FROM V$SESSION_WAIT_HISTORY WHERE EVENT LIKE 'enq: TX%';
```

### Bước 4 — Giải phóng lock

```sql
-- Từ session đang giữ lock
ROLLBACK;
```

Sau rollback:
- `V$SESSION` → event biến mất (session không còn chờ)
- `V$SESSION_EVENT` → vẫn còn ghi nhận (tích lũy lịch sử)
- `V$SESSION_WAIT_HISTORY` → event xuất hiện (đã kết thúc)
- Khi session disconnect → không còn thấy trong `V$SESSION_EVENT`

---

## Sơ đồ vòng đời Wait Event

```
Session bắt đầu chờ
        │
        ▼
  V$SESSION          ← event hiển thị (STATE='WAITING', WAIT_TIME=0)
  V$SESSION_WAIT     ← chi tiết real-time
        │
        ▼ (event kết thúc)
  V$SESSION_EVENT    ← cộng vào TIME_WAITED tích lũy
  V$SESSION_WAIT_HISTORY ← ghi vào (giữ 10 events gần nhất)
        │
        ▼ (session disconnect)
  Tất cả biến mất từ V$ views
```

---

## Tóm tắt — Khi nào dùng View nào?

| Tình huống | View |
|-----------|------|
| Database chậm, muốn biết wait class nào chiếm nhiều nhất | `V$SYSTEM_WAIT_CLASS` |
| Tìm wait event cụ thể nào gây vấn đề | `V$SYSTEM_EVENT` |
| Session cụ thể bị chậm, tìm wait event của nó | `V$SESSION_EVENT` |
| Session đang bị treo ngay bây giờ | `V$SESSION` (STATE='WAITING') |
| Tìm thống kê activity (parse, scan...) | `V$SYSSTAT`, `V$SESSTAT` |
| Troubleshoot session của chính mình | `V$MYSTAT` |
| Xem 10 wait events vừa kết thúc của session | `V$SESSION_WAIT_HISTORY` |

---

## Câu hỏi Ôn tập

1. Sự khác biệt giữa `V$SESSION_EVENT` và `V$SESSION_WAIT` là gì?
2. Tại sao `WAIT_TIME = 0` khi `STATE = 'WAITING'` trong `V$SESSION`?
3. `V$MYSTAT` khác `V$SESSTAT` ở điểm gì? Khi nào dùng `V$MYSTAT`?
4. Sau khi session disconnect, dữ liệu trong `V$SESSION_EVENT` sẽ như thế nào?
5. Event `enq: TX - row lock contention` thuộc Wait Class nào? Nguyên nhân thường gặp là gì?

<details>
<summary>Gợi ý trả lời</summary>

1. `V$SESSION_WAIT` = chi tiết real-time của event **đang xảy ra**, bao gồm P1/P2/P3 parameters. `V$SESSION_EVENT` = lịch sử tích lũy tất cả events đã xảy ra của session từ khi connect.

2. Khi `STATE = 'WAITING'`, session đang trong event chờ. Oracle chưa ghi `WAIT_TIME` cho event đó vì event chưa kết thúc. Thay vào đó dùng `SECONDS_IN_WAIT` để biết đã chờ bao lâu.

3. `V$MYSTAT` chỉ hiển thị thống kê của **session hiện tại** mà không cần JOIN với `V$SESSION` để lấy SID. Dùng khi developer/DBA muốn đo hiệu năng của code họ đang chạy trong session của mình.

4. Tất cả dữ liệu trong `V$SESSION_EVENT` biến mất khi session disconnect — đây là dynamic performance view, không persistent. Để có lịch sử lâu dài cần dùng AWR (`DBA_HIST_*`).

5. `enq: TX - row lock contention` thuộc class **Application**. Nguyên nhân: một session đang giữ row lock (chưa COMMIT/ROLLBACK) và session khác muốn update/delete cùng row đó.

</details>


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/section_all/section_8_instance_activity_wait_events_guide.md`
