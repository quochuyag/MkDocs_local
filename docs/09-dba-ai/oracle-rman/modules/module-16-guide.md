---
title: '📘 Module 16: Tối ưu Hiệu năng & Xử lý Sự cố RMAN (Performance Tuning & Troubleshooting)'
course: 09-dba-ai
source: dba_ai/oracle_rman/modules/module_16_guide.md
---

# 📘 Module 16: Tối ưu Hiệu năng & Xử lý Sự cố RMAN (Performance Tuning & Troubleshooting)

> **Module**: 16/17
> **Phạm vi**: Bài 64 đến 66 (Performance Tuning & Troubleshooting)
> **Giảng viên**: Ahmed Baraka
> **Thời gian học ước tính**: 2.5 giờ
> **Nguồn PDF**: `pdf_extracted/module_16/`

---

## 📑 Mục lục

- [Phần 1: RMAN Performance Tuning — Kiến trúc I/O](#-phần-1-rman-performance-tuning--kiến-trúc-io)
- [Phần 2: Tối ưu Bộ nhớ (Large Pool & SGA)](#-phần-2-tối-ưu-bộ-nhớ-large-pool--sga)
- [Phần 3: Parallelism — Đa kênh (Channels)](#-phần-3-parallelism--đa-kênh-channels)
- [Phần 4: Multiplexing — Chiến thuật gom/chia File](#-phần-4-multiplexing--chiến-thuật-gomchia-file)
- [Phần 5: DURATION & RATE — Kiểm soát tải](#-phần-5-duration--rate--kiểm-soát-tải)
- [Phần 6: Giám sát Backup bằng V$ Views](#-phần-6-giám-sát-backup-bằng-v-views)
- [Phần 7: RMAN Troubleshooting — Đọc lỗi & Xử lý](#-phần-7-rman-troubleshooting--đọc-lỗi--xử-lý)
- [Phần 8: DEBUG Mode — Bật còi chẩn đoán](#-phần-8-debug-mode--bật-còi-chẩn-đoán)
- [Thực hành Practice 22: Lab Tuning & Troubleshooting](#-thực-hành-practice-22-lab-tuning--troubleshooting)
- [Câu hỏi ôn tập Module 16](#-câu-hỏi-ôn-tập-module-16)

---

# 📖 Phần 1: RMAN Performance Tuning — Kiến trúc I/O

Tốc độ backup RMAN phụ thuộc vào **3 tầng thắt cổ chai** theo thứ tự tần suất xảy ra:

```
[Disk/Tape I/O]  ──► Thường gặp nhất — check async I/O, Large Pool
[Network BW]     ──► Khi backup qua mạng (NFS, OSB Cloud)
[Database]       ──► Hiếm — CPU compression, deduplication
```

> **Quy tắc thực chiến**: 90% vấn đề chậm backup đến từ Disk I/O và Large Pool chưa đủ lớn.

---

## 1. Synchronous vs Asynchronous I/O

### Synchronous (mặc định khi chưa cấu hình):
```
RMAN đọc Block 1 → GỬI ra Disk → CHỜ xác nhận → đọc Block 2 → CHỜ → ...
```
RMAN bị khóa (blocked) trong suốt quá trình chờ OS ghi xong. Hiệu suất kém.

### Asynchronous I/O (mục tiêu cần đạt):
```
RMAN đọc Block 1 → GỬI → đọc Block 2 → GỬI → đọc Block 3 → GỬI → ...
                    ↓                    ↓
               [OS xử lý ngầm]     [Báo xong]
```
RMAN liên tục đẩy data, không chờ OS. Hiệu suất tăng 3–5 lần.

---

## 2. Kích hoạt Asynchronous I/O ⭐⭐⭐

### Cho Disk:
Đa số Linux/Unix hiện đại đã hỗ trợ native Async I/O. Kiểm tra bằng:
```sql
-- Xem RMAN đang dùng Sync hay Async
SELECT FILENAME, TYPE, EFFECTIVE_BYTES_PER_SECOND/1024/1024 AS "MB/s",
       BUFFER_SIZE, BUFFER_COUNT, OPEN_TIME, IO_COUNT
FROM V$BACKUP_ASYNC_IO
ORDER BY OPEN_TIME DESC;

-- Nếu không có row → RMAN đang dùng Sync I/O
SELECT * FROM V$BACKUP_SYNC_IO;
```

Nếu OS không hỗ trợ native async → ép Oracle giả lập bằng I/O Slaves:
```sql
ALTER SYSTEM SET DBWR_IO_SLAVES = 4 SCOPE=SPFILE;
-- Yêu cầu restart database — Large Pool tự động được dùng
```

### Cho Tape (Media Manager):
```sql
ALTER SYSTEM SET BACKUP_TAPE_IO_SLAVES = TRUE SCOPE=SPFILE;
-- Khi bật: bộ đệm I/O chuyển từ PGA sang Large Pool (SGA)
```

> **Cảnh báo**: Thay đổi `BACKUP_TAPE_IO_SLAVES` và `DBWR_IO_SLAVES` yêu cầu **restart database** vì `SCOPE=SPFILE`.

---

# 📖 Phần 2: Tối ưu Bộ nhớ (Large Pool & SGA)

Khi Async I/O được kích hoạt, RMAN cần vùng nhớ đệm (**I/O Buffer**) để chứa các block đang bay. Vùng nhớ này lấy từ **Large Pool**.

### Vì sao Large Pool quan trọng?

```
Khi BACKUP_TAPE_IO_SLAVES=TRUE hoặc DBWR_IO_SLAVES > 0:
  Buffer lấy từ Large Pool (không phải PGA)
  ↓
Nếu Large Pool quá nhỏ → ORA-04031: unable to allocate bytes from shared memory
  ↓
RMAN tự động rơi về Sync I/O (chậm như ban đầu!)
```

### Tính toán Large Pool cần thiết:
```
Large Pool tối thiểu cho RMAN = (số channels) × 4 × BACKUP_DISK_IO_SLAVES buffer size
Thực tế khuyến nghị: đặt LARGE_POOL_SIZE ≥ 128MB cho production
```

### Kiểm tra và cấu hình:
```sql
-- Kiểm tra Large Pool hiện tại
SHOW PARAMETER large_pool_size;

-- Kiểm tra Large Pool đủ không — có ORA-04031 hay không
SELECT * FROM V$SHARED_POOL_RESERVED WHERE REQUEST_FAILURES > 0;

-- Tăng Large Pool (không cần restart)
ALTER SYSTEM SET LARGE_POOL_SIZE = 256M SCOPE=BOTH;
```

**Output mẫu `SHOW PARAMETER large_pool_size`:**
```
NAME                                 TYPE        VALUE
------------------------------------ ----------- ------------------------------
large_pool_size                      big integer 64M
```

---

# 📖 Phần 3: Parallelism — Đa kênh (Channels)

Mỗi Channel là 1 luồng xử lý riêng biệt. Nhiều channel = nhiều Datafiles được đọc song song.

### Cấu hình Persistent (ảnh hưởng mọi backup):
```sql
RMAN> CONFIGURE DEVICE TYPE DISK PARALLELISM 4;
-- RMAN tự cấp 4 channel cho mọi lệnh BACKUP sau này
```

### Override cho 1 backup cụ thể trong RUN Block:
```sql
RMAN> RUN {
  ALLOCATE CHANNEL c1 DEVICE TYPE DISK FORMAT '/u02/backup/%U';
  ALLOCATE CHANNEL c2 DEVICE TYPE DISK FORMAT '/u02/backup/%U';
  ALLOCATE CHANNEL c3 DEVICE TYPE DISK FORMAT '/u02/backup/%U';
  BACKUP DATABASE PLUS ARCHIVELOG;
  RELEASE CHANNEL c1;
  RELEASE CHANNEL c2;
  RELEASE CHANNEL c3;
}
```

### Chọn số channel tối ưu:
| Tình huống | Số channel khuyến nghị |
|------------|----------------------|
| 1 ổ đĩa vật lý | 1–2 channels |
| RAID hoặc LVM striping | 4–8 channels |
| Tape library nhiều drive | 1 channel/tape drive |
| SSD/NVMe | 4–16 channels |

> **Cảnh báo thực chiến**: Quá nhiều channel trên 1 spindle disk có thể làm chậm do head seeking. Test với 2, 4, 8 rồi đo thời gian.

---

# 📖 Phần 4: Multiplexing — Chiến thuật gom/chia File

Multiplexing là việc RMAN **nhét nhiều Datafile vào chung 1 luồng đọc** của 1 Channel.

### Các tham số kiểm soát:

#### FILESPERSET — Số Datafile tối đa trong 1 Backupset
```sql
RMAN> BACKUP DATABASE FILESPERSET 5;
-- Mỗi backupset chứa tối đa 5 datafile (mặc định: 64)
-- Dùng khi muốn Restore 1 tablespace nhanh (ít file hơn phải scan)
```

#### MAXOPENFILES — Số Datafile mở song song trong 1 Channel
```sql
RMAN> RUN {
  ALLOCATE CHANNEL c1 TYPE DISK MAXOPENFILES 4;
  BACKUP DATABASE;
}
-- 1 channel mở tối đa 4 datafile cùng lúc (mặc định: 8)
```

#### MAXPIECESIZE — Giới hạn kích thước từng Backup Piece
```sql
RMAN> RUN {
  ALLOCATE CHANNEL c1 DEVICE TYPE DISK
    MAXPIECESIZE 2048M
    FORMAT '/u02/backup/%U.bkp';
  BACKUP DATABASE;
}
-- Datafile 50GB → RMAN tự cắt thành 25 files × 2GB
-- Dùng khi: FAT32 limit 4GB, NFS mount size limit, FTP upload limit
```

### Công thức VÀNG — Effective Multiplexing: ⭐⭐⭐
```
Số Datafiles đọc song song thực tế = MIN(MAXOPENFILES, FILESPERSET)
```

**Ví dụ minh họa:**
```
MAXOPENFILES = 8 (mặc định)
FILESPERSET  = 3
→ Effective Multiplexing = MIN(8, 3) = 3 files đọc cùng lúc/channel
```

---

# 📖 Phần 5: DURATION & RATE — Kiểm soát tải

### DURATION — Ép backup chạy đúng khung giờ

```sql
-- Backup được tối đa 7 tiếng, ưu tiên tốc độ (MINIMIZE TIME)
BACKUP DATABASE
  DURATION 07:00 MINIMIZE TIME;

-- Backup được tối đa 4 tiếng, tiết kiệm tài nguyên (MINIMIZE LOAD)
BACKUP DATABASE
  DURATION 04:00 MINIMIZE LOAD;

-- Backup được tối đa 6 tiếng, nếu không xong thì chấp nhận partial
BACKUP DATABASE NOT BACKED UP SINCE 'SYSDATE-3'
  DURATION 06:00 PARTIAL MINIMIZE TIME;
```

| Tham số | Hành vi | Dùng khi |
|---------|---------|---------|
| `MINIMIZE TIME` | Full throttle — I/O tối đa | Backup ban đêm, ít user |
| `MINIMIZE LOAD` | Rải đều — sleep ngắt quãng | Backup ban ngày, server đang phục vụ |
| `PARTIAL` | Chấp nhận backup chưa xong | DB 50TB+ không thể hoàn tất 1 đêm |

### RATE — Giới hạn băng thông per Channel

```sql
RMAN> RUN {
  ALLOCATE CHANNEL c1 DEVICE TYPE DISK
    RATE 50M;               -- tối đa 50 MB/s cho channel này
  BACKUP DATABASE;
}
-- Dùng khi backup qua mạng — tránh flood mạng production
```

---

# 📖 Phần 6: Giám sát Backup bằng V$ Views

### V$SESSION_LONGOPS — Xem tiến độ backup đang chạy ⭐⭐⭐

```sql
SELECT SID, SERIAL#,
       OPNAME,
       SOFAR, TOTALWORK,
       ROUND(SOFAR/TOTALWORK*100, 1) AS PCT_DONE,
       ELAPSED_SECONDS,
       TIME_REMAINING
FROM V$SESSION_LONGOPS
WHERE OPNAME LIKE 'RMAN%'
  AND TOTALWORK > 0
  AND SOFAR < TOTALWORK
ORDER BY TIME_REMAINING;
```

**Output mẫu (backup đang chạy 68%):**
```
SID  SERIAL# OPNAME                 SOFAR TOTALWORK PCT_DONE ELAPSED_SECONDS TIME_REMAINING
---- ------- ---------------------- ----- --------- -------- --------------- --------------
 142    8821 RMAN: aggregate input   1532      2248     68.1             423            197
```

---

### V$RMAN_STATUS — Lịch sử các lần backup

```sql
SELECT OPERATION, STATUS,
       TO_CHAR(START_TIME,'DD-MON-YY HH24:MI') AS START_TIME,
       TO_CHAR(END_TIME,'DD-MON-YY HH24:MI') AS END_TIME,
       MBYTES_PROCESSED
FROM V$RMAN_STATUS
WHERE OPERATION IN ('BACKUP','RESTORE')
ORDER BY START_TIME DESC
FETCH FIRST 10 ROWS ONLY;
```

---

### V$BACKUP_ASYNC_IO — Kiểm tra Async I/O đang dùng

```sql
SELECT FILENAME,
       TYPE,
       BUFFER_SIZE/1024 AS BUFFER_KB,
       BUFFER_COUNT,
       EFFECTIVE_BYTES_PER_SECOND/1024/1024 AS THROUGHPUT_MBS,
       IO_COUNT,
       READY,
       SHORT_WAITS,
       LONG_WAITS
FROM V$BACKUP_ASYNC_IO
ORDER BY OPEN_TIME DESC;
```

**Ý nghĩa các cột:**
| Cột | Ý nghĩa |
|-----|---------|
| `THROUGHPUT_MBS` | Tốc độ thực tế MB/s |
| `SHORT_WAITS` | Số lần chờ ngắn (<1ms) — bình thường |
| `LONG_WAITS` | Số lần chờ dài (>1ms) — dấu hiệu bottleneck |

---

### V$BACKUP_SYNC_IO — Kiểm tra Sync I/O (khi Async không chạy)

```sql
SELECT FILENAME, TYPE,
       EFFECTIVE_BYTES_PER_SECOND/1024/1024 AS THROUGHPUT_MBS,
       IO_COUNT
FROM V$BACKUP_SYNC_IO;
-- Nếu có dữ liệu ở đây → RMAN đang chạy Sync I/O (chậm)
```

---

### V$RMAN_OUTPUT — Xem output RMAN từ SQL*Plus

```sql
-- Xem 50 dòng log gần nhất của RMAN job đang/vừa chạy
SELECT RMAN_STATUS_RECID, OUTPUT
FROM V$RMAN_OUTPUT
WHERE RMAN_STATUS_RECID = (SELECT MAX(RECID) FROM V$RMAN_STATUS)
ORDER BY RECNO;
```

---

# 📖 Phần 7: RMAN Troubleshooting — Đọc lỗi & Xử lý

## 1. Giải mã Error Stack — Đọc từ DƯỚI LÊN ⭐⭐⭐

Khi RMAN báo lỗi, error stack trông như sau:
```
RMAN-03009: failure of backup command on c1 channel at 12/15/2024 02:31:45
RMAN-10015: error compiling PL/SQL program
ORA-19506: failed to create sequential file
ORA-27037: unable to obtain file status
SVR4 Error: 2: No such file or directory
```

**Cách đọc:**
```
Đọc TỪ DƯỚI LÊN:
  SVR4 Error: 2 → OS báo: thư mục không tồn tại
  ORA-27037    → Oracle xác nhận: không thể kiểm tra file
  ORA-19506    → Oracle báo: không tạo được file
  RMAN-10015   → RMAN: PL/SQL compile lỗi
  RMAN-03009   → RMAN: lệnh backup thất bại (hệ quả cuối)

→ Root cause: Thư mục backup không tồn tại hoặc sai quyền
→ Fix: mkdir -p /u02/backup && chown oracle:oinstall /u02/backup
```

## 2. Bảng lỗi thường gặp

| Mã lỗi | Nguyên nhân | Cách fix |
|--------|-------------|---------|
| `ORA-19506` | Không tạo được file backup | Kiểm tra thư mục tồn tại + quyền |
| `ORA-19504` | Không thể tạo file mới | Disk full hoặc quota exceeded |
| `ORA-27037` | OS không thể stat file | Đường dẫn sai hoặc NFS mount lỗi |
| `ORA-19809` | Vượt quá số lượng backup file cho phép | `CROSSCHECK BACKUP` rồi `DELETE EXPIRED` |
| `RMAN-06059` | Expected archived log not found | Archive log bị xóa thủ công ngoài RMAN |
| `RMAN-20005` | Target database name mismatch | DB_NAME trong tnsnames.ora không khớp |
| `ORA-04031` | Large Pool hết chỗ | Tăng `LARGE_POOL_SIZE` |

## 3. Kiểm tra Alert Log khi backup treo

Khi RMAN treo mà không báo lỗi:
```bash
# Tìm alert log của database
ls $ORACLE_BASE/diag/rdbms/$(echo $ORACLE_SID | tr '[:upper:]' '[:lower:]')/$ORACLE_SID/trace/alert_$ORACLE_SID.log

# Xem 100 dòng cuối
tail -100 $ORACLE_BASE/diag/rdbms/oradb/ORADB/trace/alert_ORADB.log

# Tìm lỗi ORA- trong alert log
grep -i "ORA-" $ORACLE_BASE/diag/rdbms/oradb/ORADB/trace/alert_ORADB.log | tail -20
```

## 4. Khi RMAN backup chạy nhưng nghi ngờ chậm bất thường

```sql
-- Xem RMAN session đang làm gì
SELECT s.SID, s.SERIAL#, s.USERNAME, s.PROGRAM,
       w.EVENT, w.WAIT_TIME, w.SECONDS_IN_WAIT
FROM V$SESSION s
JOIN V$SESSION_WAIT w ON s.SID = w.SID
WHERE s.PROGRAM LIKE '%rman%'
   OR s.MODULE  LIKE '%RMAN%';
```

**Output mẫu (RMAN đang chờ I/O):**
```
SID   SERIAL# USERNAME PROGRAM         EVENT                          WAIT_TIME SECONDS_IN_WAIT
----- ------- -------- --------------- ------------------------------ --------- ---------------
  142    8821 SYS      rman@srv1       db file sequential read                0               3
  143    9012 SYS      rman@srv1       direct path read                       0               1
```

---

# 📖 Phần 8: DEBUG Mode — Bật còi chẩn đoán

### Khi nào cần DEBUG?
- RMAN treo im lặng nhiều giờ mà không ra ORA error
- Cần trace từng bước RMAN giao tiếp với Oracle kernel
- Khi support Oracle yêu cầu trace để phân tích SR (Service Request)

### Cách 1: DEBUG từ dòng lệnh OS (trước khi vào RMAN)
```bash
rman target / debug=all trace=/tmp/rman_debug.trc log=/tmp/rman_run.log
```

### Cách 2: DEBUG trong Channel (sau khi đã vào RMAN)
```sql
RMAN> RUN {
  ALLOCATE CHANNEL c1 TYPE DISK
    DEBUG = 5     -- Mức debug: 1 (ít) đến 5 (nhiều nhất)
    TRACE = 5;
  BACKUP DATABASE;
  RELEASE CHANNEL c1;
}
```

### Cách 3: Bật/tắt DEBUG trong phiên RMAN đang chạy
```sql
RMAN> DEBUG ON;
  -- Thực hiện lệnh cần debug
  BACKUP TABLESPACE users;
RMAN> DEBUG OFF;
```

### Xem trace file:
```bash
# File trace trong Automatic Diagnostic Repository (ADR)
ls $ORACLE_BASE/diag/rdbms/oradb/ORADB/trace/ | grep rman

# Hoặc file log chỉ định ở dòng lệnh
tail -f /tmp/rman_debug.trc | grep -E "RMAN-|ORA-|ERROR"
```

> **CẢNH BÁO**: Bật DEBUG=5 làm RMAN chạy chậm đi 10–30 lần. Chỉ bật trong môi trường Test hoặc cho thời gian ngắn. Nhớ `DEBUG OFF` khi xong.

---

# 🎯 Thực hành Practice 22: Lab Tuning & Troubleshooting

## Step 1: Kiểm tra cấu hình I/O hiện tại

```sql
-- Kết nối SQL*Plus
conn / as sysdba

-- Xem các tham số liên quan I/O
SELECT NAME, VALUE, DESCRIPTION
FROM V$PARAMETER
WHERE NAME IN (
  'backup_tape_io_slaves',
  'dbwr_io_slaves',
  'large_pool_size',
  'db_recovery_file_dest',
  'db_recovery_file_dest_size'
);
```

**Output mẫu:**
```
NAME                       VALUE  DESCRIPTION
-------------------------- ------ ------------------------------------------
backup_tape_io_slaves      FALSE  use I/O slaves for tape devices
dbwr_io_slaves             0      number of DBWR I/O slaves
large_pool_size            33554432  size in bytes of large pool
db_recovery_file_dest      /u02/fra  default database recovery file location
db_recovery_file_dest_size 5368709120  database recovery files size limit
```

## Step 2: Tăng Large Pool và kiểm tra hiệu ứng

```sql
-- Tăng Large Pool lên 128MB (không cần restart)
ALTER SYSTEM SET LARGE_POOL_SIZE = 128M SCOPE=BOTH;

-- Xác nhận
SHOW PARAMETER large_pool_size;
```

**Output mẫu:**
```
NAME                                 TYPE        VALUE
------------------------------------ ----------- ------------------------------
large_pool_size                      big integer 128M
```

## Step 3: Chạy backup và monitor tiến độ

```sql
-- Terminal 1: Chạy backup (RMAN)
-- rman target /
BACKUP DATABASE PLUS ARCHIVELOG FORMAT '/u02/backup/%U.bkp';
```

```sql
-- Terminal 2: Theo dõi tiến độ (SQL*Plus cùng lúc)
SELECT OPNAME,
       SOFAR || '/' || TOTALWORK AS PROGRESS,
       ROUND(SOFAR/TOTALWORK*100,1) AS PCT_DONE,
       TIME_REMAINING || 's' AS ETA
FROM V$SESSION_LONGOPS
WHERE OPNAME LIKE 'RMAN%'
  AND TOTALWORK > 0
  AND SOFAR < TOTALWORK;
```

**Output mẫu (chạy mỗi 30 giây để theo dõi):**
```
OPNAME                    PROGRESS PCT_DONE ETA
------------------------- -------- -------- ------
RMAN: aggregate input     445/1248     35.7 312s
RMAN: full datafile backup 89/248      35.9 315s
```

## Step 4: Xem I/O Throughput thực tế

```sql
SELECT TYPE,
       ROUND(EFFECTIVE_BYTES_PER_SECOND/1024/1024, 2) AS "MB/s",
       SHORT_WAITS,
       LONG_WAITS,
       BUFFER_SIZE,
       BUFFER_COUNT
FROM V$BACKUP_ASYNC_IO
ORDER BY OPEN_TIME DESC
FETCH FIRST 5 ROWS ONLY;
```

**Output mẫu (Async I/O đang chạy tốt):**
```
TYPE   MB/s   SHORT_WAITS LONG_WAITS BUFFER_SIZE BUFFER_COUNT
------ ------ ----------- ---------- ----------- ------------
INPUT  102.34        8821        123       65536            4
OUTPUT  98.76        8445         98       65536            4
```

> `LONG_WAITS` nhiều → dấu hiệu I/O bottleneck → cân nhắc thêm channel hoặc phân tán disk.

## Step 5: Demo Multiplexing — FILESPERSET & MAXPIECESIZE

```sql
-- RMAN
RUN {
  ALLOCATE CHANNEL c1 DEVICE TYPE DISK
    MAXPIECESIZE 512M
    FORMAT '/u02/backup/%U.bkp';
  BACKUP DATABASE FILESPERSET 2;
  RELEASE CHANNEL c1;
}
```

**Output mẫu (RMAN tự cắt piece):**
```
channel c1: starting full datafile backup set
channel c1: specifying datafile(s) in backup set
input datafile file number=00001 name=/u01/oradata/ORADB/system01.dbf
input datafile file number=00003 name=/u01/oradata/ORADB/sysaux01.dbf
channel c1: starting piece 1 at 15-DEC-24
channel c1: finished piece 1 at 15-DEC-24  ← Đạt 512MB, tự ngắt
Piece handle=/u02/backup/08sp4b1c_1_1.bkp tag=TAG20241215T023115 comment=NONE
channel c1: starting piece 2 at 15-DEC-24
channel c1: finished piece 2 at 15-DEC-24
...
```

## Step 6: Mô phỏng lỗi và đọc Error Stack

```sql
-- RMAN: Cố tình backup vào thư mục không tồn tại
BACKUP DATABASE FORMAT '/nonexistent/path/%U.bkp';
```

**Output lỗi mẫu (đọc từ DƯỚI LÊN):**
```
RMAN-03009: failure of backup command on ORA_DISK_1 channel at 12/15/2024 02:42:11
ORA-19504: failed to create file "/nonexistent/path/09sp4c2d_1_1.bkp"
ORA-27040: file create error, unable to create file
Linux-x86_64 Error: 2: No such file or directory
```

```
Phân tích từ dưới lên:
  ↓ Linux Error: 2  → OS: thư mục /nonexistent/path không tồn tại
  ↓ ORA-27040       → Oracle: không tạo được file
  ↓ ORA-19504       → Oracle backup engine: tạo backup piece thất bại
  ↓ RMAN-03009      → RMAN: lệnh backup thất bại (symptom cuối cùng)

Fix: mkdir -p /nonexistent/path && chown oracle:oinstall /nonexistent/path
```

## Step 7: Thực hành DURATION MINIMIZE LOAD

```sql
-- Backup trong 30 phút, minimize tải DB (demo ngắn)
BACKUP DATABASE DURATION 00:30 MINIMIZE LOAD;
```

**Output mẫu:**
```
Starting backup at 15-DEC-24
...
channel ORA_DISK_1: throttling due to DURATION MINIMIZE LOAD
channel ORA_DISK_1: finished full datafile backup set
Finished backup at 15-DEC-24
```

---

# 🎯 Câu hỏi ôn tập Module 16

**1. Trong lúc cấu hình `BACKUP DURATION 4:00`, tham số đuôi `MINIMIZE LOAD` có tác dụng gì? Khác gì `MINIMIZE TIME`?**
<details>
<summary>💡 Đáp án</summary>

- **MINIMIZE TIME**: RMAN chạy full throttle, tận dụng 100% I/O để kết thúc sớm nhất có thể trong 4 tiếng.
- **MINIMIZE LOAD**: RMAN tính xem thực ra bao lâu thì xong (ví dụ 1 tiếng). Sau đó nó **rải đều** tiến trình bằng cách chèn sleep, kéo dài ra đúng 4 tiếng. Giúp server Production ban ngày không bị backup cắm cúi chiếm I/O.
</details>

---

**2. RMAN gặp lỗi `ORA-19506` và `SVR4 Error: 2: No such file`. Bắt đầu fix từ đâu?**
<details>
<summary>💡 Đáp án</summary>

Đọc error stack từ DƯỚI LÊN. Root cause là **SVR4 Error: 2** — OS báo thư mục đích không tồn tại. Fix đầu tiên: kiểm tra và tạo thư mục backup trên OS, gán đúng quyền cho user oracle. Không cần động vào cấu hình database.
</details>

---

**3. Nếu `FILESPERSET=5` và `MAXOPENFILES=3`, RMAN sẽ mở bao nhiêu Datafile cùng lúc trong 1 Channel?**
<details>
<summary>💡 Đáp án</summary>

**3 files** — Công thức VÀNG: `MIN(MAXOPENFILES, FILESPERSET) = MIN(3, 5) = 3`.

MAXOPENFILES là giới hạn cứng của Channel, nhỏ hơn FILESPERSET nên nó thắng.
</details>

---

**4. Tại sao RMAN đột nhiên chạy chậm hơn sau khi bật `BACKUP_TAPE_IO_SLAVES=TRUE` nhưng không tăng Large Pool?**
<details>
<summary>💡 Đáp án</summary>

Khi bật Tape I/O Slaves, RMAN cần cấp phát bộ nhớ đệm (I/O Buffer) từ Large Pool. Nếu Large Pool quá nhỏ → **ORA-04031** (không đủ shared memory) → RMAN tự động **fallback về Sync I/O**, vốn chậm hơn cả trước. Fix: tăng `LARGE_POOL_SIZE` trước rồi mới bật I/O Slaves.
</details>

---

**5. RMAN treo 2 tiếng không có output, không có ORA error. Cần làm gì theo thứ tự?**
<details>
<summary>💡 Đáp án</summary>

1. Kiểm tra `V$SESSION_LONGOPS` — xem RMAN đang ở bước nào, còn bao lâu nữa.
2. Kiểm tra `V$SESSION_WAIT` join với `V$SESSION` — xem RMAN đang wait event gì (disk I/O? network? lock?).
3. Xem Alert Log: `tail -100 alert_ORADB.log` — tìm ORA error.
4. Nếu vẫn mù tịt → bật `DEBUG ON` để thu trace, xem RMAN đang làm gì phía sau.
</details>

---

## ➡️ Bài tiếp theo
**Module 17: Multitenant, RAC & Cloud — Bài tốt nghiệp**
Đây là module CUỐI CÙNG của toàn khóa! RMAN trong kiến trúc Container Database (CDB/PDB), Real Application Clusters (RAC), và Oracle Cloud Infrastructure (OCI). Các quy tắc khắt khe hơn nhưng nền tảng đã học 16 module sẽ giúp anh tiếp thu nhanh.


---

!!! info "Nguồn gốc"
    `dba_ai/oracle_rman/modules/module_16_guide.md`
