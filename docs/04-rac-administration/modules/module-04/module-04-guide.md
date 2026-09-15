---
title: '📘 Module 04: RAC Basic Administration & Backup'
course: 04-rac-administration
source: The-Oracle-Database-RAC-Administration-Course/modules/module_04/module_04_guide.md
---

# 📘 Module 04: RAC Basic Administration & Backup

> **Section**: 04/14
> **Khóa học**: Oracle Database RAC Administration Course (Ahmed Baraka)
> **Thời gian học ước tính**: 4-5 giờ

---

## 📋 Bài học trong Module

| #   | Bài học                                         | File nguồn                                                  | Loại        |
| --- | ----------------------------------------------- | ----------------------------------------------------------- | ----------- |
| 1   | Oracle RAC Basic Administration                 | `Section 04/Oracle RAC Basic Administration.pdf`            | Lý thuyết   |
| 2   | Managing Backup and Recovery in Oracle RAC      | `Section 04/Managing Backup and Recovery in Oracle RAC.pdf` | Lý thuyết   |
| 3   | Practice 3: Oracle RAC Administration Topics    | `Section 04/Practice 3/`                                    | 🔧 Thực hành |
| 4   | Practice 4: Managing Backup and Recovery        | `Section 04/Practice 4 ...pdf`                              | 🔧 Thực hành |
| 5   | Practice 5: Installing and Using Swingbench 2.5 | `Section 04/Practice 5/`                                    | 🔧 Thực hành |
| 6   | Practice 6: Oracle EM Database Express          | `Section 04/Practice 6 ...pdf`                              | 🔧 Thực hành |

---

## 🎯 Mục tiêu Module

- Start/stop RAC **database** và **instance** bằng `srvctl` và SQL*Plus.
- Chuyển đổi **management policy** AUTOMATIC ↔ MANUAL.
- Nắm các **phương pháp kết nối** tới RAC và điểm đặc thù của chúng.
- Quản lý **initialization parameters** trong RAC (database-level vs instance-level, SPFILE dùng chung).
- Quản lý **Undo** trong RAC.
- **Kill session** trên đúng instance; dùng **GV$** views.
- Hiểu các cân nhắc **Backup & Recovery** trong RAC và dùng **RMAN** (archivelog, snapshot control file, autobackup, parallelism/channels).

---

## 📋 Nội dung chính

### 1. Oracle RAC Basic Administration

> 📄 Nguồn: `Section 04/Oracle RAC Basic Administration.pdf`

#### 1.1 Nguyên tắc Start/Stop

- RAC database **available** khi có **ít nhất một instance** đang chạy.
- Shutdown database = shutdown **tất cả** các instance.
- Công cụ: **EM Cloud Control**, **`srvctl`**, hoặc **SQL*Plus**.

**Cú pháp `srvctl` (start/stop):**

```bash
# Instance
srvctl start|stop instance -db db_unique_name {-node node_name | -instance inst_list}
       [-startoption open|mount|nomount | -stopoption normal|transactional|immediate|abort]

# Database
srvctl start|stop database -db db_unique_name
       [-startoption open|mount|nomount | -stopoption normal|transactional|immediate|abort]
```

**Ví dụ:**

```bash
srvctl start instance -db rac -instance rac1,rac2
srvctl stop  instance -d  rac -i        rac1,rac2
srvctl start database -db rac -startoption mount
srvctl stop  database -db rac -o immediate      # -o = -stopoption
```

**SQL*Plus** chỉ tác động lên **instance hiện tại** (theo `$ORACLE_SID`):

```bash
echo $ORACLE_SID     # rac1
sqlplus / as sysdba
  STARTUP
  SHUTDOWN IMMEDIATE
```

> ⚠️ Trong RAC, `startup` bằng SQL*Plus chỉ mở **instance cục bộ**, không mở cả database. **Luôn ưu tiên `srvctl`.**

#### 1.2 Management Policy (AUTOMATIC / MANUAL)

Clusterware điều khiển việc **tự khởi động lại** database:

- **AUTOMATIC** (mặc định): tự khôi phục database về trạng thái trước đó khi node reboot.
- **MANUAL**: không bao giờ tự khởi động lại.
- **NORESTART**.

```bash
srvctl modify database -db rac -policy [AUTOMATIC | MANUAL | NORESTART]
srvctl config database -db rac -all         # xem policy hiện tại
```

#### 1.3 Các phương pháp kết nối tới RAC

| Phương pháp           | Ví dụ                          | Đặc điểm                                                                                                                      |
| --------------------- | ------------------------------ | ----------------------------------------------------------------------------------------------------------------------------- |
| **OS authentication** | `sqlplus / as sysdba`          | Không cần mật khẩu; cần user thuộc nhóm `dba`; **luôn nối tới instance cục bộ** (`ORACLE_SID`); **ưu tiên hơn** password file |
| **Password file**     | `sqlplus sys/oracle as sysdba` | Dùng credential trong password file                                                                                           |
| **Database auth**     | `sqlplus system/oracle@rac`    | Mật khẩu phải đúng                                                                                                            |

> 💡 Khi dùng `as sysdba`, Oracle đăng nhập là `sys` bất kể username bạn gõ. Kết nối qua **TNS (`@rac`)** đi qua listener và được coi là **client connection** — lúc này password file mới thực sự được kiểm tra.

#### 1.4 Quản lý Initialization Parameters

- Tất cả instance **dùng chung một SPFILE**, đặt trên **shared storage**.
- Tham số có thể set ở **database level** (áp dụng mọi instance) hoặc **instance level**.

```sql
-- áp dụng cho TẤT CẢ instance
ALTER SYSTEM SET param=value SCOPE=[MEMORY|SPFILE|BOTH] SID='*';
-- chỉ cho một instance
ALTER SYSTEM SET param=value SCOPE=[MEMORY|SPFILE|BOTH] SID='rac1';
-- xóa setting khỏi SPFILE
ALTER SYSTEM RESET param SCOPE=SPFILE SID='[*|rac1]';
```

**Tham số RAC-specific:**

| Tham số                      | Ý nghĩa                                |
| ---------------------------- | -------------------------------------- |
| `CLUSTER_DATABASE`           | Luôn = TRUE trong RAC                  |
| `CLUSTER_DATABASE_INSTANCES` | Tổng số instance                       |
| `DB_NAME`                    | ≤ 8 ký tự, **giống nhau** mọi instance |
| `INSTANCE_NAME`              | SID; tự set = db unique name + số      |

- **Phải giống nhau** mọi instance: `COMPATIBLE`, `CONTROL_FILES`, `DB_BLOCK_SIZE`, `DB_NAME`, `DB_UNIQUE_NAME`, `DB_DOMAIN`, `DB_RECOVERY_FILE_DEST(_SIZE)`, `UNDO_MANAGEMENT`, `REMOTE_LOGIN_PASSWORDFILE`, ...
- **Phải khác nhau** mỗi instance: `INSTANCE_NAME`, `INSTANCE_NUMBER`, `UNDO_TABLESPACE`, `CLUSTER_INTERCONNECTS`, `ROLLBACK_SEGMENTS`.

#### 1.5 Automatic Undo Management trong RAC

- Mỗi instance có **undo tablespace riêng** (`UNDO_TABLESPACE`).
- Bình thường **chỉ instance sở hữu mới ghi** vào undo của nó; **mọi instance đều đọc được** mọi undo đang active (phục vụ read-consistency); khi **transaction recovery**, một instance có thể cập nhật undo bất kỳ.

```sql
ALTER SYSTEM SET UNDO_TABLESPACE=undotbs1 SID='rac1';
ALTER SYSTEM SET UNDO_TABLESPACE=undotbs2 SID='rac2';
```

#### 1.6 Kill session trên instance cụ thể & GV$ views

```sql
SELECT SID, SERIAL#, INST_ID FROM GV$SESSION WHERE USERNAME='XYZ';
ALTER SYSTEM KILL SESSION 'sid,serial#,@inst_id';   -- ví dụ '125,698,@2'
-- ORA-00031: session marked for kill  → đã đánh dấu, sẽ kết thúc sau
```

- **GV$** (Global Dynamic Performance Views) = phiên bản toàn cluster của **V$**; cột **`INST_ID`** cho biết instance nào. Hầu hết V$ đều có GV$ tương ứng.

---

### 2. Managing Backup and Recovery in Oracle RAC

> 📄 Nguồn: `Section 04/Managing Backup and Recovery in Oracle RAC.pdf`

#### 2.1 Tư duy nền tảng

> ⚠️ **RAC KHÔNG thay thế cho backup & recovery.** Vẫn phải có chiến lược như single-instance để phòng: lỗi phần cứng, user sửa nhầm dữ liệu, PITR dài hạn, off-site backup, clone production.

#### 2.2 Điểm đặc thù khi dùng RMAN trong RAC

- Về cơ bản **không khác nhiều** single-instance.
- Node thực hiện recovery **phải đọc được** toàn bộ backup + archived redo logs → **lưu backup ở nơi mọi node truy cập được** (khuyến nghị **FRA**). ASM đọc được mà không cần cấu hình thêm.

#### 2.3 Archived Redo Logs trong RAC

- Production nên chạy **ARCHIVELOG**.
- Trong `LOG_ARCHIVE_FORMAT` phải dùng đủ **`%t` (thread), `%s` (sequence), `%r` (resetlogs id)**, ví dụ `arclog_%t_%s_%r.arc`.
- Nếu bật **OMF**, tham số format này **không có tác dụng**.
- Lưu archive log trên **shared storage** để các instance đọc được khi recovery.

#### 2.4 Snapshot Control File

- **Không phải** bản backup control file; RMAN tạo mỗi khi đồng bộ repository hoặc backup control file.
- Mặc định nằm dưới `ORACLE_HOME` (⇒ mỗi node một bản riêng — nguy hiểm khi recovery từ node khác).
- **Khuyến nghị chuyển sang shared storage:**

```sql
SHOW SNAPSHOT CONTROLFILE NAME;
CONFIGURE SNAPSHOT CONTROLFILE NAME TO '+FRA/RAC/AUTOBACKUP/snapcf_rac.f';
```

#### 2.5 Control File & SPFILE Autobackup

```sql
SHOW CONTROLFILE AUTOBACKUP;
CONFIGURE CONTROLFILE AUTOBACKUP ON;
CONFIGURE CONTROLFILE AUTOBACKUP FORMAT FOR DEVICE TYPE DISK TO '+FRA';
```

#### 2.6 RMAN Parallelism / Multiple Channels

Channel có thể nối tới các instance khác nhau:

```sql
-- Thủ công: mỗi channel nối 1 instance
CONFIGURE DEVICE TYPE sbt PARALLELISM 3;
CONFIGURE CHANNEL 1 DEVICE TYPE sbt CONNECT='sys/oracle@rac1';
CONFIGURE CHANNEL 2 DEVICE TYPE sbt CONNECT='sys/oracle@rac2';
CONFIGURE CHANNEL 3 DEVICE TYPE sbt CONNECT='sys/oracle@rac3';

-- Tự động: dùng connect string không xác định node cụ thể
CONFIGURE CHANNEL DEVICE TYPE sbt CONNECT='sys/oracle@bkp_serv';
```

---

### 3. Practice 3: Oracle RAC Administration Topics

> 📄 Nguồn: `Section 04/Practice 3/Practice 03 Oracle RAC Administration Topics.pdf`

**A. Các phương pháp kết nối**

```bash
sqlplus / as sysdba                 # OS auth → luôn nối instance cục bộ (theo ORACLE_SID)
sqlplus sys/wrong as sysdba         # vẫn vào được! OS auth "đè" password file
conn system/wrong                   # DB auth → thất bại vì sai mật khẩu
conn sys/wrong@rac as sysdba        # qua TNS/listener → thất bại (client connection)
# Easy Connect:
conn system/oracle@//srv-scan/rac.localdomain
```

**B. Start/Stop instance & database**

```bash
srvctl status database -d rac
srvctl stop  instance -d rac -i rac1 -o immediate
srvctl stop  instance -d rac -i rac1,rac2 -o immediate
srvctl start database -db rac -startoption open
# Dừng toàn bộ resource của một Oracle Home (tiện trước khi patch):
srvctl stop  home -oraclehome $ORACLE_HOME -statefile ~/rac1_state.dmp -node srv1
srvctl start home -oraclehome $ORACLE_HOME -statefile ~/rac1_state.dmp -node srv1
```

**C. Quản lý tham số (ví dụ `ddl_lock_timeout`)** — quan sát `GV$PARAMETER` (memory) và `V$SPPARAMETER` (SPFILE):

```sql
ALTER SYSTEM SET DDL_LOCK_TIMEOUT=60  SID='*';      -- không SCOPE ⇒ BOTH
ALTER SYSTEM SET DDL_LOCK_TIMEOUT=120 SID='rac1';   -- riêng rac1 (thấy 2 entry trong SPFILE)
ALTER SYSTEM RESET DDL_LOCK_TIMEOUT;                -- xóa entry '*'
ALTER SYSTEM RESET DDL_LOCK_TIMEOUT SID='rac1';     -- xóa entry rac1
```

> 📝 `pfile` tạo từ spfile cho thấy `INSTANCE_NUMBER`, `THREAD`, `UNDO_TABLESPACE` **khác nhau** giữa các instance; `DB_NAME` **giống nhau**.

---

### 4. Practice 4: Managing Backup and Recovery

> 📄 Nguồn: `Section 04/Practice 4 Managing Backup and Recovery in Oracle RAC.pdf`

**A. Bật ARCHIVELOG (quy trình như single-instance):**

```bash
srvctl stop  database -d rac -o immediate
srvctl start database -d rac -o mount
sqlplus / as sysdba
  SELECT INSTANCE_NAME,STATUS FROM GV$INSTANCE;   -- MOUNT
  ALTER SYSTEM SET LOG_ARCHIVE_DEST_1='LOCATION=USE_DB_RECOVERY_FILE_DEST' SCOPE=SPFILE;
  ALTER DATABASE ARCHIVELOG;
srvctl stop database -d rac; srvctl start database -d rac
  ARCHIVE LOG LIST;
```

Switch logfile trên **cả 2 instance** → thấy 2 archive log (thread 1 = rac1, thread 2 = rac2) trong `V$ARCHIVED_LOG`.

**B. Cấu hình RMAN:**

```sql
ALTER SYSTEM SET CONTROL_FILE_RECORD_KEEP_TIME=30 SCOPE=BOTH SID='*';  -- mặc định 7 ngày
CONFIGURE CONTROLFILE AUTOBACKUP ON;
CONFIGURE DEVICE TYPE DISK PARALLELISM 2;      -- bật auto load balancing của RMAN
CONFIGURE RETENTION POLICY TO REDUNDANCY 1;
CONFIGURE SNAPSHOT CONTROLFILE NAME TO '+FRA/RAC/AUTOBACKUP/snapcf_rac.f';
```

**C. Backup & Restore:**

```sql
-- backup
BACKUP DATABASE PLUS ARCHIVELOG TAG FULDB3092017;
LIST BACKUPSET;  DELETE OBSOLETE;

-- restore/recover (parallelism không tác dụng khi recover → cấp channel thủ công)
run {
  ALLOCATE CHANNEL c1 DEVICE TYPE disk CONNECT 'sys/oracle@rac1';
  ALLOCATE CHANNEL c2 DEVICE TYPE disk CONNECT 'sys/oracle@rac2';
  RESTORE DATABASE;
  RECOVER DATABASE;
}
```

> 💡 Có thể lên lịch backup tự động qua **crontab** gọi script RMAN (`backup ... ; backup archivelog all delete input; delete noprompt obsolete;`).

---

### 5. Practice 5: Installing and Using Swingbench 2.5

> 📄 Nguồn: `Section 04/Practice 5/Practice 5 Installing and Using Swingbench 2.5.pdf`

**Swingbench** là công cụ tạo tải (workload generator) trên hosting PC, dùng để **giả lập user OLTP** (schema `soe`). Nó phục vụ cho các bài EM Express (Practice 6) và Monitoring/Tuning (Practice 7) — cần có tải thật để quan sát performance.

---

### 6. Practice 6: Oracle EM Database Express

> 📄 Nguồn: `Section 04/Practice 6 Getting Familiar with Oracle EM Database Express.pdf`

Truy cập: `https://<host>:5500/em` (lấy port: `SELECT DBMS_XDB_CONFIG.GETHTTPSPORT() FROM DUAL;`).

**EM Express là RAC-aware:**

- Trang chủ hiển thị số liệu **toàn database (aggregate)**, real-time **1 giờ gần nhất**; region **Status** cho biết số instance.
- Click **"RAC - N instance(s) up"** để xem theo **từng instance**.
- **Configuration**: Initialization Parameters, Memory (Advisor), Feature Usage, Database Properties.
- **Storage**: Tablespaces, **Undo Management** (undo của mỗi instance), Redo Log Groups, Archive Logs, Control Files.
- **Security**: Users, Roles.
- **Performance → Performance Hub**: real-time (in-memory views) vs historical (AWR). Tab **Activity** (theo Wait Class / User / Module / Action), tab **Workload** (Top SQL), tab **RAC** (Global Cache Blocks Received, Get Time, Instances). Có thể xuất **Active Report** (PerfHub Report).

---

## 🧠 Tóm tắt để nhớ lâu

- **`srvctl`** là công cụ chuẩn để start/stop database/instance/service; SQL*Plus chỉ tác động **instance cục bộ**.
- Management policy **AUTOMATIC** (mặc định) cho Clusterware tự phục hồi database khi reboot.
- **OS auth "đè" password file**; kết nối qua **TNS/listener** mới là client connection thực sự.
- **Một SPFILE dùng chung** trên shared storage; dùng `SID='*'` (mọi instance) hoặc `SID='rac1'`.
- Mỗi instance có **undo tablespace riêng**; dùng **GV$** + `INST_ID` để nhìn toàn cluster.
- **RAC không thay thế backup**. RMAN: bật ARCHIVELOG (đủ `%t %s %r`), chuyển **snapshot control file** + autobackup sang **shared storage/FRA**, dùng **parallelism/channels** đa instance; khi **recover phải cấp channel thủ công**.

---

## 🛠️ Sau khi học xong, hãy tự làm

1. Viết checklist start/stop database & instance bằng `srvctl` (kèm `-startoption`/`-stopoption`).
2. Giải thích vì sao `sqlplus sys/wrong as sysdba` vẫn vào được nhưng `sys/wrong@rac as sysdba` thì không.
3. Thực hành đổi một tham số ở mức `SID='*'` và `SID='rac1'`, quan sát `GV$PARAMETER` vs `V$SPPARAMETER`.
4. Bật ARCHIVELOG cho `rac`, cấu hình snapshot control file + autobackup vào FRA, chạy một backup + restore.
5. Dùng Swingbench tạo tải rồi quan sát tab **RAC** trong EM Express Performance Hub.

---

## ⏭️ Module tiếp theo

**Module 05: Global Resource Management & Performance Tuning** — GRD, mastering/shadowing, Cache Fusion (các scenario block), wait events và tuning RAC.


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-RAC-Administration-Course/modules/module_04/module_04_guide.md`
