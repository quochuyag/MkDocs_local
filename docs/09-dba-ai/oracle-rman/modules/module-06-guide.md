---
title: '📘 Module 06: Cấu hình RMAN Persistent Settings'
course: 09-dba-ai
source: dba_ai/oracle_rman/modules/module_06_guide.md
---

# 📘 Module 06: Cấu hình RMAN Persistent Settings

> **Phạm vi**: Bài 17 - 18 (Cấu hình RMAN Persistent Settings) trong khóa học Oracle Database Backup and Recovery using RMAN.
> **Thời gian học ước tính**: 2 giờ
> **Tiền điều kiện**: Hệ thống lý thuyết Full Backup và Incremental Backup từ Module 04-05. Đã tiếp xúc với Control File Autobackup.

---

## 📑 Mục lục

- [Bài 17: Cấu hình Thiết lập Vĩnh viễn nâng cao](#-bài-17-cấu-hình-thiết-lập-vĩnh-viễn-nâng-cao)
- [Bài 18: Thực hành (Practice 6) cấu hình Channel & Retention](#-bài-18-thực-hành-practice-6-cấu-hình-channel--retention)
- [Bảng tổng hợp & Cú pháp](#-bảng-tổng-hợp--cú-pháp)
- [Câu hỏi ôn tập tổng hợp](#-câu-hỏi-ôn-tập-tổng-hợp)

---

# 📖 Bài 17: Cấu hình Thiết lập Vĩnh viễn nâng cao

## 🎯 Mục tiêu bài học
Sau khi hoàn thành bài này, bạn sẽ:
- ✅ Thiết lập và vận hành chính sách lưu giữ Backup (Retention Policy) theo số lượng bản (Redundancy) hoặc theo khung thời gian (Recovery Window).
- ✅ Cấu hình định dạng tên file tự động (Default FORMAT) cho mọi bản backup.
- ✅ Khởi tạo Backup song song với đa luồng kênh (Parallelism) để tối ưu thời gian I/O.
- ✅ Thiết lập chính sách xóa an toàn tự động cho Archived Redo Logs (Deletion Policy).

## 💡 Ý tưởng cốt lõi (Memory Hack)
Thuật ngữ **Persistent Settings** tức là những cấu hình được "Ghim" lại. Bạn chỉ cần gõ lệnh `CONFIGURE` 1 lần duy nhất trong đời, RMAN sẽ tự khắc ghi nhớ vào Control File của Database và áp dụng nó cho toàn bộ mọi dòng lệnh `BACKUP` từ nay về sau mà bạn không cần phải thêm tham số dài dòng!

---

## 📋 Nội dung chính

### 1. Chính sách lưu giữ Backup (Retention Policy) ⭐⭐⭐

> [!IMPORTANT]
> Cấu hình Retention Policy là cách bạn nói với RMAN: "Hãy giữ lại dữ liệu trong chừng này ngày/bản. Cái nào cũ hơn tiêu chuẩn, hãy dán nhãn là 'Hết đát - OBSOLETE' để tôi xóa dọn ổ đĩa hằng đêm!". 
> Việc này tránh cho ổ đĩa (FRA) bị tràn 100%.

RMAN cung cấp 2 trường phái cấu hình Retention (Bạn CHỈ ĐƯỢC CHỌN 1 TRONG 2, không thể bật cả hai):

#### a. Theo số lượng sao lưu (Redundancy-based)
Duy trì một số lượng bản sao Full (Hoặc Level 0) cụ thể.
```sql
RMAN> CONFIGURE RETENTION POLICY TO REDUNDANCY 3;
```
*Giải thích:* Nếu bạn tạo bản backup Full thứ 4, bản thứ 1 sẽ tự động bị RMAN chuyển trạng thái sang `OBSOLETE`. Mặc định của RMAN nếu không set gì là Redundancy = 1.

#### b. Theo khung thời gian quy định (Window-based)
Duy trì Backup đủ để DBA có thể "quay ngược thời gian" về bất kì giây phút nào trong giới hạn.
```sql
RMAN> CONFIGURE RETENTION POLICY TO RECOVERY WINDOW OF 7 DAYS;
```
*Giải thích:* Bất kì file Backup hay file Archive Log nào mà nằm "ngoài biên của 7 ngày khôi phục" sẽ biến thành Obsolete.

**Trong Production:** Các doanh nghiệp Enterprise thường áp dụng Window-Based (ví dụ `RECOVERY WINDOW OF 30 DAYS`). Tuy nhiên nếu bạn ứng dụng công nghệ *Incrementally Updated Backups* (Từ module 05), thì bắt buộc bạn phải giữ Redundancy 1, nếu không ổ cứng sẽ phình to ra vô hạn!

**Lỗi thường gặp:** 
Nhiều DBA tưởng lệnh dọn dẹp `DELETE OBSOLETE` sẽ bị chặn nếu cố tình set `RECOVERY WINDOW OF 7 DAYS` nhưng thực tế chỉ chạy backup 1 lần/tuần. Kết quả: Chả có file nào bị đánh dấu Obsolete, và FRA của bạn vẫn đầy băng! Khắc phục: Phải backup thường xuyên.

### 2. Cấu hình định dạng RMAN Output (Channel FORMAT)

Thay vì lúc nào cũng phải gõ đường dẫn dài ngoằng khi Backup, hãy cấu hình sẵn vào Channel mặc định của Disk.

**Lệnh RMAN thực thi:**
```sql
RMAN> CONFIGURE CHANNEL DEVICE TYPE DISK FORMAT '/u02/backup/orcl_df%t_s%s_p%p';
```

**Output mẫu & Giải thích:**
```text
new RMAN configuration parameters:
CONFIGURE CHANNEL DEVICE TYPE DISK FORMAT   '/u02/backup/orcl_df%t_s%s_p%p';
new RMAN configuration parameters are successfully stored
```
*Tham số bí mật:*
- `%t`: Time stamp (Định dạng thời gian độc nhất).
- `%s`: Backup Set number (Số series theo thứ tự sinh ra).
- `%p`: Piece number (Trường hợp Backup Set đó quá lớn bị cắt thành nhiều mảnh Piece).
- Điều này giải quyết thảm họa vô tình đè file cùng tên trên OS.

### 3. Khởi tạo Kênh Đa Luồng (Parallelism) 🔀

Đây là kỹ thuật thu nhỏ thời gian Backup (Backup Window). RMAN chia nhỏ công việc quét Database cho nhiều "kênh" (Channel) làm việc băm song song.

```text
CƠ CHẾ SONG SONG 2 KÊNH (PARALLELISM = 2)

[RMAN Session] ──┬──> Channel 1 ──> Datafile 1, 3, 5 ──> Tập Backup A (Disk 1)
                 └──> Channel 2 ──> Datafile 2, 4 ────> Tập Backup B (Disk 2)
```

**Lệnh RMAN thực thi cấu hình vĩnh viễn:**
```sql
RMAN> CONFIGURE DEVICE TYPE disk PARALLELISM 2;

-- Nếu công ty có 2 ổ đĩa khác nhau, ta map mỗi kênh (channel) vào 1 ổ khác biệt để Max Speed Write:
RMAN> CONFIGURE CHANNEL 1 DEVICE TYPE DISK FORMAT '/disk1/%U';
RMAN> CONFIGURE CHANNEL 2 DEVICE TYPE DISK FORMAT '/disk2/%U';
```

> [!WARNING]
> Quy luật bất hủ: Số lượng Parallelism **nên bằng hoặc nhỏ hơn** số lượng thiết bị vật lý (Disk vật lý hoặc Tape Drives). Nếu máy bạn chỉ có 1 ổ cứng HDD quay chậm, mà bạn Set Parallelism = 8, tốc độ sẽ CHẬM ĐI vì nghẽn cổ chai I/O đọc/ghi tranh chấp trên 1 mặt đĩa từ.

### 4. Thiết lập chính sách bảo vệ tự động Archive Log (Archived Redo Log Deletion Policy)

Với chính sách tự động, RMAN sẽ ngăn cản hành vi xóa log thủ công nếu Archive log đó chưa được chép an toàn vào Disk/Tape, bảo hiểm tối đa chống mất dữ liệu.

**Lệnh RMAN thực thi:**
```sql
RMAN> CONFIGURE ARCHIVELOG DELETION POLICY BACKED UP 1 TIMES TO DEVICE TYPE DISK;
```
*Giải thích*: RMAN thông báo với hệ thống Auto-cleanup của FRA: "Khoan xóa bất cứ file log nào khỏi Database, trừ khi bạn chắc chắn rằng tôi đã làm thao tác Backup nó sang vùng Disk ít nhất 1 lần mới được". 

---

# 💻 Bài 18: Thực hành (Practice 6) cấu hình Channel & Retention

> **Mục tiêu**: Cài đặt thử nghiệm Retention Policy, Format, làm quen lệnh `CLEAR` khôi phục thiết lập gốc và chạy Đa luồng (Parallelism). Cứ thao tác thoải mái vì RMAN có chức năng Reset vĩnh viễn!

## Tình huống 1: Trải nghiệm Retention Policy qua `OBSOLETE`

Chúng ta mô phỏng việc sao lưu 3 lần để ép RMAN phải nhận diện có 1 file bị dư (Obsolete):
```sql
# 1. Đặt chính sách số lượng bản (Giữ 2 bản gốc)
RMAN> CONFIGURE RETENTION POLICY TO REDUNDANCY 2;

# 2. Sinh ra 3 bản Backup của cùng 1 TableSpace (Thao tác trong 3 phút)
RMAN> BACKUP TABLESPACE users TAG 'USERS_TBS';
RMAN> BACKUP TABLESPACE users TAG 'USERS_TBS';
RMAN> BACKUP TABLESPACE users TAG 'USERS_TBS';

# 3. Kích hoạt báo cáo và Dọn dẹp
RMAN> REPORT OBSOLETE;  
# Output sẽ liệt kê bản Backup lần 1 (Cũ nhất) đã rớt khỏi danh sách được bảo vệ.

# Hãy dùng lệnh dọn rác huyền thoại (Nên để vào Cronjob hằng ngày)
RMAN> DELETE OBSOLETE;
```

## Tình huống 2: Thiết lập Định dạng (Format) Default vs Manual Channel

RMAN ưu tiên cấu hình như thế nào? 

```sql
# 1. Ấn định đường dẫn cho toàn bộ Default Disk
RMAN> CONFIGURE CHANNEL DEVICE TYPE DISK FORMAT '/media/sf_extdisk/%U.bkp';

# Lệnh này sẽ tự bay thẳng vào Output format trên:
RMAN> BACKUP TABLESPACE users TAG 'USERS_TBS'; 

# 2. XÓA BỎ Thiết lập vĩnh viễn vừa lưu (Trả về RMAN nguyên thủy)
RMAN> CONFIGURE CHANNEL DEVICE TYPE DISK CLEAR;

# 3. Sử dụng GHI ĐÈ bằng phân bổ luồng thủ công (ALLOCATE CHANNEL):
RMAN> RUN {
  ALLOCATE CHANNEL c1 DEVICE TYPE disk FORMAT '/media/sf_extdisk/oradb_%t_s%s_p%p';
  BACKUP TABLESPACE users TAG 'USERS_TBS';
}
# Allocate channel thủ công sẽ GHI ĐÈ (Override) luôn cấu hình Default ở trên.
```

## Tình huống 3: Ràng buộc Song Song (Parallelism)
Ta cấu hình và quan sát Log để hình dung chia tải.
```sql
# 1. Thiết lập 2 kênh chạy song hành thay vì 1 (mặc định)
RMAN> CONFIGURE DEVICE TYPE disk PARALLELISM 2; 

# 2. Chạy thử Backup và soi kĩ Log Output
RMAN> BACKUP DATABASE TAG 'DB_FULL';
```
**Output mẫu:**
```text
allocated channel: ORA_DISK_1
allocated channel: ORA_DISK_2
channel ORA_DISK_1: starting full datafile backup set
channel ORA_DISK_2: starting full datafile backup set
channel ORA_DISK_1: specifying datafile(s) in backup set
input datafile file number=00001 name=/u01/app/.../system01.dbf
channel ORA_DISK_2: specifying datafile(s) in backup set
input datafile file number=00003 name=/u01/app/.../sysaux01.dbf
```
*Giải thích*: Cùng 1 mốc thời gian, `ORA_DISK_1` gánh File System01, còn `ORA_DISK_2` đang cày File SysAux01. Chia đôi việc, giảm phân nửa thời gian trích xuất! Đây là nền tảng để DBA tối ưu hệ thống! 

---

# 📊 Bảng tổng hợp & Cú pháp

| Mục Đích / Tùy chọn Persistent | Lệnh thực thi kinh điển (Chỉ cần 1 lần) | Diễn giải chức năng |
|----------|-------------------|--------------------------------------|
| **Cấu hình Retention Windows** | `CONFIGURE RETENTION POLICY TO RECOVERY WINDOW OF 7 DAYS;` | Backup quá hạn 7 ngày sẽ bị dán nhãn Obsolete. Dùng nhiều trong Doanh nghiệp. |
| **Cấu hình Redundancy** | `CONFIGURE RETENTION POLICY TO REDUNDANCY 3;` | Giữ số bản Copy nhất định. Dùng kết hợp Incrementally Updated Backup. |
| **Reset Tùy chỉnh (Đưa về gốc)** | `CONFIGURE RETENTION POLICY CLEAR;` | Chữ `CLEAR` dùng để Undo bất cứ lệnh Configure nào trở về trạng thái Default. |
| **Dọn Rác Hệ thống** | `DELETE OBSOLETE;` | Giải phóng dung lượng FRA. Nếu không có bước set Retention, lệnh này không sinh ra rác. |
| **Song song Đa luồng** | `CONFIGURE DEVICE TYPE disk PARALLELISM 2;` | Backup siêu tốc bằng cách bắn Datafiles cho 2 channel cày chung một lúc. |

---

# 🎯 Câu hỏi ôn tập tổng hợp

1. Theo bạn, lệnh `CONFIGURE RETENTION POLICY TO NONE;` (Vô hiệu hóa vĩnh viễn chính sách) có đi kèm rủi ro cực lớn gì đối với không gian ổ cứng Fraud Recovery Area (FRA) và lệnh `DELETE OBSOLETE`?
2. Trong doanh nghiệp sử dụng Băng từ (Tape Drive - sbt) có tốc độ rất chậm, bạn có một Tape Drive vật lý duy nhất. Bạn set `PARALLELISM = 4` với hi vọng Backup qua Tape sẽ nhanh hơn 4 lần. Kết cục đau lòng nào sẽ diễn ra?
3. Trình bày rõ sự ghi đè theo thứ tự khi sử dụng tham số FORMAT. Giới hạn `ALLOCATE CHANNEL ... FORMAT ...` trong khối `RUN {}` có mạnh hơn `CONFIGURE CHANNEL` được set vĩnh viễn không?
4. Thiết lập `ARCHIVELOG DELETION POLICY BACKED UP 1 TIMES` bảo vệ an toàn cho Server Database như thế nào khi gặp các DBA non tay hoặc các đoạn script crontab Linux dọn ổ cứng có chứa lệnh `DELETE ARCHIVELOG`?

---

## ➡️ Bài tiếp theo

Bây giờ RMAN của bạn đã trở nên "Thông minh và Tự động sinh tồn", chúng ta sẽ chuyển sang một phần cực kì quan trọng: Giám sát toàn cục. 
Đó là **Module 07: Reporting and Monitoring RMAN Backups and Jobs**. Nếu bạn rành mạch lệnh `REPORT` và kiểm tra `LIST`, sếp hỏi "Hệ thống tháng qua backup thành công bao nhiêu lần", bạn sẽ trích thẳng báo cáo siêu mượt mà. 🚀 

Bạn muốn ôn lại cấu hình Multi-channel để tăng tốc hay muốn qua học cách Reporting báo cáo thông tin Dashboard ngay lập tức? 


---

!!! info "Nguồn gốc"
    `dba_ai/oracle_rman/modules/module_06_guide.md`
