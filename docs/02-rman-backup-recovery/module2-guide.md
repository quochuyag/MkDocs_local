---
title: '📘 Module 2: Nền tảng Backup & Recovery'
course: 02-rman-backup-recovery
source: Oracle-Database-Backup-and-Recovery-using-RMAN/module2_guide.md
---

# 📘 Module 2: Nền tảng Backup & Recovery

> **Phạm vi**: Bài 06 & Bài 07 trong khóa học Oracle Database Backup and Recovery using RMAN
> **Thời gian học ước tính**: 2-3 giờ
> **Tiền điều kiện**: Đã hoàn thành Module 1 (Giới thiệu & Chuẩn bị môi trường)

---

## 📑 Mục lục

- [Bài 06: Introduction to Oracle Backup and Recovery Solutions](#-bài-06-introduction-to-oracle-backup-and-recovery-solutions)
- [Bài 07: Configuring Oracle Database for Backup and Recovery](#-bài-07-configuring-oracle-database-for-backup-and-recovery)
- [Bảng tổng hợp Module 2](#-bảng-tổng-hợp-module-2)
- [Câu hỏi ôn tập tổng hợp](#-câu-hỏi-ôn-tập-tổng-hợp)

---

# 📖 Bài 06: Introduction to Oracle Backup and Recovery Solutions

## 🎯 Mục tiêu bài học
Sau khi hoàn thành bài này, bạn sẽ:
- ✅ Hiểu **kiến trúc Oracle Database** liên quan đến backup/recovery
- ✅ Biết được **các thành phần** cần backup trong Oracle Database
- ✅ Phân loại được các **loại failure** (lỗi) có thể xảy ra
- ✅ Hiểu các **giải pháp backup và recovery** có sẵn trong Oracle

## 📚 Kiến thức nền tảng cần biết

Trước khi học bài này, bạn cần hiểu:
- Oracle instance gồm những gì (SGA + background processes)
- Cách Oracle lưu trữ dữ liệu (datafiles, tablespaces)
- Khái niệm cơ bản về SQL và quản trị database

---

## 📋 Nội dung chính

### 1. Kiến trúc Oracle Database - Góc nhìn Backup/Recovery

> [!IMPORTANT]
> Hiểu rõ kiến trúc là **nền tảng** để biết cần backup những gì và recovery hoạt động ra sao.

#### 1.1 Cấu trúc vật lý (Physical Structure)

Oracle Database gồm các file vật lý trên disk:

```
Oracle Database Physical Structure
├── 📁 Data Files (.dbf)           ← Chứa dữ liệu thực tế
│   ├── SYSTEM tablespace          ← Data dictionary
│   ├── SYSAUX tablespace          ← Auxiliary system data
│   ├── UNDO tablespace            ← Undo segments (rollback)
│   ├── TEMP tablespace            ← Temporary segments
│   └── USER tablespaces           ← User data
│
├── 📁 Control Files (.ctl)        ← "Bộ não" của database
│   ├── Database name & ID
│   ├── Datafile locations
│   ├── Redo log info
│   └── Backup metadata
│
├── 📁 Online Redo Log Files (.log) ← Ghi nhận mọi thay đổi
│   ├── Group 1 (member a, member b)
│   ├── Group 2 (member a, member b)
│   └── Group 3 (member a, member b)
│
├── 📁 Archived Redo Logs (.arc)   ← Bản sao redo logs đã đầy
│
├── 📄 Server Parameter File       ← Cấu hình instance (SPFILE)
│   (spfile<SID>.ora)
│
└── 📄 Password File               ← Xác thực SYSDBA/SYSOPER
    (orapw<SID>)
```

#### 1.2 Các thành phần QUAN TRỌNG cần backup

| Thành phần | Vai trò | Mức độ quan trọng |
|------------|---------|-------------------|
| **Data Files** | Chứa toàn bộ dữ liệu user, system | ⭐⭐⭐⭐⭐ Critical |
| **Control Files** | Metadata của database | ⭐⭐⭐⭐⭐ Critical |
| **Online Redo Logs** | Transaction logs hiện tại | ⭐⭐⭐⭐⭐ Critical |
| **Archived Redo Logs** | Lịch sử thay đổi | ⭐⭐⭐⭐ Rất quan trọng |
| **SPFILE** | Cấu hình database | ⭐⭐⭐ Quan trọng |
| **Password File** | Xác thực admin | ⭐⭐ Trung bình |

---

### 2. Các loại Failure (Lỗi)

> [!WARNING]
> Một DBA giỏi không chỉ biết cách recovery mà phải **dự đoán** được các loại failure có thể xảy ra.

#### 2.1 Statement Failure (Lỗi câu lệnh)

**Là gì?** Một câu lệnh SQL thất bại do lỗi logic hoặc runtime.

```sql
-- Ví dụ: Insert dữ liệu vượt quá kích thước cột
SQL> INSERT INTO employees (name) VALUES ('Tên quá dài vượt quá giới hạn varchar2...');
-- ORA-12899: value too large for column

-- Ví dụ: Tablespace hết dung lượng
SQL> INSERT INTO large_table SELECT * FROM another_large_table;
-- ORA-01653: unable to extend table
```

**Cách xử lý:** 
- Sửa logic câu lệnh
- Thêm dung lượng cho tablespace
- **KHÔNG cần backup/recovery**

#### 2.2 User Process Failure (Lỗi từ phía user)

**Là gì?** Session bị ngắt bất thường (network lỗi, user kill process...).

```
User Process Failure Flow:
   User App ──X──> Oracle Server
   (mất kết nối)
         │
         ▼
   Oracle tự động phát hiện
         │
         ▼
   PMON process tự cleanup
   (rollback uncommitted transactions)
```

**Cách xử lý:**
- Oracle **tự động** xử lý qua **PMON** (Process Monitor)
- **KHÔNG cần DBA can thiệp**

#### 2.3 Network Failure (Lỗi mạng)

**Là gì?** Mất kết nối giữa client và server.

**Cách xử lý:**
- Kiểm tra network infrastructure
- Kiểm tra Oracle Net configuration (`tnsnames.ora`, `listener.ora`)
- **KHÔNG cần backup/recovery**

#### 2.4 User Error (Lỗi do người dùng)

**Là gì?** User xóa nhầm dữ liệu, drop table nhầm, v.v.

```sql
-- 😱 Thảm họa thường gặp:
SQL> DROP TABLE customers PURGE;    -- Xóa bảng quan trọng!
SQL> DELETE FROM orders;            -- Quên mệnh đề WHERE!
SQL> COMMIT;                        -- Và rồi commit luôn!
```

**Cách xử lý:**
- 💡 **Flashback Technology** (Table, Database, Drop)
- 💡 **Point-in-Time Recovery (PITR)** bằng RMAN
- 💡 **LogMiner** để phân tích và undo

> [!TIP]
> Đây là lý do quan trọng tại sao cần bật **ARCHIVELOG mode** — sẽ học ở Bài 07!

#### 2.5 Instance Failure (Lỗi instance)

**Là gì?** Oracle instance bị crash (mất điện, OS crash, kill -9 process...).

```
Instance Failure → Recovery Flow:
   Instance CRASH
        │
        ▼
   DBA khởi động lại: STARTUP
        │
        ▼
   Oracle tự động chạy Instance Recovery
        │
        ├── ROLL FORWARD (redo)
        │   └── Áp dụng redo logs để khôi phục committed transactions
        │
        └── ROLL BACK (undo)
            └── Dùng undo segments để rollback uncommitted transactions
```

**Cách xử lý:**
- Oracle **tự động** thực hiện **Instance Recovery**
- DBA chỉ cần chạy `STARTUP`
- Yêu cầu: **Online Redo Logs phải còn nguyên vẹn**

#### 2.6 Media Failure (Lỗi phần cứng lưu trữ) ⚠️ NGHIÊM TRỌNG NHẤT

**Là gì?** Disk hỏng, file bị corrupt, file bị xóa.

```
Media Failure Examples:
├── Disk failure        → Mất datafiles
├── File corruption     → Data bị hỏng
├── Accidental delete   → Xóa nhầm datafile
└── Controller failure  → Mất nhiều files cùng lúc
```

**Cách xử lý:**
- 🔧 **RMAN RESTORE + RECOVER** ← _Đây là trọng tâm của cả khóa học!_
- Yêu cầu: Phải có **backup** + **archived redo logs**

---

### 3. Giải pháp Backup & Recovery của Oracle

#### 3.1 Phân loại Backup

```
                    Oracle Backup Types
                          │
            ┌─────────────┼─────────────┐
            │             │             │
      Physical Backup  Logical Backup  Hybrid
            │             │
      ┌─────┴─────┐      │
      │           │       │
   Offline     Online   Export/
   (Cold)     (Hot)     Data Pump
      │           │
      │     Yêu cầu
      │     ARCHIVELOG
      │     mode
      │
  Database     
  phải SHUTDOWN
```

#### 3.2 Physical Backup - Sao lưu vật lý

| Đặc điểm | Cold Backup (Offline) | Hot Backup (Online) |
|-----------|----------------------|---------------------|
| **Database state** | SHUTDOWN (đóng) | OPEN (đang chạy) |
| **Downtime** | ❌ Có downtime | ✅ Không downtime |
| **ARCHIVELOG** | Không bắt buộc | ⚠️ BẮT BUỘC |
| **Backup gồm** | Tất cả files | Datafiles + Archived logs |
| **Công cụ** | OS copy hoặc RMAN | RMAN (khuyến nghị) |
| **Dùng khi** | DỮ liệu ít, chấp nhận downtime | Production, 24/7 |

**Cold Backup** (User-Managed - Thủ công):
```sql
-- Bước 1: Shutdown database
SQL> SHUTDOWN IMMEDIATE;

-- Bước 2: Copy tất cả files bằng OS command
-- Windows:
> copy D:\oradata\orcl\*.dbf D:\backup\cold\
> copy D:\oradata\orcl\*.ctl D:\backup\cold\
> copy D:\oradata\orcl\*.log D:\backup\cold\

-- Linux:
$ cp /u01/oradata/orcl/*.dbf /backup/cold/
$ cp /u01/oradata/orcl/*.ctl /backup/cold/
$ cp /u01/oradata/orcl/*.log /backup/cold/

-- Bước 3: Startup lại database
SQL> STARTUP;
```

**Hot Backup** (User-Managed - Thủ công):
```sql
-- ⚠️ Yêu cầu: Database phải ở ARCHIVELOG mode

-- Bước 1: Đưa tablespace vào chế độ backup
SQL> ALTER TABLESPACE users BEGIN BACKUP;

-- Bước 2: Copy datafiles của tablespace đó
> copy D:\oradata\orcl\users01.dbf D:\backup\hot\

-- Bước 3: Kết thúc chế độ backup
SQL> ALTER TABLESPACE users END BACKUP;

-- ⚠️ Phải lặp lại cho TỪNG tablespace!
```

> [!CAUTION]
> Hot Backup thủ công rất **dễ sai sót** nếu quên `END BACKUP`. Đây là lý do **RMAN ra đời** — tự động hóa toàn bộ quá trình này!

#### 3.3 Logical Backup - Sao lưu logic

```sql
-- Export Data Pump (expdp) - Backup logic
$ expdp system/password DIRECTORY=backup_dir DUMPFILE=full_backup.dmp FULL=Y

-- Import Data Pump (impdp) - Restore logic  
$ impdp system/password DIRECTORY=backup_dir DUMPFILE=full_backup.dmp FULL=Y
```

| So sánh | Physical Backup | Logical Backup (Data Pump) |
|---------|----------------|---------------------------|
| **Backup cái gì** | Files vật lý (binary) | Dữ liệu logic (SQL) |
| **Point-in-Time Recovery** | ✅ Có | ❌ Không |
| **Tốc độ** | ⚡ Nhanh hơn | 🐢 Chậm hơn |
| **Cross-platform** | ⚠️ Hạn chế | ✅ Linh hoạt |
| **Granularity** | File/Tablespace | Schema/Table/Row |
| **Dùng cho** | Full DB recovery | Migration, di chuyển data |

#### 3.4 So sánh công cụ Backup

```
              Backup Tools Comparison
   ┌──────────────────────────────────────────┐
   │          User-Managed Backup             │
   │  (OS commands: cp, copy, tar, etc.)      │
   │  ├── Thủ công, dễ sai sót               │
   │  ├── Không tracking backup metadata      │
   │  └── Không hỗ trợ incremental backup     │
   └──────────────────────────────────────────┘
                      vs
   ┌──────────────────────────────────────────┐
   │          RMAN (Recovery Manager)         │
   │  ├── ✅ Tự động hóa                      │
   │  ├── ✅ Incremental backup               │
   │  ├── ✅ Block-level corruption detection  │
   │  ├── ✅ Compressed backup                 │
   │  ├── ✅ Encrypted backup                  │
   │  ├── ✅ Backup validation                 │
   │  ├── ✅ Recovery catalog                  │
   │  └── ✅ Oracle khuyến nghị sử dụng!       │
   └──────────────────────────────────────────┘
```

### 📌 Lưu ý quan trọng bài 06

> [!NOTE]
> 1. **TEMP tablespace** không cần backup — Oracle tự tạo lại khi cần
> 2. **Online Redo Logs** không nên backup bằng RMAN — dùng **multiplexing** thay thế
> 3. **RMAN** là công cụ được Oracle **khuyến nghị chính thức** cho backup/recovery
> 4. **Media Failure** là loại failure duy nhất **bắt buộc** cần có backup để recovery

---

### ❓ Câu hỏi ôn tập Bài 06

1. **Liệt kê 6 loại failure** trong Oracle Database. Loại nào nghiêm trọng nhất và tại sao?
2. **Cold Backup vs Hot Backup**: Khi nào dùng cái nào? Hot Backup yêu cầu điều kiện gì?
3. **Tại sao RMAN tốt hơn User-Managed Backup?** Kể ít nhất 4 ưu điểm.
4. **Physical Backup vs Logical Backup**: Điểm khác biệt chính là gì?
5. **Instance Failure** được Oracle xử lý tự động như thế nào? (Gợi ý: Roll Forward + Roll Back)

---
---

# 📖 Bài 07: Configuring Oracle Database for Backup and Recovery

## 🎯 Mục tiêu bài học
Sau khi hoàn thành bài này, bạn sẽ:
- ✅ Hiểu và chuyển đổi database sang **ARCHIVELOG mode**
- ✅ Cấu hình **Fast Recovery Area (FRA)**
- ✅ Thực hiện **multiplexing** cho Control Files và Redo Log Files
- ✅ Biết cách kiểm tra cấu hình backup/recovery

## 📚 Kiến thức nền tảng cần biết
- Bài 06 (đã học ở trên)
- Biết cách start/stop Oracle Database
- Hiểu khái niệm redo log switching

---

## 📋 Nội dung chính

### 1. ARCHIVELOG Mode vs NOARCHIVELOG Mode ⭐

> [!IMPORTANT]
> Đây là **cấu hình QUAN TRỌNG NHẤT** cho backup/recovery. Production database **BẮT BUỘC** phải ở ARCHIVELOG mode!

#### 1.1 NOARCHIVELOG Mode (Mặc định)

```
   Redo Log Switching trong NOARCHIVELOG mode:
   
   Group 1 ──write──> Group 2 ──write──> Group 3
     │                                      │
     │        ┌────────────────────────────┘
     │        │
     ▼        ▼
   Group 1 bị GHI ĐÈ     ← ⚠️ MẤT lịch sử thay đổi!
   (dữ liệu cũ bị mất)
```

**Hậu quả:**
- ❌ **KHÔNG THỂ** hot backup (online backup)
- ❌ **KHÔNG THỂ** point-in-time recovery
- ❌ Chỉ có thể restore về thời điểm backup cuối cùng
- ❌ **KHÔNG PHẢI** cho production!

#### 1.2 ARCHIVELOG Mode (Khuyến nghị)

```
   Redo Log Switching trong ARCHIVELOG mode:
   
   Group 1 ──write──> Group 2 ──write──> Group 3
     │                                      │
     │     ┌───────────────────────────────┘
     │     │
     ▼     ▼
   Group 1 được ARCHIVE trước      ← ✅ Lưu giữ lịch sử!
   rồi mới bị ghi đè
     │
     ▼
   archived_log_001.arc  ← Lưu trong Archive Log Destination
   archived_log_002.arc
   archived_log_003.arc
   ...
```

**Lợi ích:**
- ✅ Hot backup (database vẫn mở)
- ✅ Point-in-time recovery
- ✅ Zero data loss (không mất dữ liệu)
- ✅ DataGuard (standby) hoạt động được

#### 1.3 Cách chuyển sang ARCHIVELOG Mode

```sql
-- ============================================
-- CHUYỂN DATABASE SANG ARCHIVELOG MODE
-- ============================================

-- Bước 1: Kiểm tra mode hiện tại
SQL> ARCHIVE LOG LIST;
-- Output mong đợi (nếu đang NOARCHIVELOG):
-- Database log mode              No Archive Mode
-- Automatic archival             Disabled
-- Archive destination            USE_DB_RECOVERY_FILE_DEST

-- Bước 2: Shutdown database
SQL> SHUTDOWN IMMEDIATE;

-- Bước 3: Mount database (KHÔNG open)
SQL> STARTUP MOUNT;

-- Bước 4: Bật ARCHIVELOG mode
SQL> ALTER DATABASE ARCHIVELOG;

-- Bước 5: Mở database
SQL> ALTER DATABASE OPEN;

-- Bước 6: Xác nhận lại
SQL> ARCHIVE LOG LIST;
-- Output mong đợi:
-- Database log mode              Archive Mode       ← ✅ Đã đổi!
-- Automatic archival             Enabled            ← ✅ Tự động archive
-- Archive destination            USE_DB_RECOVERY_FILE_DEST
-- Oldest online log sequence     1
-- Next log sequence to archive   2
-- Current log sequence           2
```

> [!WARNING]
> **Phải SHUTDOWN database trước** khi thay đổi ARCHIVELOG mode! Đây là thay đổi ở mức database, không thể làm khi database đang OPEN.

#### 1.4 Xác nhận bằng V$ views

```sql
-- Cách 1: Dùng V$DATABASE
SQL> SELECT LOG_MODE FROM V$DATABASE;
-- LOG_MODE
-- --------
-- ARCHIVELOG

-- Cách 2: Kiểm tra archive log files đã tạo
SQL> SELECT SEQUENCE#, FIRST_TIME, NEXT_TIME, STATUS
     FROM V$ARCHIVED_LOG
     ORDER BY SEQUENCE#;

-- Cách 3: Xem archive destination
SQL> SELECT DEST_NAME, STATUS, DESTINATION 
     FROM V$ARCHIVE_DEST 
     WHERE STATUS = 'VALID';
```

---

### 2. Fast Recovery Area (FRA) ⭐

> [!NOTE]
> FRA (trước đây gọi là **Flash Recovery Area**) là vùng lưu trữ tập trung cho tất cả file liên quan đến recovery.

#### 2.1 FRA chứa những gì?

```
Fast Recovery Area (FRA)
├── 📁 Archived Redo Logs
├── 📁 RMAN Backups (backupsets, image copies)
├── 📁 Flashback Logs
├── 📁 Control File autobackup
├── 📁 Multiplexed copies of:
│   ├── Current control file
│   └── Online redo logs
└── 📁 Foreign archived logs (DataGuard)
```

#### 2.2 Cấu hình FRA

```sql
-- ============================================
-- CẤU HÌNH FAST RECOVERY AREA
-- ============================================

-- Bước 1: Xem cấu hình FRA hiện tại
SQL> SHOW PARAMETER DB_RECOVERY_FILE_DEST;
-- NAME                          VALUE
-- ----------------------------- -----
-- db_recovery_file_dest         
-- db_recovery_file_dest_size    

-- Bước 2: Đặt vị trí FRA
-- ⚠️ NÊN đặt trên DISK KHÁC với datafiles để tránh single point of failure!

-- Windows:
SQL> ALTER SYSTEM SET DB_RECOVERY_FILE_DEST = 'D:\fast_recovery_area' SCOPE=BOTH;

-- Linux:
SQL> ALTER SYSTEM SET DB_RECOVERY_FILE_DEST = '/u02/fra' SCOPE=BOTH;

-- Bước 3: Đặt kích thước FRA
-- 💡 Khuyến nghị: Gấp 2-3 lần kích thước database
SQL> ALTER SYSTEM SET DB_RECOVERY_FILE_DEST_SIZE = 50G SCOPE=BOTH;

-- Bước 4: Xác nhận
SQL> SHOW PARAMETER DB_RECOVERY_FILE_DEST;
-- NAME                           VALUE
-- ------------------------------ -----
-- db_recovery_file_dest          D:\fast_recovery_area
-- db_recovery_file_dest_size     53687091200   (= 50GB)
```

#### 2.3 Giám sát FRA

```sql
-- Kiểm tra dung lượng FRA
SQL> SELECT 
         SPACE_LIMIT / 1024 / 1024       AS "Tổng (MB)",
         SPACE_USED / 1024 / 1024        AS "Đã dùng (MB)",
         SPACE_RECLAIMABLE / 1024 / 1024 AS "Có thể thu hồi (MB)",
         ROUND((SPACE_USED - SPACE_RECLAIMABLE) / SPACE_LIMIT * 100, 2) 
                                          AS "% Đang dùng thực"
     FROM V$RECOVERY_FILE_DEST;

-- Xem chi tiết từng loại file trong FRA
SQL> SELECT 
         FILE_TYPE,
         PERCENT_SPACE_USED       AS "% Dùng",
         PERCENT_SPACE_RECLAIMABLE AS "% Thu hồi được",
         NUMBER_OF_FILES          AS "Số files"
     FROM V$RECOVERY_AREA_USAGE;

-- Output ví dụ:
-- FILE_TYPE               % Dùng  % Thu hồi được  Số files
-- ----------------------- ------- --------------- ---------
-- CONTROL FILE                 0              0         1
-- REDO LOG                     0              0         0
-- ARCHIVED LOG              15.2            8.1        45
-- BACKUP PIECE              22.5            0         12
-- IMAGE COPY                   0              0         0
-- FLASHBACK LOG              5.3            2.1        15
-- FOREIGN ARCHIVED LOG         0              0         0
```

> [!TIP]
> **Quy tắc vàng cho FRA size:**
> - Database size: 100GB → FRA tối thiểu: 200GB
> - Nếu dùng Flashback Database: FRA = 3x database size
> - Luôn giám sát `V$RECOVERY_AREA_USAGE` để tránh FRA đầy!

#### 2.4 Khi FRA bị đầy

```sql
-- ⚠️ Khi FRA đầy, Oracle sẽ ghi cảnh báo vào Alert Log:
-- ORA-19815: WARNING: db_recovery_file_dest_size of XXXXX bytes is 100.00% used

-- Giải pháp:
-- 1️⃣ Tăng kích thước FRA
SQL> ALTER SYSTEM SET DB_RECOVERY_FILE_DEST_SIZE = 100G SCOPE=BOTH;

-- 2️⃣ Xóa backup/archivelog cũ không cần thiết (qua RMAN)
RMAN> DELETE ARCHIVELOG ALL COMPLETED BEFORE 'SYSDATE-7';
RMAN> DELETE OBSOLETE;

-- 3️⃣ Di chuyển backup ra ngoài FRA (ví dụ: sang tape)

-- ❌ KHÔNG BAO GIỜ xóa files trong FRA bằng OS command!
-- Luôn dùng RMAN để quản lý!
```

---

### 3. Multiplexing Control Files ⭐

> [!CAUTION]
> **Control File** là "bộ não" của database. Nếu mất control file duy nhất, database KHÔNG THỂ mở được! Luôn có ít nhất **3 bản copy** trên các disk khác nhau.

#### 3.1 Tại sao cần Multiplexing?

```
KHÔNG multiplexing (NGUY HIỂM):
   Disk A: control01.ctl  ← Nếu Disk A hỏng → MẤT DATABASE!

CÓ multiplexing (AN TOÀN):
   Disk A: control01.ctl  ← Disk A hỏng?
   Disk B: control02.ctl  ← Vẫn còn bản sao!
   Disk C: control03.ctl  ← Thêm 1 bản nữa cho chắc!
```

#### 3.2 Thêm Control File Copy

```sql
-- ============================================
-- MULTIPLEXING CONTROL FILES
-- ============================================

-- Bước 1: Kiểm tra control files hiện tại
SQL> SELECT NAME FROM V$CONTROLFILE;
-- NAME
-- ----------------------------------------
-- D:\ORADATA\ORCL\CONTROL01.CTL
-- D:\FAST_RECOVERY_AREA\ORCL\CONTROL02.CTL

-- Bước 2: Muốn thêm CONTROL03.CTL trên disk khác
-- Cần thay đổi SPFILE:
SQL> ALTER SYSTEM SET CONTROL_FILES = 
     'D:\ORADATA\ORCL\CONTROL01.CTL',
     'D:\FAST_RECOVERY_AREA\ORCL\CONTROL02.CTL',
     'E:\BACKUP\ORCL\CONTROL03.CTL'
     SCOPE=SPFILE;

-- Bước 3: Shutdown database
SQL> SHUTDOWN IMMEDIATE;

-- Bước 4: Copy control file bằng OS command
-- Windows:
> copy "D:\ORADATA\ORCL\CONTROL01.CTL" "E:\BACKUP\ORCL\CONTROL03.CTL"

-- Linux:
$ cp /u01/oradata/orcl/control01.ctl /u03/backup/orcl/control03.ctl

-- Bước 5: Startup database
SQL> STARTUP;

-- Bước 6: Xác nhận
SQL> SELECT NAME FROM V$CONTROLFILE;
-- Phải thấy 3 control files
```

---

### 4. Multiplexing Online Redo Log Files ⭐

#### 4.1 Khái niệm Redo Log Groups và Members

```
Redo Log Architecture:
   ┌─────────────────────────────────────────────┐
   │  Group 1                                    │
   │  ├── Member A: D:\oradata\redo01a.log       │
   │  └── Member B: E:\oradata\redo01b.log       │ ← MULTIPLEXED!
   ├─────────────────────────────────────────────┤
   │  Group 2                                    │
   │  ├── Member A: D:\oradata\redo02a.log       │
   │  └── Member B: E:\oradata\redo02b.log       │ ← MULTIPLEXED!
   ├─────────────────────────────────────────────┤
   │  Group 3                                    │
   │  ├── Member A: D:\oradata\redo03a.log       │
   │  └── Member B: E:\oradata\redo03b.log       │ ← MULTIPLEXED!
   └─────────────────────────────────────────────┘
   
   Oracle ghi ĐỒNG THỜI vào tất cả members trong cùng group.
   Nếu 1 member hỏng, Oracle vẫn dùng member còn lại.
```

#### 4.2 Thêm Redo Log Member

```sql
-- ============================================
-- MULTIPLEXING REDO LOG FILES
-- ============================================

-- Bước 1: Kiểm tra redo log groups hiện tại
SQL> SELECT GROUP#, MEMBER FROM V$LOGFILE ORDER BY GROUP#;
-- GROUP#  MEMBER
-- ------  ----------------------------------------
-- 1       D:\ORADATA\ORCL\REDO01.LOG
-- 2       D:\ORADATA\ORCL\REDO02.LOG
-- 3       D:\ORADATA\ORCL\REDO03.LOG
-- → Mỗi group chỉ có 1 member → NGUY HIỂM!

-- Bước 2: Thêm member cho mỗi group (trên disk khác)
SQL> ALTER DATABASE ADD LOGFILE MEMBER
     'E:\ORADATA\ORCL\REDO01B.LOG' TO GROUP 1;

SQL> ALTER DATABASE ADD LOGFILE MEMBER
     'E:\ORADATA\ORCL\REDO02B.LOG' TO GROUP 2;

SQL> ALTER DATABASE ADD LOGFILE MEMBER
     'E:\ORADATA\ORCL\REDO03B.LOG' TO GROUP 3;

-- ✅ Không cần shutdown! Làm được khi database đang OPEN.

-- Bước 3: Xác nhận
SQL> SELECT GROUP#, MEMBER, STATUS FROM V$LOGFILE ORDER BY GROUP#;
-- GROUP#  MEMBER                           STATUS
-- ------  -------------------------------- -------
-- 1       D:\ORADATA\ORCL\REDO01.LOG       (null)
-- 1       E:\ORADATA\ORCL\REDO01B.LOG      (null)
-- 2       D:\ORADATA\ORCL\REDO02.LOG       (null)
-- 2       E:\ORADATA\ORCL\REDO02B.LOG      (null)
-- 3       D:\ORADATA\ORCL\REDO03.LOG       (null)
-- 3       E:\ORADATA\ORCL\REDO03B.LOG      (null)
```

#### 4.3 Thêm Redo Log Group

```sql
-- Thêm group mới (khuyến nghị tối thiểu 3 groups)
SQL> ALTER DATABASE ADD LOGFILE GROUP 4 (
     'D:\ORADATA\ORCL\REDO04A.LOG',
     'E:\ORADATA\ORCL\REDO04B.LOG'
     ) SIZE 200M;

-- Kiểm tra tất cả groups
SQL> SELECT GROUP#, BYTES/1024/1024 AS "Size(MB)", MEMBERS, STATUS
     FROM V$LOG ORDER BY GROUP#;
```

> [!TIP]
> **Best Practices cho Redo Logs:**
> - Tối thiểu **3 groups**, mỗi group **2 members**
> - Members đặt trên **disk khác nhau**
> - Size mỗi group: **100MB - 500MB** tùy workload
> - Giám sát tần suất log switch: nên **15-20 phút/lần**

---

### 5. Tổng kết cấu hình cho Production Database

```sql
-- ============================================
-- CHECKLIST CẤU HÌNH BACKUP/RECOVERY CHO PRODUCTION
-- ============================================

-- ✅ 1. Bật ARCHIVELOG mode
SQL> SELECT LOG_MODE FROM V$DATABASE;
-- Phải là: ARCHIVELOG

-- ✅ 2. FRA đã cấu hình và đủ dung lượng
SQL> SHOW PARAMETER DB_RECOVERY_FILE_DEST;
-- Phải có giá trị, size >= 2x database size

-- ✅ 3. Control files multiplexed (>=3 copies)
SQL> SELECT COUNT(*) FROM V$CONTROLFILE;
-- Phải >= 3

-- ✅ 4. Redo logs multiplexed (>=2 members/group)
SQL> SELECT GROUP#, COUNT(*) AS MEMBERS FROM V$LOGFILE GROUP BY GROUP# ORDER BY 1;
-- Mỗi group phải >= 2

-- ✅ 5. Redo log groups đủ (>=3 groups)
SQL> SELECT COUNT(*) FROM V$LOG;
-- Phải >= 3

-- ✅ 6. SPFILE đang được sử dụng (không phải PFILE)
SQL> SHOW PARAMETER SPFILE;
-- Phải có giá trị (RMAN có thể backup SPFILE)
```

### 📌 Lưu ý quan trọng bài 07

> [!WARNING]
> 1. **KHÔNG BAO GIỜ** chạy production database ở **NOARCHIVELOG** mode
> 2. FRA phải nằm trên **disk khác** với datafiles
> 3. **KHÔNG** xóa files trong FRA bằng OS command — luôn dùng **RMAN**
> 4. Khi thay đổi `CONTROL_FILES` trong SPFILE, phải **SHUTDOWN** và copy file thủ công
> 5. Thêm redo log member **KHÔNG cần** shutdown (có thể làm online)

---

### ❓ Câu hỏi ôn tập Bài 07

1. **ARCHIVELOG vs NOARCHIVELOG**: Sự khác biệt chính? Tại sao production **bắt buộc** dùng ARCHIVELOG?
2. **Các bước chuyển sang ARCHIVELOG mode**? Database phải ở trạng thái nào khi thực hiện?
3. **FRA là gì?** Chứa những loại file nào? Nên đặt size bao nhiêu?
4. **Khi FRA đầy** thì sao? Cách xử lý? Tại sao không được xóa file bằng OS command?
5. **Multiplexing**: Tại sao cần? Sự khác biệt giữa multiplexing control file và redo log file?

---

# 📊 Bảng tổng hợp Module 2

| Chủ đề | Khái niệm chính | Lệnh quan trọng |
|--------|-----------------|------------------|
| **Failure Types** | 6 loại: Statement, User Process, Network, User Error, Instance, Media | — |
| **Backup Types** | Physical (Cold/Hot) vs Logical (Data Pump) | `ALTER TABLESPACE ... BEGIN/END BACKUP` |
| **ARCHIVELOG** | Bật để cho phép hot backup & PITR | `ALTER DATABASE ARCHIVELOG` |
| **FRA** | Vùng lưu trữ tập trung cho recovery files | `DB_RECOVERY_FILE_DEST`, `DB_RECOVERY_FILE_DEST_SIZE` |
| **Multiplex CTL** | Ít nhất 3 copies trên disk khác nhau | `ALTER SYSTEM SET CONTROL_FILES` |
| **Multiplex Redo** | Ít nhất 2 members/group trên disk khác nhau | `ALTER DATABASE ADD LOGFILE MEMBER` |

---

# 🎯 Câu hỏi ôn tập tổng hợp

## Tình huống thực tế (Scenario-Based)

### Tình huống 1:
> Bạn vừa tiếp nhận một database production đang chạy ở **NOARCHIVELOG** mode. Manager yêu cầu bạn chuyển sang ARCHIVELOG mode. Bạn sẽ làm gì?

<details>
<summary>💡 Gợi ý trả lời</summary>

1. Lên kế hoạch downtime (cần shutdown)
2. Cấu hình FRA trước (`DB_RECOVERY_FILE_DEST` + `_SIZE`)
3. `SHUTDOWN IMMEDIATE` → `STARTUP MOUNT` → `ALTER DATABASE ARCHIVELOG` → `ALTER DATABASE OPEN`
4. Xác nhận bằng `ARCHIVE LOG LIST`
5. Thực hiện full backup ngay sau khi chuyển mode
</details>

### Tình huống 2:
> Alert log báo **FRA 95% full**. Bạn xử lý như thế nào?

<details>
<summary>💡 Gợi ý trả lời</summary>

1. Kiểm tra `V$RECOVERY_AREA_USAGE` xem loại file nào chiếm nhiều
2. Dùng RMAN xóa backup/archivelog cũ: `DELETE OBSOLETE`, `DELETE ARCHIVELOG ALL COMPLETED BEFORE 'SYSDATE-7'`
3. Nếu vẫn thiếu: tăng `DB_RECOVERY_FILE_DEST_SIZE`
4. Cân nhắc di chuyển backup cũ ra tape/external storage
5. **KHÔNG xóa file bằng OS command!**
</details>

### Tình huống 3:
> Database có 3 redo log groups, mỗi group chỉ có **1 member**. Disk chứa redo log group 2 bị hỏng. Điều gì xảy ra?

<details>
<summary>💡 Gợi ý trả lời</summary>

- Nếu group 2 **đang CURRENT** (đang ghi): Instance **CRASH** ngay lập tức!
- Nếu group 2 **đang INACTIVE**: Database vẫn chạy, nhưng cần fix ngay
- **Bài học**: Luôn multiplex redo logs trên disk khác nhau để tránh tình huống này
</details>

---

## ➡️ Bài tiếp theo

**Module 3: Làm quen RMAN**
- Bài 08: Introduction to Recovery Manager (RMAN) — Kiến trúc RMAN, cách kết nối, các lệnh cơ bản
- Bài 09: Practice 2 — Thực hành kết nối và sử dụng RMAN

> Bạn muốn **tiếp tục Module 3** hay **ôn lại phần nào** trong Module 2? 😊


---

!!! info "Nguồn gốc"
    `Oracle-Database-Backup-and-Recovery-using-RMAN/module2_guide.md`
