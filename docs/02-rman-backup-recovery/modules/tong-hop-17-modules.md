---
title: 📊 Tổng hợp 17 Modules — Oracle RMAN Backup & Recovery
course: 02-rman-backup-recovery
source: Oracle-Database-Backup-and-Recovery-using-RMAN/modules/tong_hop_17_modules.md
---

# 📊 Tổng hợp 17 Modules — Oracle RMAN Backup & Recovery

> **Khóa học**: Oracle Database 12c Backup and Recovery using RMAN (Ahmed Baraka – Packt Publishing)
> **Trạng thái**: ✅ Hoàn thành 17/17 modules
> **Cập nhật**: 2026-04-23

---

## 🗺️ Lộ trình tổng thể

```
[Nền tảng] → [Backup] → [Advanced Backup] → [Recovery] → [Advanced Topics]
  M01–M03     M04–M06      M07–M11            M12–M13       M14–M17
```

---

## 📦 NHÓM 1: Nền tảng (Modules 01–03)

### Module 01 — Giới thiệu & Lab Setup (Bài 01–05)
- **Môi trường**: 2 VM qua VirtualBox
  - `srv1` (Oracle Linux): ORADB — máy Production chính
  - `winsrv2` (Windows Server): ORAWIN — máy Catalog/Test
- **Tools**: PuTTY, Shared Folder, Swingbench (sinh data SOE)
- **Lưu ý**: Snapshot VM sau khi cài xong để rollback khi luyện tập

### Module 02 — Nền tảng Backup & Recovery (Bài 06–07)
- **12 loại failure**: User process, Network, Instance, **Media** (cần RMAN), Physical/Logical Corruption, User Error...
- **RPO** = Mất tối đa bao nhiêu data? | **RTO** = Mất bao lâu để recover?
- **FRA (Fast Recovery Area)**: Warning ở 85%, Critical ở 97% → DB có thể HANG
- **ARCHIVELOG mode**: BẮT BUỘC cho production OLTP và hot backup
- **Multiplexing**: Control file ≥ 2 bản, Redo log ≥ 3 groups × 2 members

```sql
-- Bật ARCHIVELOG
SHUTDOWN IMMEDIATE;
STARTUP MOUNT;
ALTER DATABASE ARCHIVELOG;
ALTER DATABASE OPEN;

-- Cấu hình FRA
ALTER SYSTEM SET DB_RECOVERY_FILE_DEST = '/u02/fra' SCOPE=BOTH;
ALTER SYSTEM SET DB_RECOVERY_FILE_DEST_SIZE = 50G SCOPE=BOTH;
```

### Module 03 — Làm quen RMAN (Bài 08–09)
- **Kết nối RMAN**: `rman target /` (local), `rman target sys@oradb` (remote)
- **SYSBACKUP**: Quyền backup only, không đọc được data user
- **Stand-alone** vs **Job Command** (RUN {}): dùng RUN khi cần ALLOCATE CHANNEL
- **Persistent Settings**: `SHOW ALL` | `CONFIGURE ...` | `CONFIGURE ... CLEAR`
- **CONTROL_FILE_RECORD_KEEP_TIME**: mặc định 7 ngày → tăng lên ≥ 30

```sql
RMAN> SHOW ALL;
RMAN> CONFIGURE CONTROLFILE AUTOBACKUP ON;
ALTER SYSTEM SET CONTROL_FILE_RECORD_KEEP_TIME=60 SCOPE=BOTH;
```

---

## 📦 NHÓM 2: Backup Techniques (Modules 04–06)

### Module 04 — RMAN Full Backups (Bài 10–13)

| Loại | Đặc điểm |
|------|---------|
| **Backup Set** | Định dạng RMAN riêng, nén được, backup được ra tape |
| **Image Copy** | Bản sao 1:1 của datafile, chỉ ra disk, SWITCH ngay lập tức |
| **Whole** | Toàn bộ database |
| **Partial** | Chỉ tablespace/datafile cụ thể |
| **Hot (Online)** | DB đang OPEN, cần ARCHIVELOG mode |
| **Cold (Offline)** | DB ở MOUNT, dùng cho NOARCHIVELOG |

```sql
RMAN> BACKUP DATABASE PLUS ARCHIVELOG;          -- Standard Production
RMAN> BACKUP NOT BACKED UP SINCE TIME 'SYSDATE-1' DATABASE;  -- Resume bị đứt
RMAN> BACKUP TABLESPACE users TAG 'MONTHLY';    -- Partial + Tag
RMAN> CONFIGURE CONTROLFILE AUTOBACKUP ON;      -- Autobackup Control File
```

### Module 05 — Incremental Backups (Bài 14–16)

```
Level 0 (Full base) → Level 1 Differential → Level 1 Differential → ...
Level 0 (Full base) → Level 1 Cumulative   → Level 1 Cumulative   → ...
```

| Tiêu chí | Differential | Cumulative |
|----------|-------------|------------|
| Backup từ | Level 0 hoặc Level 1 gần nhất | Level 0 gần nhất |
| Dung lượng | Ít nhất | Nhiều hơn |
| RTO khi recover | Chậm hơn (nhiều pieces) | Nhanh hơn (ít pieces) |

```sql
RMAN> BACKUP INCREMENTAL LEVEL 0 DATABASE;
RMAN> BACKUP INCREMENTAL LEVEL 1 DATABASE;
RMAN> BACKUP INCREMENTAL LEVEL 1 CUMULATIVE DATABASE;

-- Block Change Tracking (tăng tốc incremental đáng kể)
ALTER DATABASE ENABLE BLOCK CHANGE TRACKING;

-- Incrementally Updated Image Copy (RTO siêu nhanh)
RUN {
  RECOVER COPY OF DATABASE WITH TAG 'incr_update';
  BACKUP INCREMENTAL LEVEL 1 FOR RECOVER OF COPY WITH TAG 'incr_update' DATABASE;
}
```

### Module 06 — Persistent Settings (Bài 17–18)

```sql
-- Retention Policy (chỉ chọn 1 trong 2)
RMAN> CONFIGURE RETENTION POLICY TO RECOVERY WINDOW OF 7 DAYS;
RMAN> CONFIGURE RETENTION POLICY TO REDUNDANCY 3;

-- Format, Parallelism, Deletion Policy
RMAN> CONFIGURE CHANNEL DEVICE TYPE DISK FORMAT '/u02/bkp/%U.bkp';
RMAN> CONFIGURE DEVICE TYPE DISK PARALLELISM 2;
RMAN> CONFIGURE ARCHIVELOG DELETION POLICY BACKED UP 1 TIMES TO DEVICE TYPE DISK;

-- Dọn rác
RMAN> REPORT OBSOLETE;
RMAN> DELETE OBSOLETE;
```

---

## 📦 NHÓM 3: Advanced Backup (Modules 07–11)

### Module 07 — Reporting & Monitoring (Bài 19–23)

| Lệnh | Mục đích |
|------|---------|
| `LIST BACKUP SUMMARY` | Xem kho backup |
| `REPORT NEED BACKUP` | File nào thiếu backup |
| `REPORT OBSOLETE` | File nào hết hạn |
| `REPORT UNRECOVERABLE` | File nào có NOLOGGING nguy hiểm |
| `CROSSCHECK BACKUP` | Kiểm tra file vật lý còn tồn tại không |
| `DELETE EXPIRED BACKUP` | Xóa record file đã mất vật lý |

> **EXPIRED** = File vật lý không tồn tại (chạy CROSSCHECK để phát hiện)
> **OBSOLETE** = File quá hạn retention (chạy DELETE OBSOLETE)

```sql
-- Giám sát tiến độ realtime
SELECT SID, SOFAR, TOTALWORK, ROUND(SOFAR/TOTALWORK*100,2) "%_COMPLETE"
FROM V$SESSION_LONGOPS WHERE OPNAME LIKE 'RMAN%' AND TOTALWORK != 0;
```

### Module 08 — Improving Backups (Bài 24–27)

```sql
-- Nén (BASIC miễn phí, LOW/MEDIUM/HIGH cần Advanced Compression license)
RMAN> CONFIGURE COMPRESSION ALGORITHM 'MEDIUM';
RMAN> BACKUP AS COMPRESSED BACKUPSET DATABASE PLUS ARCHIVELOG;

-- Multisection (cắt datafile lớn ra nhiều pieces để chạy song song)
RMAN> BACKUP SECTION SIZE 500M DATAFILE '/oradata/orcl/users.dbf';

-- Duplex (nhân đôi backup ra 2 vị trí)
RMAN> BACKUP COPIES 2 DATABASE FORMAT '/disk1/%U', '/disk2/%U';

-- Archival Backup (giữ vĩnh viễn, không bị OBSOLETE)
RMAN> BACKUP DATABASE TAG 'YEAREND_2026' KEEP FOREVER RESTORE POINT RP_YEAREND;
```

### Module 09 — Recovery Catalog (Bài 28–30)

| | Control File | Recovery Catalog |
|--|---|---|
| Thời gian lưu | Giới hạn (CONTROL_FILE_RECORD_KEEP_TIME) | Vô hạn |
| Stored Scripts | ❌ | ✅ |
| Nhiều DB | ❌ | ✅ |

```sql
-- Tạo Catalog (trên DB riêng biệt)
CREATE USER rcowner IDENTIFIED BY oracle;
GRANT RECOVERY_CATALOG_OWNER TO rcowner;
RMAN> CREATE CATALOG;

-- Đăng ký Target DB vào Catalog
rman TARGET / CATALOG rcowner/oracle@catdb
RMAN> REGISTER DATABASE;
RMAN> RESYNC CATALOG;

-- Catalog file ngoài hệ thống
RMAN> CATALOG START WITH '/media/backup_dir/';

-- Stored Script
RMAN> CREATE GLOBAL SCRIPT full_bkp { BACKUP DATABASE PLUS ARCHIVELOG; DELETE OBSOLETE; }
RMAN> RUN { EXECUTE GLOBAL SCRIPT full_bkp; }
```

### Module 10 — Encrypted Backups (Bài 31–32)

| Mode | Lấy Key từ | Dùng khi |
|------|-----------|---------|
| **Transparent** | TDE Keystore tự động | Backup hàng ngày, on-site |
| **Password** (ONLY) | Password nhập tay | Backup gửi off-site |
| **Dual** | Keystore HOẶC Password | Cần cả 2 phương án |

```sql
-- Chuẩn bị Keystore
ADMINISTER KEY MANAGEMENT CREATE KEYSTORE '/path/keystore' IDENTIFIED BY oracle;
ADMINISTER KEY MANAGEMENT SET KEYSTORE OPEN IDENTIFIED BY oracle;
ADMINISTER KEY MANAGEMENT SET KEY IDENTIFIED BY oracle WITH BACKUP;

-- Backup với mã hóa
RMAN> SET ENCRYPTION ON;                                    -- Transparent
RMAN> SET ENCRYPTION ON IDENTIFIED BY MyPass ONLY;         -- Password
RMAN> SET ENCRYPTION ON IDENTIFIED BY MyPass;              -- Dual Mode

-- ⚠️ Chỉ áp dụng cho Backup Sets, không dùng được với Image Copies
```

### Module 11 — Common Backup Practices (Bài 33–34)

**Kiến trúc D2D2T (Disk → Disk → Tape)**:
- **Disk (FRA)**: Short term, 7-30 ngày, quick RTO
- **Tape**: Long term, off-site, compliance

**Kịch bản thiết kế theo yêu cầu**:
| Yêu cầu | Giải pháp |
|---------|-----------|
| RTO < 10 phút | **Image Copy** + SWITCH |
| RTO 2-5 giờ | **Backupset** + RESTORE |
| RPO = 0 | Data Guard SYNC |
| Compliance 5 năm | KEEP FOREVER + Catalog |

---

## 📦 NHÓM 4: Recovery (Modules 12–13)

### Module 12 — Performing Recovery (Bài 35–48)

**Tư duy cốt lõi**:
- `RESTORE` = Lấy file backup ra (xác chưa có hồn)
- `RECOVER` = Apply archive logs (đưa hồn về)
- **Complete Recovery** = Recover đến hiện tại, KHÔNG mất data
- **Incomplete Recovery (PITR)** = Recover đến quá khứ, CÓ mất data, phải `RESETLOGS`

```sql
-- Complete Recovery
STARTUP MOUNT;
RESTORE DATABASE;
RECOVER DATABASE;
ALTER DATABASE OPEN;

-- PITR
RUN {
  SET UNTIL TIME "TO_DATE('2026-10-01 09:00:00','YYYY-MM-DD HH24:MI:SS')";
  RESTORE DATABASE;
  RECOVER DATABASE;
}
ALTER DATABASE OPEN RESETLOGS;

-- Switch datafile sang Image Copy (RTO siêu nhanh)
ALTER DATABASE DATAFILE 4 OFFLINE;
SWITCH DATAFILE 4 TO COPY;
RECOVER DATAFILE 4;
ALTER DATABASE DATAFILE 4 ONLINE;

-- TSPITR (khôi phục 1 tablespace về quá khứ)
RECOVER TABLESPACE hr_data UNTIL TIME 'SYSDATE-1'
AUXILIARY DESTINATION '/disk1/auxdest';

-- Table Recovery (chỉ lấy lại 1 table)
RECOVER TABLE HR.EMP UNTIL TIME 'SYSDATE-1'
AUXILIARY DESTINATION '/tmp/auxdest'
REMAP TABLE HR.EMP:TEST.RECOVERED_EMP;

-- Mất Control File
SET DBID 12345;
STARTUP NOMOUNT;
RESTORE CONTROLFILE FROM AUTOBACKUP;

-- Redo Log bị mất
ALTER DATABASE CLEAR LOGFILE GROUP 2;               -- Inactive group
ALTER DATABASE CLEAR UNARCHIVED LOGFILE GROUP 2;    -- Active group
```

### Module 13 — Data Recovery Advisor & Block Corruption (Bài 49–52)

```
DBA gọi DRA: LIST FAILURE → ADVISE FAILURE → REPAIR FAILURE → CHANGE FAILURE CLOSED
```

```sql
-- Block Media Recovery
RMAN> RECOVER CORRUPTION LIST;
RMAN> RECOVER DATAFILE 6 BLOCK 14;

-- Quét tìm block hỏng
RMAN> VALIDATE DATABASE;
RMAN> VALIDATE CHECK LOGICAL DATABASE;

-- Lỗi thường gặp
ORA-01578: ORACLE data block corrupted (file# n, block# s)
```

> ⚠️ DRA không hỗ trợ môi trường RAC

---

## 📦 NHÓM 5: Advanced Topics (Modules 14–17)

### Module 14 — Cross-Platform Data Transportation (Bài 53–60)

- **Endian Format**: Linux/Windows = Little Endian | AIX/Solaris = Big Endian
- Khác endian → phải **CONVERT** | Cùng endian → transport toàn bộ DB

```sql
-- Kiểm tra endian
SELECT PLATFORM_NAME, ENDIAN_FORMAT FROM V$TRANSPORTABLE_PLATFORM;

-- Convert tại Source
RMAN> CONVERT TABLESPACE fin TO PLATFORM 'Linux IA (64-bit)' FORMAT '/tmp/%U';

-- Vận tải bằng Backupset (12c+, nhỏ hơn Image Copy)
BACKUP TO PLATFORM 'Linux x86 64-bit' TABLESPACE rc_tbs;
RESTORE FOREIGN TABLESPACE rc_tbs TO NEW FROM BACKUPSET '/.../RC_TBS.BCK';
```

**Kỹ thuật giảm downtime**: Level 0 → Level 1 hàng ngày (DB vẫn Read-Write) → Level 1 cuối cùng khi Cut-over (DB Read Only vài phút)

### Module 15 — Database Duplication (Bài 61–63)

```sql
-- Active Duplication (qua mạng, không cần file backup)
RMAN> DUPLICATE DATABASE TO oradb_dev FROM ACTIVE DATABASE
  PASSWORD FILE SPFILE SET DB_CREATE_FILE_DEST='/oracle/dev';

-- Backup-Based Duplication
RMAN> DUPLICATE DATABASE TO oradb_dev
  BACKUP LOCATION '/tmp/db_files';
```

> ✅ RMAN tự động đổi DBID cho bản clone (độc lập với Production)
> ⚠️ Quên `DB_FILE_NAME_CONVERT` → ghi đè lên Production!

### Module 16 — Performance Tuning & Troubleshooting (Bài 64–66)

```sql
-- Tối ưu I/O
BACKUP_TAPE_IO_SLAVES = TRUE  -- Async I/O cho Tape

-- Backup lớn nhiều đêm
BACKUP DATABASE NOT BACKED UP SINCE 'SYSDATE-3'
DURATION 07:00 PARTIAL MINIMIZE TIME;

-- Giới hạn kích thước piece
ALLOCATE CHANNEL c1 DEVICE TYPE DISK MAXPIECESIZE 2048M FORMAT '/temp/%U.BAK';

-- Troubleshooting: ĐỌC TỪ DƯỚI ĐÁY ERROR STACK LÊN
-- Bật Debug
rman target / debug=all trace=rman.trc log=rman.log
```

### Module 17 — Multitenant, RAC & Cloud (Bài 67–73)

**CDB/PDB Backup**:
```sql
-- Từ CDB Root: backup toàn bộ
BACKUP DATABASE;  -- backup ROOT + tất cả PDB + archivelogs

-- Từ PDB: backup riêng lẻ
BACKUP DATABASE;  -- chỉ backup PDB đó, không có archivelog

-- Recover PDB cụ thể mà không down CDB
RESTORE PLUGGABLE DATABASE pdb1;
```

**RAC**:
```sql
-- Snapshot Control File phải trên Shared Storage
CONFIGURE SNAPSHOT CONTROLFILE NAME TO '+FRA/RAC/snapcf_rac.f';

-- Multi-channel theo từng node
CONFIGURE CHANNEL 1 DEVICE TYPE sbt CONNECT='sys/oracle@rac1';
CONFIGURE CHANNEL 2 DEVICE TYPE sbt CONNECT='sys/oracle@rac2';
```

**Cloud**: `libopc.so` plugin → bắt buộc mã hóa trước khi push lên OCI

---

## 🔑 Top 20 Lệnh RMAN Quan Trọng Nhất

| # | Lệnh | Mục đích |
|---|------|---------|
| 1 | `rman target /` | Kết nối RMAN local |
| 2 | `SHOW ALL` | Xem tất cả persistent settings |
| 3 | `BACKUP DATABASE PLUS ARCHIVELOG` | Full backup chuẩn production |
| 4 | `BACKUP INCREMENTAL LEVEL 1 DATABASE` | Incremental backup |
| 5 | `BACKUP AS COMPRESSED BACKUPSET DATABASE` | Backup có nén |
| 6 | `LIST BACKUP SUMMARY` | Liệt kê backup |
| 7 | `CROSSCHECK BACKUP` | Kiểm tra file vật lý |
| 8 | `DELETE OBSOLETE` | Xóa backup hết hạn |
| 9 | `DELETE EXPIRED BACKUP` | Xóa record file đã mất |
| 10 | `REPORT NEED BACKUP` | File nào chưa đủ backup |
| 11 | `RESTORE DATABASE` | Restore toàn bộ DB |
| 12 | `RECOVER DATABASE` | Apply archivelogs |
| 13 | `RECOVER DATABASE UNTIL TIME '...'` | Point-in-time recovery |
| 14 | `SWITCH DATAFILE N TO COPY` | Dùng Image Copy ngay lập tức |
| 15 | `RECOVER DATAFILE N BLOCK M` | Block media recovery |
| 16 | `LIST FAILURE` | DRA: liệt kê lỗi |
| 17 | `ADVISE FAILURE` | DRA: tư vấn giải pháp |
| 18 | `REPAIR FAILURE` | DRA: tự sửa lỗi |
| 19 | `DUPLICATE DATABASE TO ... FROM ACTIVE DATABASE` | Clone DB |
| 20 | `CONFIGURE RETENTION POLICY TO RECOVERY WINDOW OF 7 DAYS` | Cài retention |

---

## ⚡ Memory Hacks — Ghi nhớ nhanh

```
EXPIRED  ≠ OBSOLETE
  EXPIRED  = File vật lý BIẾN MẤT (CROSSCHECK phát hiện)
  OBSOLETE = File QUÁ HẠN retention (xóa bằng DELETE OBSOLETE)

RESTORE  ≠ RECOVER
  RESTORE  = Lấy file backup RA (xác chưa có hồn)
  RECOVER  = Apply archive logs VÀO (trả hồn về)

Complete ≠ Incomplete Recovery
  Complete   = Recover đến HIỆN TẠI, mở bằng ALTER DATABASE OPEN
  Incomplete = Recover đến QUÁ KHỨ, mở bằng ALTER DATABASE OPEN RESETLOGS

Differential ≠ Cumulative
  Differential = Backup từ Level 0 hoặc Level 1 GẦN NHẤT (ít data hơn)
  Cumulative   = Backup từ Level 0 GẦN NHẤT (nhiều data hơn, recover nhanh hơn)

Backup Set ≠ Image Copy
  Backup Set  = Định dạng RMAN, có thể nén/mã hóa, ra disk/tape
  Image Copy  = Bản sao 1:1, chỉ ra disk, SWITCH ngay lập tức
```

---

## 🔥 Fire Drill Scenarios (trong `reviews_all/`)

| File | Kịch bản | Kỹ năng |
|------|---------|---------|
| `20260418_FireDrill_StorageCrash.md` | Storage crash, mất datafile | RESTORE + RECOVER |
| `20260418_MegaChallenge_BlockCorruption_Optimized.md` | Block corruption nặng | BMR + DRA |
| `20260420_FireDrill_DroppedTablePITR.md` | DROP TABLE nhầm | PITR + Table Recovery |
| `20260420_CrossModule_MigrateEncryptedToNewPlatform.md` | Migrate encrypted DB | Cross-Platform + Encryption |
| `20260420_133505_Optimization_ParallelRecovery.md` | Tối ưu parallel recovery | Channels + Parallelism |
| `20260420_133510_Optimization_MergeIncrementalBackups.md` | Merge incremental | Updated Image Copy |
| `20260422_155001_FireDrill_LossOfUNDO.md` | Mất UNDO tablespace | RESTORE TABLESPACE |
| `20260422_155002_LogAnalysis_ORA19809.md` | ORA-19809 FRA đầy | FRA Management |
| `20260422_155004_CrossModule_ActiveDBDuplication.md` | Active DB Duplication | DUPLICATE + Network |
| `20260422_155006_FireDrill_TSPITR.md` | Tablespace PITR | TSPITR + Auxiliary |
| `20260422_155007_LogAnalysis_ORA01578.md` | ORA-01578 Block corrupt | VALIDATE + BMR |
| `20260422_155009_CrossModule_DRA.md` | Data Recovery Advisor | LIST/ADVISE/REPAIR FAILURE |
| `20260422_155010_MockExam_RetentionPolicy.md` | Mock exam retention | Policy Design |

---

## 📈 Sơ đồ Recovery Flow

```
DB CRASH / SỰ CỐ
       │
       ▼
Xác định loại failure
       │
       ├─── Instance failure ──────► Startup tự phục hồi (SMON/Instance Recovery)
       │
       ├─── Media failure ─────────► RESTORE DATABASE + RECOVER DATABASE
       │
       ├─── User error (DROP/DELETE)► Flashback Table | Table PITR | TSPITR
       │
       ├─── Block corruption ──────► RECOVER DATAFILE X BLOCK Y (BMR)
       │
       └─── Mất Control File ──────► SET DBID → RESTORE CONTROLFILE FROM AUTOBACKUP
```

---

*File tổng hợp này trích xuất từ 17 module guides trong thư mục `modules/`. Xem chi tiết từng module tại `modules/module_XX/module_XX_guide.md`.*


---

!!! info "Nguồn gốc"
    `Oracle-Database-Backup-and-Recovery-using-RMAN/modules/tong_hop_17_modules.md`
