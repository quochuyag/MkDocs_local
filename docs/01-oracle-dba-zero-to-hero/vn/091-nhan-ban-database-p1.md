---
title: 'Bài 91: Nhân bản Database bằng RMAN (Phần I)'
course: 01-oracle-dba-zero-to-hero
source: Oracle-Database-Administration-from-Zero-to-Hero/VN/91-nhan-ban-database-p1.md
---

# Bài 91: Nhân bản Database bằng RMAN (Phần I)

## Mục tiêu
Trong bài học này, bạn sẽ học các nội dung sau:
- Các kỹ thuật nhân bản (Cloning/Duplicating) database.
- Các yêu cầu tiên quyết (Prerequisites) để thực hiện Duplication.
- Các bước chuẩn bị cho máy chủ đích (Auxiliary Instance Host).
- Cấu hình vị trí thư mục lưu trữ file cho Database mới.

## Tổng quan về lệnh DUPLICATE
RMAN cung cấp lệnh `DUPLICATE` để tự động hóa quá trình copy một database đang hoạt động (Source) sang một database mới (Duplicate/Auxiliary).
Các kỹ thuật nhân bản bao gồm:
1. **Từ Active Database (Database nguồn đang chạy):** 
   - Dữ liệu được chép trực tiếp qua mạng (Network) từ Database nguồn sang Database đích.
   - Thường yêu cầu băng thông mạng lớn và ổn định.
2. **Từ các file Backup:**
   - **Có kết nối tới Database nguồn:** RMAN lấy thông tin về các file backup từ Control file của nguồn.
   - **Có kết nối tới Recovery Catalog:** RMAN lấy thông tin backup từ Catalog.
   - **Không có kết nối (Chỉ có các file vật lý):** Quản trị viên phải chỉ định thư mục chứa file backup bằng tham số `BACKUP LOCATION`.

## RMAN thực hiện Duplicate như thế nào ở chế độ ngầm?
Khi bạn chạy lệnh `DUPLICATE`, RMAN sẽ làm các bước sau:
1. Khởi động *Auxiliary instance* (database đích) ở chế độ `NOMOUNT`.
2. Tự động cấp phát các luồng (channels).
3. Restore lại database đích và thực hiện Recovery (nếu cần thiết, dựa trên archive log gần nhất hoặc điểm PITR chỉ định).
4. **Tạo ra một DBID hoàn toàn mới** cho database đích (để tránh xung đột hệ thống).
5. Mở database đích bằng `OPEN RESETLOGS`.

## Điều kiện tiên quyết (Prerequisites)
- Source Database và Duplicate Database **bắt buộc phải cùng nền tảng hệ điều hành (Platform)** (Ví dụ: Cùng là Linux x86_64).
- Để kết nối giữa 2 máy chủ, Auxiliary instance phải được đăng ký **Tĩnh (Static Registration)** trong file `listener.ora` của máy chủ đích.
- Phải thiết lập Oracle Net Services (cấu hình `tnsnames.ora`) để máy chủ này "thấy" được máy chủ kia.

## Các bước chuẩn bị Máy chủ đích (Auxiliary Instance Host)
Trước khi gõ lệnh `DUPLICATE`, bạn phải thiết lập máy chủ đích:
1. Tạo các thư mục vật lý (`mkdir`) để chứa datafiles, redo logs, control files.
2. Tạo file cấu hình tham số khởi tạo (Initialization Parameter File - `pfile` hoặc `spfile`) dạng cơ bản nhất.
3. Tạo file mật khẩu (Password file) - có thể copy file này từ máy chủ nguồn sang.
4. Cấu hình Listener tĩnh và khởi động Auxiliary instance lên trạng thái `NOMOUNT`.

## Cấu hình thay đổi tên/đường dẫn File
Vì database mới thường có cấu trúc thư mục khác (hoặc trùng máy chủ nhưng khác tên thư mục), RMAN cung cấp nhiều cách để đổi tên file trên đường bay:
- **Dùng tham số cấu hình pfile:** `DB_FILE_NAME_CONVERT` và `LOG_FILE_NAME_CONVERT`.
  ```text
  DB_FILE_NAME_CONVERT = ('/oradata/oradb1', '/oradata/oradb2')
  ```
- **Dùng lệnh `SET NEWNAME` trong khối lệnh RUN:**
  ```rman
  RUN {
    SET NEWNAME FOR DATABASE TO '/oradata/newdb/%U';
    ...
  }
  ```
  *(Biến `%U` sẽ sinh ra một chuỗi ký tự duy nhất tự động cho file).*

## Bỏ qua các Tablespace (Subset Duplication)
Nếu database nguồn quá lớn (vài TB) nhưng bạn chỉ muốn clone một phần dữ liệu (vd: dữ liệu HR) để dev test, bạn có thể loại trừ các tablespace không cần thiết:
```rman
DUPLICATE DATABASE TO oradb2 SKIP TABLESPACE sales, history;
```
*(Ghi chú: SYSTEM, SYSAUX và UNDO là các tablespace hệ thống, luôn luôn được tự động chép qua, không thể SKIP).*

---
## Câu hỏi ôn tập

**Câu 1: Lệnh `DUPLICATE` có giữ nguyên DBID của database nguồn cho database đích không?**
- **Trả lời:** Không. RMAN tự động tạo ra một DBID (Database Identifier) hoàn toàn mới cho database đích. Điều này giúp hệ thống (và Recovery Catalog) nhận diện đây là một database độc lập, không bị trùng lặp với bản gốc.

**Câu 2: Tại sao Auxiliary Instance (Database đích) bắt buộc phải được đăng ký "Tĩnh" (Static) trong Listener?**
- **Trả lời:** Vì ở giai đoạn đầu của việc nhân bản, database đích đang ở trạng thái `NOMOUNT` (hoặc thậm chí chưa có control file). Tính năng đăng ký động (Dynamic Registration) của Oracle không hoạt động hiệu quả khi database chưa khởi động hoàn toàn. Cấu hình tĩnh đảm bảo RMAN từ xa luôn có thể kết nối vào instance phụ này.

**Câu 3: Kỹ thuật "Active Database Duplication" sao chép dữ liệu thông qua con đường nào?**
- **Trả lời:** Nó sao chép dữ liệu trực tiếp qua đường truyền mạng (Oracle Net) từ Database đang chạy sang Database mới, không cần sử dụng đến bất kỳ file backup trung gian nào.

**Câu 4: Tham số `DB_FILE_NAME_CONVERT` dùng để làm gì?**
- **Trả lời:** Nó dùng để chuyển đổi hàng loạt đường dẫn (path) của các datafiles từ thư mục của database gốc sang thư mục của database mới một cách tự động (Ví dụ: đổi từ chữ `oradb1` thành `oradb2`).

**Câu 5: Khi nhân bản một tập con (subset), ta có thể dùng tham số `SKIP TABLESPACE SYSTEM` được không?**
- **Trả lời:** Không. Các tablespace hệ thống như SYSTEM, SYSAUX và UNDO chứa từ điển dữ liệu lõi của Oracle, do đó chúng luôn bắt buộc phải được nhân bản. Bạn chỉ có thể bỏ qua (SKIP) các tablespace chứa dữ liệu người dùng.


---

!!! info "Nguồn gốc"
    `Oracle-Database-Administration-from-Zero-to-Hero/VN/91-nhan-ban-database-p1.md`
