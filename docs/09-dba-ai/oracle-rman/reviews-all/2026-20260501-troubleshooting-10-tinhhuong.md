---
title: 🔥 10 Tình Huống Sự Cố Oracle RMAN — Hướng Dẫn Xử Lý Chi Tiết
course: 09-dba-ai
source: dba_ai/oracle_rman/reviews_all/20260501_TroubleShooting_10_TinhHuong.md
---

# 🔥 10 Tình Huống Sự Cố Oracle RMAN — Hướng Dẫn Xử Lý Chi Tiết

**Ngày tạo**: 2026-05-01  
**Lab target**: Oracle 12c · SID=ORADB · 192.168.1.8  
**Mức độ**: Production-ready — đủ chi tiết để xử lý thực tế  

---

## Mục lục

| # | Tình huống | Lỗi chính |
|---|-----------|-----------|
| 1 | [FRA Full — DB bị treo](#tình-huống-1-fra-full--database-bị-treo) | ORA-19809 / ORA-16038 |
| 2 | [Datafile offline sau storage crash](#tình-huống-2-datafile-offline-sau-storage-crash) | ORA-01157 / RMAN-06026 |
| 3 | [Không tìm được backup để recover](#tình-huống-3-không-tìm-được-backup-để-recover) | RMAN-06023 / RMAN-06025 |
| 4 | [Block corruption — media recovery](#tình-huống-4-block-corruption--block-media-recovery) | ORA-01578 / RMAN-10015 |
| 5 | [Wallet chưa mở — backup mã hóa không restore được](#tình-huống-5-wallet-chưa-mở--backup-mã-hóa-không-restore-được) | ORA-28365 / RMAN-03009 |
| 6 | [Control file bị mất sau RESETLOGS](#tình-huống-6-control-file-bị-mất-sau-resetlogs) | ORA-00205 / RMAN-06495 |
| 7 | [RMAN channel bị ngắt giữa backup dài](#tình-huống-7-rman-channel-bị-ngắt-giữa-backup-dài) | RMAN-03009 / ORA-03113 |
| 8 | [Recovery Catalog mất đồng bộ](#tình-huống-8-recovery-catalog-mất-đồng-bộ) | RMAN-06004 / RMAN-06019 |
| 9 | [PITR thất bại — SCN không hợp lệ](#tình-huống-9-pitr-thất-bại--scn-không-hợp-lệ) | ORA-01547 / ORA-01152 |
| 10 | [Database Duplication thất bại nửa chừng](#tình-huống-10-database-duplication-thất-bại-nửa-chừng) | RMAN-05537 / RMAN-03002 |

---

## Tình Huống 1: FRA Full — Database Bị Treo

### Triệu chứng

```
ORA-19809: limit exceeded for recovery files
ORA-16038: log 3 sequence# 145 cannot be archived
ORA-19804: cannot reclaim 52428800 bytes disk space
                from 10737418240 limit
```

- DB **HANG** — session user không thể commit  
- Alert log liên tục báo "archiver stuck"  
- `df -h` trên mount FRA thấy 100%  

### Nguyên nhân

Flash Recovery Area (`DB_RECOVERY_FILE_DEST`) hết dung lượng.  
Oracle không thể ghi archivelog → LGWR block → toàn DB chờ.

### Chẩn đoán

```sql
-- 1. Kiểm tra FRA usage
SELECT space_limit/1073741824 AS limit_gb,
       space_used/1073741824  AS used_gb,
       space_reclaimable/1073741824 AS reclaimable_gb,
       number_of_files
FROM V$RECOVERY_FILE_DEST;

-- 2. Xem file nào đang chiếm nhiều nhất
SELECT file_type, percent_space_used, number_of_files
FROM V$RECOVERY_AREA_USAGE
ORDER BY percent_space_used DESC;

-- 3. Xem archivelog bị stuck
SELECT sequence#, name, STATUS
FROM V$ARCHIVED_LOG
WHERE STATUS = 'A'
ORDER BY sequence# DESC
FETCH FIRST 10 ROWS ONLY;
```

### Xử lý từng bước

**Bước 1 — Tăng FRA tạm thời (không restart DB)**

```sql
-- Kết nối sysdba
ALTER SYSTEM SET db_recovery_file_dest_size = 20G SCOPE=BOTH;
```

**Bước 2 — Xóa backup obsolete trong RMAN**

```bash
rman target /
```

```rman
-- Xóa backup obsolete theo retention policy hiện tại
DELETE NOPROMPT OBSOLETE;

-- Nếu vẫn chưa đủ: xóa archivelog đã backed up
DELETE NOPROMPT ARCHIVELOG ALL BACKED UP 1 TIMES TO DISK;

-- Kiểm tra lại
REPORT NEED BACKUP;
```

**Bước 3 — Crosscheck và xóa expired**

```rman
CROSSCHECK BACKUP;
CROSSCHECK ARCHIVELOG ALL;
DELETE NOPROMPT EXPIRED BACKUP;
DELETE NOPROMPT EXPIRED ARCHIVELOG ALL;
```

**Bước 4 — Verify DB đã hoạt động trở lại**

```sql
-- Buộc log switch để test archiver
ALTER SYSTEM SWITCH LOGFILE;
ALTER SYSTEM ARCHIVE LOG ALL;

-- Kiểm tra archiver
SELECT * FROM V$ARCHIVE_DEST_STATUS WHERE TARGET = 'PRIMARY';
```

### Phòng Ngừa

```sql
-- Cấu hình alert sớm (85% warning mặc định, hạ xuống 75%)
-- Thiết lập trong monitoring job:
SELECT ROUND(space_used/space_limit*100,1) AS pct_used
FROM V$RECOVERY_FILE_DEST;
-- Alert khi > 75%

-- Tăng FRA size đủ lớn: retention_days × daily_archivelog_size × 2
ALTER SYSTEM SET db_recovery_file_dest_size = 50G SCOPE=SPFILE;
```

```rman
-- Job xóa archivelog tự động hàng ngày
DELETE NOPROMPT ARCHIVELOG UNTIL TIME 'SYSDATE-2'
  BACKED UP 1 TIMES TO DEVICE TYPE DISK;
```

---

## Tình Huống 2: Datafile Offline Sau Storage Crash

### Triệu chứng

```
ORA-01157: cannot identify/lock data file 7
            - see DBWR trace file
ORA-01110: data file 7: '/u01/oradata/ORADB/users01.dbf'
RMAN-06026: some targets not found - aborting restore
```

- DB OPEN nhưng tablespace `USERS` bị OFFLINE  
- User gặp `ORA-00376: file 7 cannot be read at this time`  

### Chẩn đoán

```sql
-- 1. Xác định datafile bị hỏng
SELECT file#, status, name, recover
FROM V$DATAFILE
WHERE status != 'ONLINE';

-- 2. Kiểm tra tablespace
SELECT tablespace_name, status
FROM DBA_TABLESPACES
WHERE status != 'ONLINE';

-- 3. Xem file vật lý còn tồn tại không
HOST ls -lh /u01/oradata/ORADB/users01.dbf
```

### Xử lý từng bước

**Bước 1 — Đưa tablespace về OFFLINE FOR RECOVER**

```sql
ALTER TABLESPACE users OFFLINE FOR RECOVER;
```

**Bước 2 — Restore và Recover trong RMAN**

```bash
rman target /
```

```rman
-- Restore datafile bị mất
RESTORE DATAFILE 7;

-- Recover để áp dụng archivelog
RECOVER DATAFILE 7;
```

**Bước 3 — Đưa tablespace ONLINE trở lại**

```sql
ALTER TABLESPACE users ONLINE;
```

**Bước 4 — Verify**

```sql
-- Kiểm tra không còn datafile OFFLINE
SELECT file#, status, checkpoint_change#, name
FROM V$DATAFILE
ORDER BY file#;

-- Test query vào tablespace
SELECT COUNT(*) FROM dba_objects WHERE tablespace_name = 'USERS';
```

### Trường hợp đặc biệt: DB phải MOUNT (system file bị mất)

```rman
-- Nếu là SYSTEM/SYSAUX datafile
STARTUP MOUNT;
RESTORE DATABASE;
RECOVER DATABASE;
ALTER DATABASE OPEN;
```

### Phòng Ngừa

```rman
-- Backup thường xuyên, tối thiểu level 0 hàng tuần
BACKUP INCREMENTAL LEVEL 0 DATABASE PLUS ARCHIVELOG;

-- Multiplexing control file sang 2 đĩa vật lý khác nhau
-- (thiết lập trong init.ora)
-- control_files = '/u01/cf/ctrl1.ctl','/u02/cf/ctrl2.ctl'
```

---

## Tình Huống 3: Không Tìm Được Backup Để Recover

### Triệu chứng

```
RMAN-06023: no backup or copy of datafile 5 found to restore
RMAN-06025: no backup of archived log for thread 1 with
            sequence 120 found to restore
RMAN-03002: failure of restore command at ...
```

### Nguyên nhân phổ biến

1. Backup bị xóa vật lý nhưng RMAN catalog chưa biết (chưa CROSSCHECK)  
2. Retention policy quá ngắn — backup bị đánh OBSOLETE và xóa  
3. Backup nằm ở location khác, channel chưa cấu hình đúng  

### Chẩn đoán

```rman
-- 1. Xem tất cả backup RMAN biết
LIST BACKUP OF DATABASE;
LIST BACKUP OF ARCHIVELOG ALL;

-- 2. Crosscheck để phát hiện file không còn tồn tại
CROSSCHECK BACKUP;
CROSSCHECK ARCHIVELOG ALL;

-- 3. Sau crosscheck: xem trạng thái
LIST EXPIRED BACKUP;

-- 4. Kiểm tra retention policy
SHOW ALL;
```

```sql
-- 5. Xem catalog (nếu dùng recovery catalog)
SELECT bs.recid, bs.status, bs.start_time, bs.completion_time,
       bp.piece#, bp.handle
FROM RC_BACKUP_SET bs
JOIN RC_BACKUP_PIECE bp ON bs.set_stamp = bp.set_stamp
WHERE bs.db_name = 'ORADB'
ORDER BY bs.start_time DESC
FETCH FIRST 20 ROWS ONLY;
```

### Xử lý: Recover từ backup cũ hơn

```rman
-- Tìm backup oldest còn available
LIST BACKUP SUMMARY;

-- Nếu phải dùng backup cũ → incomplete recovery
STARTUP MOUNT;

-- Recover đến SCN của backup cũ nhất còn có
RESTORE DATABASE UNTIL SCN 12345678;
RECOVER DATABASE UNTIL SCN 12345678;

ALTER DATABASE OPEN RESETLOGS;
```

### Xử lý: Catalog backup từ location khác

```rman
-- Nếu backup file vẫn còn ở disk, chỉ chưa được catalog
CATALOG START WITH '/backup/old_location/';

-- Hoặc catalog từng file
CATALOG BACKUPPIECE '/backup/old/oradb_full_20260420.bkp';

-- Sau đó retry restore
RESTORE DATABASE;
RECOVER DATABASE;
```

### Phòng Ngừa

```rman
-- Kiểm tra khả năng recovery hàng ngày (không restore thật)
RESTORE DATABASE PREVIEW SUMMARY;
RESTORE ARCHIVELOG ALL PREVIEW;
```

```sql
-- Tăng CONTROL_FILE_RECORD_KEEP_TIME để giữ lịch sử backup lâu hơn
ALTER SYSTEM SET control_file_record_keep_time = 30 SCOPE=SPFILE;
```

---

## Tình Huống 4: Block Corruption — Block Media Recovery

### Triệu chứng

```
ORA-01578: ORACLE data block corrupted (file # 6, block # 1284)
ORA-01110: data file 6: '/u01/oradata/ORADB/example01.dbf'
```

- Query vào table cụ thể báo lỗi  
- `DBVERIFY` hoặc RMAN `VALIDATE` phát hiện corruption  
- Alert log: `Corrupt block relative dba: 0x01800504`  

### Chẩn đoán

```bash
# 1. Chạy DBVERIFY để xác nhận phạm vi corruption
dbv file=/u01/oradata/ORADB/example01.dbf blocksize=8192
```

```sql
-- 2. Xem báo cáo corruption trong data dictionary
SELECT file#, block#, blocks, corruption_type, object_name
FROM V$DATABASE_BLOCK_CORRUPTION
ORDER BY file#, block#;

-- 3. Xem object bị ảnh hưởng
SELECT owner, segment_name, segment_type, tablespace_name
FROM DBA_EXTENTS
WHERE file_id = 6
  AND block_id <= 1284
  AND block_id + blocks - 1 >= 1284;
```

```rman
-- 4. Validate toàn bộ database
VALIDATE DATABASE;

-- Hoặc validate chỉ datafile nghi ngờ
VALIDATE DATAFILE 6;
```

### Xử lý: Block Media Recovery (BMR) — Chỉ restore block bị hỏng

```rman
-- BMR: khôi phục từng block cụ thể — DB vẫn OPEN
RECOVER DATAFILE 6 BLOCK 1284;

-- Nhiều block
RECOVER DATAFILE 6 BLOCK 1284, 1285, 1286;

-- Dùng DRA để tự phát hiện và repair
LIST FAILURE;
ADVISE FAILURE;
REPAIR FAILURE PREVIEW;
REPAIR FAILURE;
```

### Xử lý: Nếu BMR không đủ — restore toàn datafile

```rman
-- Offline tablespace
SQL "ALTER TABLESPACE example OFFLINE FOR RECOVER";

RESTORE DATAFILE 6;
RECOVER DATAFILE 6;

SQL "ALTER TABLESPACE example ONLINE";
```

### Xử lý: Corruption ở segment không critical — skip

```sql
-- Nếu segment không quan trọng, có thể MOVE/REBUILD
ALTER TABLE owner.table_name MOVE;
ALTER INDEX owner.idx_name REBUILD;
```

### Phòng Ngừa

```rman
-- Backup với validate
BACKUP VALIDATE DATABASE;

-- Schedule validate hàng tuần
VALIDATE DATABASE;

-- Bật Block Change Tracking để theo dõi block thay đổi
SQL "ALTER DATABASE ENABLE BLOCK CHANGE TRACKING
     USING FILE '/u01/bct/oradb_bct.f' REUSE";
```

---

## Tình Huống 5: Wallet Chưa Mở — Backup Mã Hóa Không Restore Được

### Triệu chứng

```
ORA-28365: wallet is not open
RMAN-03009: failure of restore command on ch01 channel
            at 05/01/2026 02:15:33
ORA-19913: unable to decrypt backup
```

- Backup encrypted (TDE/RMAN encryption) nhưng wallet bị đóng sau restart  
- Mọi lệnh RESTORE đều fail  

### Chẩn đoán

```sql
-- 1. Kiểm tra trạng thái wallet
SELECT status, wallet_type FROM V$ENCRYPTION_WALLET;
-- Expected: OPEN
-- Actual: CLOSED hoặc NOT_AVAILABLE

-- 2. Kiểm tra wallet location
SHOW PARAMETER wallet_root;
SHOW PARAMETER encryption_wallet_location;

-- 3. Kiểm tra file wallet có tồn tại không
HOST ls -la /etc/oracle/wallets/oradb/
-- Cần thấy: cwallet.sso hoặc ewallet.p12
```

### Xử lý: Mở wallet

```sql
-- Cách 1: Auto-login wallet (cwallet.sso)
-- Wallet sẽ tự mở khi DB start nếu có auto-login
-- Nếu không có, tạo auto-login:
ADMINISTER KEY MANAGEMENT CREATE AUTO_LOGIN KEYSTORE
  FROM KEYSTORE '/etc/oracle/wallets/oradb/'
  IDENTIFIED BY "WalletPassword123";

-- Cách 2: Mở wallet thủ công bằng password
ADMINISTER KEY MANAGEMENT SET KEYSTORE OPEN
  IDENTIFIED BY "WalletPassword123"
  CONTAINER = ALL;

-- Verify
SELECT status, wallet_type FROM V$ENCRYPTION_WALLET;
-- Phải thấy: OPEN, SOFTWARE_KEYSTORE
```

### Xử lý: Backup dùng password encryption (không có wallet)

```rman
-- Nếu backup dùng password mode, cung cấp password khi restore
SET DECRYPTION IDENTIFIED BY "BackupPassword123";
RESTORE DATABASE;
RECOVER DATABASE;
```

### Xử lý: Wallet bị mất (thảm họa)

```bash
# Kiểm tra backup của wallet
ls -la /backup/wallet/
# Restore wallet từ backup
cp /backup/wallet/ewallet.p12 /etc/oracle/wallets/oradb/
cp /backup/wallet/cwallet.sso /etc/oracle/wallets/oradb/

# Phân quyền đúng
chown oracle:oinstall /etc/oracle/wallets/oradb/*.p12
chown oracle:oinstall /etc/oracle/wallets/oradb/*.sso
chmod 600 /etc/oracle/wallets/oradb/*.p12
```

### Phòng Ngừa

```bash
# Luôn backup wallet cùng với backup database
mkdir -p /backup/wallet/$(date +%Y%m%d)
cp /etc/oracle/wallets/oradb/* /backup/wallet/$(date +%Y%m%d)/

# Script kiểm tra wallet mở trước khi chạy RMAN
sqlplus -S / as sysdba <<'EOF'
WHENEVER SQLERROR EXIT 1
SELECT CASE WHEN status = 'OPEN' THEN 'OK'
            ELSE NULL END AS chk  -- Sẽ lỗi nếu CLOSED
FROM V$ENCRYPTION_WALLET
WHERE status = 'OPEN';
EXIT;
EOF
```

```sql
-- Cấu hình auto-login keystore để tự mở sau restart
-- (Thực hiện 1 lần)
ADMINISTER KEY MANAGEMENT CREATE AUTO_LOGIN KEYSTORE
  FROM KEYSTORE '/etc/oracle/wallets/oradb/'
  IDENTIFIED BY "WalletPassword123";
```

---

## Tình Huống 6: Control File Bị Mất Sau RESETLOGS

### Triệu chứng

```
ORA-00205: error in identifying control file, check alert log
ORA-27037: unable to obtain file status
```

- Database không MOUNT được sau khi đã OPEN RESETLOGS  
- Multiplexed control file đều mất (storage failure)  
- RMAN autobackup control file đã thực hiện trước RESETLOGS  

### Chẩn đoán

```bash
# 1. Xem alert log
tail -100 $ORACLE_BASE/diag/rdbms/oradb/oradb/trace/alert_oradb.log

# 2. Kiểm tra file vật lý
ls -la /u01/oradata/ORADB/*.ctl
ls -la /u02/oradata/ORADB/*.ctl
```

```sql
-- 3. Xem SPFILE biết control file nào
SHOW PARAMETER control_files;
```

### Xử lý: Restore Control File từ Autobackup

```bash
rman target /
```

```rman
-- Nếu biết DBID
SET DBID 1234567890;

-- Restore control file từ autobackup
STARTUP NOMOUNT;

RESTORE CONTROLFILE FROM AUTOBACKUP;
-- Hoặc restore từ file cụ thể:
RESTORE CONTROLFILE FROM '/backup/rman/c-1234567890-20260501-00.ctl';

-- Mount với control file vừa restore
ALTER DATABASE MOUNT;

-- Catalog lại tất cả backup pieces
CATALOG START WITH '/backup/rman/';

-- Recover database (bắt buộc dùng RESETLOGS)
RECOVER DATABASE USING BACKUP CONTROLFILE UNTIL CANCEL;
-- Khi hỏi: nhập tên archivelog cuối cùng, rồi CANCEL

ALTER DATABASE OPEN RESETLOGS;
```

### Xử lý: Sau OPEN RESETLOGS — Resync catalog

```rman
-- Kết nối với recovery catalog
-- rman TARGET sys/oracle@oradb CATALOG rcowner/oracle@catdb

RESYNC CATALOG;
```

### Vấn đề đặc biệt: SCN không khớp sau RESETLOGS

```rman
-- Nếu backup có sau RESETLOGS nhưng control file từ trước
RECOVER DATABASE USING BACKUP CONTROLFILE;
-- Cung cấp archivelog từ sau RESETLOGS

-- Verify incarnation
LIST INCARNATION;
RESET DATABASE TO INCARNATION 2; -- chọn incarnation đúng
```

### Phòng Ngừa

```rman
-- Autobackup control file sau mỗi backup
CONFIGURE CONTROLFILE AUTOBACKUP ON;
CONFIGURE CONTROLFILE AUTOBACKUP FORMAT
  FOR DEVICE TYPE DISK TO '/backup/cf/cf_%F';

-- Backup control file thủ công trước và sau RESETLOGS
BACKUP CURRENT CONTROLFILE FORMAT '/backup/cf/cf_pre_resetlogs_%T_%s.bkp';
```

---

## Tình Huống 7: RMAN Channel Bị Ngắt Giữa Backup Dài

### Triệu chứng

```
RMAN-03009: failure of backup command on ch01 channel
            at 05/01/2026 03:45:12
ORA-03113: end-of-file on communication channel
RMAN-08132: WARNING: cannot update recovery catalog
```

- Backup 8TB bị ngắt sau 5 tiếng  
- SSH timeout hoặc network drop  
- RMAN job trong cron bị kill bởi OOM killer  

### Chẩn đoán

```sql
-- 1. Xem job RMAN nào đang/vừa chạy
SELECT sid, serial#, opname, target_desc,
       sofar, totalwork,
       ROUND(sofar/totalwork*100,1) AS pct_done,
       time_remaining
FROM V$SESSION_LONGOPS
WHERE opname LIKE '%RMAN%'
  AND totalwork > 0
ORDER BY start_time DESC;

-- 2. Xem backup set nào incomplete
SELECT set_count, set_stamp, status, start_time, completion_time
FROM V$BACKUP_SET
WHERE status = 'A' -- Active (chưa complete)
ORDER BY start_time DESC;

-- 3. Xem process RMAN
SELECT spid, program, status
FROM V$PROCESS
WHERE program LIKE '%rman%';
```

```rman
-- 4. Crosscheck để phát hiện backup pieces orphan
CROSSCHECK BACKUP;
LIST EXPIRED BACKUP;
```

### Xử lý: Tiếp tục backup từ nơi còn thiếu

```rman
-- Xóa backup incomplete
DELETE NOPROMPT EXPIRED BACKUP;

-- Backup chỉ những datafile chưa được backup từ hôm qua
BACKUP DATABASE NOT BACKED UP SINCE TIME 'SYSDATE-1';

-- Hoặc backup những datafile cụ thể bị miss
BACKUP DATAFILE 5, 6, 7;
```

### Xử lý: Tránh timeout — Dùng DURATION

```rman
-- Backup với giới hạn thời gian (tự stop gracefully trước 6h)
BACKUP DURATION 5:30 PARTIAL MINIMIZE LOAD
  INCREMENTAL LEVEL 0 DATABASE;
-- PARTIAL = cho phép incomplete nếu hết giờ
-- MINIMIZE LOAD = ưu tiên tránh ảnh hưởng production
```

### Xử lý: Tách backup thành nhiều phần

```bash
#!/bin/bash
# backup_by_tablespace.sh
TABLESPACES=("SYSTEM" "SYSAUX" "USERS" "EXAMPLE" "UNDOTBS1")

for ts in "${TABLESPACES[@]}"; do
    rman target / <<RMAN_EOF
    BACKUP TABLESPACE ${ts} FORMAT '/backup/rman/${ts}_%T_%s_%p.bkp';
RMAN_EOF
    echo "Done: ${ts}"
done
```

### Phòng Ngừa

```bash
# Chạy RMAN trong nohup để tránh SSH timeout
nohup rman target / @/home/oracle/scripts/full_backup.rman \
  > /home/oracle/logs/rman_$(date +%Y%m%d).log 2>&1 &

# Hoặc dùng screen/tmux
screen -dmS rman_backup rman target / @full_backup.rman
```

```rman
-- Tăng timeout cho channel
CONFIGURE CHANNEL DEVICE TYPE DISK
  CONNECT 'SYS/oracle@oradb'
  RATE = 200M;  -- Rate limiting tránh I/O spike

-- Parallel channels để backup nhanh hơn
CONFIGURE DEVICE TYPE DISK PARALLELISM 4;
```

---

## Tình Huống 8: Recovery Catalog Mất Đồng Bộ

### Triệu chứng

```
RMAN-06004: ORACLE error from recovery catalog database:
            ORA-01403: no data found
RMAN-06019: could not translate tablespace name
RMAN-04006: error from recovery catalog database:
            ORA-20001: DBMS_RCVCAT: db incarnation
            not found in the catalog
```

- Catalog DB (catdb) và target DB (oradb) mất đồng bộ  
- Thường xảy ra sau: RESETLOGS, restore control file, hoặc catalog DB recover  

### Chẩn đoán

```sql
-- Trên catalog DB (catdb):
SELECT db_name, db_key, dbid, current_incarnation
FROM RC_DATABASE
WHERE db_name = 'ORADB';

-- Xem incarnation history
SELECT dbinc_key, db_key, resetlogs_change#, resetlogs_time,
       prior_incarnation_key
FROM RC_DATABASE_INCARNATION
WHERE db_name = 'ORADB'
ORDER BY resetlogs_change#;
```

```rman
-- Kết nối cả target + catalog
-- rman TARGET sys/oracle@oradb CATALOG rcowner/oracle@catdb

-- Xem incarnation từ control file
LIST INCARNATION;

-- So sánh với catalog
SELECT * FROM RC_DATABASE_INCARNATION WHERE DB_NAME='ORADB';
```

### Xử lý: Resync catalog

```rman
-- Kết nối với catalog
-- rman TARGET sys/oracle@oradb CATALOG rcowner/oracle@catdb

-- Resync toàn bộ
RESYNC CATALOG;

-- Nếu có backup pieces chưa được catalog
CATALOG START WITH '/backup/rman/';

-- Nếu có archivelogs chưa catalog
CATALOG ARCHIVELOG ALL;
```

### Xử lý: Reset incarnation

```rman
-- Liệt kê incarnation
LIST INCARNATION;

-- INCARNATION# 1: RESETLOGS SCN=1, KEY=1
-- INCARNATION# 2: RESETLOGS SCN=12345, KEY=2  <-- current

-- Reset về incarnation đúng
RESET DATABASE TO INCARNATION 2;

-- Resync lại
RESYNC CATALOG;
```

### Xử lý: Unregister và register lại

```rman
-- Nếu catalog hoàn toàn confused, unregister và register lại
-- (CẢNH BÁO: mất lịch sử backup trong catalog!)
UNREGISTER DATABASE NOPROMPT;
REGISTER DATABASE;
RESYNC CATALOG;
```

### Phòng Ngừa

```rman
-- Resync catalog sau mỗi backup quan trọng
BACKUP DATABASE PLUS ARCHIVELOG;
RESYNC CATALOG;

-- Resync sau mỗi OPEN RESETLOGS
-- (đặt lệnh này trong script recovery standard)
```

```sql
-- Monitor catalog sync lag
SELECT db_name, last_time AS last_sync
FROM RC_DATABASE
WHERE db_name = 'ORADB';
```

---

## Tình Huống 9: PITR Thất Bại — SCN Không Hợp Lệ

### Triệu chứng

```
ORA-01547: warning: RECOVER succeeded but OPEN RESETLOGS
            would get error below
ORA-01152: file 1 was not restored from a sufficiently
            old backup
ORA-01110: data file 1: '/u01/oradata/ORADB/system01.dbf'
```

- Muốn PITR về 2 tiếng trước  
- Backup available nhưng từ sau thời điểm muốn recover  
- Không có backup đủ cũ cho SCN target  

### Chẩn đoán

```rman
-- 1. Preview để biết backup nào sẽ được dùng
RESTORE DATABASE UNTIL TIME "TO_DATE('2026-05-01 01:00:00','YYYY-MM-DD HH24:MI:SS')" PREVIEW SUMMARY;

-- 2. Xem backup available timeline
LIST BACKUP OF DATABASE SUMMARY;

-- 3. Xác định SCN tại thời điểm muốn recover
SELECT timestamp_to_scn(
         TO_TIMESTAMP('2026-05-01 01:00:00','YYYY-MM-DD HH24:MI:SS')
       ) AS target_scn
FROM DUAL;
```

```sql
-- 4. Xem RMAN backup set theo thời gian
SELECT set_stamp, start_time, completion_time, backup_type
FROM V$BACKUP_SET
WHERE start_time < TO_DATE('2026-05-01 01:00:00','YYYY-MM-DD HH24:MI:SS')
ORDER BY start_time DESC
FETCH FIRST 5 ROWS ONLY;
```

### Xử lý: Tìm đúng thời điểm có backup

```rman
-- Tìm thời điểm PITR khả thi gần nhất
RESTORE DATABASE UNTIL TIME "TO_DATE('2026-05-01 02:00:00','YYYY-MM-DD HH24:MI:SS')" PREVIEW;
-- Nếu fail, thử: 03:00, 04:00... cho đến khi tìm được
```

### Xử lý: PITR đúng cách

```rman
STARTUP MOUNT;

-- PITR đến thời điểm cụ thể
RESTORE DATABASE
  UNTIL TIME "TO_DATE('2026-05-01 01:00:00','YYYY-MM-DD HH24:MI:SS')";

RECOVER DATABASE
  UNTIL TIME "TO_DATE('2026-05-01 01:00:00','YYYY-MM-DD HH24:MI:SS')";

ALTER DATABASE OPEN RESETLOGS;
```

### Xử lý: Table-Level Recovery (Oracle 12c+) — không cần RESETLOGS

```rman
-- Recover table cụ thể về thời điểm quá khứ — DB vẫn OPEN
RECOVER TABLE scott.emp
  UNTIL TIME "TO_DATE('2026-05-01 01:00:00','YYYY-MM-DD HH24:MI:SS')"
  AUXILIARY DESTINATION '/tmp/aux_recover'
  DATAPUMP DESTINATION '/tmp/dp_recover'
  DUMP FILE 'emp_recover.dmp'
  NOTABLEIMPORT;
-- Sau đó import thủ công bằng impdp
```

### Xử lý: TSPITR — Tablespace Point-in-Time Recovery

```rman
-- Recover 1 tablespace về thời điểm cũ, DB vẫn phục vụ tablespace khác
RECOVER TABLESPACE users
  UNTIL TIME "TO_DATE('2026-05-01 01:00:00','YYYY-MM-DD HH24:MI:SS')"
  AUXILIARY DESTINATION '/tmp/tspitr_aux';
```

### Phòng Ngừa

```rman
-- Backup level 0 thường xuyên (tối thiểu mỗi tuần)
-- Giữ archive log đủ lâu để PITR

-- Kiểm tra PITR window hàng ngày
RESTORE DATABASE UNTIL TIME 'SYSDATE-1' PREVIEW SUMMARY;
-- Nếu báo không đủ backup → alert ngay
```

---

## Tình Huống 10: Database Duplication Thất Bại Nửa Chừng

### Triệu chứng

```
RMAN-05537: DUPLICATE without TARGET connection
            when auxiliary instance is started with
            server parameter file cannot use
            SPFILE clause
RMAN-03002: failure of Duplicate Db command at ...
RMAN-05501: aborting duplication of target database
```

- Đang duplicate database sang server mới  
- Fail sau 2 tiếng khi đã restore 60% datafiles  
- Auxiliary DB trở thành trạng thái MOUNT không sạch  

### Chẩn đoán

```bash
# 1. Kiểm tra trạng thái auxiliary instance
sqlplus sys/oracle@dupdb as sysdba <<EOF
SELECT status FROM V\$INSTANCE;
EOF

# 2. Kiểm tra datafile nào đã được restore
sqlplus sys/oracle@dupdb as sysdba <<EOF
SELECT file#, status, name FROM V\$DATAFILE;
EOF

# 3. Xem alert log của auxiliary
tail -200 $ORACLE_BASE/diag/rdbms/dupdb/dupdb/trace/alert_dupdb.log
```

### Xử lý: Reset và bắt đầu lại

```bash
# Shutdown auxiliary để cleanup
sqlplus sys/oracle@dupdb as sysdba <<EOF
SHUTDOWN ABORT;
EOF

# Xóa datafiles đã được restore (incomplete)
rm -f /u01/oradata/DUPDB/*.dbf
rm -f /u01/oradata/DUPDB/*.log
rm -f /u02/oradata/DUPDB/*.ctl

# Startup NOMOUNT lại với init.ora đơn giản (không SPFILE)
sqlplus sys/oracle@dupdb as sysdba <<EOF
STARTUP NOMOUNT PFILE='/home/oracle/init_dupdb.ora';
EOF
```

### Nội dung `init_dupdb.ora` tối thiểu

```ini
db_name=DUPDB
sga_target=1G
pga_aggregate_target=512M
```

### Xử lý: Retry duplication

```bash
# Active duplication (target DB đang OPEN)
rman TARGET sys/oracle@oradb AUXILIARY sys/oracle@dupdb
```

```rman
DUPLICATE TARGET DATABASE TO dupdb
  FROM ACTIVE DATABASE
  SPFILE
    PARAMETER_VALUE_CONVERT 'oradb','dupdb',
                            '/u01/oradata/ORADB','/u01/oradata/DUPDB'
    SET db_unique_name = 'DUPDB'
    SET log_archive_dest_1 = 'LOCATION=/u01/arch/DUPDB/'
    SET control_files = '/u01/oradata/DUPDB/ctrl1.ctl',
                        '/u02/oradata/DUPDB/ctrl2.ctl'
  LOGFILE
    GROUP 1 '/u01/oradata/DUPDB/redo01.log' SIZE 50M,
    GROUP 2 '/u01/oradata/DUPDB/redo02.log' SIZE 50M
  NOFILENAMECHECK;
```

### Xử lý: Backup-based duplication (network yếu)

```rman
-- Nếu mạng yếu: copy backup sang auxiliary server trước, rồi duplicate
DUPLICATE TARGET DATABASE TO dupdb
  BACKUP LOCATION '/backup/rman/'
  SPFILE SET db_unique_name = 'DUPDB'
  LOGFILE GROUP 1 '/u01/oradata/DUPDB/redo01.log' SIZE 50M
  NOFILENAMECHECK;
```

### Xử lý: Lỗi RMAN-05537 (SPFILE conflict)

```rman
-- Lỗi này xảy ra khi auxiliary đã có SPFILE trong data dictionary
-- Fix: không dùng SPFILE clause khi auxiliary đã start với SPFILE
DUPLICATE TARGET DATABASE TO dupdb
  -- BỎ clause SPFILE
  PARAMETER_VALUE_CONVERT 'oradb','dupdb'
  LOGFILE ...
  NOFILENAMECHECK;
```

### Phòng Ngừa

```bash
# Checklist trước khi duplicate
echo "=== Pre-Duplicate Checklist ==="
echo "1. Auxiliary listener running?"
lsnrctl status | grep DUPDB

echo "2. Auxiliary startup NOMOUNT OK?"
sqlplus sys/oracle@dupdb as sysdba <<EOF
SELECT status FROM V\$INSTANCE;
EOF

echo "3. Disk space đủ cho duplicate?"
df -h /u01/oradata/DUPDB/

echo "4. Network từ target đến auxiliary OK?"
tnsping dupdb
```

---

## Tổng Kết — Bảng Tham Chiếu Nhanh

| # | Lỗi | Nguyên nhân | Lệnh xử lý đầu tiên |
|---|-----|------------|---------------------|
| 1 | ORA-19809 FRA Full | FRA hết dung lượng | `DELETE NOPROMPT OBSOLETE;` |
| 2 | ORA-01157 Datafile offline | Storage crash | `ALTER TABLESPACE x OFFLINE FOR RECOVER;` |
| 3 | RMAN-06023 Không tìm backup | Backup bị xóa/moved | `CROSSCHECK BACKUP; CATALOG START WITH...` |
| 4 | ORA-01578 Block corrupt | Media failure | `RECOVER DATAFILE n BLOCK m;` |
| 5 | ORA-28365 Wallet closed | Wallet chưa mở sau restart | `ADMINISTER KEY MANAGEMENT SET KEYSTORE OPEN...` |
| 6 | ORA-00205 Control file mất | Storage crash | `RESTORE CONTROLFILE FROM AUTOBACKUP;` |
| 7 | RMAN-03009 Channel ngắt | Timeout/network | `BACKUP DATABASE NOT BACKED UP SINCE TIME...` |
| 8 | RMAN-06004 Catalog async | RESETLOGS không resync | `RESYNC CATALOG;` |
| 9 | ORA-01547 PITR fail | Backup không đủ cũ | `RESTORE DATABASE UNTIL TIME... PREVIEW;` |
| 10 | RMAN-05537 Duplicate fail | SPFILE conflict | Cleanup aux + retry `DUPLICATE... NOFILENAMECHECK;` |

---

## Sơ Đồ Quyết Định Khi Gặp Sự Cố RMAN

```
DB không OPEN?
├── ORA-00205 → Control file mất → [TH6]
├── ORA-01157 → Datafile mất → [TH2]
└── ORA-16038/19809 → FRA full → [TH1]

DB OPEN nhưng lỗi query?
├── ORA-01578 → Block corrupt → [TH4]
└── ORA-00376 → Datafile offline → [TH2]

RMAN RESTORE fail?
├── RMAN-06023 → Không tìm backup → [TH3]
├── ORA-28365 → Wallet closed → [TH5]
├── ORA-01547 → PITR SCN invalid → [TH9]
└── RMAN-05537 → Duplicate conflict → [TH10]

RMAN Backup fail?
├── ORA-19809 → FRA full → [TH1]
├── RMAN-03009 → Channel drop → [TH7]
└── RMAN-06004 → Catalog async → [TH8]
```


---

!!! info "Nguồn gốc"
    `dba_ai/oracle_rman/reviews_all/20260501_TroubleShooting_10_TinhHuong.md`
