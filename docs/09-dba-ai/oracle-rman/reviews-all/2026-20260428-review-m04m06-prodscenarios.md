---
title: '🎯 Ôn Tập Module 04–06: Tình Huống Production Thực Chiến'
course: 09-dba-ai
source: dba_ai/oracle_rman/reviews_all/20260428_Review_M04M06_ProdScenarios.md
---

# 🎯 Ôn Tập Module 04–06: Tình Huống Production Thực Chiến

**Phạm vi**: Module 04 (Full Backup) + Module 05 (Incremental Backup) + Module 06 (Persistent Settings)  
**Ngày tạo**: 2026-04-28  
**Lab target**: Oracle 12c · SID=ORADB · 192.168.1.8  
**Script thực hành**: `20260428_lab_M04M06.sh` (chạy được trực tiếp trên server)

---

## Mục lục

- [Tình huống 1 – FRA đầy bất ngờ lúc 2h sáng](#tình-huống-1--fra-đầy-bất-ngờ-lúc-2h-sáng-firedrill)
- [Tình huống 2 – Incremental Level 1 chạy lâu bằng Full Backup](#tình-huống-2--incremental-level-1-chạy-lâu-bằng-full-backup-firedrill)
- [Tình huống 3 – Đọc log và chẩn đoán backup fail](#tình-huống-3--đọc-log-và-chẩn-đoán-backup-fail-loganalysis)
- [Tình huống 4 – Thiết kế backup strategy cho DB mới go-live](#tình-huống-4--thiết-kế-backup-strategy-cho-db-mới-go-live-crossmodule)
- [Tình huống 5 – Config drift sau khi DBA cũ nghỉ việc](#tình-huống-5--config-drift-sau-khi-dba-cũ-nghỉ-việc-crossmodule)
- [Mock Exam – 20 câu hỏi M04–M06](#mock-exam--20-câu-hỏi-m04m06)

---

## Tình huống 1 – FRA đầy bất ngờ lúc 2h sáng (FireDrill)

### Bối cảnh production

Hệ thống giám sát (OEM) gửi alert lúc **02:17 sáng**:

```
ORA-19809: limit exceeded for recovery files
ORA-19804: cannot reclaim 2145386496 bytes disk space from 10737418240 limit
```

Bạn SSH vào server. Database vẫn **OPEN** nhưng **không thể ghi Archive Log mới** → mọi transaction đang bị treo.

### Nguyên nhân gốc rễ

DBA đã set FRA = 10GB nhưng **không bao giờ chạy DELETE OBSOLETE** và **không có RETENTION POLICY**. Sau 30 ngày accumulate, FRA đầy tràn.

### Nhiệm vụ của bạn

1. Xác định nhanh FRA đang ở bao nhiêu phần trăm
2. Tìm xem file loại nào chiếm nhiều nhất
3. Giải phóng FRA trong vòng 5 phút để database hoạt động lại
4. Cấu hình đúng để sự cố không tái phát

---

### Action Plan

#### Bước 1 – Chẩn đoán nhanh (< 1 phút)

```sql
-- Tổng FRA
SELECT ROUND(SUM(PERCENT_SPACE_USED), 1)         AS TOTAL_PCT,
       ROUND(VALUE/1024/1024/1024, 1)             AS FRA_GB
FROM   V$RECOVERY_AREA_USAGE, V$PARAMETER
WHERE  NAME = 'db_recovery_file_dest_size';

-- Chi tiết từng loại file
SELECT FILE_TYPE,
       ROUND(PERCENT_SPACE_USED, 1)        AS PCT_USED,
       ROUND(PERCENT_SPACE_RECLAIMABLE, 1) AS PCT_RECLAIM,
       NUMBER_OF_FILES
FROM   V$RECOVERY_AREA_USAGE
ORDER  BY PERCENT_SPACE_USED DESC;
```

**Đọc kết quả**: Nếu `BACKUP PIECE` chiếm 80%+ → quá nhiều backup không được dọn. Nếu `ARCHIVED LOG` chiếm nhiều → archive log chưa backup.

#### Bước 2 – Giải phóng khẩn cấp (< 3 phút)

```bash
rman target /
```

```rman
-- Crosscheck để RMAN cập nhật trạng thái file vật lý
CROSSCHECK BACKUP;
CROSSCHECK ARCHIVELOG ALL;

-- Xóa ngay backup hết hạn (file không còn trên disk)
DELETE NOPROMPT EXPIRED BACKUP;
DELETE NOPROMPT EXPIRED ARCHIVELOG ALL;

-- Xóa backup OBSOLETE (cũ hơn retention)
-- Lúc này chưa có retention → dùng lệnh dưới để xóa tất cả backup cũ hơn 3 ngày
DELETE NOPROMPT BACKUP COMPLETED BEFORE 'SYSDATE-3';
```

#### Bước 3 – Kiểm tra database đã hoạt động lại chưa

```sql
-- Database có thể ghi archive log chưa?
SELECT SEQUENCE#, STATUS, NAME FROM V$ARCHIVED_LOG
WHERE  COMPLETION_TIME > SYSDATE - 1/24   -- 1 giờ gần nhất
ORDER  BY SEQUENCE# DESC;

-- FRA còn bao nhiêu?
SELECT ROUND(SUM(PERCENT_SPACE_USED), 1) AS PCT,
       CASE WHEN SUM(PERCENT_SPACE_USED) < 70 THEN 'AN TOAN'
            WHEN SUM(PERCENT_SPACE_USED) < 85 THEN 'CHU Y'
            ELSE 'NGUY HIEM' END AS STATUS
FROM   V$RECOVERY_AREA_USAGE;
```

#### Bước 4 – Cấu hình phòng ngừa tái phát

```rman
-- Đặt Retention Policy phù hợp
CONFIGURE RETENTION POLICY TO RECOVERY WINDOW OF 7 DAYS;

-- Bật Archivelog Deletion Policy
CONFIGURE ARCHIVELOG DELETION POLICY TO BACKED UP 1 TIMES TO DEVICE TYPE DISK;

-- Bật autobackup controlfile
CONFIGURE CONTROLFILE AUTOBACKUP ON;

-- Xác nhận
SHOW ALL;
```

**Thêm vào cronjob nightly backup:**
```bash
# /home/oracle/rman_jobs/nightly_backup.sh
$ORACLE_HOME/bin/rman target / <<EOF
BACKUP AS COMPRESSED BACKUPSET DATABASE PLUS ARCHIVELOG;
DELETE NOPROMPT OBSOLETE;
DELETE NOPROMPT EXPIRED BACKUP;
EOF
```

---

### Lab Practice

> **Chạy script**: `bash 20260428_lab_M04M06.sh` → chọn **[1]**

Kịch bản lab:
1. Script tạo nhiều backup nhỏ để tích lũy trong FRA
2. Giả lập FRA ~85% bằng cách set limit nhỏ tạm thời
3. Bạn thực hành các bước chẩn đoán + giải phóng

---

## Tình huống 2 – Incremental Level 1 chạy lâu bằng Full Backup (FireDrill)

### Bối cảnh production

DB **ORADB** kích thước 50GB. Chiến lược backup:
- Chủ nhật: Level 0 → 45 phút
- Thứ 2–7: Level 1 Differential → **45 phút** (bằng Level 0!)

DBA kiểm tra: DB chỉ thay đổi khoảng **2GB/ngày** (4% tổng dung lượng). Lý thuyết Level 1 phải chạy trong ~3 phút. Tại sao lại mất 45 phút?

### Chẩn đoán

```sql
-- Kiểm tra BCT có bật không
SELECT STATUS, NVL(FILENAME,'(chua bat)') AS BCT_FILE
FROM   V$BLOCK_CHANGE_TRACKING;
-- Kết quả: STATUS = 'DISABLED' → Root cause!

-- Xem lịch sử backup: Level 0 vs Level 1
SELECT INCREMENTAL_LEVEL, COUNT(*) AS JOBS,
       ROUND(AVG(BYTES)/1024/1024, 0) AS AVG_MB,
       ROUND(AVG((END_TIME-START_TIME)*24*60), 1) AS AVG_MIN
FROM   V$BACKUP_SET
WHERE  BACKUP_TYPE IN ('D','I') AND START_TIME > SYSDATE - 14
GROUP  BY INCREMENTAL_LEVEL;
-- Kết quả: Level 1 có AVG_MB ≈ Level 0 → RMAN đang full scan!
```

**Giải thích**: Khi BCT tắt, RMAN phải **quét toàn bộ 50GB** để tìm block nào thay đổi kể từ Level 0. I/O = I/O của Full Scan 50GB → thời gian ≈ Level 0.

### Action Plan

#### Bật BCT và đo hiệu quả

```rman
-- Bước 1: Xem đường dẫn datafile để chọn chỗ đặt BCT file
SELECT FILE#, NAME FROM V$DATAFILE;
-- Ví dụ: /u01/app/oracle/oradata/ORADB/

-- TUYỆT ĐỐI KHÔNG đặt BCT trong FRA!
-- BCT trong FRA = FRA space management bị hỏng
```

```sql
-- Bước 2: Bật BCT
ALTER DATABASE ENABLE BLOCK CHANGE TRACKING
  USING FILE '/u01/app/oracle/oradata/ORADB/bct_oradb.chg';
```

```rman
-- Bước 3: Chạy Level 0 sau khi bật BCT (bắt buộc để BCT có baseline)
BACKUP INCREMENTAL LEVEL 0 DATABASE TAG 'AFTER_BCT_ENABLE';

-- Bước 4: Chạy Level 1 ngay sau đó để có dữ liệu so sánh
BACKUP INCREMENTAL LEVEL 1 DATABASE TAG 'FIRST_L1_WITH_BCT';
```

```sql
-- Bước 5: Đo hiệu quả BCT
SELECT USED_CHANGE_TRACKING   AS BCT_USED,
       FILE#,
       ROUND(AVG(DATAFILE_BLOCKS), 0)  AS TOTAL_BLOCKS,
       ROUND(AVG(BLOCKS_READ), 0)      AS BLOCKS_READ,
       ROUND(AVG(BLOCKS_READ)/NULLIF(AVG(DATAFILE_BLOCKS),0)*100, 1) AS PCT_SCAN
FROM   V$BACKUP_DATAFILE
WHERE  INCREMENTAL_LEVEL > 0
GROUP  BY USED_CHANGE_TRACKING, FILE#
ORDER  BY FILE#;
-- Mong đợi: PCT_SCAN < 10% sau khi BCT hoạt động ổn định
```

### Kết quả mong đợi sau khi fix

| Metric | Trước BCT | Sau BCT |
|--------|-----------|---------|
| Level 1 time | 45 phút | 3–5 phút |
| BLOCKS_READ | 50GB worth | ~2GB worth |
| PCT_SCAN | ~100% | < 5% |

---

### Lab Practice

> **Chạy script**: `bash 20260428_lab_M04M06.sh` → chọn **[2]**

1. Tắt BCT → chạy Level 1 → ghi lại thời gian
2. Bật BCT → chạy Level 0 → chạy Level 1 → so sánh thời gian
3. Query PCT_SCAN để xác nhận hiệu quả

---

## Tình huống 3 – Đọc log và chẩn đoán backup fail (LogAnalysis)

### Bối cảnh

Buổi sáng bạn nhận được email: *"Nightly backup job FAILED at 02:43"*. Log file được đính kèm. Hãy đọc và xác định nguyên nhân.

### Log mẫu (giả lập từ lab)

```
Recovery Manager: Release 12.2.0.1.0

RMAN> BACKUP AS COMPRESSED BACKUPSET INCREMENTAL LEVEL 1
2>   DATABASE TAG 'NIGHTLY_L1_20260428' PLUS ARCHIVELOG;
Starting backup at 28-APR-2026 02:40:15
allocated channel: ORA_DISK_1
allocated channel: ORA_DISK_2
channel ORA_DISK_1: starting compressed incremental level 1 datafile backup set
channel ORA_DISK_1: specifying datafile(s) in backup set
input datafile file number=00001 name=/u01/.../system01.dbf
input datafile file number=00003 name=/u01/.../sysaux01.dbf
channel ORA_DISK_2: starting compressed incremental level 1 datafile backup set
channel ORA_DISK_2: specifying datafile(s) in backup set
input datafile file number=00004 name=/u01/.../undotbs01.dbf
input datafile file number=00007 name=/u01/.../users01.dbf
channel ORA_DISK_1: backup set complete, elapsed time: 00:00:45
channel ORA_DISK_2: backup set complete, elapsed time: 00:00:43
channel ORA_DISK_1: starting compressed archive log backup set
channel ORA_DISK_1: specifying archive log(s) in backup set
...
RMAN-00571: ===========================================================
RMAN-00569: =============== ERROR MESSAGE STACK FOLLOWS ===============
RMAN-00571: ===========================================================
RMAN-03009: failure of backup command on ORA_DISK_1 channel
            at 04/28/2026 02:43:17
ORA-19809: limit exceeded for recovery files
ORA-19804: cannot reclaim 1073741824 bytes disk space from 10737418240 limit
```

### Câu hỏi chẩn đoán

1. Backup fail ở giai đoạn nào? Backup datafile hay Archive Log?
2. Lỗi gốc rễ là gì? (đọc ORA code cuối cùng)
3. Tại sao RMAN_DISK_1 fail nhưng ORA_DISK_2 vẫn chạy song song?
4. Cần làm gì NGAY để hệ thống hoạt động lại?
5. Cần cấu hình gì để tránh tái phát?

### Đáp án phân tích

**Câu 1**: Fail ở giai đoạn backup **Archive Log** (sau khi datafile backup thành công). Chú ý: `channel ORA_DISK_1: backup set complete` cho datafile → OK. Lỗi xuất hiện sau đó ở archive log backup.

**Câu 2**: `ORA-19804: cannot reclaim X bytes disk space from Y limit` = FRA đã **100% đầy**, không còn chỗ để ghi archive log backup piece. `ORA-19809` là lỗi trigger từ việc FRA đầy.

**Câu 3**: RMAN 2 channels chạy song song cho 2 tập datafile riêng biệt. ORA_DISK_1 handle archive log → fail trước. ORA_DISK_2 đã hoàn thành datafile của nó trước khi nhận task archive log.

**Câu 4 – Fix ngay**:
```rman
-- Giải phóng FRA
CROSSCHECK BACKUP;
DELETE NOPROMPT OBSOLETE;
DELETE NOPROMPT EXPIRED BACKUP;

-- Chạy lại job bị fail
BACKUP ARCHIVELOG ALL NOT BACKED UP 1 TIMES;
```

**Câu 5 – Phòng ngừa**:
```rman
CONFIGURE RETENTION POLICY TO RECOVERY WINDOW OF 7 DAYS;
CONFIGURE ARCHIVELOG DELETION POLICY TO BACKED UP 1 TIMES TO DEVICE TYPE DISK;
```
Và thêm `DELETE NOPROMPT OBSOLETE;` vào cuối mỗi nightly backup job.

---

### Lab Practice

> **Chạy script**: `bash 20260428_lab_M04M06.sh` → chọn **[3]**

Script sẽ giả lập tình huống:
1. Tạo backup nhiều lần để tích lũy
2. Set FRA nhỏ để gây ORA-19809
3. Bạn đọc log, chẩn đoán, và fix

---

## Tình huống 4 – Thiết kế backup strategy cho DB mới go-live (CrossModule)

### Bối cảnh production

DB **FINDB** (financial system) sẽ go-live vào thứ Hai tới. Specs:
- Kích thước: **80GB** (dự kiến tăng 500MB/ngày)
- SLA: **RPO = 24h** (mất tối đa 1 ngày data), **RTO = 1h** (phục hồi trong 1 tiếng)
- Backup window: **01:00–05:00** (4 tiếng mỗi đêm)
- Lưu trữ: **1 disk backup** tại `/u02/backup/FINDB`, FRA = 30GB
- Yêu cầu: Backup tự động, có log, cảnh báo khi fail

### Nhiệm vụ thiết kế

Xây dựng hoàn chỉnh:
1. CONFIGURE persistent settings
2. Lịch backup hàng tuần (Level 0 / Level 1)
3. Cronjob script
4. Monitoring checklist

---

### Action Plan

#### Phần 1 – CONFIGURE Settings

```rman
-- Retention: 7 ngày Recovery Window
-- Giải thích: RPO=24h nên phải phục hồi được mọi thời điểm trong 7 ngày
CONFIGURE RETENTION POLICY TO RECOVERY WINDOW OF 7 DAYS;

-- Autobackup controlfile: LUÔN bật trong production
CONFIGURE CONTROLFILE AUTOBACKUP ON;
CONFIGURE CONTROLFILE AUTOBACKUP FORMAT FOR DEVICE TYPE DISK
  TO '/u02/backup/FINDB/ctlfile_%F';

-- Parallelism: 2 channel (DB 80GB, cần finish trong 4h window)
CONFIGURE DEVICE TYPE DISK PARALLELISM 2 BACKUP TYPE TO BACKUPSET;

-- Format rõ ràng: dễ audit, phân loại theo ngày
CONFIGURE CHANNEL DEVICE TYPE DISK FORMAT '/u02/backup/FINDB/%d_%T_%U';

-- Archivelog Deletion Policy: bảo vệ archive log khỏi bị xóa nhầm
CONFIGURE ARCHIVELOG DELETION POLICY TO BACKED UP 1 TIMES TO DEVICE TYPE DISK;

-- Backup Optimization: bỏ qua archive log đã backup rồi
CONFIGURE BACKUP OPTIMIZATION ON;

-- Xác nhận
SHOW ALL;
```

#### Phần 2 – Lịch backup hàng tuần

```
  Chủ nhật 01:00  → Level 0 (Full baseline) + ARCHIVELOG + DELETE OBSOLETE
  Thứ 2–7  01:00  → Level 1 Differential + ARCHIVELOG + DELETE OBSOLETE
```

**Ước tính thời gian**:
- Level 0 (80GB compressed): ~45–60 phút
- Level 1 (daily change ~500MB): ~3–5 phút (với BCT)
- Archive log backup: ~5–10 phút
- Tổng: Max 75 phút → Fit trong 4h window

#### Phần 3 – Cronjob scripts

**Script Chủ nhật (Level 0)**:
```bash
#!/bin/bash
# /home/oracle/rman_jobs/sunday_level0.sh
export ORACLE_SID=FINDB
export ORACLE_HOME=/u01/app/oracle/product/12.2.0/db_1
export PATH=$ORACLE_HOME/bin:/usr/local/bin:/bin:/usr/bin
export NLS_DATE_FORMAT='DD-MON-YYYY HH24:MI:SS'

LOG=/home/oracle/rman_logs/sunday_l0_$(date +%Y%m%d).log

rman target / log="$LOG" <<EOF
BACKUP AS COMPRESSED BACKUPSET
  INCREMENTAL LEVEL 0 DATABASE TAG 'WEEKLY_L0_$(date +%Y%m%d)'
  PLUS ARCHIVELOG;

DELETE NOPROMPT OBSOLETE;
DELETE NOPROMPT EXPIRED BACKUP;

LIST BACKUP SUMMARY;
EOF

[[ $? -ne 0 ]] && mail -s "RMAN FAIL: FINDB Sunday Level 0" dba@company.com < "$LOG"
find /home/oracle/rman_logs -name "sunday_l0_*.log" -mtime +30 -delete
```

**Script Thứ 2–7 (Level 1 Differential)**:
```bash
#!/bin/bash
# /home/oracle/rman_jobs/daily_level1.sh
export ORACLE_SID=FINDB
export ORACLE_HOME=/u01/app/oracle/product/12.2.0/db_1
export PATH=$ORACLE_HOME/bin:/usr/local/bin:/bin:/usr/bin

LOG=/home/oracle/rman_logs/daily_l1_$(date +%Y%m%d).log

rman target / log="$LOG" <<EOF
BACKUP AS COMPRESSED BACKUPSET
  INCREMENTAL LEVEL 1 DATABASE TAG 'DAILY_L1_$(date +%Y%m%d)'
  PLUS ARCHIVELOG;

DELETE NOPROMPT OBSOLETE;
LIST BACKUP SUMMARY;
EOF

[[ $? -ne 0 ]] && mail -s "RMAN FAIL: FINDB Daily Level 1" dba@company.com < "$LOG"
find /home/oracle/rman_logs -name "daily_l1_*.log" -mtime +30 -delete
```

**Crontab setup**:
```bash
# Chủ nhật: Level 0 lúc 01:00
0 1 * * 0 /home/oracle/rman_jobs/sunday_level0.sh >> /dev/null 2>&1

# Thứ 2-7: Level 1 lúc 01:00
0 1 * * 1-6 /home/oracle/rman_jobs/daily_level1.sh >> /dev/null 2>&1
```

#### Phần 4 – Bật BCT ngay sau Level 0 đầu tiên

```sql
-- Sau khi database go-live và Level 0 đầu tiên hoàn thành:
ALTER DATABASE ENABLE BLOCK CHANGE TRACKING
  USING FILE '/u01/app/oracle/oradata/FINDB/bct_findb.chg';
-- Sau đó chạy Level 0 lần nữa để BCT có baseline
```

#### Phần 5 – Monitoring checklist hàng ngày

```sql
-- DBA check buổi sáng (chạy sau khi backup đêm xong):
-- 1. Backup có thành công không?
SELECT STATUS, TO_CHAR(START_TIME,'DD-MON HH24:MI') AS START,
       INPUT_TYPE, OUTPUT_BYTES_DISPLAY
FROM   V$RMAN_STATUS
WHERE  OPERATION = 'BACKUP' AND START_TIME > SYSDATE - 1
ORDER  BY START_TIME DESC;

-- 2. FRA còn bao nhiêu?
SELECT ROUND(SUM(PERCENT_SPACE_USED),1) AS PCT FROM V$RECOVERY_AREA_USAGE;

-- 3. Archive log đã backup chưa?
SELECT BACKED_UP, COUNT(*) FROM V$ARCHIVED_LOG
WHERE  STANDBY_DEST='NO' GROUP BY BACKED_UP;
```

---

### Lab Practice

> **Chạy script**: `bash 20260428_lab_M04M06.sh` → chọn **[4]**

Lab sẽ thực hiện toàn bộ quy trình trên ORADB (thay FINDB bằng ORADB), gồm:
- CONFIGURE tất cả settings
- Tạo cronjob scripts
- Chạy 1 chu kỳ Level 0 + Level 1 hoàn chỉnh
- Bật BCT và verify

---

## Tình huống 5 – Config drift sau khi DBA cũ nghỉ việc (CrossModule)

### Bối cảnh production

DBA cũ rời công ty 2 tuần trước. Bạn được giao quản lý DB **ORADB**. Kiểm tra sơ bộ cho thấy có điều gì đó bất thường:

```text
Email từ Sếp: "Tháng trước backup chạy 3 channel, giờ tại sao
chạy 1 channel? Backup mất gấp 3 lần thời gian!"
```

Và trong monitoring log tuần trước:
```
[2026-04-21 09:15] FRA WARNING: 78% used (increased from 52% yesterday)
[2026-04-22 09:15] FRA WARNING: 89% used
[2026-04-23 09:15] FRA CRITICAL: 97% used → backup FAILED!
```

### Chẩn đoán toàn diện

```rman
-- Bước 1: SHOW ALL để xem config thực tế
SHOW ALL;
```

**Kết quả đáng lo ngại** (config drift symptoms):
```text
CONFIGURE RETENTION POLICY TO REDUNDANCY 1;       ← Đổi thành REDUNDANCY 1 (cũ là WINDOW 7)
CONFIGURE DEVICE TYPE DISK PARALLELISM 1;          ← Giảm xuống 1 (cũ là 3)
CONFIGURE CHANNEL DEVICE TYPE DISK CLEAR;          ← Format bị CLEAR
CONFIGURE ARCHIVELOG DELETION POLICY TO NONE;      ← Deletion policy bị tắt!
CONFIGURE CONTROLFILE AUTOBACKUP OFF;               ← Autobackup bị tắt!
```

### Phân tích hậu quả

| Setting bị drift | Hậu quả tức thời |
|-----------------|-----------------|
| PARALLELISM 1 → 3 channel | Backup chậm gấp 3 lần |
| RETENTION REDUNDANCY 1 | Chỉ giữ 1 bản → khi backup fail, không có fallback |
| ARCHIVELOG DELETION NONE | Archive log không được xóa tự động → FRA đầy dần |
| AUTOBACKUP OFF | Nếu controlfile hỏng trong recovery → mất hết metadata |

### Action Plan – Khôi phục config

```rman
-- Bước 1: Snapshot trước khi sửa
-- Lưu config hiện tại vào file để audit
SHOW ALL;  -- copy output vào file /tmp/config_audit_before_fix.txt
```

```rman
-- Bước 2: Backup controlfile trước khi thay đổi
BACKUP CURRENT CONTROLFILE FORMAT '/tmp/ctlfile_before_fix_%T.bkp';
```

```rman
-- Bước 3: Khôi phục từng setting
CONFIGURE RETENTION POLICY TO RECOVERY WINDOW OF 7 DAYS;
CONFIGURE CONTROLFILE AUTOBACKUP ON;
CONFIGURE DEVICE TYPE DISK PARALLELISM 3 BACKUP TYPE TO BACKUPSET;

-- Khôi phục format nếu biết setting cũ từ tài liệu
CONFIGURE CHANNEL DEVICE TYPE DISK FORMAT '/u02/backup/ORADB/%d_%T_%U';

CONFIGURE ARCHIVELOG DELETION POLICY TO BACKED UP 1 TIMES TO DEVICE TYPE DISK;
CONFIGURE BACKUP OPTIMIZATION ON;

-- Xác nhận
SHOW ALL;
```

```rman
-- Bước 4: Dọn dẹp FRA ngay lập tức
CROSSCHECK BACKUP;
CROSSCHECK ARCHIVELOG ALL;
DELETE NOPROMPT EXPIRED BACKUP;
DELETE NOPROMPT OBSOLETE;

-- Backup archive log chưa backup
BACKUP ARCHIVELOG ALL NOT BACKED UP 1 TIMES;
```

### Bài học: Audit CONFIGURE định kỳ

```sql
-- Scheduled audit: chạy mỗi tuần để phát hiện config drift
SELECT CONF#, NAME, VALUE,
       'KY VONG' AS NOTE
FROM   V$RMAN_CONFIGURATION
MINUS
-- So sánh với snapshot tuần trước
SELECT 1, 'CONFIGURE RETENTION POLICY TO RECOVERY WINDOW OF 7 DAYS', NULL, NULL FROM DUAL;
```

**Khuyến nghị production**: Lưu output `SHOW ALL` vào file có timestamp mỗi tuần, so sánh để phát hiện drift.

---

### Lab Practice

> **Chạy script**: `bash 20260428_lab_M04M06.sh` → chọn **[5]**

Script sẽ:
1. Giả lập config drift (tự đổi các settings)
2. Bạn audit, phát hiện vấn đề
3. Restore về config chuẩn

---

## Mock Exam – 20 câu hỏi M04–M06

### Phần A – Trắc nghiệm (10 câu)

**Câu 1**: Lệnh nào tạo Full Backup toàn bộ database kèm archive log, dùng 2 channel, nén file?

A) `BACKUP DATABASE PLUS ARCHIVELOG;`  
B) `BACKUP AS COMPRESSED BACKUPSET DATABASE PLUS ARCHIVELOG;`  
C) `BACKUP COMPRESSED DATABASE WITH ARCHIVELOG;`  
D) `BACKUP FULL DATABASE COMPRESSED;`

> **Đáp án: B** – Phải thêm `AS COMPRESSED BACKUPSET` để bật nén. Channel được cấu hình qua CONFIGURE PARALLELISM.

---

**Câu 2**: RMAN đang chạy `BACKUP INCREMENTAL LEVEL 1 DATABASE`. BCT (Block Change Tracking) đang **tắt**. RMAN sẽ làm gì?

A) Báo lỗi và dừng  
B) Tự bật BCT rồi tiếp tục  
C) Quét toàn bộ tất cả data blocks để tìm block thay đổi  
D) Chỉ backup block từ archive log

> **Đáp án: C** – Khi không có BCT, RMAN phải full scan tất cả blocks để so sánh SCN. Đây là lý do Level 1 chậm bằng Level 0 khi BCT tắt.

---

**Câu 3**: BCT file nên đặt ở đâu?

A) Trong FRA (`db_recovery_file_dest`)  
B) Trong cùng thư mục với datafile  
C) Trên một đĩa riêng biệt, KHÔNG trong FRA  
D) Bất kỳ đâu cũng được

> **Đáp án: C** – BCT file trong FRA làm hỏng cơ chế space management của FRA. Đặt cùng datafile là chấp nhận được nhưng riêng đĩa là tốt nhất.

---

**Câu 4**: `CONFIGURE RETENTION POLICY TO REDUNDANCY 2` nghĩa là gì?

A) Giữ backup trong 2 ngày  
B) RMAN tạo 2 bản copy cho mỗi backup  
C) RMAN giữ 2 bản Full/Level 0 mới nhất; bản thứ 3 trở về trước = OBSOLETE  
D) Backup chạy 2 lần để đảm bảo

> **Đáp án: C** – Redundancy đếm số lượng bản Full/Level 0, không phải thời gian.

---

**Câu 5**: Sau khi chạy `CONFIGURE RETENTION POLICY TO RECOVERY WINDOW OF 7 DAYS`, lệnh nào xóa backup cũ hơn 7 ngày?

A) `DELETE BACKUP OLDER THAN 7 DAYS;`  
B) `DELETE NOPROMPT OBSOLETE;`  
C) `DELETE EXPIRED BACKUP;`  
D) `CROSSCHECK BACKUP;`

> **Đáp án: B** – `DELETE OBSOLETE` xóa backup không còn cần thiết theo retention policy. `DELETE EXPIRED` xóa record của file đã mất trên disk (khác nhau!).

---

**Câu 6**: Tag trong Incrementally Updated Backup (`INCR_UPDATE`) phải được giữ **nhất quán** qua các ngày. Điều gì xảy ra nếu ngày Thứ 4 bạn đổi tag thành `INCR_UPDATE_V2`?

A) RMAN tự nhận ra và merge vào Image Copy cũ  
B) RMAN tạo Image Copy mới từ đầu với tag mới  
C) RMAN báo lỗi  
D) Không ảnh hưởng gì

> **Đáp án: B** – Tag là key để RMAN tìm Image Copy cần merge vào. Tag khác = Image Copy khác = phải tạo Level 0 Image Copy mới từ đầu = mất toàn bộ dung lượng đĩa.

---

**Câu 7**: Thứ tự ưu tiên FORMAT trong RMAN từ cao nhất đến thấp nhất là:

A) `CONFIGURE CHANNEL` → `ALLOCATE CHANNEL` → FRA  
B) `ALLOCATE CHANNEL` trong `RUN {}` → `CONFIGURE CHANNEL N` → `CONFIGURE CHANNEL` chung → FRA  
C) FRA → `CONFIGURE CHANNEL` → `ALLOCATE CHANNEL`  
D) Tất cả đều bằng nhau, cái nào sau thì thắng

> **Đáp án: B** – ALLOCATE CHANNEL (thủ công trong RUN block) luôn thắng. Rồi mới đến CONFIGURE per-channel, rồi CONFIGURE chung, rồi FRA mặc định.

---

**Câu 8**: DBA set `CONFIGURE DEVICE TYPE DISK PARALLELISM 4` trên server chỉ có 1 HDD vật lý. Kết quả?

A) Backup nhanh gấp 4 lần  
B) Backup nhanh gấp 2 lần (lý tưởng là 4 nhưng thực tế chỉ đạt 2)  
C) Backup **chậm hơn** do I/O contention trên 1 đĩa  
D) RMAN tự detect 1 đĩa và giảm về PARALLELISM 1

> **Đáp án: C** – 4 channel tranh nhau đọc/ghi trên 1 spindle → I/O contention → throughput giảm. Parallelism chỉ có lợi khi = số physical disk thực tế.

---

**Câu 9**: Sự khác biệt giữa `DELETE OBSOLETE` và `DELETE EXPIRED BACKUP`?

A) Không khác gì, cùng xóa file cũ  
B) `DELETE OBSOLETE` = xóa logic (theo retention), `DELETE EXPIRED` = xóa record của file đã mất vật lý  
C) `DELETE OBSOLETE` = xóa file khỏi disk, `DELETE EXPIRED` = xóa record khỏi catalog  
D) `DELETE EXPIRED` cần chạy CROSSCHECK trước, `DELETE OBSOLETE` thì không

> **Đáp án: B** – OBSOLETE: file vẫn còn trên disk nhưng quá hạn retention. EXPIRED: record còn trong RMAN metadata nhưng file vật lý đã biến mất. Câu D cũng đúng một phần (nên CROSSCHECK trước khi DELETE EXPIRED).

---

**Câu 10**: `CONFIGURE ARCHIVELOG DELETION POLICY TO BACKED UP 1 TIMES TO DEVICE TYPE DISK` có tác dụng gì khi FRA đầy?

A) Tự động xóa tất cả archive log để giải phóng FRA  
B) Cho phép FRA tự xóa archive log đã được backup ít nhất 1 lần sang disk  
C) Chặn không cho xóa bất kỳ archive log nào  
D) Không có tác dụng gì với FRA

> **Đáp án: B** – FRA space management kiểm tra policy này khi cần giải phóng không gian. Archive log đã backup ≥ 1 lần → FRA được phép tự xóa. Archive log chưa backup → FRA giữ lại → nếu full thì gây ORA-19809.

---

### Phần B – Tự luận ngắn (5 câu)

**Câu 11**: Mô tả luồng hoạt động của Incrementally Updated Backup. Tại sao RTO lại ngắn hơn chiến lược Level 0 + Level 1 truyền thống?

> **Đáp án**: 
> - Ngày 1: Tạo Image Copy (Level 0 format, block-for-block copy)
> - Ngày 2: `RECOVER COPY` (merge Level 1 hôm qua vào Image Copy) + `BACKUP INCREMENTAL LEVEL 1 FOR RECOVER OF COPY` (tạo Level 1 hôm nay cho ngày mai)
> - Image Copy luôn cập nhật đến "tối qua"
> - Khi recovery: `SWITCH DATABASE TO COPY` (0 giây restore) + `RECOVER DATABASE` (chỉ apply ~1 ngày archive log)
> - Truyền thống: RESTORE (extract từ backup set = chậm) + RECOVER (nhiều archive log hơn)

**Câu 12**: Giải thích tại sao `CONFIGURE RETENTION POLICY TO NONE` là cấu hình nguy hiểm trong production.

> **Đáp án**: `TO NONE` vô hiệu hóa hoàn toàn retention policy. RMAN không đánh dấu backup nào là OBSOLETE → `DELETE OBSOLETE` không xóa được gì → FRA tích lũy không ngừng → Eventually FRA đầy → backup fail → không còn recovery capability. Đồng thời không có retention = không biết backup nào có thể xóa an toàn khi cần giải phóng disk.

**Câu 13**: Phân biệt Differential và Cumulative Incremental. Tradeoff giữa hai chiến lược?

> **Đáp án**:
> - **Differential**: Backup tất cả blocks thay đổi kể từ Level 0 **hoặc Level 1 gần nhất** → file nhỏ hơn hàng ngày, backup nhanh → recovery cần restore Level 0 + áp dụng từng Level 1 theo chuỗi (chậm)
> - **Cumulative**: Backup tất cả blocks thay đổi kể từ Level 0 gần nhất → file lớn dần theo ngày, backup chậm hơn → recovery chỉ cần Level 0 + 1 Level 1 Cumulative duy nhất (nhanh)
> - Tradeoff: Differential = tiết kiệm đĩa backup / Cumulative = RTO nhanh hơn

**Câu 14**: Tại sao cần export `ORACLE_SID`, `ORACLE_HOME`, `PATH` đầy đủ trong script cronjob backup?

> **Đáp án**: Cron daemon chạy với **shell môi trường rỗng** (minimal environment), không kế thừa session của oracle user. Nếu không export, khi cron gọi `rman target /` sẽ không tìm thấy binary RMAN (PATH thiếu), hoặc RMAN connect thành công nhưng target sai SID, hoặc kết nối fail silently. Đây là lỗi phổ biến nhất khiến "backup chạy được thủ công nhưng fail trong cron".

**Câu 15**: Mô tả cách kiểm tra backup có thực sự khả dụng để restore không (không phải chỉ xem LIST BACKUP SUMMARY).

> **Đáp án**:
> ```rman
> -- Crosscheck: RMAN kiểm tra file vật lý còn tồn tại không
> CROSSCHECK BACKUP;
> -- Nếu file biến mất → trạng thái = EXPIRED
>
> -- Validate: RMAN đọc toàn bộ backup piece, kiểm tra checksum
> BACKUP VALIDATE DATABASE;
> -- Hoặc validate 1 backup set cụ thể:
> VALIDATE BACKUPSET <recid>;
>
> -- Sau VALIDATE, kiểm tra kết quả:
> SELECT * FROM V$DATABASE_BLOCK_CORRUPTION;
> -- Bảng trống = backup khỏe mạnh
> ```

---

### Phần C – Thực hành nhanh (5 câu – chạy ngay trên lab)

**Câu 16**: Chạy `SHOW ALL` và xác định xem các settings sau đã được CONFIGURE chưa, và giá trị là gì:
- Retention Policy
- Parallelism
- Controlfile Autobackup
- Archivelog Deletion Policy

**Câu 17**: Chạy query sau và giải thích ý nghĩa mỗi cột:
```sql
SELECT INCREMENTAL_LEVEL, COUNT(*), AVG(BYTES)/1024/1024 AS AVG_MB,
       AVG((END_TIME-START_TIME)*24*60) AS AVG_MIN
FROM V$BACKUP_SET WHERE BACKUP_TYPE IN ('D','I') AND START_TIME > SYSDATE-30
GROUP BY INCREMENTAL_LEVEL;
```

**Câu 18**: Kiểm tra BCT có hoạt động hiệu quả không bằng query PCT_SCAN. Nếu PCT_SCAN ~ 100%, điều đó có nghĩa gì?

**Câu 19**: Chạy `REPORT OBSOLETE` và `REPORT NEED BACKUP`. Kết quả cho biết điều gì?

**Câu 20**: Tìm tất cả backup job FAILED trong 7 ngày qua và cho biết nguyên nhân (dựa trên V$RMAN_STATUS).

---

## Tổng kết và lộ trình tiếp theo

| Module | Kỹ năng cốt lõi | Điểm mấu chốt |
|--------|----------------|---------------|
| M04 | Full Backup, Backup Set, Image Copy | Always PLUS ARCHIVELOG; compressed by default |
| M05 | Incremental L0/L1, BCT, Merge | Tag consistency; BCT KHÔNG trong FRA |
| M06 | CONFIGURE persistent settings | 5 settings bắt buộc trong production |

**5 CONFIGURE bắt buộc trong production**:
1. `CONFIGURE RETENTION POLICY TO RECOVERY WINDOW OF 7 DAYS;`
2. `CONFIGURE CONTROLFILE AUTOBACKUP ON;`
3. `CONFIGURE DEVICE TYPE DISK PARALLELISM 2;`
4. `CONFIGURE ARCHIVELOG DELETION POLICY TO BACKED UP 1 TIMES TO DEVICE TYPE DISK;`
5. `CONFIGURE BACKUP OPTIMIZATION ON;`

**Tiếp theo**: Module 07 – Reporting & Monitoring (LIST, REPORT, V$RMAN_STATUS dashboard)


---

!!! info "Nguồn gốc"
    `dba_ai/oracle_rman/reviews_all/20260428_Review_M04M06_ProdScenarios.md`
