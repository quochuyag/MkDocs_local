---
title: Section 25 — CPU Bottleneck Detection
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/section_all/section_25_cpu_bottleneck_guide.md
---

# Section 25 — CPU Bottleneck Detection

**Nguồn:** Oracle Database Performance Tuning — Ahmed Baraka (v2.3)  
**Practice:** 27  
**Ngày học:** 2026-04-20

---

## Tổng quan Section 25

Section 25 tập trung vào **phát hiện CPU bottleneck** — phân biệt nguồn gốc CPU consumption: từ **external process** (OS level) hay từ **bên trong database** (Oracle sessions/SQL).

---

## Kiến thức nền tảng

### CPU Consumption — hai nguồn chính

```
Total CPU Power (100%)
    ├── Oracle DB Foreground (sessions chạy SQL)   ← DB CPU (Time Model)
    ├── Oracle DB Background (LGWR, DBWn, CKPT...) ← background cpu time
    └── External Process (OS, apps khác)            ← phần còn lại
```

### Công thức tính CPU trong AWR

```
Maximum CPU Time = # of CPUs × Duration (giây)
Ví dụ: 2 CPUs × 5 phút = 2 × 300 = 600 giây

%DB CPU của total CPU = DB CPU / Maximum CPU Time × 100
%Busy CPU            = Total Database CPU Time / CPU Busy Time × 100
```

**Lưu ý quan trọng về Time Model:**

> `% of Total CPU Time` trong Time Model **KHÔNG phải** % của DB CPU trên total CPU.  
> Đây là: `DB CPU / (DB CPU + background cpu time)` — tức là % trong tổng Oracle CPU, không phải máy.

---

## Hai kịch bản CPU Bottleneck

### Kịch bản 1: CPU stress từ External Process

**Triệu chứng trong AWR:**

| Section AWR | Dấu hiệu |
|-------------|---------|
| **Host CPU** | Load Average >> 2× số CPUs; `%User` cao |
| **Top 10 Foreground Events** | DB CPU thấp (nhỏ so với Max CPU Time) |
| **Instance CPU** | `%Busy CPU` thấp |
| **Time Model** | `background cpu time` thấp |

**Kết luận:** CPU bị tiêu thụ bởi process ngoài Oracle, không phải database.

**Hạn chế của AWR:** AWR **không thể xác định** process nào ở OS đang gây ra vấn đề.  
→ Phải dùng OS tools: `top`, `htop`, `ps aux`, `OSWatcher` (Section 34).

---

### Kịch bản 2: CPU stress từ bên trong Database

**Triệu chứng trong AWR:**

| Section AWR | Dấu hiệu |
|-------------|---------|
| **ADDM Findings** | `CPU Usage` xuất hiện là một finding |
| **Top 10 Foreground Events** | DB CPU **cao** — chiếm nhiều % của Max CPU Time |
| **Wait Classes** | `Avg Active Sessions` gần bằng số CPUs |
| **Host CPU** | `%User` + `%System` + `%WIO` cao |
| **Instance CPU** | `%Busy CPU` rất cao |
| **SQL ordered by CPU Time** | **Culprit SQL/PL-SQL được xác định** |

**Kết luận:** Database sessions đang tiêu thụ CPU quá mức.  
→ AWR `SQL ordered by CPU Time` chỉ thẳng vào SQL/PLSQL gây ra vấn đề.

---

## Quy trình Chẩn đoán CPU Bottleneck

### Bước 1: Xác định nguồn gốc từ AWR

```
Đọc AWR → Host CPU section
    ├── Load Average > 2× CPUs?  → CPU có vấn đề
    └── Instance CPU section
            ├── %Busy CPU cao?  → Vấn đề TỪ DATABASE
            └── %Busy CPU thấp? → Vấn đề từ EXTERNAL PROCESS
```

### Bước 2a: Nếu External → OS Level Investigation

```bash
# Trên Linux — xem process tiêu thụ CPU
top -b -n 1 | head -20
ps aux --sort=-%cpu | head -20

# OSWatcher (Section 34) cho historical data
```

### Bước 2b: Nếu Database → Tìm SQL gây ra

**Trong AWR Report:**
- Section **"SQL ordered by CPU Time"** → top SQL tiêu thụ CPU
- Section **"SQL ordered by Elapsed Time"** → top SQL chậm nhất

**Trong ASH (real-time hoặc historical):**
```sql
-- Top SQL đang tiêu thụ CPU ngay lúc này
SELECT SQL_ID, COUNT(*) SESSIONS_ON_CPU
FROM V$ACTIVE_SESSION_HISTORY
WHERE SESSION_STATE = 'ON CPU'
  AND SAMPLE_TIME > SYSDATE - 1/24  -- trong 1 giờ qua
GROUP BY SQL_ID
ORDER BY 2 DESC
FETCH FIRST 10 ROWS ONLY;

-- Top sessions đang tiêu thụ CPU
SELECT SESSION_ID, SESSION_SERIAL#, USER_ID, SQL_ID, COUNT(*) SAMPLES
FROM V$ACTIVE_SESSION_HISTORY
WHERE SESSION_STATE = 'ON CPU'
  AND SAMPLE_TIME > SYSDATE - 1/24/12  -- trong 5 phút qua
GROUP BY SESSION_ID, SESSION_SERIAL#, USER_ID, SQL_ID
ORDER BY 5 DESC;
```

**Từ V$SESSION (real-time):**
```sql
-- Sessions đang dùng CPU nhiều nhất
SELECT S.SID, S.USERNAME, S.STATUS, S.SQL_ID,
       T.VALUE/100 CPU_SECONDS
FROM V$SESSION S, V$SESSTAT T, V$STATNAME N
WHERE S.SID = T.SID
  AND T.STATISTIC# = N.STATISTIC#
  AND N.NAME = 'CPU used by this session'
  AND S.USERNAME IS NOT NULL
ORDER BY T.VALUE DESC
FETCH FIRST 10 ROWS ONLY;
```

---

## Đọc AWR Report — Các Section quan trọng cho CPU

### 1. Report Header

```
DB Time:          X.X minutes
DB CPU:           Y.Y minutes
Maximum CPU:      2 CPUs × 5 min = 10 CPU-minutes
```

### 2. Top 10 Foreground Events

```
Event                    Waits   Time(s)   Avg Wait  % DB Time   Wait Class
DB CPU                            450       N/A        75.0       N/A
db file sequential read  1000      50       50ms        8.3       User I/O
```

**Đọc:** DB CPU = 450s, Max CPU = 600s → DB dùng 75% tổng CPU → database-side issue.

### 3. Host CPU (AWR section quan trọng nhất cho CPU)

```
CPUs:  2    Cores:  2    Sockets:  1    Load Average Begin:  15.2   End:  18.5

%User   %System   %WIO   %Idle
 85.2      8.1     3.2    3.5
```

**Đọc:**
- `Load Average` >> số CPUs (2) → CPU overloaded
- `%Idle` thấp → CPU không còn headroom
- `%User` cao → process user-space tiêu thụ (có thể Oracle hoặc external)

### 4. Instance CPU

```
%Total CPU:   72.5
%Busy CPU:    78.3
%DB CPU:      75.0
```

**Đọc:**
- `%Busy CPU` = Oracle CPU / CPU Busy Time
- Cao (>70%) → Oracle là nguồn chính gây CPU load

### 5. Time Model Statistics

```
Statistic                       Time (s)   % of Total DB Time   % Total CPU
DB CPU                            450          75.0               75.0
background cpu time                30           5.0                5.0
```

**Công thức % Total CPU trong Time Model:**
```
% of Total CPU Time = Stat / (DB CPU + background cpu time)
```

### 6. SQL ordered by CPU Time

```
CPU Time (s)   Executions   CPU per Exec   SQL Id        SQL Text
   380              1         380.0        a1b2c3d4e5   BEGIN apply_cpu_load...
    45             100           0.45       x9y8z7w6v5   SELECT * FROM ORDERS...
```

→ PL/SQL block `apply_cpu_load` là culprit.

---

## Phân biệt: Nguồn gốc CPU Bottleneck

| Dấu hiệu | External CPU | Database CPU |
|----------|-------------|-------------|
| `%Busy CPU` (Instance CPU section) | **Thấp** | **Cao** |
| DB CPU / Max CPU (Top Events) | **Thấp** (<30%) | **Cao** (>60%) |
| `background cpu time` | Thấp | Có thể cao hoặc thấp |
| Load Average | > 2× CPUs | > 2× CPUs |
| ADDM Finding | Không có CPU finding | `CPU Usage` xuất hiện |
| AWR giúp tìm culprit? | **Không** (cần OS tools) | **Có** (SQL ordered by CPU Time) |

---

## ASH vs AWR cho CPU Detection

| | AWR | ASH |
|-|-----|-----|
| **Dùng khi** | Post-mortem, historical | Real-time hoặc gần đây |
| **Độ chi tiết** | Aggregated (trong window) | Per-sample (1 giây) |
| **Tìm culprit SQL** | SQL ordered by CPU Time | `SESSION_STATE='ON CPU'` |
| **External CPU** | Phát hiện được (Host CPU section) | Không phát hiện được |

---

## Checklist CPU Bottleneck

| Bước | Câu hỏi | Nơi kiểm tra |
|------|---------|-------------|
| 1 | Load Average >> số CPUs? | AWR — Host CPU |
| 2 | %Busy CPU cao? | AWR — Instance CPU |
| 3 | DB CPU chiếm nhiều % Max CPU? | AWR — Top 10 Events |
| 4 | ADDM có CPU finding? | AWR — ADDM Findings |
| 5 | SQL nào dùng CPU nhiều? | AWR — SQL by CPU Time / ASH |
| 6 | Nếu external: process nào? | OS: `top`, `ps`, OSWatcher |

---

## Tóm tắt

| Công cụ | Dùng để |
|---------|---------|
| AWR — Host CPU | Phát hiện CPU overload tổng thể |
| AWR — Instance CPU (`%Busy CPU`) | Xác định Oracle là nguồn hay external |
| AWR — SQL by CPU Time | Tìm SQL/PLSQL culprit (nếu database-side) |
| ASH (`SESSION_STATE='ON CPU'`) | Real-time: sessions/SQL đang dùng CPU |
| OS tools (`top`, `htop`) | External process gây CPU load |

---

## Câu hỏi ôn tập

1. Làm thế nào phân biệt CPU bottleneck từ **external process** vs từ **database sessions** qua AWR?
2. `%Busy CPU` trong AWR tính như thế nào? Giá trị nào cho thấy database là nguyên nhân?
3. Tại sao `% of Total CPU Time` trong Time Model section **không phải** là % DB CPU trên total CPU của máy?
4. AWR section nào giúp tìm được SQL gây CPU bottleneck? Tại sao ASH cũng hữu ích?
5. Khi Load Average = 15 trên máy 2 CPUs, điều đó có nghĩa gì?
6. Nếu AWR cho thấy CPU bottleneck từ external process, bước tiếp theo là gì? Công cụ nào dùng?
7. `Avg Active Sessions` gần bằng số CPUs có ý nghĩa gì trong việc chẩn đoán CPU bottleneck?


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/section_all/section_25_cpu_bottleneck_guide.md`
