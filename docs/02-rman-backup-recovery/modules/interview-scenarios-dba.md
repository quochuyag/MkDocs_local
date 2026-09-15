---
title: 🎯 10 Tình Huống Phỏng Vấn Oracle DBA — Phân tích theo JD
course: 02-rman-backup-recovery
source: Oracle-Database-Backup-and-Recovery-using-RMAN/modules/interview_scenarios_dba.md
---

# 🎯 10 Tình Huống Phỏng Vấn Oracle DBA — Phân tích theo JD

> **Vị trí tham chiếu**: Oracle Database Administrator (Amaris)
> **Nền tảng kiến thức**: 17 modules Oracle RMAN Backup & Recovery (xem [tong_hop_17_modules.md](tong-hop-17-modules.md))
> **Cập nhật**: 2026-07-07
> **Mục tiêu**: Chuẩn bị phỏng vấn — mỗi tình huống gồm *Câu hỏi → Điều nhà tuyển dụng đánh giá → Hướng giải quyết → Liên hệ module*.

---

## 📋 Ánh xạ Yêu cầu công việc (JD) → Tình huống

| # | Yêu cầu JD | Tình huống |
|---|-----------|-----------|
| 1 | Design & implement disaster recovery, backup strategies | DR Design theo RTO/RPO |
| 2 | Shell/Python/PL-SQL automation | Tự động hóa backup + giám sát |
| 3 | Data Guard — high availability | Xây dựng Standby, RPO=0 |
| 4 | Data Pump — data migration | Migrate schema lên môi trường mới |
| 5 | Hybrid environments (on-prem + cloud) | Backup lên OCI + Cross-Platform |
| 6 | Performance tuning (AWR, ADDM) | Backup chậm & tuning DB |
| 7 | Data privacy laws, security compliance | Mã hóa backup + TDE + audit |
| 8 | Support production DBs (Multitenant) | Recover 1 PDB không down CDB |
| 9 | Security monitoring, vulnerabilities | Phát hiện & xử lý corruption/DRA |
| 10 | Automation value, emerging trends | Tối ưu chi phí & tự phục hồi |

---

## 🔥 Tình huống 1 — Thiết kế chiến lược Backup & DR theo SLA

**Câu hỏi phỏng vấn:**
> "Khách hàng có một database OLTP 4TB, yêu cầu **RTO < 15 phút** và **RPO gần bằng 0**. Ngân sách storage giới hạn. Anh sẽ thiết kế chiến lược backup & disaster recovery như thế nào?"

**Nhà tuyển dụng đánh giá:** Khả năng dịch yêu cầu nghiệp vụ (SLA) thành kiến trúc kỹ thuật; hiểu sự đánh đổi giữa RTO/RPO/chi phí.

**Hướng giải quyết (các bước bằng lệnh):**

**Bước 1 — Kiểm tra tiền đề** (ARCHIVELOG, FORCE LOGGING, FRA):
```sql
SQL> ARCHIVE LOG LIST;
SQL> SELECT log_mode, force_logging, flashback_on FROM v$database;
SQL> SHOW PARAMETER db_recovery_file_dest;
```

**Bước 2 — Bật ARCHIVELOG + FORCE LOGGING** (bắt buộc cho hot backup & Data Guard):
```sql
SQL> SHUTDOWN IMMEDIATE;
SQL> STARTUP MOUNT;
SQL> ALTER DATABASE ARCHIVELOG;
SQL> ALTER DATABASE FORCE LOGGING;
SQL> ALTER DATABASE OPEN;
```

**Bước 3 — Cấu hình FRA** đủ chứa image copy + archivelog:
```sql
SQL> ALTER SYSTEM SET db_recovery_file_dest_size = 8T SCOPE=BOTH;
SQL> ALTER SYSTEM SET db_recovery_file_dest = '+FRA'  SCOPE=BOTH;
```

**Bước 4 — Bật Block Change Tracking** (để incremental không quét toàn bộ 4TB):
```sql
SQL> ALTER DATABASE ENABLE BLOCK CHANGE TRACKING USING FILE '/u02/bct/bct.chg';
```

**Bước 5 — Cấu hình RMAN persistent** (retention, autobackup, song song):
```sql
RMAN> CONFIGURE RETENTION POLICY TO RECOVERY WINDOW OF 7 DAYS;
RMAN> CONFIGURE CONTROLFILE AUTOBACKUP ON;
RMAN> CONFIGURE DEVICE TYPE DISK PARALLELISM 4;
```

**Bước 6 — Tạo image copy nền** (chạy 1 lần, đạt RTO thấp cho lỗi media):
```sql
RMAN> BACKUP AS COPY INCREMENTAL LEVEL 0 DATABASE TAG 'daily_merge';
```

**Bước 7 — Script HÀNG ĐÊM: merge incremental vào image copy** (giữ copy luôn mới):
```sql
RMAN> RUN {
  RECOVER COPY OF DATABASE WITH TAG 'daily_merge';
  BACKUP INCREMENTAL LEVEL 1 FOR RECOVER OF COPY WITH TAG 'daily_merge' DATABASE;
}
```

**Bước 8 — Đạt RPO ~0: tạo Physical Standby (Data Guard SYNC)** bằng RMAN không cần down primary:
```sql
RMAN> DUPLICATE TARGET DATABASE FOR STANDBY FROM ACTIVE DATABASE
      DORECOVER SPFILE SET DB_UNIQUE_NAME='oradb_stby';
-- Sau đó trên primary: bật SYNC
SQL> ALTER SYSTEM SET log_archive_dest_2=
     'SERVICE=oradb_stby SYNC AFFIRM VALID_FOR=(ONLINE_LOGFILES,PRIMARY_ROLE) DB_UNIQUE_NAME=oradb_stby';
SQL> ALTER DATABASE SET STANDBY DATABASE TO MAXIMIZE AVAILABILITY;
```

**Bước 9 — Khi có sự cố media: dùng image copy NGAY (RTO vài phút)**, không restore:
```sql
RMAN> RUN {
  SQL 'ALTER DATABASE DATAFILE 4 OFFLINE';
  SWITCH DATAFILE 4 TO COPY;
  RECOVER DATAFILE 4;
  SQL 'ALTER DATABASE DATAFILE 4 ONLINE';
}
```

> **Đánh đổi:** SYNC có thể làm chậm commit ở primary khi mạng trễ cao → chọn `MAXIMIZE AVAILABILITY` (không sập primary khi standby lỗi) thay vì `MAXIMIZE PROTECTION`. Luôn giữ **RMAN song song Data Guard** vì standby lây mọi lỗi logic.

**Liên hệ module:** Module 04 (Image Copy), 05 (Incremental + BCT), 11 (D2D2T, bảng RTO/RPO), 02 (FRA, ARCHIVELOG), 15 (DUPLICATE FOR STANDBY).

---

## 🔥 Tình huống 2 — Tự động hóa Backup & Giám sát (Automation)

**Câu hỏi phỏng vấn:**
> "JD yêu cầu automation bằng Shell/Python. Anh hãy mô tả cách tự động hóa toàn bộ quy trình backup hàng đêm cho 20 database và tự động cảnh báo khi backup thất bại."

**Nhà tuyển dụng đánh giá:** Kỹ năng scripting thực chiến, tư duy vận hành ở quy mô lớn (không làm thủ công), khả năng chủ động phát hiện lỗi.

**Hướng giải quyết (các bước bằng lệnh):**

**Bước 1 — Tạo Global Stored Script trong Recovery Catalog** (một script, dùng cho cả 20 DB):
```sql
$ rman catalog rcowner/pwd@catdb
RMAN> CREATE GLOBAL SCRIPT full_bkp COMMENT 'Nightly standard backup' {
  BACKUP AS COMPRESSED BACKUPSET DATABASE PLUS ARCHIVELOG;
  DELETE NOPROMPT OBSOLETE;
  DELETE NOPROMPT EXPIRED BACKUP;
}
```

**Bước 2 — Wrapper Bash** (chạy qua cron, ghi log, bắt lỗi RMAN-/ORA-):
```bash
#!/bin/bash
# /backup/bin/run_backup.sh — tham số $1 = ORACLE_SID
export ORACLE_SID=$1
LOG=/backup/log/${1}_$(date +%F_%H%M).log

rman target / catalog rcowner/pwd@catdb log=$LOG <<EOF
RUN { EXECUTE GLOBAL SCRIPT full_bkp; }
EOF

# Cảnh báo chủ động nếu có lỗi
if grep -Eq "RMAN-|ORA-" "$LOG"; then
    mail -s "BACKUP FAILED [$1] $(hostname)" dba@company.com < "$LOG"
    exit 1
fi
```

**Bước 3 — Lịch cron cho 20 DB** (mỗi DB một dòng, giãn giờ tránh nghẽn I/O):
```bash
$ crontab -e
0 1 * * *  /backup/bin/run_backup.sh ORADB1
30 1 * * * /backup/bin/run_backup.sh ORADB2
# ... hoặc dùng vòng lặp đọc từ /etc/oratab
```

**Bước 4 — Xác nhận thành công bằng dữ liệu** (không chỉ tin exit code) — query kết quả job:
```sql
SQL> SELECT session_key, input_type, status,
            TO_CHAR(start_time,'DD-MON HH24:MI') start_time,
            output_bytes_display, time_taken_display
     FROM   v$rman_backup_job_details
     WHERE  start_time > SYSDATE - 1
     ORDER  BY start_time DESC;
-- Bất kỳ dòng nào STATUS != 'COMPLETED' → điều tra
```

**Bước 5 — Python giám sát tập trung** (gom trạng thái 20 DB, đẩy cảnh báo):
```python
import oracledb  # python-oracledb
SQL = """SELECT status, COUNT(*) FROM v$rman_backup_job_details
         WHERE start_time > SYSDATE-1 GROUP BY status"""
for db in db_list:                         # danh sách connect string 20 DB
    with oracledb.connect(db.dsn) as con:
        for status, cnt in con.cursor().execute(SQL):
            if status != 'COMPLETED':
                alert_slack(f"{db.name}: {cnt} backup {status}")
```

**Bước 6 — Thay cron OS bằng DBMS_SCHEDULER** (chạy trong DB, không phụ thuộc OS):
```sql
SQL> BEGIN
  DBMS_SCHEDULER.CREATE_JOB(
    job_name        => 'NIGHTLY_RMAN_BACKUP',
    job_type        => 'EXECUTABLE',
    job_action      => '/backup/bin/run_backup.sh',
    number_of_arguments => 1,
    repeat_interval => 'FREQ=DAILY;BYHOUR=1;BYMINUTE=0',
    enabled         => FALSE);
  DBMS_SCHEDULER.SET_JOB_ARGUMENT_VALUE('NIGHTLY_RMAN_BACKUP',1,'ORADB1');
  DBMS_SCHEDULER.ENABLE('NIGHTLY_RMAN_BACKUP');
END;
/
```

> **Nhấn mạnh:** *idempotency* (chạy lại an toàn), *log tập trung*, *cảnh báo chủ động* (không đợi user báo), và xác nhận qua `V$RMAN_BACKUP_JOB_DETAILS` thay vì chỉ exit code.

**Liên hệ module:** Module 09 (Global Stored Scripts), 06 (Persistent settings, DELETE OBSOLETE), 07 (V$RMAN_BACKUP_JOB_DETAILS, monitoring), 08 (Compression).

---

## 🔥 Tình huống 3 — High Availability với Data Guard

**Câu hỏi phỏng vấn:**
> "Production cần zero-downtime khi datacenter chính gặp sự cố. Anh triển khai Data Guard ra sao và làm thế nào để RMAN backup hỗ trợ cho standby?"

**Nhà tuyển dụng đánh giá:** Hiểu HA/DR khác nhau thế nào; vai trò của standby; giảm tải backup khỏi primary.

**Hướng giải quyết (các bước bằng lệnh):**

**Bước 1 — Chuẩn bị primary** (FORCE LOGGING + standby redo logs):
```sql
SQL> ALTER DATABASE FORCE LOGGING;
SQL> ALTER DATABASE ADD STANDBY LOGFILE SIZE 512M;   -- lặp lại, số group = online+1
SQL> ALTER SYSTEM SET standby_file_management=AUTO SCOPE=BOTH;
```

**Bước 2 — Tạo Physical Standby bằng RMAN DUPLICATE** (qua mạng, không down primary):
```sql
$ rman target sys/pwd@oradb_pri auxiliary sys/pwd@oradb_stby
RMAN> DUPLICATE TARGET DATABASE FOR STANDBY FROM ACTIVE DATABASE
      DORECOVER
      SPFILE
        SET DB_UNIQUE_NAME='oradb_stby'
        SET DB_FILE_NAME_CONVERT='/pri/','/stby/'
        SET LOG_FILE_NAME_CONVERT='/pri/','/stby/'
      NOFILENAMECHECK;
```

**Bước 3 — Bật transport & chọn protection mode** (SYNC cho RPO=0):
```sql
-- Trên PRIMARY
SQL> ALTER SYSTEM SET log_archive_dest_2=
     'SERVICE=oradb_stby SYNC AFFIRM VALID_FOR=(ONLINE_LOGFILES,PRIMARY_ROLE) DB_UNIQUE_NAME=oradb_stby';
SQL> ALTER DATABASE SET STANDBY DATABASE TO MAXIMIZE AVAILABILITY;
-- Trên STANDBY: bật apply real-time
SQL> ALTER DATABASE RECOVER MANAGED STANDBY DATABASE USING CURRENT LOGFILE DISCONNECT;
```

**Bước 4 — Kiểm tra đồng bộ** (độ trễ apply/transport):
```sql
SQL> SELECT name, value, unit FROM v$dataguard_stats
     WHERE name IN ('transport lag','apply lag');
SQL> SELECT process, status, sequence# FROM v$managed_standby;
```

**Bước 5 — Offload backup sang standby** (giảm tải I/O primary — backup vẫn dùng được cho primary vì cùng DBID):
```sql
$ rman target / catalog rcowner/pwd@catdb   -- kết nối trên STANDBY
RMAN> BACKUP AS COMPRESSED BACKUPSET DATABASE PLUS ARCHIVELOG;
```

**Bước 6 — Diễn tập failover** (khi datacenter chính chết):
```sql
-- Trên STANDBY
SQL> ALTER DATABASE RECOVER MANAGED STANDBY DATABASE FINISH;
SQL> ALTER DATABASE ACTIVATE STANDBY DATABASE;   -- hoặc dùng DGMGRL: FAILOVER TO oradb_stby;
```

> **Nhấn mạnh:** Data Guard = HA + DR (failover), RMAN = insurance cho **lỗi logic/corruption** mà standby cũng bị lây (DROP nhầm nhân bản ngay). Cần **cả hai**.

**Liên hệ module:** Module 15 (DUPLICATE FOR STANDBY, Active Duplication), 11 (RPO=0 → Data Guard SYNC), 09 (Recovery Catalog cho nhiều DB).

---

## 🔥 Tình huống 4 — Migration bằng Data Pump

**Câu hỏi phỏng vấn:**
> "Cần migrate schema `SALES` (500GB) từ Oracle 19c sang một CDB 21c mới, giảm tối đa downtime. Dùng RMAN hay Data Pump? Vì sao?"

**Nhà tuyển dụng đánh giá:** Phân biệt migration *vật lý* (RMAN) vs *logic* (Data Pump); chọn công cụ đúng bối cảnh; kỹ thuật giảm downtime.

**Hướng giải quyết (các bước bằng lệnh):**

**Bước 1 — Kiểm tra tính khả thi Transportable Tablespace** (self-contained + endian):
```sql
-- Endian nguồn vs đích (cùng Little Endian thì không cần CONVERT)
SQL> SELECT platform_name, endian_format FROM v$transportable_platform
     WHERE platform_name LIKE 'Linux%';
-- Kiểm tra tablespace tự chứa, không tham chiếu ra ngoài
SQL> EXEC DBMS_TTS.TRANSPORT_SET_CHECK('SALES_TBS', TRUE);
SQL> SELECT * FROM transport_violations;   -- rỗng = OK
```

**Bước 2 — (Giảm downtime) Cross-platform incremental** — backup Level 0 khi DB còn READ-WRITE:
```sql
RMAN> BACKUP FOR TRANSPORT INCREMENTAL LEVEL 0
      TABLESPACE sales_tbs FORMAT '/stage/sales_lvl0_%U';
-- Các ngày sau: Level 1 (DB vẫn Read-Write), giảm dữ liệu phải copy lúc cut-over
RMAN> BACKUP FOR TRANSPORT INCREMENTAL LEVEL 1
      TABLESPACE sales_tbs FORMAT '/stage/sales_lvl1_%U';
```

**Bước 3 — Cut-over (downtime tối thiểu): đưa tablespace READ ONLY + export metadata**:
```sql
SQL> ALTER TABLESPACE sales_tbs READ ONLY;
$ expdp system/pwd directory=DP dumpfile=sales_meta.dmp logfile=sales_meta.log \
        transport_tablespaces=SALES_TBS
```

**Bước 4 — Chuyển file + datafile sang server đích** (scp/rsync datafile + dump):
```bash
$ scp /oradata/sales_tbs01.dbf  target:/oradata/
$ scp /stage/sales_meta.dmp     target:/stage/
```

**Bước 5 — Import vào PDB của CDB 21c** (nạp metadata, gắn datafile có sẵn):
```bash
$ impdp system/pwd@cdb21_pdbsales directory=DP dumpfile=sales_meta.dmp \
        transport_datafiles='/oradata/sales_tbs01.dbf' \
        remap_schema=SALES:SALES logfile=imp_sales.log
```

**Bước 6 — Đưa tablespace về READ WRITE + kiểm tra**:
```sql
SQL> ALTER TABLESPACE sales_tbs READ WRITE;
SQL> SELECT COUNT(*) FROM sales.orders;   -- đối chiếu số dòng với nguồn
```

> **Nhấn mạnh:** Data Pump = **logical** (portable, cross-version 19c→21c, chậm nếu export toàn bộ 500GB); Transportable Tablespace = **physical** (nhanh, chỉ export metadata, cần cùng endian hoặc `RMAN CONVERT`). Kết hợp cả hai cho 500GB downtime thấp.

**Liên hệ module:** Module 14 (Cross-Platform Transport, endian, incremental cut-over), 17 (nạp vào PDB của CDB 21c).

---

## 🔥 Tình huống 5 — Hybrid Cloud: Backup lên OCI

**Câu hỏi phỏng vấn:**
> "Công ty muốn giữ backup dài hạn trên Oracle Cloud (OCI) thay vì tape, để tiết kiệm chi phí. Anh triển khai và bảo mật quy trình này thế nào?"

**Nhà tuyển dụng đánh giá:** Kinh nghiệm hybrid (on-prem + cloud) — đúng yêu cầu JD "hybrid environments"; ý thức bảo mật khi data rời khỏi datacenter.

**Hướng giải quyết (các bước bằng lệnh):**

**Bước 1 — Cài Cloud Backup Module** (tải & cài plugin `libopc.so` + wallet OCI):
```bash
$ java -jar oci_install.jar -host https://objectstorage.<region>.oraclecloud.com \
    -pvtKeyFile /home/oracle/oci_api_key.pem -pubFingerPrint <fp> \
    -tOCID <tenancy_ocid> -uOCID <user_ocid> -bucket db-backups \
    -walletDir /opt/oracle/oci/wallet -libDir /opt/oracle/oci/lib -configFile /opt/oracle/oci/opc.ora
```

**Bước 2 — Cấu hình channel SBT trỏ OCI** (persistent):
```sql
RMAN> CONFIGURE CHANNEL DEVICE TYPE sbt
      PARMS 'SBT_LIBRARY=/opt/oracle/oci/lib/libopc.so,
             SBT_PARMS=(OPC_PFILE=/opt/oracle/oci/opc.ora)';
RMAN> CONFIGURE DEVICE TYPE sbt PARALLELISM 4;
```

**Bước 3 — Chuẩn bị mã hóa (BẮT BUỘC với data rời on-prem)** — chọn Password mode cho off-site:
```sql
RMAN> CONFIGURE ENCRYPTION FOR DATABASE ON;         -- bật mã hóa persistent
RMAN> SET ENCRYPTION ON IDENTIFIED BY 'StrongPass#2026' ONLY;
```

**Bước 4 — Backup nén + mã hóa lên OCI** (giảm chi phí storage & băng thông):
```sql
RMAN> BACKUP AS COMPRESSED BACKUPSET DEVICE TYPE sbt
      DATABASE PLUS ARCHIVELOG TAG 'OCI_LONGTERM';
```

**Bước 5 — Xác minh & liệt kê backup trên cloud**:
```sql
RMAN> LIST BACKUP SUMMARY DEVICE TYPE sbt;
RMAN> RESTORE DATABASE VALIDATE DEVICE TYPE sbt;   -- kiểm tra restore được, không ghi file
```

**Bước 6 — Kiến trúc hybrid** (giữ RTO nhanh local, dài hạn lên cloud):
```sql
-- Backup ngắn hạn xuống FRA local (RTO nhanh)
RMAN> BACKUP DEVICE TYPE DISK DATABASE;
-- Backup dài hạn KEEP lên OCI cho compliance
RMAN> BACKUP DEVICE TYPE sbt DATABASE KEEP UNTIL TIME 'SYSDATE+365' TAG 'OCI_1YEAR';
```

> **Nhấn mạnh:** encryption là **non-negotiable** khi data ra khỏi biên giới mạng; cloud backup **chỉ dùng Backup Sets** (không Image Copy); kiểm soát chi phí bằng lifecycle policy/storage tiering trên OCI. Đây là D2D2**C** (Disk→Disk→Cloud) thay cho tape.

**Liên hệ module:** Module 17 (Cloud, libopc.so, bắt buộc mã hóa), 10 (Encryption modes), 08 (Compression), 11 (D2D2T).

---

## 🔥 Tình huống 6 — Backup chậm & Performance Tuning (AWR/ADDM)

**Câu hỏi phỏng vấn:**
> "Backup hàng đêm trước đây chạy 3 tiếng, giờ kéo dài 9 tiếng và tràn sang giờ làm việc. Anh chẩn đoán và xử lý thế nào?"

**Nhà tuyển dụng đánh giá:** Kỹ năng troubleshooting có phương pháp; dùng AWR/ADDM; tối ưu I/O — đúng JD "performance tuning".

**Hướng giải quyết (các bước bằng lệnh):**

**Bước 1 — Đo tiến độ realtime** (backup đang kẹt ở đâu):
```sql
SQL> SELECT sid, serial#, opname,
            ROUND(sofar/totalwork*100,2) pct_done,
            ROUND(time_remaining/60,1) min_left
     FROM   v$session_longops
     WHERE  opname LIKE 'RMAN%' AND totalwork != 0 AND sofar != totalwork;
```

**Bước 2 — Xác định nghẽn ở tape hay disk** (so tỷ lệ EFFECTIVE I/O):
```sql
-- Nếu LONG_WAITS/IO_COUNT cao ở kênh nào → kênh đó là nút thắt
SQL> SELECT type, device_type, num_waits, ROUND(total_time_waited/100,1) wait_s,
            effective_bytes_per_second/1024/1024 mb_per_s
     FROM   v$backup_async_io ORDER BY wait_s DESC;
```

**Bước 3a — Nếu tape I/O chậm** → bật async slaves:
```sql
SQL> ALTER SYSTEM SET backup_tape_io_slaves = TRUE SCOPE=SPFILE;   -- cần restart
```

**Bước 3b — Nếu datafile lớn chạy đơn luồng** → Multisection song song:
```sql
RMAN> CONFIGURE DEVICE TYPE DISK PARALLELISM 4;
RMAN> BACKUP SECTION SIZE 20G DATABASE;   -- cắt datafile lớn thành pieces chạy //
```

**Bước 4 — Giảm KHỐI LƯỢNG phải backup** (bật BCT + nén):
```sql
SQL>  ALTER DATABASE ENABLE BLOCK CHANGE TRACKING USING FILE '/u02/bct/bct.chg';
RMAN> BACKUP AS COMPRESSED BACKUPSET INCREMENTAL LEVEL 1 DATABASE;
```

**Bước 5 — Giới hạn cửa sổ thời gian** (không tràn giờ làm việc, chạy dở tiếp đêm sau):
```sql
RMAN> BACKUP DATABASE NOT BACKED UP SINCE 'SYSDATE-3'
      DURATION 07:00 PARTIAL MINIMIZE TIME;
```

**Bước 6 — Đối chiếu với AWR/ADDM** (loại trừ DB bị contention trong cửa sổ backup):
```sql
SQL> @?/rdbms/admin/awrrpt.sql     -- đọc Top Foreground Events cho window backup
SQL> @?/rdbms/admin/addmrpt.sql    -- ADDM tự đề xuất nút thắt
```

> **Nhấn mạnh:** *đọc error stack từ dưới lên*, **đo trước khi tối ưu**. Nguyên nhân phổ biến của backup phình giờ: dữ liệu tăng nhưng vẫn full backup mỗi đêm → chuyển sang incremental + BCT; hoặc BCT bị disable/ chưa bật.

**Liên hệ module:** Module 16 (Performance Tuning, TAPE_IO_SLAVES, DURATION, troubleshooting), 08 (Multisection, Compression), 05 (BCT), 07 (V$SESSION_LONGOPS).

---

## 🔥 Tình huống 7 — Bảo mật & Tuân thủ quyền riêng tư (Compliance)

**Câu hỏi phỏng vấn:**
> "Do quy định bảo vệ dữ liệu (GDPR/data privacy), toàn bộ backup phải được mã hóa và phải chứng minh được ai truy cập backup. Anh đáp ứng thế nào?"

**Nhà tuyển dụng đánh giá:** Ý thức compliance & data privacy law (JD nêu rõ); kiến thức TDE, encryption, audit.

**Hướng giải quyết (các bước bằng lệnh):**

**Bước 1 — Tạo & mở TDE Keystore** (nền tảng cho mã hóa):
```sql
SQL> ADMINISTER KEY MANAGEMENT CREATE KEYSTORE '/etc/oracle/wallet' IDENTIFIED BY "Wallet#Pwd";
SQL> ADMINISTER KEY MANAGEMENT SET KEYSTORE OPEN IDENTIFIED BY "Wallet#Pwd";
SQL> ADMINISTER KEY MANAGEMENT SET KEY IDENTIFIED BY "Wallet#Pwd" WITH BACKUP;
-- Auto-login để job tự chạy không cần nhập pass
SQL> ADMINISTER KEY MANAGEMENT CREATE AUTO_LOGIN KEYSTORE FROM KEYSTORE '/etc/oracle/wallet' IDENTIFIED BY "Wallet#Pwd";
```

**Bước 2 — Tạo tài khoản backup least-privilege** (SYSBACKUP, không đọc được data user):
```sql
SQL> CREATE USER bkpadmin IDENTIFIED BY "Bkp#Pwd";
SQL> GRANT SYSBACKUP TO bkpadmin;
$ rman target '"bkpadmin AS SYSBACKUP"'
```

**Bước 3 — Chọn encryption mode theo đích đến:**

| Mode | Lệnh | Dùng khi |
|------|------|---------|
| Transparent | `SET ENCRYPTION ON;` | Backup on-site hàng ngày (key tự lấy từ keystore) |
| Password ONLY | `SET ENCRYPTION ON IDENTIFIED BY p ONLY;` | Gửi off-site / bên thứ ba |
| Dual | `SET ENCRYPTION ON IDENTIFIED BY p;` | Cần cả hai phương án |

**Bước 4 — Backup mã hóa** (ví dụ Dual mode cho vừa on-site vừa off-site):
```sql
RMAN> CONFIGURE ENCRYPTION FOR DATABASE ON;
RMAN> SET ENCRYPTION ON IDENTIFIED BY "Offsite#Pwd";
RMAN> BACKUP AS COMPRESSED BACKUPSET DATABASE PLUS ARCHIVELOG;
```

**Bước 5 — Bật audit truy vết ai RESTORE/DELETE backup** (Unified Auditing cho compliance):
```sql
SQL> CREATE AUDIT POLICY rman_ops_pol ACTIONS ALL;   -- hoặc lọc theo user bkpadmin
SQL> AUDIT POLICY rman_ops_pol;
SQL> SELECT dbusername, action_name, event_timestamp
     FROM   unified_audit_trail WHERE dbusername='BKPADMIN' ORDER BY event_timestamp DESC;
```

**Bước 6 — Giữ backup dài hạn cho compliance** (không bị obsolete):
```sql
RMAN> BACKUP DATABASE KEEP UNTIL TIME 'SYSDATE+1825'   -- 5 năm
      RESTORE POINT RP_COMPLIANCE_2026 TAG 'COMPLIANCE_2026';
```

**Bước 7 — Sao lưu keystore & lưu Catalog** (mất key = mất backup):
```bash
$ cp -r /etc/oracle/wallet /secure/offsite/wallet_backup_$(date +%F)
```

> **Nhấn mạnh:** encryption **chỉ dùng với Backup Sets** (không Image Copy); quản lý key an toàn quan trọng hơn thuật toán — **mất key = mất backup vĩnh viễn**; SYSBACKUP thực thi nguyên tắc least-privilege.

**Liên hệ module:** Module 10 (Encryption modes, keystore), 03 (SYSBACKUP least privilege), 08 (KEEP Archival), 09 (Catalog lưu lịch sử).

---

## 🔥 Tình huống 8 — Multitenant: Recover 1 PDB không ảnh hưởng CDB

**Câu hỏi phỏng vấn:**
> "Trong một CDB có 30 PDB, một PDB `HR` bị hỏng datafile lúc 2h chiều giờ cao điểm. Làm sao khôi phục `HR` mà không down 29 PDB còn lại?"

**Nhà tuyển dụng đánh giá:** Kiến thức kiến trúc Multitenant (19c/21c — đúng JD); khả năng cô lập sự cố, giảm blast radius.

**Hướng giải quyết (các bước bằng lệnh):**

**Bước 1 — Xác định mức độ hỏng** (cả datafile hay chỉ vài block):
```sql
$ rman target /
RMAN> VALIDATE PLUGGABLE DATABASE hr;
SQL>  SELECT file#, block#, blocks FROM v$database_block_corruption;
SQL>  SELECT name, status FROM v$datafile WHERE con_id=(SELECT con_id FROM v$pdbs WHERE name='HR');
```

**Bước 2a — Nếu hỏng cả datafile: restore/recover ở cấp PDB** (29 PDB khác vẫn chạy):
```sql
RMAN> ALTER PLUGGABLE DATABASE hr CLOSE;
RMAN> RESTORE PLUGGABLE DATABASE hr;
RMAN> RECOVER PLUGGABLE DATABASE hr;
RMAN> ALTER PLUGGABLE DATABASE hr OPEN;
```

**Bước 2b — Nếu chỉ hỏng vài block: Block Media Recovery** (PDB vẫn ONLINE, downtime ~0):
```sql
RMAN> RECOVER DATAFILE 25 BLOCK 130;
RMAN> RECOVER CORRUPTION LIST;   -- sửa mọi block trong v$database_block_corruption
```

**Bước 3 — Nếu là user error trong HR (DROP nhầm): PITR cấp PDB** (không đụng PDB khác):
```sql
RMAN> RUN {
  ALTER PLUGGABLE DATABASE hr CLOSE;
  SET UNTIL TIME "TO_DATE('2026-07-07 13:55:00','YYYY-MM-DD HH24:MI:SS')";
  RESTORE PLUGGABLE DATABASE hr;
  RECOVER PLUGGABLE DATABASE hr AUXILIARY DESTINATION '/u02/auxdest';
  ALTER PLUGGABLE DATABASE hr OPEN RESETLOGS;
}
```

**Bước 4 — Xác minh sau phục hồi**:
```sql
SQL> ALTER SESSION SET CONTAINER=hr;
SQL> SELECT status, open_mode FROM v$pdbs WHERE name='HR';
RMAN> VALIDATE PLUGGABLE DATABASE hr;
```

> **Nhấn mạnh:** kết nối **đúng container** — backup từ CDB Root bao trọn 30 PDB, nhưng recover thì trỏ đúng PDB `hr`. Lợi thế Multitenant là **cô lập sự cố**: một PDB hỏng không kéo sập CDB — khác biệt lớn so với non-CDB.

**Liên hệ module:** Module 17 (CDB/PDB backup, RESTORE/RECOVER PLUGGABLE DATABASE, PDB PITR), 13 (Block Media Recovery, VALIDATE), 12 (PITR).

---

## 🔥 Tình huống 9 — Security Monitoring: Phát hiện & xử lý Corruption

**Câu hỏi phỏng vấn:**
> "Ứng dụng báo lỗi `ORA-01578: data block corrupted`. Anh xử lý sự cố này và làm sao chủ động phát hiện corruption trước khi user gặp lỗi?"

**Nhà tuyển dụng đánh giá:** Xử lý sự cố production dưới áp lực; tư duy *proactive monitoring* (JD: "security features and vulnerabilities", "monitoring").

**Hướng giải quyết (các bước bằng lệnh):**

**Bước 1 — Khoanh vùng block hỏng** (từ ORA-01578 đọc ra file# và block#):
```sql
SQL> SELECT * FROM v$database_block_corruption;   -- FILE#, BLOCK#, BLOCKS, CORRUPTION_TYPE
-- Từ file#/block# → tìm object bị ảnh hưởng
SQL> SELECT segment_name, segment_type, owner
     FROM   dba_extents
     WHERE  file_id = &file# AND &block# BETWEEN block_id AND block_id+blocks-1;
```

**Bước 2 — Reactive (cách A): Data Recovery Advisor tự chẩn đoán & sửa** (non-RAC):
```sql
$ rman target /
RMAN> LIST FAILURE;
RMAN> ADVISE FAILURE;
RMAN> REPAIR FAILURE PREVIEW;   -- xem RMAN định làm gì trước
RMAN> REPAIR FAILURE;
RMAN> CHANGE FAILURE ... CLOSED;
```

**Bước 3 — Reactive (cách B): Block Media Recovery thủ công** (DB vẫn ONLINE — dùng cho RAC vì DRA không hỗ trợ RAC):
```sql
RMAN> RECOVER DATAFILE 6 BLOCK 14;
RMAN> RECOVER CORRUPTION LIST;   -- sửa mọi block trong v$database_block_corruption
```

**Bước 4 — Xác minh đã sạch**:
```sql
RMAN> VALIDATE DATAFILE 6;
SQL>  SELECT COUNT(*) FROM v$database_block_corruption;   -- kỳ vọng = 0
```

**Bước 5 — Proactive: bật cơ chế Oracle tự phát hiện corruption sớm**:
```sql
SQL> ALTER SYSTEM SET db_block_checksum = TYPICAL SCOPE=BOTH;
SQL> ALTER SYSTEM SET db_block_checking = MEDIUM  SCOPE=BOTH;
SQL> ALTER SYSTEM SET db_lost_write_protect = TYPICAL SCOPE=BOTH;
```

**Bước 6 — Proactive: job quét định kỳ + cảnh báo tự động**:
```sql
-- Quét cả corruption vật lý & logic (lịch chạy hàng đêm qua DBMS_SCHEDULER)
RMAN> VALIDATE CHECK LOGICAL DATABASE;
-- Job cảnh báo khi phát hiện block hỏng
SQL> SELECT * FROM v$database_block_corruption;   -- nếu có dòng → gửi mail/Slack
```

> **Nhấn mạnh:** DRA **không hỗ trợ RAC** → RAC phải dùng BMR thủ công (Bước 3). Giám sát chủ động (VALIDATE định kỳ + alert) biến sự cố bất ngờ thành bảo trì có kế hoạch.

**Liên hệ module:** Module 13 (DRA: LIST/ADVISE/REPAIR, BMR, VALIDATE, lưu ý RAC), 07 (Monitoring, CROSSCHECK).

---

## 🔥 Tình huống 10 — User Error: DROP TABLE nhầm trên Production

**Câu hỏi phỏng vấn:**
> "Lúc 10h sáng, một dev vô tình `DROP TABLE HR.SALARY` (đã commit) trên production. Anh khôi phục *chỉ mỗi bảng đó* mà không ảnh hưởng dữ liệu các bảng khác đã thay đổi từ 10h?"

**Nhà tuyển dụng đánh giá:** Phân biệt các loại recovery cho user error; chọn giải pháp *ít tác động nhất* thay vì restore cả DB.

**Hướng giải quyết (các bước bằng lệnh — thang từ nhẹ đến nặng):**

**Bước 0 — KHÔNG restore cả DB** (sẽ xóa mọi thay đổi sau 10h của các bảng khác). Kiểm tra tài nguyên còn dùng được không:
```sql
SQL> SHOW RECYCLEBIN;                              -- bảng còn trong recycle bin?
SQL> SELECT retention FROM dba_tablespaces WHERE tablespace_name='UNDOTBS1';
SQL> SELECT flashback_on FROM v$database;
```

**Bước 1 — Ưu tiên 1: Flashback** (nhanh nhất, vài giây, blast radius nhỏ nhất):
```sql
-- Nếu còn trong recycle bin (DROP chưa PURGE)
SQL> FLASHBACK TABLE HR.SALARY TO BEFORE DROP;
-- Nếu đã PURGE nhưng undo còn giữ: dựng lại từ Flashback Query
SQL> CREATE TABLE HR.SALARY_RESTORE AS
     SELECT * FROM HR.SALARY AS OF TIMESTAMP (SYSTIMESTAMP - INTERVAL '30' MINUTE);
```

**Bước 2 — Ưu tiên 2: RMAN Table Recovery** (khi đã purge & hết undo — cần backup + archivelog):
```sql
$ rman target /
RMAN> RECOVER TABLE HR.SALARY
      UNTIL TIME "TO_DATE('2026-07-07 09:55:00','YYYY-MM-DD HH24:MI:SS')"
      AUXILIARY DESTINATION '/u02/auxdest'
      REMAP TABLE HR.SALARY:HR.SALARY_RECOVERED;
-- RMAN tự dựng auxiliary instance → restore → export bảng → import lại, KHÔNG đụng bảng khác
```

**Bước 3 — Ưu tiên 3: TSPITR** (khi cần khôi phục nhiều object trong 1 tablespace về quá khứ):
```sql
RMAN> RECOVER TABLESPACE hr_data
      UNTIL TIME "TO_DATE('2026-07-07 09:55:00','YYYY-MM-DD HH24:MI:SS')"
      AUXILIARY DESTINATION '/u02/auxdest';
```

**Bước 4 — Đối chiếu trước khi thay bảng thật** (tránh ghi đè nhầm nếu recover sai thời điểm):
```sql
SQL> SELECT COUNT(*) FROM HR.SALARY_RECOVERED;
SQL> -- Sau khi xác nhận đúng: RENAME hoặc INSERT ngược lại bảng gốc
```

> **Nhấn mạnh:** thang giải pháp Flashback → Table Recovery → TSPITR → PITR cả DB (cuối cùng). Luôn chọn *blast radius* nhỏ nhất; luôn REMAP sang tên khác để đối chiếu, không import đè thẳng.

**Liên hệ module:** Module 12 (Table Recovery, TSPITR, PITR, RESTORE/RECOVER, Flashback), 13 (chọn đúng phương pháp theo loại failure).

---

## 🧠 Mẹo trả lời phỏng vấn (áp dụng chung)

1. **Luôn hỏi lại RTO/RPO/ngân sách trước khi đề xuất giải pháp** — thể hiện tư duy nghiệp vụ, không nhảy vào kỹ thuật ngay.
2. **Nêu sự đánh đổi (trade-off)** — mọi giải pháp đều có giá; nhà tuyển dụng đánh giá cao người biết *tại sao chọn A thay B*.
3. **Phân biệt các cặp khái niệm hay bị hỏi bẫy:**
   - `RESTORE` (lấy file ra) ≠ `RECOVER` (apply redo/archive).
   - `Complete` (đến hiện tại) ≠ `Incomplete/PITR` (đến quá khứ, phải RESETLOGS).
   - `EXPIRED` (mất file vật lý) ≠ `OBSOLETE` (quá hạn retention).
   - `Backup Set` (nén/mã hóa được) ≠ `Image Copy` (SWITCH ngay).
   - HA (Data Guard) ≠ Backup (RMAN) — cần **cả hai**.
4. **Nhấn mạnh proactive** — giám sát chủ động, tự động hóa, cảnh báo sớm > chữa cháy.
5. **Kết nối on-prem ↔ cloud** — JD nhấn mạnh hybrid; luôn nêu phương án cloud (OCI) khi hợp lý.

---

*Phần 1 ánh xạ kiến thức 17 module RMAN sang yêu cầu thực tế của vị trí Oracle DBA. Xem chi tiết kỹ thuật từng chủ đề tại `modules/module_XX/module_XX_guide.md` và các kịch bản thực hành trong `reviews_all/`.*

---
---

# 🚀 PHẦN 2 — 5 Tình Huống Performance Tuning

> **Nguồn kiến thức**: The Oracle Database Performance Tuning Course — Senior DBA guides (`section_all_new/`)
> **Đáp ứng JD**: *"performance tuning (AWR, ADDM)"* và *"Identify and act on automation opportunities to improve performance"*
> **Nguyên tắc xuyên suốt**: Đo trước, sửa sau. Không đoán mò. Luôn dùng **DB Time method** — tối ưu thứ chiếm nhiều DB Time nhất, không tối ưu cái mình "đoán" là chậm.

## 📋 Ánh xạ chủ đề → Tình huống Tuning

| # | Triệu chứng | Kỹ năng chính | Section nguồn |
|---|------------|--------------|--------------|
| T1 | "DB chậm" mơ hồ | Triage bằng AWR Load Profile + DB Time method | 6, 8, 9 |
| T2 | SQL đột nhiên chậm | Plan regression + SQL Plan Baseline (SPM) | 9, 13 |
| T3 | Nhiều session treo | Blocking chain + library cache lock cascade | 13, 19, 21 |
| T4 | Ứng dụng chậm khi đọc | I/O bottleneck + hot block + missing index | 22, 26, 27 |
| T5 | Commit chậm | `log file sync` + redo path tuning | 24 |

---

## 🔧 Tình huống T1 — "Database chậm", không có thông tin gì thêm

**Câu hỏi phỏng vấn:**
> "Sếp gọi lúc 3h chiều: 'Database chậm, khách hàng phàn nàn'. Không có thêm chi tiết nào. Anh làm gì trong 10 phút đầu tiên?"

**Nhà tuyển dụng đánh giá:** Có **phương pháp luận** hay không (đây là câu hỏi lọc ứng viên quan trọng nhất). Junior đi đoán mò; senior dùng framework đo lường.

**Hướng giải quyết (các bước bằng lệnh):**

**Bước 1 — Chụp nhanh hoạt động realtime** (đang chờ gì ngay lúc này):
```sql
SQL> SELECT wait_class, COUNT(*) sessions
     FROM   v$session WHERE status='ACTIVE' AND wait_class != 'Idle'
     GROUP  BY wait_class ORDER BY sessions DESC;
```

**Bước 2 — Mini-AWR từ ASH: DB Time breakdown theo event** (30 phút gần nhất):
```sql
SQL> SELECT NVL(event,'ON CPU') event, COUNT(1) samples,
            ROUND(COUNT(1)/SUM(COUNT(1)) OVER ()*100,2) pct_dbtime
     FROM   v$active_session_history
     WHERE  session_type='FOREGROUND'
       AND  sample_time >= SYSTIMESTAMP - INTERVAL '30' MINUTE
     GROUP  BY NVL(event,'ON CPU') ORDER BY samples DESC FETCH FIRST 15 ROWS ONLY;
```

**Bước 3 — Khoanh vùng thủ phạm theo MODULE rồi SQL_ID**:
```sql
SQL> SELECT sql_id, sql_plan_hash_value, COUNT(1) dbtime_samples
     FROM   v$active_session_history
     WHERE  session_type='FOREGROUND' AND sql_id IS NOT NULL
       AND  sample_time >= SYSTIMESTAMP - INTERVAL '30' MINUTE
     GROUP  BY sql_id, sql_plan_hash_value
     ORDER  BY dbtime_samples DESC FETCH FIRST 10 ROWS ONLY;
```

**Bước 4 — Nếu sự cố kéo dài/lặp lại: sinh AWR report + phân loại CPU vs Wait**:
```sql
SQL> @?/rdbms/admin/awrrpt.sql
-- Đọc theo thứ tự ưu tiên: (1) Top 10 Foreground Events → (2) Load Profile → (3) Top SQL
-- Phân loại từ header:  DB Time ≈ #CPU × Elapsed  → CPU-bound
--                        DB Time >> #CPU × Elapsed → Wait-bound
SQL> @?/rdbms/admin/addmrpt.sql    -- ADDM tự chỉ nút thắt + khuyến nghị
```

> **Nhấn mạnh:** wait class chủ đạo quyết định hướng đi tiếp: **User I/O → T4**, **Concurrency → T3**, **Commit → T5**, **CPU → T2**. AWR cho sự cố > 30 phút; ASH cho sự cố thoáng qua < 30 phút. *"Tôi để dữ liệu dẫn đường, không mang định kiến vào."*

**Liên hệ section:** 6 (Time Model, DB Time), 8 (Wait Events), 9 (AWR reading order, DB Time/CPU ratio), 13 (ASH real-time).

---

## 🔧 Tình huống T2 — SQL đột nhiên chậm gấp 20 lần (Plan Regression)

**Câu hỏi phỏng vấn:**
> "Một report query sáng nay chạy 2 giây, chiều nay chạy 40 giây, dù không ai đổi code. Anh chẩn đoán và xử lý thế nào, và làm sao ngăn tái diễn?"

**Nhà tuyển dụng đánh giá:** Hiểu Optimizer/execution plan; biết plan có thể đổi mà không đổi SQL; biết công cụ ổn định plan (SPM) — dấu hiệu senior thực thụ.

**Hướng giải quyết (các bước bằng lệnh):**

**Bước 1 — Xác nhận plan regression** (cùng SQL_ID, khác PLAN_HASH_VALUE, thời gian nhảy vọt):
```sql
SQL> SELECT snap_id, plan_hash_value, executions_delta,
            ROUND(elapsed_time_delta/1e6/NULLIF(executions_delta,0),3) sec_per_exec
     FROM   dba_hist_sqlstat WHERE sql_id='&sql_id' ORDER BY snap_id;
-- sec_per_exec tăng vọt đúng lúc plan_hash_value đổi = confirmed regression
```

**Bước 2 — So sánh plan cũ (tốt) vs mới (xấu)** — tìm chỗ hồi quy (thường FULL SCAN thay INDEX):
```sql
SQL> SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY_AWR('&sql_id', &good_plan_hash, NULL, 'BASIC'));
SQL> SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY_AWR('&sql_id', &bad_plan_hash,  NULL, 'BASIC'));
```

**Bước 3 — Truy nguyên nhân plan đổi** (stats mới? histogram? index?):
```sql
-- Có gather stats gần đây trên bảng liên quan không?
SQL> SELECT table_name, last_analyzed, num_rows FROM dba_tables
     WHERE table_name IN ('CUSTOMERS','ORDERS') AND owner='SALES';
SQL> SELECT operation, target, start_time FROM dba_optstat_operations
     WHERE start_time > SYSDATE-1 ORDER BY start_time DESC;
```
> ≥3 trigger cần nêu: (1) auto gather stats đổi cardinality, (2) bind peeking/ACS với bind lệch (data skew), (3) thêm/mất index hoặc dữ liệu vượt ngưỡng, patch optimizer.

**Bước 4 — Sửa NHANH (immediate): ép lại plan tốt bằng SQL Plan Baseline (SPM)**:
```sql
SQL> VAR n NUMBER;
SQL> EXEC :n := DBMS_SPM.LOAD_PLANS_FROM_AWR( -
       begin_snap => &good_begin, end_snap => &good_end, -
       basic_filter => q'[sql_id='&sql_id' and plan_hash_value=&good_plan_hash]');
-- Kiểm tra baseline đã ENABLED + ACCEPTED
SQL> SELECT sql_handle, plan_name, enabled, accepted FROM dba_sql_plan_baselines
     WHERE sql_text LIKE '%&keyword%';
```

**Bước 5 — Sửa GỐC (permanent) theo nguyên nhân**:
```sql
-- Nếu do stats bất ổn: khóa stats đã tốt
SQL> EXEC DBMS_STATS.LOCK_TABLE_STATS('SALES','ORDERS');
-- Nếu do thiếu histogram cho cột lệch:
SQL> EXEC DBMS_STATS.GATHER_TABLE_STATS('SALES','ORDERS', -
       method_opt=>'FOR COLUMNS SIZE 254 REGION_CODE');
-- Nếu do thiếu index: tạo index phù hợp (sau khi kiểm chứng bằng plan)
```

> **Nhấn mạnh:** tách **immediate fix** (SPM ép plan — an toàn ngay) vs **root fix** (stats/histogram/index). Tránh phản xạ "kill session"/"flush shared pool" — chữa cháy tạm, chắc chắn tái diễn.

**Liên hệ section:** 9 (SQL regression detection, DBA_HIST_SQLSTAT), 13 (ASH: cùng SQL_ID 2 plan hash → plan change), 15 (SQL Tracing đo chính xác).

---

## 🔧 Tình huống T3 — Hàng loạt session treo cùng lúc (Concurrency Cascade)

**Câu hỏi phỏng vấn:**
> "Lúc 16:45, active sessions vọt từ 35 lên 142, TPS tụt từ 380 xuống 80. AWR cho thấy `enq: TX - row lock contention` 28% và `library cache lock` 8.8%. Sau 22 phút tự hết. Root cause là gì?"

**Nhà tuyển dụng đánh giá:** Khả năng dựng **blocking chain** và tìm root cause *không hiển nhiên* — không dừng ở "có row lock" mà hỏi *tại sao session đầu chuỗi bị kẹt*.

**Hướng giải quyết (các bước bằng lệnh):**

**Bước 1 — Dựng blocking chain, truy đến session GỐC** (đừng dừng ở nạn nhân):
```sql
SQL> SELECT TO_CHAR(sample_time,'HH24:MI:SS') t, session_id, blocking_session, event, sql_id
     FROM   v$active_session_history
     WHERE  blocking_session IS NOT NULL
       AND  sample_time >= TIMESTAMP '2026-07-07 16:45:00'
     ORDER  BY sample_time, blocking_session;
-- Kết quả: 36 session chờ TX lock trên CÙNG 1 SID gốc
```

**Bước 2 — Soi chính session gốc đó đang chờ gì** (mấu chốt — KHÔNG phải row lock):
```sql
SQL> SELECT TO_CHAR(sample_time,'HH24:MI:SS') t, event, blocking_session, sql_id, sql_plan_hash_value
     FROM   v$active_session_history
     WHERE  session_id = &root_sid
       AND  sample_time >= TIMESTAMP '2026-07-07 16:45:00'
     ORDER  BY sample_time;
-- Phát hiện: session gốc đang chờ 'library cache lock', blocking_session của nó = NULL
```

**Bước 3 — Xác nhận cursor bị invalidate** (cùng SQL_ID có 2 plan_hash trong window = reparse):
```sql
SQL> SELECT sql_id, COUNT(DISTINCT sql_plan_hash_value) plans
     FROM   v$active_session_history
     WHERE  sample_time BETWEEN TIMESTAMP '2026-07-07 16:45:00' AND TIMESTAMP '2026-07-07 17:07:00'
       AND  sql_id IS NOT NULL
     GROUP  BY sql_id HAVING COUNT(DISTINCT sql_plan_hash_value) > 1;
```

**Bước 4 — Tìm thủ phạm invalidate: DDL hay gather stats lúc 16:45**:
```sql
SQL> SELECT operation, target, start_time, end_time
     FROM   dba_optstat_operations
     WHERE  start_time BETWEEN TIMESTAMP '2026-07-07 16:40:00' AND TIMESTAMP '2026-07-07 16:50:00';
SQL> SELECT object_name, last_ddl_time FROM dba_objects
     WHERE object_name='ORDERS' AND last_ddl_time > TIMESTAMP '2026-07-07 16:00:00';
```

**Bước 5 — Đọc đúng cascade (root cause):**
> Session gốc kẹt `library cache lock` (do DDL/gather-stats invalidate cursor ORDERS) → không commit được → **giữ nguyên row lock** → 36 session cascade chờ `enq: TX`. Các session muốn share cursor đang bị mutate thì kẹt `cursor: pin S wait on X`. Tự hết sau 22 phút vì DDL/stats hoàn tất → nhả library cache lock → gốc commit → cascade tan. **Triệu chứng (TX lock) ≠ root cause (library cache lock).**

**Bước 6 — Ngăn tái diễn:**
```sql
-- Dời auto gather stats ra ngoài giờ peak
SQL> BEGIN DBMS_AUTO_TASK_ADMIN.DISABLE('auto optimizer stats collection', NULL, NULL); END;/
SQL> -- rồi lên lịch gather stats thủ công ngoài giờ cao điểm
-- Gather stats giờ làm việc thì hoãn invalidation:
SQL> EXEC DBMS_STATS.GATHER_TABLE_STATS('SALES','ORDERS', no_invalidate=>TRUE);
-- Alert khi blocking chain vượt ngưỡng
SQL> SELECT blocking_session, COUNT(*) waiters FROM v$session
     WHERE blocking_session IS NOT NULL GROUP BY blocking_session HAVING COUNT(*) > 10;
```

> **Nhấn mạnh:** "kill session gốc" có rủi ro (rollback lớn/DDL chạy lại) — phải đánh giá trước. Giá trị senior là chỉ ra **DDL/stats trong giờ peak** mới là nguyên nhân hệ thống, không dừng ở "có row lock".

**Liên hệ section:** 13 (ASH blocking chain, library cache lock cascade — đúng Lab Ex3), 19 (Enqueue TX), 20 (Latch & Mutex: cursor pin S), 21 (Shared Pool: library cache, cursor invalidation).

---

## 🔧 Tình huống T4 — Ứng dụng chậm khi đọc dữ liệu (I/O Bottleneck)

**Câu hỏi phỏng vấn:**
> "AWR cho thấy top event là `db file sequential read` và `read by other session` chiếm phần lớn DB Time. Hệ thống đọc chậm. Anh xử lý theo hướng nào?"

**Nhà tuyển dụng đánh giá:** Hiểu I/O internals; biết `read by other session` = hot block contention chứ không phải "disk chậm"; ưu tiên giảm khối lượng I/O trước khi mua thêm phần cứng.

**Hướng giải quyết (các bước bằng lệnh):**

**Bước 1 — Tìm object nóng gây User I/O bằng ASH** (chỉ đích danh, không đoán):
```sql
SQL> SELECT o.object_name, o.object_type, n.name event, SUM(1) samples
     FROM   v$active_session_history h
     JOIN   dba_objects  o ON h.current_obj#=o.object_id
     JOIN   v$event_name n ON h.event_id=n.event_id
     WHERE  h.session_state='WAITING' AND n.wait_class='User I/O'
       AND  h.sample_time >= SYSTIMESTAMP - INTERVAL '30' MINUTE
     GROUP  BY o.object_name,o.object_type,n.name
     ORDER  BY samples DESC FETCH FIRST 10 ROWS ONLY;
```

**Bước 2 — Tìm SQL gây nhiều physical reads nhất trên object đó**:
```sql
SQL> SELECT sql_id, SUM(1) samples
     FROM   v$active_session_history
     WHERE  event LIKE 'db file%' AND current_obj# = &hot_object_id
       AND  sample_time >= SYSTIMESTAMP - INTERVAL '30' MINUTE
     GROUP  BY sql_id ORDER BY samples DESC FETCH FIRST 5 ROWS ONLY;
SQL> SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY_CURSOR('&sql_id',NULL,'ALLSTATS LAST'));
```
> Đọc plan: `db file sequential read` cao = **thiếu index/index kém chọn lọc**; `db file scattered read` cao = **full table scan**; `read by other session` = **hot block contention** (không phải disk yếu).

**Bước 3 — Giảm I/O (rẻ nhất): thêm index đúng** cho SQL đang full scan:
```sql
SQL> CREATE INDEX sales.ix_orders_region ON sales.orders(region_code) ONLINE;
SQL> EXEC DBMS_STATS.GATHER_TABLE_STATS('SALES','ORDERS');
-- Đo lại plan để xác nhận đã dùng index & physical reads giảm
```

**Bước 4 — Xử lý hot block** (`read by other session`) — giảm contention:
```sql
-- Tăng INITRANS / giảm dồn block cho segment nóng
SQL> ALTER TABLE sales.orders INITRANS 8;
SQL> ALTER INDEX sales.pk_orders REBUILD ONLINE;   -- cân nhắc reverse key nếu nghẽn right-most leaf
```

**Bước 5 — Tối ưu buffer cache** (nếu working set không đủ cache):
```sql
SQL> SELECT ROUND((1-(phy.value/(cur.value+con.value)))*100,2) hit_ratio
     FROM v$sysstat cur, v$sysstat con, v$sysstat phy
     WHERE cur.name='db block gets' AND con.name='consistent gets' AND phy.name='physical reads';
-- Bảng nóng nhỏ → ghim vào KEEP pool
SQL> ALTER SYSTEM SET db_keep_cache_size = 2G SCOPE=BOTH;
SQL> ALTER TABLE sales.lookup_codes STORAGE (BUFFER_POOL KEEP);
```

**Bước 6 — Kiểm tra sức khỏe index** (phình/rời rạc làm tăng I/O — rebuild có căn cứ):
```sql
SQL> ANALYZE INDEX sales.pk_orders VALIDATE STRUCTURE;
SQL> SELECT name, height, del_lf_rows, lf_rows,
            ROUND(del_lf_rows/NULLIF(lf_rows,0)*100,1) pct_deleted FROM index_stats;
-- pct_deleted cao (>20%) hoặc height bất thường → REBUILD/COALESCE
```

> **Nhấn mạnh:** thứ tự đúng = **giảm reads bằng SQL & index** → **tối ưu buffer cache** → *cuối cùng* mới bàn storage. "Đọc chậm" thường do đọc **quá nhiều block thừa**, không phải disk yếu.

**Liên hệ section:** 22 (Buffer Cache & Flash Cache, hot block), 26 (Disk I/O internals), 27 (Index Defrag), 13 (ASH object/block identification).

---

## 🔧 Tình huống T5 — Commit chậm, `log file sync` cao (Redo Path)

**Câu hỏi phỏng vấn:**
> "Ứng dụng OLTP báo mỗi commit mất ~40ms thay vì <5ms. AWR cho thấy `log file sync` là top wait. Anh chẩn đoán và tối ưu ra sao?"

**Nhà tuyển dụng đánh giá:** Hiểu redo path (LGWR, redo log, commit mechanism); phân biệt vấn đề I/O redo vs commit quá thường xuyên ở tầng ứng dụng.

**Hướng giải quyết (các bước bằng lệnh):**

**Bước 1 — Đo commit có quá thường xuyên không** (redo size mỗi commit rất nhỏ = commit-per-row):
```sql
SQL> SELECT ROUND(redo.value/NULLIF(com.value,0)) redo_bytes_per_commit,
            com.value user_commits
     FROM   v$sysstat redo, v$sysstat com
     WHERE  redo.name='redo size' AND com.name='user commits';
-- redo_bytes_per_commit rất nhỏ (vài trăm byte) → app commit từng dòng
```

**Bước 2 — Phân biệt I/O-bound vs commit-bound** — so `log file sync` với `log file parallel write`:
```sql
SQL> SELECT event, total_waits, ROUND(time_waited_micro/1e6,1) sec,
            ROUND(time_waited_micro/NULLIF(total_waits,0)/1000,2) avg_ms
     FROM   v$system_event
     WHERE  event IN ('log file sync','log file parallel write');
```
> - Cả hai `avg_ms` đều cao → **I/O redo chậm** (Bước 4). - `parallel write` thấp mà `sync` cao → **commit quá nhiều / LGWR đói CPU** (Bước 3).

**Bước 3 — Sửa tầng ứng dụng (thường hiệu quả nhất): batch commit**:
```sql
-- ❌ Sai: commit mỗi dòng trong vòng lặp
--   FOR r IN cur LOOP ... ; COMMIT; END LOOP;
-- ✅ Đúng: gom commit theo lô
SQL> BEGIN
       FOR i IN 1..n LOOP
         -- DML ...
         IF MOD(i,1000)=0 THEN COMMIT; END IF;
       END LOOP;
       COMMIT;
     END;/
-- Dữ liệu chịu mất mát nhỏ (staging/log): cân nhắc — CÓ đánh đổi độ bền, nêu rõ rủi ro
SQL> COMMIT WRITE BATCH NOWAIT;
```

**Bước 4 — Sửa tầng hệ thống: tối ưu redo I/O**:
```sql
-- Kiểm tra redo log đủ lớn / không log switch quá dày
SQL> SELECT group#, bytes/1024/1024 mb, members, status FROM v$log;
SQL> SELECT to_char(first_time,'HH24:MI') t, COUNT(*) switches
     FROM v$log_history WHERE first_time>SYSDATE-1 GROUP BY to_char(first_time,'HH24:MI');
-- Tăng size redo log (tạo group mới lớn hơn, drop group cũ), đặt trên disk low-latency riêng
SQL> ALTER DATABASE ADD LOGFILE GROUP 4 ('/redo_fast/redo04.log') SIZE 2G;
```

**Bước 5 — Loại trừ LGWR đói CPU** (nếu server CPU-bound):
```sql
SQL> SELECT NVL(event,'ON CPU') event, COUNT(*) FROM v$active_session_history
     WHERE program LIKE '%LGWR%' AND sample_time >= SYSTIMESTAMP - INTERVAL '15' MINUTE
     GROUP BY NVL(event,'ON CPU');
-- LGWR nhiều 'ON CPU' + server CPU cao → giảm tải CPU tổng thể (Section 25)
```

> **Nhấn mạnh:** `log file sync` cao **~90% do ứng dụng commit quá thường xuyên**, không phải disk. Luôn hỏi *"commit bao lâu một lần?"* trước khi đề xuất mua SSD.

**Liên hệ section:** 24 (Redo Path, LGWR, log file sync vs parallel write), 25 (CPU Bottleneck — LGWR starvation), 8 (phân loại wait event Commit class).

---

## 🧠 Mẹo trả lời phỏng vấn Tuning (áp dụng chung)

1. **Luôn bắt đầu bằng DB Time method** — "tôi tối ưu thứ chiếm nhiều DB Time nhất, đo bằng AWR/ASH" — câu mở đầu này ngay lập tức phân biệt senior với junior.
2. **AWR vs ASH — chọn đúng công cụ:** sự cố kéo dài/lặp lại > 30 phút → **AWR**; sự cố thoáng qua/đã kết thúc < 1 giờ → **ASH** (giữ được chiều thời gian).
3. **Phân biệt immediate fix vs root fix** — nhà tuyển dụng luôn hỏi "và để nó không tái diễn?". Có 2 tầng câu trả lời.
4. **Không "flush shared pool" / "kill session" như phản xạ** — đó là chữa cháy; phải giải thích rủi ro và nêu giải pháp gốc.
5. **Triệu chứng ≠ root cause** — `enq: TX` có thể bắt nguồn từ `library cache lock`; `log file sync` có thể bắt nguồn từ commit-per-row. Luôn hỏi *"tại sao"* thêm một lớp nữa.
6. **Liên hệ automation (đúng JD)** — đề xuất script giám sát chủ động (ASH snapshot tự động, alert blocking chain, capture baseline định kỳ) thay vì chỉ phản ứng.

---

*Phần 2 tổng hợp từ The Oracle Database Performance Tuning Course (`section_all_new/`). Xem chi tiết internals từng chủ đề tại `section_all_new/section_<N>_<topic>_senior_guide.md`.*

---

*File này gồm 15 tình huống phỏng vấn Oracle DBA: 10 tình huống Backup/Recovery/DR (Phần 1) + 5 tình huống Performance Tuning (Phần 2), ánh xạ trực tiếp sang yêu cầu công việc.*


---

!!! info "Nguồn gốc"
    `Oracle-Database-Backup-and-Recovery-using-RMAN/modules/interview_scenarios_dba.md`
