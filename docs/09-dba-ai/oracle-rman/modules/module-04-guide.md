---
title: '📘 Module 04: RMAN Full Backups'
course: 09-dba-ai
source: dba_ai/oracle_rman/modules/module_04_guide.md
---

# 📘 Module 04: RMAN Full Backups

> **Phạm vi**: Bài 10-13 (Lý thuyết & Thực hành Part I & II)
> **Thời gian học ước tính**: 3-4 giờ
> **Tiền điều kiện**: Đã hoàn thành Module 02 (Kiến trúc & ARCHIVELOG) và Module 03 (Làm quen lệnh cơ bản RMAN).

---

## 📑 Mục lục

- [Bài 10: Khái niệm cơ bản & RMAN Full Backups Part I](#-bài-10-khái-niệm-cơ-bản--rman-full-backups-part-i)
- [Bài 11: Thực hành (Practice 3) - Part I](#-bài-11-thực-hành-practice-3---part-i)
- [Bài 12: RMAN Backups Nâng cao Part II](#-bài-12-rman-backups-nâng-cao-part-ii)
- [Bài 13: Thực hành (Practice 4) - Part II](#-bài-13-thực-hành-practice-4---part-ii)
- [Bảng tổng hợp & Cú pháp](#-bảng-tổng-hợp--cú-pháp)
- [Câu hỏi ôn tập tổng hợp](#-câu-hỏi-ôn-tập-tổng-hợp)

---

# 📖 Bài 10: Khái niệm cơ bản & RMAN Full Backups Part I

## 🎯 Mục tiêu bài học
Sau khi hoàn thành bài này, bạn sẽ:
- Trình bày được các chiến lược sao lưu: Whole vs Partial, Full vs Incremental, và Cold vs Hot Backup.
- Giải thích sâu được sự khác biệt giữa hai định dạng file RMAN: **Backup Sets** và **Image Copies**.
- Backup thành công toàn bộ cơ sở dữ liệu cũng như một phần (tablespace, datafile) cụ thể.
- Nắm rõ cách áp dụng biến Format để quản lý file backup hợp lý.

## 📚 Kiến thức nền tảng
- Cần biết cách hoạt động của Datafiles, Control Files và Archived Redo Logs (Xem Module 02).
- Cấu hình ARCHIVELOG MODE phải bật để thực hiện Hot Backup an toàn.

---

## 📋 Nội dung chính

### 1. Phân loại thuật ngữ Backup (Terminologies)

Để hiểu cách tiếp cận sao lưu trong Oracle, bạn cần làm rõ 3 câu hỏi sau:

1. **Phạm vi Backup (Strategy):**
   - **Whole**: Sao lưu toàn bộ Database (Mọi datafiles + control file).
   - **Partial**: Sao lưu một phần (chỉ 1 tablespace hoặc 1 datafile).

2. **Kiểu dữ liệu (Type):**
   - **Full**: Quét và sao chép tất cả các block có chứa dữ liệu.
   - **Incremental**: Chỉ sao chép những block bị thay đổi (sẽ học kỹ ở Module 05).

3. **Chế độ Database (Mode):**
   - **Offline (Cold / Consistent)**: Database ở trạng thái MOUNT. Dữ liệu đang hoàn toàn tĩnh, không bị thay đổi. Tuyến mồ hôi không chảy. Chế độ duy nhất được hỗ trợ nếu DB nằm ở NOARCHIVELOG mode.
   - **Online (Hot / Inconsistent)**: Database ở trạng thái OPEN. Ai cũng có thể ghi/xóa. Do dữ liệu liên tục thay đổi (inconsistent), nên Oracle *bắt buộc* phải dùng đến Archived Logs trong quá trình khôi phục để làm đồng nhất trở lại. Nghĩa là, DB BẮT BUỘC ở ARCHIVELOG Mode.

### 2. Định dạng đầu ra: Backup Sets vs Image Copies

RMAN có thể lưu trữ dữ liệu bản quyền bằng 2 cơ chế xuất file kỹ thuật số khác nhau. Đây là khái niệm cốt lõi khi thiết kế lộ trình lưu trữ.

```text
       RMAN OUTPUT TYPES
              │
      ┌───────┴───────┐
      ▼               ▼
 Backup Sets       Image Copies
 (Định dạng RMAN)  (Bản sao 1-1 OS)
              
+ Nén nhẹ hơn       + Bằng kích thước gốc
+ Rất tốt cho       + Lý tưởng để chuyển đổi 
  lưu trữ dài hạn     nhanh khi ổ chính bị cháy
```

**Bảng so sánh chi tiết:**

| Tiêu chí | Backup Sets | Image Copies |
|----------|-------------|-------------|
| **Bản chất File** | RMAN tạo ra các files gọi là *Backup Pieces*. Gói nhiều datafiles vào chung 1 file gốc. | Là bản clone y chang của Datafile. Tương tự dán file trong Windows. |
| **Kích thước** | Rất nhỏ. Chỉ chứa những Block **đã ghi dữ liệu** (phớt lờ không gian trống). | Bằng đúng 100% dung lượng Datafile gốc, kể cả vùng trống chưa có mẩu tin. |
| **Thiết bị lưu trữ** | Ổ đĩa (Disk) hoăc Băng từ (Tape). | Chỉ hỗ trợ duy nhất trên **Disk**. |
| **Hỗ trợ phục hồi nhanh?** | ❌ Không, phải chờ RMAN extract bung nén ra. | ✅ Có. Cho phép "Tráo đổi" (Switch) ngay lập tức nếu file cũ bị sập. Rất hữu ích đảm bảo SLA. |
| **Incremental Option** | ✅ Hỗ trợ | ✅ Hỗ trợ |

> [!TIP]
> Việc xây dựng quy định khi nào dùng Backup Sets, khi nào dùng Image Copies thể hiện năng lực kiến trúc của DBA. Thường Data nằm ở Tape thì dùng Backup Set nén. Trách nhiệm phục hồi trong 5 phút RTO thì dùng Image Copy cắm thẳng SSD cho load lại ngay.

### 3. Những gì không tương thích sao lưu bằng RMAN?

Các tệp được chứng thực an toàn RMAN gồm: **Data files**, **Control files**, **SPFILE**, **Archived Redo Logs**. (Nó không support Online redo log, do Online redos liên tục được luân chuyển và không tĩnh lặng hoàn toàn - bạn dùng multiplexing OS để bảo vệ redo này). Các phụ kiện OS (password file `orapwd`, listener, tnsnames) bạn phải quản lý OS Copy.

### 4. Backing up a Whole Database (Toàn bộ)

Cú pháp thực hiện tùy thuộc vào trạng thái DB của bạn (Offline hay Online).

#### 4.1. Backup Online (Database đang OPEN)
Bắt buộc Database đã bật ARCHIVELOG. 

**Lệnh RMAN thực thi:**
```sql
RMAN> BACKUP DATABASE PLUS ARCHIVELOG;
```

**Output mẫu (Giản lược):**
```text
Starting backup at 16-APR-26
current log archived
using channel ORA_DISK_1
channel ORA_DISK_1: starting archived log backup set
...
channel ORA_DISK_1: starting full datafile backup set
channel ORA_DISK_1: specifying datafile(s) in backup set
input datafile file number=00001 name=/u01/app/oracle/oradata/ORADB/system01.dbf
input datafile file number=00003 name=/u01/app/oracle/oradata/ORADB/sysaux01.dbf
...
current log archived
channel ORA_DISK_1: starting archived log backup set
...
Finished backup at 16-APR-26
```

**Giải thích từng dòng lệnh RMAN thực hiện ẩn dưới nền:**
Từ khóa `PLUS ARCHIVELOG` rất mạnh. RMAN tự động làm 5 bước:
1. `current log archived`: Yêu cầu DB thực thi đổi log hiện tại (Archive log switch).
2. `starting archived log backup set`: Backup tất cả Archive Logs vào trước.
3. `starting full datafile backup set`: Backup Datafiles cốt lõi của database.
4. `current log archived`: Switch một lần nữa để chứa các thay đổi phát sinh ngay trong lúc backup datafile.
5. Sao lưu những log nhỏ giọt cuối cùng này.

> [!WARNING]
> **Lỗi thường gặp**: `ORA-01145: offline normal or immediate not allowed unless media recovery enabled.`
> Nguyên nhân: Bạn gõ `BACKUP DATABASE;` trong khi DB đang chạy OPEN nhưng chế độ `NOARCHIVELOG` chưa chuyển. Hệ thống không thể đảm bảo an toàn. 

**Trong production:** Chạy `PLUS ARCHIVELOG` là tiêu chuẩn vàng của ngành. Nếu bạn chỉ gõ `BACKUP DATABASE`, và trong thời gian backup có ai đó Update table quan trọng, bạn sẽ KHÔNG phục hồi được trạng thái nguyên sinh của thay đổi đó do thiếu bản lưu Archive Logs mới nhất.

#### 4.2. Khôi phục Partial định dạng File xuất ra (%U)

Để Backup từng phần và bảo hiểm tên không trùng lặp khi chạy qua đêm, gán biến Format:

**Lệnh RMAN thực thi:**
```sql
-- Chỉ backup 2 tablespaces cụ thể
RMAN> BACKUP TABLESPACE users, tools FORMAT "/u02/backup/orcl_%U.bkp";
```

**Giải thích tham số:**
- `%U`: Tự động tạo một hệ thống ID nhận diện 8 ký tự duy nhất toàn cầu và độc quyền thời gian. Bắt buộc dùng để hệ thống OS đè file không xảy ra. Nếu DB 4 node RAC đẩy backup chung qua biến này, chúng hoàn toàn cách ly nhau thành công.

---

# 💻 Bài 11: Thực hành (Practice 3) - Part I

## 📝 Ví dụ thực hành: Trải nghiệm RMAN cơ bản
Trong Script tập dượt này, bạn sẽ làm quen với OS Command, check System, và lợi dụng Syntax Checking của Parser:

```sql
# 1. Đăng nhập RMAN
[oracle@srv1 ~]$ rman target "'/ as SYSBACKUP'"

# 2. Xóa Backupset qua thử sai Syntax - RMAN CỰC KỲ KHÔN!
# Nhập thử DELETE và nhấn Enter
RMAN> DELETE
RMAN-01009: syntax error: found "end-of-file": expecting one of: "archivelog, backuppiece, backupset, backup, copy..."
# Giải thích: RMAN báo đang chờ bạn gõ 1 từ cụ thể, ví dụ backupset

# Bổ sung theo ý muốn:
RMAN> DELETE BACKUPSET
RMAN-01009: syntax error: found "end-of-file": expecting one of: "for, guid, like, of, tag..."
# Vẫn thiếu! Cần báo RMAN là xóa cụm nào

# Hoàn thành câu đúng:
RMAN> DELETE BACKUPSET OF DATABASE;
Do you really want to delete the above objects (enter YES or NO)? YES

# 3. Xem báo cáo dung lượng FRA từ bên trong RMAN (Cực kỳ đáng giá)
RMAN> SELECT FILE_TYPE, PERCENT_SPACE_USED FROM V$RECOVERY_AREA_USAGE WHERE PERCENT_SPACE_USED<>0 ORDER BY PERCENT_SPACE_USED DESC;
```
**Output mẫu của query FRA:**
```text
FILE_TYPE            PERCENT_SPACE_USED
-------------------- ------------------
BACKUP PIECE                       22.5
ARCHIVED LOG                       15.2
FLASHBACK LOG                       5.3
```
*Giải thích*: Cột phần trăm này cho biết bao nhiêu phân vùng lưu trữ đã bị chiếm. DBA có thể dự phòng tăng ổ lên 100GB khi đạt 80% để tránh nghẽn.

---

# 📖 Bài 12: RMAN Backups Nâng cao Part II

## 🎯 Mục tiêu bài học
- Nắm bắt và giải cấu trúc tự động sao lưu Control files và SPFILE.
- Quản lý cách nạp lại Archived Redo Logs và xóa an toàn ngay sau khi lấy.
- Ứng dụng nhuần nhuyễn Tags, Device Types và tham số tối ưu thời gian "Not Backed Up".

## 📋 Nội dung chính

### 1. Snapshot Control File & Cấu hình Autobackup

> [!IMPORTANT]
> Mất Control File là mất trọn bộ Database Metadata. Nó lưu mọi tọa độ. Bạn luôn phải cấu hình tự động lưu Control File.

**Lệnh RMAN thực thi cấu hình chung:**
```sql
RMAN> CONFIGURE CONTROLFILE AUTOBACKUP ON;
```
Bất kì khi nào bạn Backup TableSpace của hệ thống, RMAN cũng lẳng lặng tự chèn Controlfile và SPFILE vào cuối hành trình để đảm bảo luôn sẵn sàng cứu sống DB.

```text
       RMAN Backup Flow
              │
  ┌───────────▼────────────┐
  │ 1. Tạo Snapshot CF     │ Lấy 1 bức ảnh tĩnh chớp nhoáng (SnapCF)
  │ 2. Backup Datafiles    │ Trích xuất data
  │ 3. Backup Autobackup   │ Chép đè nguyên gốc SnapCF và SPFile lên đĩa
  └───────────┬────────────┘
```

**Trong Production (RAC):** 
Snapshot mặc định nằm ở thư mục cấp Local `$ORACLE_HOME/dbs/snapcf_orcl.f`. Trong môi trường cụm (RAC Cluster), Node 2 không thể truy cập thư mục của Node 1! Bạn sẽ BẮT BUỘC phải đổi cấu hình Move cái Snapshot này ra ASM (Shared Storage).
```sql
RMAN> CONFIGURE SNAPSHOT CONTROLFILE NAME TO '+FRA/RAC/AUTOBACKUP/snapcf_rac.f';
```

### 2. Xóa và Dọn rác Archive Logs thông minh

Archive log liên tục sinh ra trong FRA và chiếm chỗ. Hàng ngày bạn sẽ cần dọn chúng vào băng từ hoặc external mount. Rõ ràng, khi đã backup thành công, bạn phải thu hồi ổ cứng.

**Lệnh RMAN thực thi:**
```sql
RMAN> BACKUP ARCHIVELOG ALL DELETE ALL INPUT;
```

**Output mẫu:**
```text
Starting backup at 16-APR-26
current log archived
channel ORA_DISK_1: starting archived log backup set
...
channel ORA_DISK_1: backup set complete, elapsed time: 00:00:03
channel ORA_DISK_1: deleting archived log(s)
archived log file name=/u01/app/oracle/fra/ORADB/archivelog/2026_04_16/o1_mf_1_538.arc RECID=15 ...
Finished backup at 16-APR-26
```
**Giải thích**: Tiền tố `BACKUP ... ALL` đảm bảo chép ra thiết bị sao lưu, trong khi hậu tố `DELETE ALL INPUT` ngay lập tức báo DB xóa source gốc → Giải phóng vùng FRA an toàn mà không phải can thiệp thủ công từ lệnh OS `rm`.

**Lỗi thường gặp**: `ORA-19809: limit exceeded for recovery files.` Database báo không ghi log đc nữa do FRA đạt 100% và sẽ bị sập treo. Việc thiết lập Cronjob chạy lệnh DELETE RMAN này mỗi 6 hoặc 12 giờ là phương án số 1!

### 3. Image Copies và Tham số Nâng Cao

Image Copies được lưu dưới dạng file gốc thuần bằng lệnh thần thánh:
```sql
RMAN> BACKUP AS COPY DATABASE;
```

**Trong Production: Lỗi nghẽn đường truyền và RMAN chạy lại**
Trong DataCenter, bạn làm gì khi backup đêm 1TB bị đứt do giật cáp lúc ở 800GB? Bắt đầu quét lại vòng lặp từ 0 và mất thêm 6 tiếng nữa? *Hoàn toàn không cần thiết*:
```sql
RMAN> BACKUP NOT BACKED UP SINCE TIME 'SYSDATE-1' DATABASE PLUS ARCHIVELOG;
```
**Output mẫu**:
```text
skipping datafile 1; already backed up on 16-APR-26
skipping datafile 2; already backed up on 16-APR-26
backing up datafile 15 ...
```
**Giải thích**: Lệnh RMAN đối chiếu thông số cờ ngày tháng lưu trên Metadata. Quét thấy 800GB đầu đã có bản lưu (báo `skipping datafile X`), chỉ sao chép 200GB còn lại (`backing up datafile 15`). Tối đa hóa băng thông và thời gian cứu hộ Server!

**Tags (Nhãn tra cứu ID)**
Tự đánh dấu nhãn (tag) cho nhóm file. Không phân biệt hoa thường. 
```sql
RMAN> BACKUP DATAFILE 1,2 TAG 'MONTHLY_OCT';
RMAN> LIST COPY TAG 'monthly_oct';
```

---

# 💻 Bài 13: Thực hành (Practice 4) - Part II

## 📝 Ví dụ thực hành: Gắn Tag và Tạo Trace File Backup

Script sau đây minh họa quá trình thực chiến OS Command trong RMAN và trace SQL của file Control:

```sql
# 1. Host Command: Bạn đâu cần thoát RMAN để dùng lệnh Linux? Từ RMAN gọi Terminal ra báo danh:
RMAN> host 'ls -al /u01/app/oracle/product/12.2.0/db_1/dbs/snapcf_ORADB.f';

# Output (Lệnh OS Unix được gọi):
# -rw-r----- 1 oracle oinstall 10600448 Apr 16 11:45 /u01/app/oracle/product/12.2.0/db_1/dbs/snapcf_ORADB.f

# 2. Tạo SQL Script Trace cho Cấp cứu Server
# Bất kì khi nào bạn muốn một văn bản code "CREATE CONTROLFILE", gọi flag Trace trong SQLPlus:
SQL> ALTER DATABASE BACKUP CONTROLFILE TO TRACE;

# Bật Terminal OS lấy tên file trace mới sinh ra để ráp mã Code SQL dự phòng:
[oracle@srv1 ~]$ tail /u01/app/oracle/diag/rdbms/oradb/ORADB/trace/alert_ORADB.log
# Trong file log sẽ chỉ định /u01/app/.../ORADB_ora_14522.trc
# Bạn dùng lệnh OS (như vi) để mổ xẻ nội dung CREATE CONTROLFILE SQL statement.
[oracle@srv1 ~]$ vi /u01/app/oracle/diag/rdbms/oradb/ORADB/trace/ORADB_ora_14522.trc

# 3. Quản lý Tag thông minh
RMAN> BACKUP AS COPY TABLESPACE users FORMAT '/media/sf_extdisk/%U' TAG 'USERS2018';
# Lệnh xóa qua Tag (không phận biệt hoa thường USERS2018 hay users2018)
RMAN> DELETE COPY TAG 'users2018'; 
```

---

# 📊 Bảng tổng hợp & Cú pháp

| Tính Năng RMAN | Cú pháp kinh điển | Phân tích Kỹ thuật |
|----------|-------------------|--------------------------------------|
| **Cứu hộ Hot Server** | `BACKUP DATABASE PLUS ARCHIVELOG;` | Bắt buộc Archive log. Tự switch 2 lần. Tiêu chuẩn toàn cầu. |
| **Bắn log, dọn rác dĩa** | `BACKUP ARCHIVELOG ALL DELETE ALL INPUT;` | Dùng định kỳ chống tràn cảnh báo FRA ORA-19809. |
| **Resume lỗi cáp** | `BACKUP NOT BACKED UP SINCE TIME 'sysdate-1'...` | Tiết kiệm RTO, cho phép bỏ qua tiến trình đã done. |
| **Bật Controlfile Auto** | `CONFIGURE CONTROLFILE AUTOBACKUP ON;` | Cấu hình SET một lần, Database bảo vệ metadata muôn đời. |
| **Gắn nhãn nhận diện** | `BACKUP AS COPY ... TAG 'USERS26';` | Tracking Job chuyên nghiệp. Xóa nhanh gọn qua Tag. |

---

# 🎯 Câu hỏi ôn tập tổng hợp

1. Phân biệt *Image Copies* và *Backup Sets*. Trong bối cảnh công ty thương mại điện tử cần khôi phục tính năng thanh toán nhanh sau 2 phút, bạn nên ưu tiên áp dụng loại nào để giải quyết Datafile hỏng? Tại sao? (Gợi ý: tốc độ Switch).
2. Trình tự 5 bước ẩn sâu phía dưới của cấu trúc dòng lệnh `BACKUP DATABASE PLUS ARCHIVELOG` diễn ra theo thứ tự nào? Nếu RMAN bỏ quên không switch archived log ở chu kỳ cuối cùng, rủi ro khôi phục DB ở thời điểm *Roll Forward* gặp phải thảm họa gì?
3. Đang đẩy backup Full dung lượng 4TB ra Tape (`DEVICE TYPE sbt`) thì thư viện băng từ sập nửa đêm. Sáng đi làm, bạn tiếp tục dùng mệnh lệnh tinh vi nào để cấu hình "SKIP" 2.5TB đã chép và vớt vèo 1.5TB lỗi thời còn dở cho tối ưu? 
4. Hệ thống sẽ trả hệ số báo lỗi OS hay ORA gì nếu bạn cố gắng `BACKUP DATABASE` trên máy chủ OPEN mà thiết lập tham số ban đầu lại ở mode `NOARCHIVELOG`?

---

## ➡️ Bài tiếp theo

Sau khi thành thạo hệ điều hành khối Full Backups tĩnh, mục tiêu tiếp nối là **Module 05: Incremental Backups** - Bài 14: Performing Incremental Backups (Khác biệt mạnh mẽ giữa Level 0, Level 1 Cumulative và Differential CỰC KÌ ấn tượng) 🚀. 
Bạn muốn tiếp tục qua học cấu trúc siêu nhẹ Differential ngay bây giờ hay muốn thử gõ hệ thống Host Command ôn lại phần Full này?


---

!!! info "Nguồn gốc"
    `dba_ai/oracle_rman/modules/module_04_guide.md`
