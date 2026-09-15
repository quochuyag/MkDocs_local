---
title: '📘 Module 03: Làm quen RMAN (Recovery Manager)'
course: 09-dba-ai
source: dba_ai/oracle_rman/modules/module_03_guide.md
---

# 📘 Module 03: Làm quen RMAN (Recovery Manager)

> **Module**: 03/17
> **Phạm vi**: Bài 08 (Lý thuyết) & Bài 09 - Practice 2 (Thực hành)
> **Giảng viên**: Ahmed Baraka (Packt Publishing)
> **Thời gian học ước tính**: 2-3 giờ
> **Tiền điều kiện**: Đã hoàn thành Module 02 (Nền tảng Backup & Recovery)
> **Nguồn PDF**: `pdf_extracted/module_03/`

---

## 📑 Mục lục

- [Bài 08: Introduction to Recovery Manager (RMAN)](#-bài-08-introduction-to-recovery-manager-rman)
- [Bài 09: Practice 2 - Introducing RMAN](#-bài-09-practice-2---introducing-rman)
- [Bảng tổng hợp Module 03](#-bảng-tổng-hợp-module-03)
- [Câu hỏi ôn tập tổng hợp](#-câu-hỏi-ôn-tập-tổng-hợp)

---

# 📖 Bài 08: Introduction to Recovery Manager (RMAN)
> 📄 Nguồn: `Introduction to Recovery Manager (RMAN).pdf` — 17 slides

## 🎯 Mục tiêu bài học (Objectives - Slide 2)
Theo bài giảng gốc, sau bài này bạn sẽ:
- ✅ Describe the **advantages of using RMAN** — Ưu điểm của RMAN
- ✅ Describe the **terms** used with explaining RMAN operations — Thuật ngữ RMAN
- ✅ Describe **RMAN components** — Các thành phần RMAN
- ✅ **Start RMAN** with connecting to target database — Khởi động và kết nối RMAN
- ✅ Use **SYSBACKUP** privilege — Dùng quyền SYSBACKUP
- ✅ Use RMAN **command-line arguments** — Tham số dòng lệnh
- ✅ Manage **RMAN persistent settings** — Quản lý cấu hình RMAN

---

## 📋 Nội dung chính

### 1. About Recovery Manager - RMAN (Slide 3)

Theo slides gốc, RMAN là:
- 📌 A **command-line client** for backup and recovery functions
- 📌 Has **powerful control and scripting language** — ngôn ngữ scripting mạnh mẽ
- 📌 Has a **published API** that enables interface with most popular backup software
- 📌 **Integrated** with Oracle Secure Backup and OEM
- 📌 Backs up files to **disk** or **tape** (through Media Management Library - MML)

```
RMAN Interface:

   DBA ────> RMAN Client ────> Target Database
              (command-line)      │
                                  ├──> Disk Storage
                                  │
                                  └──> Tape (qua MML)
```

---

### 2. RMAN Features (Slide 4) ⭐

Danh sách tính năng RMAN theo slides gốc:

| # | Feature | Giải thích tiếng Việt |
|---|---------|----------------------|
| 1 | **Back up** data files, control files, parameter file, archived redo logs | Backup toàn bộ thành phần DB |
| 2 | **Perform incremental backups** | Backup gia tăng (chỉ backup phần thay đổi) |
| 3 | **Perform block-level media recovery** | Khôi phục ở mức block (không cần recover cả file) |
| 4 | **Detect corrupted blocks** during backup | Tự phát hiện block lỗi khi backup |
| 5 | Use **binary compression** when creating backups | Nén backup để tiết kiệm disk |
| 6 | **Encrypt** the data in backup files using TDE | Mã hóa backup bằng TDE |
| 7 | **Make an online copy** of a database | Tạo bản sao DB khi đang chạy |
| 8 | Can seamlessly operate with **ASM** | Hoạt động mượt mà với ASM |

> [!TIP]
> Những tính năng **RMAN có mà User-Managed Backup KHÔNG có**: Incremental backup, block-level recovery, corruption detection, compression, encryption. Đây là lý do Oracle khuyến nghị RMAN!

---

### 3. RMAN Terminologies (Slide 5) ⭐⭐

Bốn thuật ngữ **BẮT BUỘC phải nhớ**:

| Thuật ngữ | Định nghĩa (slides gốc) | Giải thích |
|-----------|------------------------|-----------|
| **Target Database** | A database RMAN is connected to to perform backup and recovery | Database mà RMAN kết nối để thao tác |
| **RMAN Client** | RMAN executable, on Linux located in `$ORACLE_HOME/bin` | File thực thi RMAN |
| **Media Management Software** | An application required by RMAN to interact with the tape. Sometimes called **SBT** (System Backup to Tape) | Phần mềm trung gian để ghi ra tape |
| **Recovery Catalog** | A separate database schema used to store RMAN repository | Schema riêng trên DB khác để lưu metadata backup |

```
Thuật ngữ RMAN - Quan hệ:

   ┌──────────────┐         ┌──────────────────┐
   │ RMAN Client  │────────>│ Target Database  │
   │ ($OH/bin/rman)│         │ (DB cần backup)  │
   └──────┬───────┘         └──────────────────┘
          │
          ├──────────────>  Disk Storage
          │
          ├──────────────>  Media Management (SBT) ──> Tape
          │
          └──────────────>  Recovery Catalog (DB khác, optional)
```

---

### 4. RMAN Components (Slide 6) ⭐⭐

Sơ đồ kiến trúc RMAN từ slides gốc:

```
                    ┌─────────────────────────┐
                    │   Enterprise Manager    │
                    │     Cloud Control       │
                    └────────────┬────────────┘
                                │ API
                    ┌───────────┴───────────┐
                    │        RMAN           │
                    └───┬────────┬────────┬─┘
                        │        │        │
              ┌─────────┘        │        └──────────┐
              ▼                  ▼                   ▼
   ┌──────────────────┐  ┌──────────────┐  ┌────────────────┐
   │ Target Database  │  │  Auxiliary   │  │   Recovery     │
   │                  │  │  Database    │  │   Catalog      │
   └────────┬─────────┘  └──────────────┘  └────────────────┘
            │
     ┌──────┴──────┐
     │             │
     ▼             ▼
┌─────────┐  ┌──────────┐
│ Channel │  │ Channel  │
│ (Disk)  │  │ (SBT)   │
└────┬────┘  └────┬─────┘
     │            │
     ▼            ▼──── MML ────> Tape Library
   Disk                           │
   Storage            ┌──────────┘
                      ├──> Oracle Secure Backup
                      ├──> Oracle Database Backup Cloud Module
                      ├──> Cloud Storage
                      └──> Third party backup software
```

**Giải thích các thành phần:**

| Thành phần | Vai trò |
|------------|---------|
| **Target Database** | Database chính cần backup/recovery |
| **Auxiliary Database** | Database phụ (dùng khi duplicate, PITR tablespace) |
| **Recovery Catalog** | Schema riêng lưu metadata RMAN (optional, nhưng khuyến nghị) |
| **Channel (Disk)** | Kênh ghi backup ra disk |
| **Channel (SBT)** | Kênh ghi backup ra tape qua MML |
| **MML** | Media Management Library — giao tiếp giữa RMAN và tape |

> [!NOTE]
> **Auxiliary Database** sẽ học chi tiết ở Module 15 (Database Duplication).
> **Recovery Catalog** sẽ học chi tiết ở Module 09.

---

### 5. Starting RMAN and Connecting to a Database (Slide 7) ⭐⭐⭐

#### 5.1 Kết nối Local Target Database

```bash
# Cách 1: Đặt ORACLE_SID rồi kết nối (OS Authentication)
export ORACLE_SID=orcl
rman target /

# Output mẫu:
# Recovery Manager: Release 19.0.0.0.0 - Production on Tue Oct 24 10:30:00 2026
# Version 19.3.0.0.0
# Copyright (c) 1982, 2019, Oracle and/or its affiliates.  All rights reserved.
# connected to target database: ORCL (DBID=1534572210)
# RMAN>

# Cách 2: Khởi động RMAN trước, rồi kết nối sau
rman
RMAN> CONNECT TARGET /
```

#### 5.2 Kết nối Remote Target Database

```bash
# Cách 1: Kết nối qua TNS (sẽ hỏi password)
rman target sys@oradb

# Cách 2: Kết nối với password trên command line
rman target sys/oracle@oradb

# Cách 3: Kết nối trong RMAN prompt
rman
RMAN> CONNECT TARGET sys/oracle@oradb
```

```
Local vs Remote Connection:

   Local Connection (OS Auth):
   ┌──────────┐     ORACLE_SID     ┌──────────────┐
   │ RMAN     │ ──────────────────>│ Target DB    │
   │ target / │   (cùng server)    │ (ORCL)       │
   └──────────┘                    └──────────────┘

   Remote Connection (Password Auth):
   ┌──────────┐      TNS/NET       ┌──────────────┐
   │ RMAN     │ ──────────────────>│ Target DB    │
   │ target   │   sys@oradb        │ (ORADB)      │
   │ sys@oradb│   (qua mạng)       │              │
   └──────────┘                    └──────────────┘
```

**Lỗi thường gặp khi kết nối (Troubleshooting):**
- **ORA-01031: insufficient privileges**: Do user Unix/Linux (như `oracle`) không thuộc group `dba`. Giải pháp: Kiểm tra lại quyền của OS user, hoặc user database không có quyền SYSDBA/SYSBACKUP.
- **ORA-12154: TNS:could not resolve the connect identifier specified**: Do sai TNS alias trong lệnh truy cập remote (`@oradb`) hoặc tnsnames.ora cấu hình chưa đúng.
- **RMAN-04005: error from target database:** ORA-01017: invalid username/password: Sai mật khẩu hoặc chưa được cấp quyền đúng.

---

### 6. Connecting as SYSBACKUP (Slide 8)

Theo slides gốc, **SYSBACKUP** privilege:
- Includes permissions for **backup and recovery**, including connect to a **closed database**
- **Does not include data access privileges** — KHÔNG có quyền truy cập dữ liệu user
- Can be explicitly used in RMAN connections by a SYSBACKUP privileged user

```bash
# Kết nối với SYSBACKUP (local)
rman target "'/ as sysbackup'"

# Kết nối với SYSBACKUP (user/password)
rman target "'backupuser/hispass as sysbackup'"
```

> [!TIP]
> **SYSBACKUP vs SYSDBA:**
> - **SYSDBA** = toàn quyền (backup + truy cập data + quản trị)
> - **SYSBACKUP** = chỉ có quyền backup/recovery, **KHÔNG** đọc được data
> 
> Dùng SYSBACKUP khi muốn **tách biệt vai trò** (roles separation) — người phụ trách backup không cần đọc data nhạy cảm.

---

### 7. RMAN Command-line Arguments (Slide 9)

Theo slides, 3 tham số dòng lệnh quan trọng:

```bash
# 1. Ghi output ra LOG file (APPEND = nối thêm, không ghi đè)
rman TARGET / LOG=~/logs/rman/rman.log APPEND

# 2. Chạy command file khi khởi động RMAN
rman TARGET / CMDFILE=~/scripts/my_rman_script.rcvd

# 3. Chạy command file từ trong RMAN prompt
RMAN> @~/scripts/my_rman_script.rcvd
```

| Argument | Mục đích | Ví dụ |
|----------|---------|-------|
| `LOG=<file>` | Ghi output ra file log | `LOG=/tmp/rman.log` |
| `APPEND` | Nối thêm vào log (không ghi đè) | `LOG=/tmp/rman.log APPEND` |
| `CMDFILE=<file>` | Chạy script file khi khởi động | `CMDFILE=backup.rcvd` |
| `@<file>` | Chạy script từ trong RMAN prompt | `@backup.rcvd` |

---

### 8. Types of RMAN Commands (Slide 10-12) ⭐⭐

Slides phân biệt 2 loại lệnh:

#### 8.1 Stand-alone Command
- Executed **individually** at the RMAN prompt — chạy độc lập
- Không cần RUN block

```sql
-- Ví dụ Stand-alone (từ slides):
RMAN> BACKUP DATABASE;

-- Có thể viết nhiều dòng:
RMAN> BACKUP
2>    DATABASE
3>    ;

-- Với comments:
RMAN> # run this command once each day
RMAN> BACKUP INCREMENTAL LEVEL 1
2>    FOR RECOVER OF COPY        # using incrementally updated backups
3>    WITH TAG "DAILY_BACKUP"    # daily backup routine
4>    DATABASE;
```

#### 8.2 Job Command
- **Must be within the braces of a RUN command** — phải nằm trong RUN { }
- Executed **as a group** — chạy cả nhóm cùng lúc

```sql
-- Ví dụ Job Command (từ slides):
RMAN> RUN
2> {
3>    ALLOCATE CHANNEL c1 DEVICE TYPE DISK
4>       FORMAT "/disk2/%U";
5>    BACKUP AS BACKUPSET DATABASE;
6>    SQL 'alter system archive log current';
7> }
```

```
So sánh 2 loại lệnh:

   Stand-alone:                    Job Command:
   ┌─────────────────┐            ┌─────────────────────┐
   │ BACKUP DATABASE;│            │ RUN {               │
   │                 │            │   ALLOCATE CHANNEL; │
   │ (chạy 1 lệnh)  │            │   BACKUP DATABASE;  │
   └─────────────────┘            │   SQL '...';        │
                                  │ }                   │
                                  │ (chạy nhóm lệnh)   │
                                  └─────────────────────┘
```

> [!IMPORTANT]
> **Khi nào dùng RUN { }?**
> - Khi cần **ALLOCATE CHANNEL** thủ công
> - Khi cần chạy **nhiều lệnh liên quan** theo thứ tự
> - Khi cần **thay đổi tạm thời** (override persistent settings)
> 
> **Khi nào KHÔNG cần RUN { }?**
> - Dùng stand-alone nếu chỉ cần chạy 1 lệnh đơn giản
> - RMAN tự allocate channel nếu đã cấu hình persistent settings

**Trong production**: 
Khi quản trị viên cần backup một Data Warehouse lớn ra nhiều tape cùng lúc (Tape library), họ bắt buộc dùng Job Command (RUN block) để cấp phát song song (ALLOCATE) 4-8 tape channels cùng một lúc nhằm giảm thời gian backup window thay vì đợi setting mặc định làm việc.

**Lỗi thường gặp**:
- **RMAN-01009: syntax error: found "identifier": expecting one of: "allocate, alter, backup...**: Thường do bạn thử chạy một lệnh (ví dụ `ALLOCATE CHANNEL`) ở chế độ Stand-alone, trong khi lệnh đó BẮT BUỘC phải đặt trong cặp ngoặc `RUN { }`.

---

### 9. RMAN Persistent Settings (Slide 13-15) ⭐⭐

Theo slides gốc:
- **Persistent settings control the behavior of RMAN** — cấu hình hoạt động của RMAN
- **Configurable by DBA or Backup Administrator** — DBA hoặc admin backup cấu hình
- **They have default values** — có giá trị mặc định
- **Always saved in the control file and in the recovery catalog** — lưu trong control file VÀ recovery catalog

**Ví dụ các settings:**
- Channel parameters
- Parallelism
- Default device type
- Backup retention policy

#### 9.1 Xem Persistent Settings (Slide 14)

```sql
-- Xem TẤT CẢ settings
RMAN> SHOW ALL;

-- Output mẫu:
-- RMAN configuration parameters for database with db_unique_name ORCL are:
-- CONFIGURE RETENTION POLICY TO REDUNDANCY 1; # default
-- CONFIGURE BACKUP OPTIMIZATION OFF; # default
-- CONFIGURE DEFAULT DEVICE TYPE TO DISK; # default
-- CONFIGURE CONTROLFILE AUTOBACKUP ON; # default
-- CONFIGURE CONTROLFILE AUTOBACKUP FORMAT FOR DEVICE TYPE DISK TO '%F'; # default
-- CONFIGURE DEVICE TYPE DISK PARALLELISM 1 BACKUP TYPE TO BACKUPSET; # default
-- CONFIGURE DATAFILE BACKUP COPIES FOR DEVICE TYPE DISK TO 1; # default

-- Xem 1 setting cụ thể
RMAN> SHOW CONTROLFILE AUTOBACKUP FORMAT;
RMAN> SHOW EXCLUDE;

-- Xem bằng SQL (từ SQL*Plus)
SQL> SELECT * FROM V$RMAN_CONFIGURATION;
```

#### 9.2 Thay đổi Persistent Settings (Slide 15)

```sql
-- Dùng CONFIGURE command để thay đổi
RMAN> CONFIGURE DEVICE TYPE sbt PARALLELISM 3;

-- Dùng CLEAR để reset về mặc định
RMAN> CONFIGURE BACKUP OPTIMIZATION CLEAR;
```

```
CONFIGURE Command Flow:

   RMAN> CONFIGURE <setting> <value>;
         │
         ▼
   Lưu vào Control File ──> (và Recovery Catalog nếu có)
         │
         ▼
   Áp dụng cho MỌI lần backup sau đó (persistent)
         │
         ▼
   RMAN> CONFIGURE <setting> CLEAR;  ← Reset về default
```

---

### 10. Issuing Commands to RMAN (Slide 16)

Slides nêu 3 cách sử dụng RMAN:

| Cách | Mô tả | Dùng khi |
|------|--------|---------|
| **Interactive client** | Gõ lệnh trực tiếp tại RMAN prompt | Thao tác 1 lần: phân tích, báo cáo, backup/recovery cụ thể, chạy stored scripts |
| **Batch mode** | Chỉ định command file + log file khi khởi động | **Automated jobs** — chạy tự động hàng ngày |
| **Pipe interface** | Dùng PIPE command-line argument | Giao tiếp giữa sessions hoặc giữa RMAN và ứng dụng bên ngoài |

```bash
# Interactive:
rman target /
RMAN> BACKUP DATABASE;

# Batch mode (dùng với cron/scheduled task):
rman TARGET / CMDFILE=/scripts/daily_backup.rcv LOG=/logs/backup.log APPEND

# Ví dụ file daily_backup.rcv:
# BACKUP INCREMENTAL LEVEL 1 DATABASE;
# DELETE OBSOLETE;
# EXIT;
```

> [!TIP]
> **Trong production**, hầu hết backup chạy ở **Batch mode** kết hợp với **cron job (Linux)** hoặc **Task Scheduler (Windows)**.

---

### 📌 Summary bài 08 (Slide 17)

1. ✅ **Advantages of RMAN**: Incremental backup, block-level recovery, corruption detection, compression, encryption, ASM support
2. ✅ **Terminologies**: Target Database, RMAN Client, Media Management (SBT), Recovery Catalog
3. ✅ **RMAN Components**: Target DB, Auxiliary DB, Recovery Catalog, Channels (Disk/SBT)
4. ✅ **Starting RMAN**: `rman target /` (local), `rman target sys@oradb` (remote)
5. ✅ **SYSBACKUP**: Quyền backup/recovery, không có quyền đọc data
6. ✅ **Command-line arguments**: LOG, APPEND, CMDFILE, @script
7. ✅ **Persistent settings**: SHOW ALL, CONFIGURE, CLEAR

---
---

# 📖 Bài 09: Practice 2 - Introducing RMAN
> 📄 Nguồn: `Practice 2 - Introducing RMAN.pdf` — 6 trang

## 🎯 Mục tiêu thực hành (Practice Target)

> "In this practice you will get familiar with **starting and configuring RMAN**."

### Practice Overview
- Examine the options to **start RMAN** and connect to a target database
- **Set the date and time format** that RMAN uses to display time stamps
- Examine the commands to **display and change RMAN persistent settings**
- Set the **CONTROL_FILE_RECORD_KEEP_TIME** parameter

### Assumptions
- Database **ORADB** is running in **OPEN** state

---

## 📋 Nội dung thực hành

### Phần A: Starting RMAN

#### Bước 1-3: Các cách kết nối RMAN

```bash
# Bước 2: Khởi động RMAN không kết nối
rman

# Bước 3: Kết nối target bằng CONNECT TARGET (OS Authentication)
# → Sử dụng ORACLE_SID hiện tại
# → Sau khi kết nối, DBID sẽ hiển thị
RMAN> CONNECT TARGET /
```

> [!NOTE]
> **DBID** (Database ID) — số định danh duy nhất của database. RMAN hiển thị DBID khi kết nối. Số này **cực kỳ quan trọng** khi cần recovery control file!

#### Bước 5-6: Kết nối trực tiếp từ command line

```bash
# Bước 5: Kết nối local bằng command line
rman target /

# Bước 6: Kết nối remote bằng username/password
rman target sys/oracle@ORADB
```

#### Bước 7-8: Tạo user SYSBACKUP

```sql
-- Bước 7: Tạo user với quyền SYSBACKUP (trong SQL*Plus)
sqlplus / as sysdba

CREATE USER BACKUPOPER IDENTIFIED BY oracle;
GRANT SYSBACKUP TO BACKUPOPER;
GRANT CREATE SESSION TO BACKUPOPER;
```

```bash
# Bước 8: Kết nối RMAN với SYSBACKUP
# → BACKUPOPER chỉ có quyền backup, KHÔNG đọc được data
rman target "'BACKUPOPER/oracle@ORADB as sysbackup'"
```

> [!IMPORTANT]
> Slides nhấn mạnh: *"BACKUPOPER user has only the privileges required to perform backup operations. In an environment where roles separation is enforced, this privilege is granted to the individual who is on charge of taking backups."*
> 
> → Trong môi trường **phân tách vai trò**, người phụ trách backup chỉ nhận quyền SYSBACKUP.

#### Bước 9-11: Ghi log output

```bash
# Bước 9: Khởi động RMAN với LOG output
rman target / log=/tmp/rman.log append

# Bước 10: Chạy lệnh (output KHÔNG hiện trên màn hình → ghi vào log)
RMAN> SHOW ALL;

# Bước 11: Thoát RMAN rồi xem log
exit
cat /tmp/rman.log
```

---

### Phần B: Making Some Configurations for RMAN Operation

#### Bước 12: Đặt NLS_DATE_FORMAT

```bash
# Mở file profile
vi .bash_profile

# Thêm biến môi trường (hiển thị ngày/giờ đầy đủ)
NLS_DATE_FORMAT="YYYY-MM-DD:HH24:MI:SS"; export NLS_DATE_FORMAT
```

> [!TIP]
> **Default format** không hiện phần thời gian. Thêm `NLS_DATE_FORMAT` để RMAN hiển thị **đầy đủ ngày VÀ giờ** — rất cần thiết khi xem timestamps của backup.

#### Bước 13: Cấu hình CONTROLFILE AUTOBACKUP

```sql
-- a. Khởi động RMAN
rman target /

-- b. Xem tất cả settings
RMAN> SHOW ALL;

-- c. Xem setting AUTOBACKUP
RMAN> SHOW CONTROLFILE AUTOBACKUP;
-- Output: CONFIGURE CONTROLFILE AUTOBACKUP ON;  # default
-- ℹ️ Từ Oracle 12.2: mặc định ON. Trước 12.2: mặc định OFF

-- d. Set AUTOBACKUP ON (thay đổi từ default → explicit)
RMAN> CONFIGURE CONTROLFILE AUTOBACKUP ON;

-- e. Xem lại → chữ "default" KHÔNG còn xuất hiện
RMAN> SHOW CONTROLFILE AUTOBACKUP;

-- f. Reset về default
RMAN> CONFIGURE CONTROLFILE AUTOBACKUP CLEAR;

-- g. Xem lại → chữ "default" xuất hiện trở lại
RMAN> SHOW CONTROLFILE AUTOBACKUP;
```

```
CONFIGURE → SHOW → CLEAR Flow:

   SHOW ALL;                      → Xem tất cả (có chữ "default")
       │
   CONFIGURE ... ON;              → Thay đổi (bỏ chữ "default")
       │
   SHOW CONTROLFILE AUTOBACKUP;   → Xem lại (không còn "default")
       │
   CONFIGURE ... CLEAR;           → Reset về mặc định
       │
   SHOW CONTROLFILE AUTOBACKUP;   → Xem lại (có lại "default")
```

---

### Phần C: Setting CONTROL_FILE_RECORD_KEEP_TIME

> [!WARNING]
> Theo Practice: *"If you do not use a recovery catalog database, RMAN keeps record of its produced backup files in the control file. By default, Oracle deletes the entries from the control file that are **older than 7 days**."*
> 
> → Nếu recovery window > 7 ngày, **BẮT BUỘC** phải tăng tham số này!

```sql
-- Bước 14: Tăng CONTROL_FILE_RECORD_KEEP_TIME lên 60 ngày
sqlplus / as sysdba

-- Kiểm tra giá trị hiện tại
SHOW PARAMETER CONTROL_FILE_RECORD_KEEP_TIME
-- NAME                              VALUE
-- --------------------------------- -----
-- control_file_record_keep_time     7      ← Mặc định 7 ngày

-- Thay đổi lên 60 ngày
ALTER SYSTEM SET CONTROL_FILE_RECORD_KEEP_TIME=60 SCOPE=BOTH;
```

| Giá trị | Ý nghĩa | Khi nào dùng |
|---------|---------|-------------|
| **7** (default) | Giữ record 7 ngày | ❌ Quá ngắn cho production |
| **30** | Giữ record 30 ngày | ✅ Tối thiểu cho production |
| **60** | Giữ record 60 ngày | ✅ Theo khuyến nghị khóa học |
| **365** | Giữ record 1 năm | Khi cần giữ lịch sử lâu |

---

### 📌 Summary Practice 2

Tóm tắt theo đúng bài thực hành:
1. ✅ Start RMAN and connect to target databases using **multiple options** (OS auth, password, SYSBACKUP)
2. ✅ Set the **date and time format** (NLS_DATE_FORMAT)
3. ✅ Display and change **RMAN persistent settings** (SHOW, CONFIGURE, CLEAR)
4. ✅ Set the **CONTROL_FILE_RECORD_KEEP_TIME** parameter (7 → 60)

---

# 📊 Bảng tổng hợp Module 03

| Slide/Step | Chủ đề | Kiến thức chính | Lệnh quan trọng |
|------------|--------|-----------------|-----------------|
| 08-S3 | About RMAN | Command-line client, API, MML | `rman` |
| 08-S4 | **RMAN Features** | 8 tính năng: incremental, block-level, compression... | — |
| 08-S5 | **Terminologies** | Target DB, RMAN Client, SBT, Recovery Catalog | — |
| 08-S6 | **Components** | Target, Auxiliary, Catalog, Channel (Disk/SBT) | — |
| 08-S7 | **Connect RMAN** | Local (`target /`), Remote (`target sys@db`) | `rman target /` |
| 08-S8 | **SYSBACKUP** | Backup-only privilege, no data access | `as sysbackup` |
| 08-S9 | **Cmd Arguments** | LOG, APPEND, CMDFILE, @script | `LOG= APPEND CMDFILE=` |
| 08-S10-12 | **Command Types** | Stand-alone vs Job (RUN { }) | `RUN { ... }` |
| 08-S13-15 | **Persistent Settings** | Saved in control file, configurable | `SHOW ALL`, `CONFIGURE`, `CLEAR` |
| 08-S16 | **Issuing Commands** | Interactive, Batch mode, Pipe interface | `CMDFILE=` |
| P2-A | Starting RMAN | 4 cách kết nối, DBID, SYSBACKUP user | `CONNECT TARGET /` |
| P2-B | Config RMAN | NLS_DATE_FORMAT, AUTOBACKUP | `CONFIGURE CONTROLFILE AUTOBACKUP` |
| P2-C | **KEEP_TIME** | Default 7 days → tăng lên 60 | `CONTROL_FILE_RECORD_KEEP_TIME` |

---

# 🎯 Câu hỏi ôn tập tổng hợp

### Câu hỏi lý thuyết

1. **RMAN Features**: Kể 5 tính năng RMAN mà User-Managed Backup KHÔNG có?
2. **4 thuật ngữ RMAN**: Giải thích Target Database, RMAN Client, SBT, Recovery Catalog?
3. **Stand-alone vs Job Command**: Khi nào cần dùng `RUN { }` và khi nào không?
4. **SYSBACKUP vs SYSDBA**: Sự khác biệt? Tại sao cần SYSBACKUP?
5. **Persistent Settings**: Được lưu ở đâu? Cách xem, thay đổi, reset?

### Tình huống thực tế

#### Tình huống 1:
> Bạn cần backup database hàng đêm lúc 2:00 AM tự động trên Linux. Cần ghi log và không yêu cầu người dùng nhập gì. Bạn thiết lập như thế nào?

<details>
<summary>💡 Gợi ý trả lời</summary>

1. Tạo script file `daily_backup.rcv`:
   ```
   BACKUP INCREMENTAL LEVEL 1 DATABASE;
   DELETE OBSOLETE;
   EXIT;
   ```

2. Tạo cron job:
   ```bash
   # crontab -e
   0 2 * * * rman TARGET / CMDFILE=/scripts/daily_backup.rcv LOG=/logs/backup_$(date +\%Y\%m\%d).log
   ```

3. Dùng **Batch mode** với `CMDFILE` + `LOG`
</details>

#### Tình huống 2:
> Bạn check `SHOW ALL` thấy `CONTROLFILE AUTOBACKUP` là OFF (trên Oracle 11g). Tại sao quan trọng phải bật ON?

<details>
<summary>💡 Gợi ý trả lời</summary>

- Khi ON: RMAN tự động backup control file + SPFILE **mỗi lần** chạy BACKUP
- Khi OFF: Nếu mất control file, không có bản backup → recovery rất khó
- Từ Oracle 12.2: mặc định ON. Trước đó: mặc định OFF → **bắt buộc phải bật**
- Lệnh: `CONFIGURE CONTROLFILE AUTOBACKUP ON;`
</details>

#### Tình huống 3:
> Recovery window của bạn là 30 ngày nhưng `CONTROL_FILE_RECORD_KEEP_TIME` vẫn là 7. Điều gì xảy ra?

<details>
<summary>💡 Gợi ý trả lời</summary>

- Sau 7 ngày, Oracle xóa record backup cũ khỏi control file
- RMAN sẽ **không biết** backup nào tồn tại trước 7 ngày
- Khi cần restore từ backup 10 ngày trước → RMAN báo "no backup found"
- Giải pháp: `ALTER SYSTEM SET CONTROL_FILE_RECORD_KEEP_TIME=60 SCOPE=BOTH;`
- Hoặc sử dụng **Recovery Catalog** (Module 09) để lưu vĩnh viễn
</details>

---

## ➡️ Bài tiếp theo

**Module 04: RMAN Full Backups**
- Bài 10: Performing RMAN Full Backups — Part I — Backup sets, image copies, tags
- Bài 11: Practice 3 — Thực hành backup full database
- Bài 12: Performing RMAN Full Backups — Part II — Backup nâng cao
- Bài 13: Practice 4 — Thực hành backup nâng cao

> Bạn muốn **tiếp tục Module 04** hay **ôn lại phần nào** trong Module 03? 😊


---

!!! info "Nguồn gốc"
    `dba_ai/oracle_rman/modules/module_03_guide.md`
