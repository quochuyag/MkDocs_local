---
title: 'Bài 69: Quản lý Archived Redo Log Files (Archive Log)'
course: 01-oracle-dba-zero-to-hero
source: Oracle-Database-Administration-from-Zero-to-Hero/VN/69-archived-redo-log-files.md
---

# Bài 69: Quản lý Archived Redo Log Files (Archive Log)

## Mục tiêu
Sau bài học này, bạn sẽ có thể:
- Hiểu sự khác biệt sống còn giữa chế độ **NOARCHIVELOG** và **ARCHIVELOG**.
- Nắm vững vai trò của tiến trình nền **ARCn (Archiver)** trong việc tạo bản sao vĩnh viễn của Redo Log.
- Cấu hình các vị trí lưu trữ Archive Log thông qua tham số `LOG_ARCHIVE_DEST_n` và tích hợp với FRA.
- Định dạng quy chuẩn đặt tên file Archive Log bằng `LOG_ARCHIVE_FORMAT`.
- Nắm vững quy trình các bước chuyển đổi Database sang chế độ ARCHIVELOG.
- Hiểu cách thức kiểm tra trạng thái lưu trữ qua lệnh `ARCHIVE LOG LIST`.

---

## 1. So sánh Chế độ NOARCHIVELOG và ARCHIVELOG

![Archivelog Architecture](123-124-managing-the-archived-redo-log-files/images/managing-the-archived-redo-log-01.png)

| Tiêu chí | Chế độ NOARCHIVELOG | Chế độ ARCHIVELOG |
| :--- | :--- | :--- |
| **Bảo vệ dữ liệu** | Chỉ chống được sự cố sập nguồn (Instance Failure). **Không bảo vệ được khi hỏng đĩa vật lý (Media Failure)**. | **Bảo vệ toàn vẹn dữ liệu** ngay cả khi đĩa cứng bị hỏng hoàn toàn. |
| **Khả năng phục hồi** | Chỉ có thể phục hồi về thời điểm của bản sao lưu Cold Backup gần nhất $\rightarrow$ **Mất sạch dữ liệu từ lúc backup đến lúc crash**. | Phục hồi dữ liệu đến từng giây cuối cùng (**Point-in-Time Recovery - Zero Data Loss**). |
| **Sao lưu trực tuyến** | ❌ **Không thể** Hot Backup (Bắt buộc phải tắt DB mới backup được). | ✅ **Thực hiện Hot Backup online 24/7** bình thường khi user đang thao tác. |
| **Oracle Data Guard** | ❌ Không thể thiết lập Data Guard Standby. | ✅ Là điều kiện tiên quyết bắt buộc để chạy Data Guard. |
| **Môi trường sử dụng** | Môi trường Test / Dev / POC (Proof of Concept). | **Bắt buộc 100% cho mọi hệ thống Production**. |

---

## 2. Tiến trình nền ARCn và Cơ chế Lưu trữ

- Khi Database ở chế độ ARCHIVELOG, mỗi khi xảy ra sự kiện **Log Switch** (nhóm Redo Log đầy), tiến trình nền **`ARCn` (Archiver)** sẽ tự động đọc toàn bộ dữ liệu từ nhóm Redo Log đó và sao chép ra một file riêng biệt trên đĩa gọi là **Archived Redo Log File (Archive Log)**.
- Chỉ sau khi `ARCn` sao chép xong an toàn, nhóm Redo Log đó mới được phép cho tiến trình `LGWR` tái sử dụng (ghi đè) ở chu kỳ tiếp theo.

---

## 3. Cấu hình Nơi Lưu trữ (Archive Destinations)

Oracle cho phép lưu trữ Archive Log tới tối đa **31 vị trí độc lập** (`LOG_ARCHIVE_DEST_1` đến `LOG_ARCHIVE_DEST_31`):

```sql
-- Lựa chọn 1 (Khuyến nghị): Lưu tự động vào Fast Recovery Area (FRA):
ALTER SYSTEM SET LOG_ARCHIVE_DEST_1 = 'LOCATION=USE_DB_RECOVERY_FILE_DEST' SCOPE=BOTH;

-- Lựa chọn 2: Chỉ định một thư mục cụ thể trên hệ điều hành:
ALTER SYSTEM SET LOG_ARCHIVE_DEST_1 = 'LOCATION=/u01/app/oracle/archivelog' SCOPE=BOTH;

-- Lựa chọn 3: Đồng thời đẩy Archive Log sang máy chủ Data Guard Standby từ xa:
ALTER SYSTEM SET LOG_ARCHIVE_DEST_2 = 'SERVICE=standby_db ASYNC' SCOPE=BOTH;
```

### Định dạng tên file: `LOG_ARCHIVE_FORMAT`
Khi lưu ra thư mục ngoài FRA, bạn có thể quy chuẩn tên file theo cú pháp:
```sql
ALTER SYSTEM SET LOG_ARCHIVE_FORMAT = 'arch_%t_%s_%r.arc' SCOPE=SPFILE;
```
- `%t`: Thread number (luôn là 1 ở Single Instance, 1 hoặc 2 trong cụm RAC).
- `%s`: Log sequence number (số thứ tự của redo log).
- `%r`: Resetlogs ID (định danh duy nhất của chu kỳ database).

---

## 4. Quy trình 4 Bước Bật Chế độ ARCHIVELOG

> ⚠️ **Lưu ý quan trọng:** Để chuyển đổi chế độ Archivelog, Database **bắt buộc phải được đưa về trạng thái `MOUNT`**.

```
[Database OPEN] ──► [SHUTDOWN IMMEDIATE] ──► [STARTUP MOUNT] ──► [ALTER DATABASE ARCHIVELOG] ──► [ALTER DATABASE OPEN]
```

```sql
-- Bước 1: Kết nối as sysdba và tắt database:
CONNECT / as sysdba
SHUTDOWN IMMEDIATE;

-- Bước 2: Khởi động database ở chế độ MOUNT:
STARTUP MOUNT;

-- Bước 3: Thực thi lệnh chuyển sang ARCHIVELOG:
ALTER DATABASE ARCHIVELOG;

-- Bước 4: Mở lại database cho người dùng:
ALTER DATABASE OPEN;

-- Bước 5: Kiểm tra lại trạng thái:
ARCHIVE LOG LIST;
```

---

## Câu hỏi ôn tập

**1. Tại sao doanh nghiệp bắt buộc phải bật chế độ ARCHIVELOG cho các cơ sở dữ liệu Production?**
> **Trả lời:**
> Vì chỉ có chế độ ARCHIVELOG mới cho phép:
> - **Sao lưu trực tuyến (Hot Backup / Online Backup 24/7):** Sao lưu toàn diện mà không cần phải dừng hoạt động của ứng dụng hay ngắt kết nối người dùng.
> - **Phục hồi không mất dữ liệu (Zero Data Loss):** Kết hợp bản backup cũ với chuỗi Archive Log để phục hồi dữ liệu chính xác đến đúng thời điểm 1 giây trước khi ổ đĩa bị nổ/cháy (Point-in-Time Recovery).
> - Là điều kiện bắt buộc để cấu hình giải pháp thảm họa **Oracle Data Guard**.

**2. Khi database đang ở chế độ ARCHIVELOG, nếu thư mục chứa Archive Log bị đầy 100%, chuyện gì sẽ xảy ra?**
> **Trả lời:**
> Tiến trình `ARCn` sẽ không thể tạo thêm file Archive Log mới và báo lỗi ra Alert Log. Khi các nhóm Online Redo Log tiếp tục quay vòng và gặp nhóm chưa được archive, tiến trình `LGWR` **buộc phải dừng ghi đè để bảo vệ dữ liệu**. Toàn bộ Database sẽ bị **đóng băng (Hanging)**: mọi câu lệnh INSERT, UPDATE, DELETE sẽ bị treo cho đến khi DBA giải phóng chỗ trống cho thư mục Archive Log.

**3. Tại sao khi chuyển đổi chế độ từ `NOARCHIVELOG` sang `ARCHIVELOG`, database bắt buộc phải ở trạng thái `MOUNT` mà không thể làm trực tiếp khi đang `OPEN`?**
> **Trả lời:**
> Vì trạng thái Archivelog là một thuộc tính cấu trúc toàn cục được ghi trực tiếp vào **Control File** của Database. Để thay đổi cờ trạng thái này một cách an toàn và nhất quán, Oracle yêu cầu tất cả các Datafiles phải ở trạng thái đóng (`CLOSED` - tức là ở mức `MOUNT`), nhằm đảm bảo không có bất kỳ giao dịch nào đang phát sinh trong lúc kiến trúc nhật ký hệ thống được định nghĩa lại.

**4. Ký tự `%r` trong tham số `LOG_ARCHIVE_FORMAT = 'arch_%t_%s_%r.arc'` có ý nghĩa gì?**
> **Trả lời:**
> `%r` đại diện cho **Resetlogs ID (Resetlogs SCN Stamp)**. Đây là một mã số duy nhất thay đổi mỗi khi database được mở bằng lệnh `OPEN RESETLOGS`. Việc đưa `%r` vào tên file giúp ngăn chặn tình trạng ghi đè hoặc nhầm lẫn giữa các file Archive Log có cùng số thứ tự Sequence (`%s`) được sinh ra từ các chu kỳ phục hồi khác nhau của database.

**5. Lệnh nào trong SQL*Plus cho phép xem nhanh chế độ lưu trữ Archive Log hiện hành của Database?**
> **Trả lời:**
> Sử dụng lệnh:
> ```sql
> ARCHIVE LOG LIST;
> ```
> Lệnh này sẽ hiển thị: Database log mode (`Archive Mode` hay `No Archive Mode`), Automatic archival (`Enabled`), Archive destination, và số sequence của log hiện tại.


---

!!! info "Nguồn gốc"
    `Oracle-Database-Administration-from-Zero-to-Hero/VN/69-archived-redo-log-files.md`
