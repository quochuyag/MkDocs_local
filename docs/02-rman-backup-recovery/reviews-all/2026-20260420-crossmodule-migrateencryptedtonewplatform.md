---
title: '🔗 Kiến Trúc Chéo: Chuyển Nền Tảng (Cross-Platform) Đóng Gói Mã Hóa'
course: 02-rman-backup-recovery
source: Oracle-Database-Backup-and-Recovery-using-RMAN/reviews_all/20260420_CrossModule_MigrateEncryptedToNewPlatform.md
---

# 🔗 Kiến Trúc Chéo: Chuyển Nền Tảng (Cross-Platform) Đóng Gói Mã Hóa

**Chế độ**: Kiến trúc chéo (Cross-Module: Module 10 + 14)
**Ngày tạo**: 2026-04-20

## 1. Tình huống doanh nghiệp
Tập đoàn quyết định ngưng sử dụng máy chủ UNIX Solaris cũ (đắt đỏ) và chuyển dịch toàn bộ cơ sở dữ liệu hệ thống Nhân sự `HRDB` sang máy chủ mới chạy hệ điều hành Red Hat Linux.

Bảng lương và thông tin cá nhân của nhân sự nằm gọn trong Tablespace `HR_DATA`.
Bạn quyết định sử dụng tính năng **Cross-Platform Transportable Tablespace** (sử dụng Backup Sets) để mang tablespace `HR_DATA` từ Solaris sang Linux.
**Vấn đề Pháp lý**: Do luật bảo vệ dữ liệu, bộ phận Bảo mật yêu cầu file backup khi trung chuyển qua mạng hoặc lưu trên ổ USB/ổ chung phải được **Mã Hóa (Encrypted)** bằng mật khẩu (Password-Based Encryption). Không ai được quyền nhòm ngó file backup này trong quá trình di chuyển.

## 2. Nhiệm vụ của bạn (DBA)
Thiết kế Workflow xử lý bài toán Cross-Platform kết hợp mã hóa:
1. Lệnh thiết lập mật khẩu mã hóa trên Source.
2. Lệnh backup Cross-Platform.
3. Lệnh giải mã và Import trên Target.

---

## 4. Hướng dẫn xử lý (Action Plan - Đáp án)

Đây là kịch bản rất thực tế trong các dự án di chuyển Datacenter kết hợp chuẩn bảo mật PCI-DSS/GDPR.

### Bước 1: Thao tác trên Source DB (Solaris)
Mở tablespace ở chế độ Read-Only để dữ liệu được đồng nhất.
```sql
SQL> ALTER TABLESPACE hr_data READ ONLY;
```

Mở RMAN, thiết lập mật khẩu mã hóa (Password-Based Encryption).
```rman
RMAN> SET ENCRYPTION ON IDENTIFIED BY 'HR$ecret2026' ONLY;
```

Thực hiện lệnh backup tablespace chuyên biệt cho Cross-Platform. Tham số `ALLOW INCONSISTENT` có thể được bỏ nếu TS đã READ ONLY, nhưng `FOR TRANSPORT` là bắt buộc.
```rman
RMAN> BACKUP AS COMPRESSED BACKUPSET 
      TO PLATFORM 'Linux x86 64-bit' 
      FORMAT '/tmp/export/hr_data_encrypted_%U.bkp'
      DATAPUMP FORMAT '/tmp/export/hr_data_metadata.dmp'
      TABLESPACE hr_data;
```
*(Trong Oracle 12c, RMAN tích hợp sẵn sinh file dump metadata của Datapump luôn ngay trong lệnh backup này).*

### Bước 2: Trung chuyển file (OS Level)
Sử dụng `scp` hoặc `sftp` để mang 2 file: `hr_data_encrypted_*.bkp` và `hr_data_metadata.dmp` sang máy chủ Linux mới. Trong lúc di chuyển, file `.bkp` hoàn toàn được mã hóa chuẩn AES256.

### Bước 3: Thao tác trên Target DB (Linux)
Tại RMAN của máy Linux đích, bạn cần nhập lại đúng mật khẩu để giải mã:
```rman
RMAN> SET DECRYPTION IDENTIFIED BY 'HR$ecret2026';
```

Thực hiện lệnh RESTORE FOREIGN TABLESPACE để đưa các Datafile vào hệ thống mới (RMAN sẽ tự động chuyển đổi Byte Order - Endianness nếu khác nhau giữa Solaris và Linux).
```rman
RMAN> RESTORE FOREIGN TABLESPACE hr_data 
      FORMAT '/u01/app/oracle/oradata/LINUXDB/%U'
      FROM BACKUPSET '/tmp/import/hr_data_encrypted_%U.bkp';
```

### Bước 4: Import Metadata
Cuối cùng, dùng lệnh OS `impdp` để nạp file `hr_data_metadata.dmp` vào Database Linux đích, để DB nhận diện được Datafile vật lý vừa được restore xong.
Đưa tablespace trở lại `READ WRITE`. Thành công!


---

!!! info "Nguồn gốc"
    `Oracle-Database-Backup-and-Recovery-using-RMAN/reviews_all/20260420_CrossModule_MigrateEncryptedToNewPlatform.md`
