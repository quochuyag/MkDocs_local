---
title: Section 24 — Redo Path Tuning
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/section_all/section_24_redo_path_guide.md
---

# Section 24 — Redo Path Tuning

**Nguồn:** Oracle Database Performance Tuning — Ahmed Baraka (v2.3)  
**Practice:** 26  
**Ngày học:** 2026-04-20

---

## Tổng quan Section 24

Section 24 tập trung vào **Redo Path** — chuỗi ghi nhật ký thay đổi (redo log) trong Oracle. Redo log files quá nhỏ gây ra **log switch liên tục**, tạo bottleneck nghiêm trọng cho toàn database.

---

## Kiến thức nền tảng

### Redo Path là gì?

Mỗi thay đổi DML (INSERT/UPDATE/DELETE) được ghi vào:

```
Session → Redo Buffer (SGA) → LGWR → Redo Log Files (Online Redo Logs)
                                            ↓
                                    Archive Log Files (nếu ARCHIVELOG mode)
```

**LGWR (Log Writer)** — background process ghi redo buffer ra disk khi:
- Commit được thực hiện
- Redo buffer 1/3 đầy
- Mỗi 3 giây
- Trước khi DBWn ghi dirty block

### Online Redo Log Groups

```
GROUP 1 → MEMBER 1a (/data/...)  ← 2 members = mirroring
          MEMBER 1b (/fra/...)
GROUP 2 → MEMBER 2a, 2b
GROUP 3 → MEMBER 3a, 3b
```

Oracle ghi tuần tự: GROUP 1 → GROUP 2 → GROUP 3 → GROUP 1 (vòng tròn).

Khi một group đầy → **Log Switch** xảy ra:
- Oracle chuyển sang group tiếp theo
- Group cũ phải được archived trước khi tái sử dụng (ARCHIVELOG mode)
- Nếu tất cả groups đang chờ archive → database **hang**

---

## Vấn đề: Redo Log File quá nhỏ

### Triệu chứng

| Dấu hiệu | Ý nghĩa |
|----------|---------|
| **Log switch quá thường** | File nhỏ → đầy nhanh → switch liên tục |
| **`redo log space requests` tăng** | LGWR chờ log switch hoàn thành để ghi tiếp |
| **AWR: Top Wait Events** xuất hiện `log file switch` | Bottleneck trực tiếp |
| **AWR: Log File Size Advisor** đề xuất kích thước lớn hơn | Tín hiệu cần resize |

### Rule of Thumb (kinh nghiệm thực tế)

> **Log switch nên xảy ra không quá 1 lần / 20 phút** khi system dưới workload bình thường.

---

## Giám sát Redo Path

### 1. Xem cấu hình Redo Log Files

```sql
-- Tất cả log groups + members + kích thước
SELECT G.GROUP#, G.ARCHIVED, G.STATUS,
       REPLACE(REPLACE(M.MEMBER,'/u01/app/oracle/oradata/ORADB/onlinelog/','DATA_DIR/'),
               '/u01/app/oracle/fra/ORADB/ORADB/onlinelog/','FRA_DIR/') MEMBER,
       BYTES/1024/1024 MB
FROM V$LOG G, V$LOGFILE M
WHERE G.GROUP#=M.GROUP#
ORDER BY M.GROUP#, M.MEMBER;
```

**STATUS của V$LOG:**

| STATUS | Ý nghĩa |
|--------|---------|
| `CURRENT` | Group đang được LGWR ghi vào |
| `ACTIVE` | Group đã switch, chưa checkpoint xong |
| `INACTIVE` | Group đã archived/checkpointed, có thể tái dùng |
| `UNUSED` | Group mới, chưa bao giờ dùng |

### 2. Theo dõi tần suất Log Switch (theo giờ)

```sql
-- Số lần switch mỗi giờ trong ngày hôm nay
SELECT TO_CHAR(FIRST_TIME,'HH24') HOUR, COUNT(*) SWITCHES
FROM V$LOG_HISTORY
WHERE TRUNC(FIRST_TIME)=TRUNC(SYSDATE)
GROUP BY TO_CHAR(FIRST_TIME,'HH24')
ORDER BY TO_CHAR(FIRST_TIME,'HH24');
```

**Đọc kết quả:**
```
HOUR  SWITCHES
----  --------
10        3    ← bình thường
11       45    ← QUÁ NHIỀU! Log files quá nhỏ
12       52    ← vẫn nghiêm trọng
```

### 3. Kiểm tra Wait Event: `redo log space requests`

```sql
-- Số lần LGWR phải chờ log switch
SELECT NAME, VALUE
FROM V$SYSSTAT
WHERE NAME = 'redo log space requests';
```

**Ngưỡng:** = 0 là lý tưởng. Tăng liên tục trong khi workload chạy → log files quá nhỏ.

### 4. AWR Report — các section liên quan đến Redo

Trong AWR Report, tìm:

- **Load Profile** → `Redo size per transaction` — ước lượng tốc độ ghi redo
- **Top 5 Timed Events** → nếu thấy:
  - `log file switch (checkpoint incomplete)` → log switch quá nhanh, checkpoint chưa kịp
  - `log file switch (archiving needed)` → archiver chậm
  - `log buffer space` → redo buffer không đủ
- **Log File Size Advisor** — Oracle đề xuất kích thước tối ưu (chỉ xuất hiện khi `FAST_START_MTTR_TARGET` được set)

---

## Redo Log File Size Advisor

### V$INSTANCE_RECOVERY

```sql
-- Yêu cầu: FAST_START_MTTR_TARGET phải được set
ALTER SYSTEM SET FAST_START_MTTR_TARGET = 3600 SCOPE=BOTH;

-- Query advisor
SELECT ESTIMATED_MTTR           "Estimated MTTR",
       TARGET_MTTR               "Effective MTTR Target",
       OPTIMAL_LOGFILE_SIZE      "OPTIMAL_LOGFILE_SIZE(MB)"
FROM V$INSTANCE_RECOVERY;
```

**Giải thích các cột:**

| Cột | Ý nghĩa |
|-----|---------|
| `ESTIMATED_MTTR` | MTTR hiện tại Oracle ước tính (giây) |
| `TARGET_MTTR` | MTTR target database có thể đạt được thực tế |
| `OPTIMAL_LOGFILE_SIZE` | **Kích thước redo log tối ưu (MB)** — cần đặt ít nhất bằng giá trị này |

**Lưu ý:**
- Nếu `TARGET_MTTR = 0` → chưa đủ workload, chạy lại workload rồi query lại
- Giá trị advisor phụ thuộc workload hiện tại — chỉ tham khảo khi system dưới normal workload

---

## Thực nghiệm: Impact của Undersized Redo Log

### Kịch bản thực hành

**Bước 1:** Tạo 3 groups mới kích thước 10MB (nhỏ)

```sql
ALTER DATABASE ADD LOGFILE GROUP 4 SIZE 10M;
ALTER DATABASE ADD LOGFILE GROUP 5 SIZE 10M;
ALTER DATABASE ADD LOGFILE GROUP 6 SIZE 10M;
```

**Bước 2:** Drop groups cũ (200MB)

```sql
-- Switch log 3 lần để groups cũ trở thành INACTIVE
ALTER SYSTEM SWITCH LOGFILE;
ALTER SYSTEM SWITCH LOGFILE;
ALTER SYSTEM SWITCH LOGFILE;
ALTER SYSTEM CHECKPOINT;

-- Drop groups 1, 2, 3
ALTER DATABASE DROP LOGFILE GROUP 1;
ALTER DATABASE DROP LOGFILE GROUP 2;
ALTER DATABASE DROP LOGFILE GROUP 3;
```

**Bước 3:** Chạy workload UPDATE liên tục (4 sessions × 2 phút)

```bash
./update_orders.sh 4 120
```

**Bước 4:** Quan sát tần suất log switch

```sql
-- Chạy nhiều lần trong khi workload đang chạy
@ display_log_history.sql
SELECT NAME, VALUE FROM V$SYSSTAT WHERE NAME = 'redo log space requests';
```

**Kết quả mong đợi:**
- SWITCHES tăng vọt (20–50+ lần/giờ)
- `redo log space requests` liên tục tăng
- AWR sẽ thấy `log file switch` trong Top Wait Events

---

## Quy trình Resize Redo Log Files

### Không thể resize trực tiếp — phải drop và recreate

```sql
-- 1. Thêm groups mới với kích thước đúng
ALTER DATABASE ADD LOGFILE GROUP 7 SIZE 200M;
ALTER DATABASE ADD LOGFILE GROUP 8 SIZE 200M;
ALTER DATABASE ADD LOGFILE GROUP 9 SIZE 200M;

-- 2. Switch log để groups nhỏ trở thành INACTIVE
ALTER SYSTEM SWITCH LOGFILE;
ALTER SYSTEM SWITCH LOGFILE;
ALTER SYSTEM SWITCH LOGFILE;
ALTER SYSTEM CHECKPOINT;

-- 3. Drop groups nhỏ (khi STATUS = INACTIVE)
ALTER DATABASE DROP LOGFILE GROUP 4;
ALTER DATABASE DROP LOGFILE GROUP 5;
ALTER DATABASE DROP LOGFILE GROUP 6;
```

**Lưu ý:** Không thể drop CURRENT group. Nếu group cần drop đang ACTIVE → chờ checkpoint.

---

## Các thông số quan trọng

| Parameter | Ý nghĩa | Mặc định |
|-----------|---------|---------|
| `LOG_BUFFER` | Kích thước Redo Buffer trong SGA | Auto |
| `FAST_START_MTTR_TARGET` | Target MTTR (giây) — bật Redo Log Size Advisor | 0 (tắt) |
| `LOG_CHECKPOINT_INTERVAL` | Checkpoint sau N redo blocks (legacy, không nên dùng) | 0 |
| `LOG_CHECKPOINT_TIMEOUT` | Checkpoint sau N giây | 1800 |
| `ARCHIVE_LAG_TARGET` | Bắt buộc log switch sau N giây (Data Guard) | 0 |

---

## Checklist đánh giá sức khỏe Redo Path

| Kiểm tra | Query/View | Ngưỡng tốt |
|---------|-----------|-----------|
| Tần suất log switch | `V$LOG_HISTORY` — SWITCHES per hour | **≤ 3 lần/giờ (max 1 lần/20 phút)** |
| Redo log space requests | `V$SYSSTAT` — `redo log space requests` | **= 0** |
| Optimal log file size | `V$INSTANCE_RECOVERY` — `OPTIMAL_LOGFILE_SIZE` | File hiện tại ≥ giá trị này |
| Top wait events | AWR — Top 5 Timed Events | Không thấy `log file switch*` |

---

## Tóm tắt Views & Cấu lệnh quan trọng

| View/Command | Dùng để |
|-------------|---------|
| `V$LOG` | Xem status và kích thước các log groups |
| `V$LOGFILE` | Xem đường dẫn các log members |
| `V$LOG_HISTORY` | Lịch sử log switches (tần suất) |
| `V$SYSSTAT` (`redo log space requests`) | Đếm số lần LGWR phải chờ |
| `V$INSTANCE_RECOVERY` | Advisor kích thước log file tối ưu |
| `ALTER DATABASE ADD/DROP LOGFILE GROUP` | Thêm/xóa log groups |
| `ALTER SYSTEM SWITCH LOGFILE` | Buộc log switch thủ công |
| `ALTER SYSTEM CHECKPOINT` | Buộc checkpoint |

---

## Câu hỏi ôn tập

1. Tại sao redo log file quá nhỏ lại gây bottleneck cho **toàn bộ** database, không chỉ cho DML?
2. `redo log space requests` đo lường điều gì? Giá trị bao nhiêu là nguy hiểm?
3. Oracle khuyến nghị tần suất log switch như thế nào khi system dưới normal workload?
4. Để sử dụng Redo Log File Size Advisor, cần set tham số nào? Tại sao?
5. Tại sao không thể `ALTER DATABASE DROP LOGFILE GROUP` khi group đang CURRENT hay ACTIVE?
6. Sự khác biệt giữa `log file switch (checkpoint incomplete)` và `log file switch (archiving needed)` là gì?
7. Trong AWR, section nào và metric nào cho thấy redo path có vấn đề?


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/section_all/section_24_redo_path_guide.md`
