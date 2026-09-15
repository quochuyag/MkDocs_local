---
title: '📘 Module 05: Incremental Backups'
course: 02-rman-backup-recovery
source: Oracle-Database-Backup-and-Recovery-using-RMAN/modules/module_05/module_05_guide.md
---

# 📘 Module 05: Incremental Backups

> **Phạm vi**: Bài 14 - 16 (Lý thuyết & Thực hành Incremental Backups) trong khóa học Oracle Database Backup and Recovery using RMAN.
> **Thời gian học ước tính**: 3-4 giờ
> **Tiền điều kiện**: Nắm vững các khái niệm Full Backup, RMAN Backup Sets, và Image Copies từ Module 04.

---

## 📑 Mục lục

- [Bài 14: Khái niệm & Cơ chế Incremental Backups](#-bài-14-khái-niệm--cơ-chế-incremental-backups)
- [Bài 15 & 16: Thực hành (Practice 5) & Tự động hóa Job](#-bài-15--16-thực-hành-practice-5--tự-động-hóa-job)
- [Bảng tổng hợp & Cú pháp](#-bảng-tổng-hợp--cú-pháp)
- [Câu hỏi ôn tập tổng hợp](#-câu-hỏi-ôn-tập-tổng-hợp)

---

# 📖 Bài 14: Khái niệm & Cơ chế Incremental Backups

## 🎯 Mục tiêu bài học
Sau khi hoàn thành bài này, bạn sẽ:
- ✅ So sánh và nắm vững sự khác biệt giữa **Differential** và **Cumulative** Incremental backups.
- ✅ Khởi tạo thành thạo các bản Incremental Backup ở level 0 và 1.
- ✅ Cấu hình và giám sát tính năng Block Change Tracking (BCT) để tăng tốc độ backup cực đại.
- ✅ Thiết lập hệ thống siêu việt **Incrementally Updated Backups** (cập nhật Incremental vào thẳng bản Image Copy để tiết kiệm RTO).

## 💡 Ý tưởng cốt lõi (Memory Hack)
Hãy nghĩ về Backup Incremental như việc *Lưu file tài liệu Word hàng ngày*:
- **Level 0**: Lưu bản Word tổng hoàn chỉnh (*Giống hệt Full Backup, nhưng RMAN đính kèm từ khóa "Mốc thời gian gốc"*).
- **Level 1 Differential (Mặc định)**: Chỉ lưu lại những chữ viết thêm *từ ngày hôm qua*. (Tiết kiệm ổ cứng).
- **Level 1 Cumulative**: Lưu lại tất cả những chữ viết thêm *tính từ đầu tuần (Level 0)*. (Tốn ổ cứng hơn nhưng phục hồi siêu nhanh).

---

## 📋 Nội dung chính

### 1. Phân biệt Differential vs Cumulative Incremental Backups ⭐⭐⭐

> [!IMPORTANT]
> Đây là kiến thức quan trọng bậc nhất khi thiết kế chiến lược sa lưu dài hạn.

RMAN Incremental Backup là tính năng quét các blocks dữ liệu và **chỉ sao lưu những block bị thay đổi** (changed blocks) kể từ một bản backup trước đó. RMAN cung cấp 2 phương thức hành động chính:

```text
SƠ ĐỒ TRUY XUẤT INCREMENTAL BACKUPS
(Chủ Nhật: DB chạy Level 0)

[Differential - Quét nét nối tiếp]
Chủ Nhật (LVL 0) ───> Thứ Hai (LVL 1) ───> Thứ Ba (LVL 1) ───> Thứ Tư (LVL 1)
                     (Thay đổi T2)        (Thay đổi T3)        (Thay đổi T4)

[Cumulative - Quét cộng dồn về mốc 0]
Chủ Nhật (LVL 0) ───> Thứ Hai (LVL 1)
       │└───────────> Thứ Ba (LVL 1)   (Bao gồm thay đổi của T2 + T3)
       └────────────> Thứ Tư (LVL 1)   (Bao gồm thay đổi của T2 + T3 + T4)
```

**Bảng so sánh chi tiết:**

| Tiêu chí | Differential (Mặc định) | Cumulative |
|----------|-----------------------|------------|
| **Cơ chế sao lưu** | Chép block thay đổi từ mốc **Level 0 hoặc Level 1 gần nhất**. | Chép block thay đổi từ mốc **Level 0 gần nhất**. (Bỏ qua các bản LVL 1 ở giữa). |
| **Dung lượng Disk (Storage)** | Tốn **Ít dung lượng nhất** (vì mỗi file chỉ chứa data mới). | Tốn **Nhiều dung lượng hơn** (file Cumulative ngày hôm sau luôn to hơn ngày hôm trước). |
| **Thời gian Khôi phục (RTO)** | Tốn **Nhiều thời gian** (RMAN phải ráp từng miếng LVL 1 của từng ngày lại). | Tốn **Rất ít thời gian** (RMAN chỉ cần lấy Level 0 + cục LVL 1 Cumulative mới nhất là xong). |

### 2. Khởi tạo Incremental Backups

**Lệnh RMAN thực thi:**
```sql
-- Tạo bản gốc (Level 0) - Thường chạy vào Chủ Nhật
RMAN> BACKUP INCREMENTAL LEVEL 0 DATABASE;

-- Tạo bản tăng dần nối tiếp (Differential) - Chạy hằng ngày
RMAN> BACKUP INCREMENTAL LEVEL 1 DATABASE;

-- Tạo bản tích lũy (Cumulative) - Nếu muốn RTO nhanh
RMAN> BACKUP INCREMENTAL LEVEL 1 CUMULATIVE DATABASE;
```

**Output mẫu khi chạy Level 1:**
```text
channel ORA_DISK_1: starting incremental level 1 datafile backup set
channel ORA_DISK_1: specifying datafile(s) in backup set
input datafile file number=00001 name=/u01/app/oracle/oradata/ORADB/system01.dbf
...
channel ORA_DISK_1: backup set complete, elapsed time: 00:01:15
```
*Giải thích*: Cụm từ `incremental level 1 datafile backup set` xác thực bạn đang chạy trích xuất mảng tăng dần. Thời gian chạy 1 phút 15 giây thường rất nhanh so với chuẩn Full Backup.

### 3. Block Change Tracking (BCT) ⭐⭐⭐

Bình thường, để RMAN biết block nào thay đổi từ hôm qua, **Nó phải quét toàn bộ Database** (Full Scan), mất rất nhiều luồng I/O. 
BCT (Block Change Tracking) là tính năng của Oracle sinh ra một file nhị phân nhỏ (khoảng chục MB) để **ghi nhớ liên tục các block bị chỉnh sửa**. Khi RMAN khởi động Incremental Level 1, thay vì quét toàn ổ cứng, RMAN chỉ việc hỏi file BCT: "Hôm qua có cụm nào đổi?" → Kết quả là tốc độ Backup Level 1 nhanh gấp hàng chục lần!

**Lệnh quản trị BCT:**
```sql
-- 1. Kích hoạt BCT (Thực thi trong SQLPlus khi quyền SYSDBA)
SQL> ALTER DATABASE ENABLE BLOCK CHANGE TRACKING;
-- Lệnh sẽ tự động tạo file lưu ở thư mục DB_CREATE_FILE_DEST

-- 2. Tắt BCT
SQL> ALTER DATABASE DISABLE BLOCK CHANGE TRACKING;

-- 3. Kiểm tra trạng thái hiện hành
SQL> SELECT STATUS, FILENAME FROM V$BLOCK_CHANGE_TRACKING;
```

> [!WARNING]
> Quy tắc vàng trong BCT: Không bao giờ được lưu file BCT trong phân vùng FRA (Fast Recovery Area). BCT là dữ liệu hoạt động quản trị, không phải là Data phục hồi, lưu trong FRA sẽ khiến quản lý dung lượng FRA sai lệch.

### 4. Thiết lập siêu việt: Incrementally Updated Backups

Đây là công nghệ tiên tiến nhất tiết kiệm thời gian khôi phục (Recovery Time).
- Thay vì lấy Level 0 và đắp đắp các file Incremental Level 1 lên vào ngày hệ thống bị sập.
- Tính năng này sử dụng **Image Copy** làm gốc. Mỗi đêm, nó lấy bản thay đổi Incremental Level 1 **GỘP (MERGE) TRỰC TIẾP** vào thẻ Image Copy cũ.
- Kết quả: Sáng ra, bạn luôn có 1 chiếc thẻ "Full Image Copy Cực Mới" để dùng RTO tốc độ ánh sáng!

**Lệnh RMAN cấu hình (Chạy trong khối RUN block mỗi ngày):**
```sql
RUN {
  -- Bước 1: Gộp bản Incremental của hôm qua vào Image Copy gốc. 
  -- (Ngày đầu tiên chưa có gì, câu lệnh sẽ skip an toàn).
  RECOVER COPY OF DATABASE WITH TAG 'incr_update';
  
  -- Bước 2: Tạo ra mảng Incremental Level 1 của hôm nay. 
  -- Cụm từ 'FOR RECOVER OF COPY' chỉ định mảng này sinh ra cốt để ngày mai gộp vào.
  BACKUP INCREMENTAL LEVEL 1 FOR RECOVER OF COPY WITH TAG 'incr_update' DATABASE;
}
```

**Trong Production:** Nếu Database của bạn 2-10TB, bạn KHÔNG THỂ có đủ cửa sổ thời gian backup qua đêm (Backup Window) để làm Full Backup hằng ngày. Bạn sử dụng giải pháp này. Khi DB sập lổn nhổn, thẻ Image Copy đã chờ sẵn (chỉ trễ dòng dữ liệu 1 đêm), thời gian cứu sống toàn cty sẽ giảm từ "Tạm ngưng 6h" xuống "5 phút"!

---

# 💻 Bài 15 & 16: Thực hành (Practice 5) & Tự động hóa Job

> **Mục tiêu**: Nắm kỹ quy trình tạo Level 0, Level 1, theo dõi BCT, và đặc biệt là kỹ năng Lên lịch Job tự động Cronjob (Linux) và Task Scheduler (Windows). Đời DBA thực chiến không bao giờ chạy lệnh thủ công lúc nửa đêm!

## Tình huống 1: So sánh Dung lượng Level 0 và Level 1

```sql
# 1. Chạy Level 0
RMAN> BACKUP INCREMENTAL LEVEL 0 DATABASE TAG 'DBLVL0';
# Ghi nhận Output dung lượng sinh ra cỡ GBs (Bằng kích thước dữ liệu đang dùng).

# 2. Sinh dữ liệu giả (Dùng tool Swingbench hoặc tự tạo table chạy Insert).

# 3. Chạy Level 1 (Differential)
RMAN> BACKUP INCREMENTAL LEVEL 1 DATABASE TAG 'DBLVL1';
# Output: RMAN> LIST BACKUP OF DATABASE; sẽ thấy Size cực nhẹ chỉ cỡ vài chục MBs!
```

## Tình huống 2: Kiểm tra BCT có đang thực sự "ra tay cứu trợ"?
Khi nén Incremental, RMAN có dùng BCT hay không? Truy vấn SQL ngay trong V$ Tables:
```sql
SQL> SELECT USED_CHANGE_TRACKING, FILE#, AVG(DATAFILE_BLOCKS), AVG(BLOCKS_READ)
     FROM V$BACKUP_DATAFILE
     WHERE INCREMENTAL_LEVEL > 0 
     GROUP BY USED_CHANGE_TRACKING, FILE#;
```
**Output mẫu & Giải nghĩa:**
```text
USED_CHANGE_TRACKING FILE# AVG(DATAFILE_BLOCKS) AVG(BLOCKS_READ)
-------------------- ----- -------------------- ----------------
YES                      1                89900              450
YES                      3                72000              120
```
- Nếu `USED_CHANGE_TRACKING` = `YES`: BCT đã tối ưu thành công. 
- Thay vì quét \~89,000 blocks cho System table, RMAN nhờ BCT chỉ việc đọc 450 blocks. I/O Disk tiết kiệm kinh khủng!

## Tình huống 3: Tự động hóa Backup bằng OS Linux (Cronjob)
Mọi lịch trình sao lưu cuối cùng đều phải được cài đặt chạy tự động.
```bash
# 1. Tạo Script bash rman_script.sh
#!/bin/bash
export ORACLE_SID=ORADB
export ORACLE_HOME=/u01/app/oracle/product/12.2.0/db_1

$ORACLE_HOME/bin/rman log=/home/oracle/scripts/rman.log append <<EOF
connect target '/ AS SYSBACKUP';
set echo on;
RUN {
  RECOVER COPY OF DATABASE WITH TAG 'incr_update';
  BACKUP INCREMENTAL LEVEL 1 FOR RECOVER OF COPY WITH TAG 'incr_update' DATABASE;
}
EXIT;
EOF

# 2. Nhúng vào Crontab chạy mỗi 4 tiếng
[oracle@srv1 ~]$ chmod 774 rman_script.sh
[oracle@srv1 ~]$ crontab -e
# Ghi dòng này vào Crontab:
* 0,4,8,12,16,20 * * * /home/oracle/scripts/rman_script.sh > /dev/null
```
> [!NOTE]
> Bức tường chặn mọi lính mới: Nếu Script RMAN chạy tay thành công nhưng Crontab chạy xịt thì **100% nguyên nhân là chưa `export ORACLE_SID` và `ORACLE_HOME` ở đầu Bash file**. Cron OS chạy trong không gian Môi trường rỗng!

## Tình huống 4: Tự động hóa Job trên Môi trường Windows 
Nếu cài Oracle hệ Windows, ta dùng File BAT và Task Scheduler.
```bat
REM File: C:\oracle\scripts\rman.bat
set ORACLE_SID=ORAWIN
set ORACLE_HOME=D:\oracle\product\12.2.0\dbhome_1

%ORACLE_HOME%\bin\rman cmdfile=C:\oracle\scripts\rman_cmd.ora log=C:\oracle\scripts\rman.log append
```
**Các bước trong Windows:**
Bật `Task Scheduler` > `Create Basic Task` > Đặt giờ Trigger > Trỏ Action vào file `.bat`. DBA hay đặt chạy lúc nửa đêm 1-2h sáng. Giám sát kỹ mục File Logs hằng ngày.

---

# 📊 Bảng tổng hợp & Cú pháp

| Tính Năng RMAN / Database | Lệnh thi hành | Ưu thế thực chiến |
|----------|-------------------|--------------------------------------|
| **Cột mốc Gốc (LVL 0)** | `BACKUP INCREMENTAL LEVEL 0 DATABASE;` | Quét tất cả Data. Không có LVL 0 sẽ không làm tiếp được Incrementals khác. |
| **Gói tăng dần Differential** | `BACKUP INCREMENTAL LEVEL 1 DATABASE;` | Mặc định. Block từ ngày trước đó. Siêu tiết kiệm ổ cứng lưu trữ. |
| **Gói tích lũy Cumulative** | `BACKUP INCREMENTAL LEVEL 1 CUMULATIVE DATABASE;` | Cứ lấy tịnh tiến dồn lên từ Level 0. Giảm thời gian chết (RTO) lúc phục hồi. |
| **Nhanh gấp đôi với BCT** | `ALTER DATABASE ENABLE BLOCK CHANGE TRACKING;` | Ổ cứng chạy sướng rung rinh vì không phải Full Scan Datafiles mỗi lần lấy Incremental. |
| **Merged DB (Updated Backup)** | `RECOVER COPY OF DATABASE...` | Đỉnh cao tối ưu SLA của DBA Oracle. Luôn có bản Full Copy sẵn sàng trong kho. |

---

# 🎯 Câu hỏi ôn tập tổng hợp

1. Nếu bạn chạy một bản `BACKUP INCREMENTAL LEVEL 1` nhưng RMAN tìm từ đông sang tây không thấy bất kì bản `LEVEL 0` nào làm gốc thì hành vi của RMAN lúc đó sẽ ra sao? (Nó báo lỗi hay nó tự động đi chụp luôn Database thành bản Level 0 thay thế?)
2. Hệ thống DB lõi kích thước 2.5 TB, lưu trữ Tape tốc độ yếu, mỗi tối hệ thống xử lý giao dịch khoảng 2GB thay đổi Data. Sắp xếp sơ đồ Cumulative hay Differential sẽ tối ưu tài nguyên lưu đêm hằng ngày nhất? Tại sao?
3. Tính năng `BLOCK CHANGE TRACKING` lưu file theo dạng gì và tại sao chúng ta tuyệt đối không được quẳng file BCT này vào vùng FRA (Fast Recovery Area)?
4. Hãy giải thích đoạn code tự động Linux: `* 0,4,8,12,16,20 * * * /home/script.sh`. Job Backup sẽ chạy bao nhiêu lần một ngày và tại sao cú pháp này không nên đặt giờ lẻ tẻ?
5. Câu hỏi tình huống bảo mật RMAN: Trong file `rman.bat` Windows tự lưu `connect target '/ AS SYSBACKUP'`, việc này sử dụng cơ chế bảo mật OS authentication gì và tại sao không bị lộ mật khẩu `sysdba`?

---

## ➡️ Bài tiếp theo

Sau thành tựu rực rỡ với cấu trúc Backup Incrementals, chúng ta sẽ tự tin tiến tới **Module 06: Cấu hình RMAN Persistent Settings**. Tại đó bạn sẽ học cách điều khiển vĩnh viễn hành vi RMAN như: Song song hóa 8 kênh cùng chạy (Parallelism) hay Luật giữ Backup 30 ngày tự hủy (Retention Policy). 🚀
Bạn muốn tinh chỉnh Job Cronjob thêm một chút hay bắt tay vào Module 06 ngay bây giờ? 


---

!!! info "Nguồn gốc"
    `Oracle-Database-Backup-and-Recovery-using-RMAN/modules/module_05/module_05_guide.md`
