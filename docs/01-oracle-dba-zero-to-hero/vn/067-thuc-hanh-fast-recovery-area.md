---
title: 'Bài 67: Thực hành - Quản lý Fast Recovery Area (FRA)'
course: 01-oracle-dba-zero-to-hero
source: Oracle-Database-Administration-from-Zero-to-Hero/VN/67-thuc-hanh-fast-recovery-area.md
---

# Bài 67: Thực hành - Quản lý Fast Recovery Area (FRA)

## Mục tiêu thực hành
Trong bài thực hành này, bạn sẽ thực hiện các thao tác quản trị hàng ngày đối với Fast Recovery Area (FRA):
- Kiểm tra trạng thái kích hoạt của FRA trên máy chủ `srv1`.
- Tính toán dung lượng tối đa được cấp phát cho FRA trong database.
- So sánh đối chiếu dung lượng logic của FRA với dung lượng vật lý thực tế của hệ thống file Linux (`df -h`).
- Khám phá cấu trúc thư mục con tự động của FRA ở tầng hệ điều hành (`ls`, `du -sh`).
- Giám sát chi tiết mức độ sử dụng không gian và tỷ lệ phần trăm theo từng loại file (`V$RECOVERY_FILE_DEST`, `V$RECOVERY_AREA_USAGE`).
- Thực hành tăng giảm kích thước FRA trực tuyến mà không cần dừng database.

---

## Sơ đồ Thực hành Quản lý FRA

![FRA Practice Structure](118-118-practice-managing-the-fast-recovery-area/images/practice-managing-the-fast-r-01.png)

---

## Các bước Thực hành Chi tiết

### Bước 1–3: Kiểm tra trạng thái FRA trong Database
Đăng nhập máy chủ `srv1` bằng user `oracle`:
```bash
sqlplus / as sysdba
```
```sql
-- Kiểm tra 2 tham số kích hoạt FRA:
SHOW PARAMETER DB_RECOVERY_FILE_DEST;
```
*Kết quả:*
- `db_recovery_file_dest`: `/u01/app/oracle/fast_recovery_area`
- `db_recovery_file_dest_size`: `12988M` (~12.6 GB)

### Bước 4–5: So sánh Dung lượng Logic và Đĩa Vật lý
```sql
-- Xem dung lượng FRA thiết lập trong database:
SELECT TO_CHAR(ROUND(VALUE/1024/1024), '999,999,999') || ' MB' AS FRA_LIMIT_SIZE
FROM V$PARAMETER
WHERE UPPER(NAME) = 'DB_RECOVERY_FILE_DEST_SIZE';

-- Kiểm tra dung lượng trống thực tế của ổ đĩa vật lý /u01:
HOST df -h /u01
```
> ⚠️ **Lưu ý của DBA:** Giá trị `DB_RECOVERY_FILE_DEST_SIZE` là **ngưỡng giới hạn logic** do DBA ấn định cho Oracle. Oracle không tự động biết ổ cứng bên dưới còn bao nhiêu GB. Nếu bạn đặt `SIZE = 100G` nhưng phân vùng `/u01` chỉ còn trống 20G, khi ghi vượt quá 20G hệ điều hành sẽ báo lỗi đầy ổ cứng (Disk Full)! Luôn đảm bảo ổ đĩa vật lý lớn hơn hoặc bằng kích thước FRA.

### Bước 6–8: Khám phá Cấu trúc Thư mục FRA ở Tầng OS
```sql
-- Xem thư mục gốc FRA:
HOST ls -al /u01/app/oracle/fast_recovery_area

-- Xem thư mục bên trong tương ứng với tên Database (ORADB):
HOST ls -al /u01/app/oracle/fast_recovery_area/ORADB

-- Xem tổng dung lượng thực tế đang chiếm dụng trên đĩa:
HOST du -sh /u01/app/oracle/fast_recovery_area/ORADB
```
> **Quan sát:** Oracle tự động tạo các thư mục con theo cấu trúc OMF chuẩn:
> - `controlfile`: Chứa bản sao Control File (`o1_mf_...`).
> - `onlinelog`: Chứa bản sao Redo Log Member.
> - `archivelog`: Chứa các file Archive Log gom nhóm theo ngày.
> - `autobackup`: Chứa các bản sao lưu tự động của Control File và SPFILE.

### Bước 9–10: Giám sát Tỷ lệ Sử dụng Không gian FRA
```sql
-- Truy vấn tổng quan dung lượng đã dùng và có thể thu hồi:
COL SPACE_LIMIT_MB FORMAT 999,999
COL SPACE_USED_MB FORMAT 999,999
COL RECLAIMABLE_MB FORMAT 999,999
COL PCT_USED FORMAT 999.99

SELECT ROUND(SPACE_LIMIT/1024/1024) AS SPACE_LIMIT_MB,
       ROUND(SPACE_USED/1024/1024)  AS SPACE_USED_MB,
       ROUND(SPACE_RECLAIMABLE/1024/1024) AS RECLAIMABLE_MB,
       ROUND((SPACE_USED - SPACE_RECLAIMABLE) / SPACE_LIMIT * 100, 2) AS PCT_USED
FROM V$RECOVERY_FILE_DEST;

-- Xem chi tiết từng loại file chiếm bao nhiêu % trong FRA:
COL FILE_TYPE FORMAT A20
SELECT FILE_TYPE, PERCENT_SPACE_USED, PERCENT_SPACE_RECLAIMABLE, NUMBER_OF_FILES
FROM V$RECOVERY_AREA_USAGE;
```

### Bước 11: Thay đổi Kích thước FRA Trực tuyến
Khi nhận thấy dung lượng sử dụng đạt trên 80%, DBA có thể tăng dung lượng ngay lập tức:
```sql
-- Tăng kích thước FRA lên 15GB:
ALTER SYSTEM SET DB_RECOVERY_FILE_DEST_SIZE = 15G SCOPE=BOTH;

-- Kiểm tra lại:
SHOW PARAMETER DB_RECOVERY_FILE_DEST_SIZE;
```

---

## Câu hỏi ôn tập

**1. Nếu phân vùng ổ cứng Linux `/u01` chỉ còn trống 5 GB, nhưng DBA lại gõ lệnh `ALTER SYSTEM SET DB_RECOVERY_FILE_DEST_SIZE = 50G;`, câu lệnh có báo lỗi không? Điều gì sẽ xảy ra sau đó?**
> **Trả lời:**
> Câu lệnh **KHÔNG báo lỗi** và thực thi thành công ngay lập tức!
> Bởi vì `DB_RECOVERY_FILE_DEST_SIZE` là một giới hạn logic nội bộ của Oracle. Tuy nhiên, khi cơ sở dữ liệu tiếp tục hoạt động và ghi các file backup/archive log vượt quá 5 GB dung lượng thực tế, hệ điều hành Linux sẽ báo lỗi **`No space left on device` (Hết dung lượng đĩa vật lý)** và database sẽ bị treo. Do đó, DBA phải luôn đồng bộ giữa quota của database và dung lượng đĩa vật lý (`df -h`).

**2. Lệnh Linux nào dùng để xem nhanh dung lượng thực tế của thư mục FRA trên máy chủ?**
> **Trả lời:**
> Sử dụng lệnh **`du -sh <đường_dẫn_thư_mục>`**:
> ```bash
> du -sh /u01/app/oracle/fast_recovery_area/ORADB
> ```
> Tham số `-s` (summary) và `-h` (human-readable: KB, MB, GB).

**3. Tại sao trong thư mục FRA lại có các thư mục con mang tên `controlfile`, `onlinelog`, `archivelog` mà không phải do DBA tự tay tạo ra?**
> **Trả lời:**
> Do tính năng **Oracle Managed Files (OMF)** được tự động kích hoạt bên trong vùng FRA. Oracle Database Engine tự động phân loại, tạo các thư mục con theo danh mục tệp tin và tự động sinh tên file chuẩn hóa (`o1_mf_...`) mà không cần con người can thiệp tạo thư mục thủ công.

**4. Khi view `V$RECOVERY_FILE_DEST` báo `SPACE_USED = 10GB` và `SPACE_RECLAIMABLE = 6GB`, dung lượng thực sự "không thể xóa" đang bị chiếm giữ là bao nhiêu?**
> **Trả lời:**
> Dung lượng thực sự không thể xóa (dữ liệu bắt buộc phải giữ lại) là:
> $$\text{Dung lượng bắt buộc} = \text{SPACE\_USED} - \text{SPACE\_RECLAIMABLE} = 10\text{ GB} - 6\text{ GB} = \mathbf{4\text{ GB}}$$
> 6 GB còn lại là các tệp tin tạm thời lỗi thời (như archive log đã backup xong hoặc bản backup RMAN cũ) mà Oracle sẵn sàng tự động ghi đè/xóa bỏ bất kỳ lúc nào nếu database cần thêm chỗ trống.

**5. View nào cho biết chi tiết tỷ lệ phần trăm dung lượng mà các file RMAN Backups hay Flashback Logs đang chiếm dụng trong FRA?**
> **Trả lời:**
> Đó là Dynamic Performance View **`V$RECOVERY_AREA_USAGE`**.
> View này phân rã chi tiết từng dòng theo `FILE_TYPE` (`CONTROLFILE`, `ONLINELOG`, `ARCHIVEDLOG`, `BACKUPPIECE`, `IMAGECOPY`, `FLASHBACKLOG`) cùng tỷ lệ `%` chiếm dụng tương ứng.


---

!!! info "Nguồn gốc"
    `Oracle-Database-Administration-from-Zero-to-Hero/VN/67-thuc-hanh-fast-recovery-area.md`
