---
title: 'Bài 81: Thực hành - Cấu hình RMAN Persistent Settings'
course: 01-oracle-dba-zero-to-hero
source: Oracle-Database-Administration-from-Zero-to-Hero/VN/81-thuc-hanh-rman-settings.md
---

# Bài 81: Thực hành - Cấu hình RMAN Persistent Settings

## Mục tiêu
Trong bài thực hành này, bạn sẽ thực hiện các thao tác:
- Cấu hình lại các thiết lập mặc định của RMAN (Persistent settings).
- Thực hành quản lý Retention Policy (Chính sách lưu giữ).
- Quản lý và xử lý các bản backup Obsolete và Expired.

## A. Quản lý RMAN Persistent Settings

**1.** Mở terminal và đăng nhập vào `srv1` với quyền `oracle`.

**2.** Khởi động RMAN và kết nối với target database.
```bash
rman target /
```

**3.** Xem toàn bộ các cấu hình mặc định (Persistent settings) hiện tại.
```rman
SHOW ALL;
```

**4.** Định cấu hình mặc định để nén các bản backupset.
```rman
CONFIGURE DEVICE TYPE DISK BACKUP TYPE TO COMPRESSED BACKUPSET;
```

**5.** Thực hiện một bản backup toàn bộ database mà không cần gõ từ khóa `COMPRESS` (để kiểm chứng thiết lập trên).
```rman
BACKUP DATABASE;
```

**6.** Liệt kê các bản backup và xem qua kết quả để chắc chắn nó đã được nén (xem cột `Size`).
```rman
LIST BACKUP OF DATABASE SUMMARY;
```

**7.** Xóa thiết lập nén, trả nó về trạng thái mặc định ban đầu của RMAN.
```rman
CONFIGURE DEVICE TYPE DISK BACKUP TYPE TO BACKUPSET;
-- Hoặc sử dụng: CONFIGURE DEVICE TYPE DISK CLEAR;
```

## B. Quản lý Retention Policy (Chính sách lưu giữ)

**8.** Thiết lập Retention Policy thành Recovery Window là 7 ngày.
```rman
CONFIGURE RETENTION POLICY TO RECOVERY WINDOW OF 7 DAYS;
```

**9.** Xem lại các thiết lập RMAN để kiểm tra.
```rman
SHOW ALL;
```

**10.** Yêu cầu RMAN báo cáo các file backup đã trở nên cũ/thừa (Obsolete) theo chính sách 7 ngày này.
```rman
REPORT OBSOLETE;
```
*(Nếu database của bạn mới tạo, có thể sẽ không có file nào báo cáo).*

**11.** Bây giờ, đổi Retention Policy sang dạng Độ dư thừa (Redundancy) là 2.
```rman
CONFIGURE RETENTION POLICY TO REDUNDANCY 2;
```

**12.** Kiểm tra lại xem có file nào Obsolete không.
```rman
REPORT OBSOLETE;
```

**13.** Trả cấu hình Retention Policy về mặc định của Oracle (Redundancy 1).
```rman
CONFIGURE RETENTION POLICY CLEAR;
```

**14.** Tiếp tục báo cáo các file Obsolete.
```rman
REPORT OBSOLETE;
```
*(Lần này có thể bạn sẽ thấy có file Obsolete, vì mặc định chỉ giữ lại 1 bản backup gần nhất, các bản cũ hơn sẽ thừa)*.

**15.** Xóa các file backup Obsolete để giải phóng dung lượng.
```rman
DELETE OBSOLETE;
```

## C. Quản lý các file Backup bị mất (Expired)

**16.** Xóa tất cả các bản backup và image copy còn lại để dọn dẹp hệ thống.
```rman
DELETE BACKUP;
DELETE COPY OF DATABASE;
```

**17.** Tạo ra 2 bản backup của tablespace `USERS`.
```rman
BACKUP TABLESPACE users;
BACKUP TABLESPACE users;
```

**18.** Kiểm tra danh sách các bản backup vừa tạo.
```rman
LIST BACKUP OF TABLESPACE users;
```
*(Ghi chú lại đường dẫn vật lý (Piece Name) của bản backup đầu tiên).*

**19.** Mở một terminal khác (phiên làm việc Linux) và xóa vật lý file backup đầu tiên bằng lệnh `rm`.
```bash
rm /u01/app/oracle/fast_recovery_area/ORCL/backupset/.../<tên_file>.bkp
```

**20.** Quay lại RMAN, kiểm tra xem RMAN có biết file này bị mất không.
```rman
LIST BACKUP OF TABLESPACE users;
```
*(Trạng thái (Status) vẫn là AVAILABLE, do RMAN không tự động kiểm tra hệ điều hành).*

**21.** Dạy RMAN kiểm tra lại thực tế ổ đĩa bằng lệnh Crosscheck.
```rman
CROSSCHECK BACKUP;
```
*(RMAN sẽ phát hiện ra file bị mất và đánh dấu nó là EXPIRED)*.

**22.** Kiểm tra lại danh sách backup.
```rman
LIST BACKUP OF TABLESPACE users;
```
*(Lúc này trạng thái của bản backup thứ nhất đã chuyển từ AVAILABLE sang EXPIRED).*

**23.** Xóa dòng thông tin về bản backup Expired này khỏi RMAN repository.
```rman
DELETE EXPIRED BACKUP;
```
*(Nhấn `Y` để xác nhận).*

**24.** Dọn dẹp lại hệ thống một lần nữa.
```rman
DELETE BACKUP;
```

---
## Câu hỏi ôn tập

**Câu 1: Lệnh nào giúp bạn xem nhanh tất cả các thiết lập RMAN mà bạn đã từng chỉnh sửa (khác với mặc định)?**
- **Trả lời:** Chạy lệnh `SHOW ALL;`. Bạn sẽ thấy các thiết lập có dấu `# default` (là mặc định chưa đụng tới) và các dòng không có chữ đó (là các thiết lập đã bị chỉnh sửa).

**Câu 2: Làm sao để cài đặt RMAN tự động tạo bản backup nén (compressed) mà không cần ghi rõ trong lệnh BACKUP?**
- **Trả lời:** Dùng lệnh: `CONFIGURE DEVICE TYPE DISK BACKUP TYPE TO COMPRESSED BACKUPSET;`

**Câu 3: Mục đích của lệnh `DELETE OBSOLETE` là gì?**
- **Trả lời:** Nó dùng để xóa các bản sao lưu (cả vật lý trên ổ cứng lẫn trong repository) không còn cần thiết nữa để duy trì chính sách `RETENTION POLICY` đã cài đặt, qua đó giải phóng không gian ổ cứng.

**Câu 4: Khi nào một file chuyển sang trạng thái EXPIRED?**
- **Trả lời:** Khi bạn chạy lệnh `CROSSCHECK`, và RMAN phát hiện ra file backup vật lý được ghi trong repository không còn tồn tại trên hệ điều hành nữa.

**Câu 5: Lệnh `DELETE EXPIRED` có làm giải phóng dung lượng đĩa không?**
- **Trả lời:** Không. Vì bản chất file đó đã bị ai đó xóa ngoài hệ điều hành (làm cho nó biến mất rồi). Lệnh `DELETE EXPIRED` chỉ xóa "thông tin" (metadata) của file đó trong Control file/Recovery Catalog để dọn dẹp kho lưu trữ RMAN cho sạch sẽ.


---

!!! info "Nguồn gốc"
    `Oracle-Database-Administration-from-Zero-to-Hero/VN/81-thuc-hanh-rman-settings.md`
