---
title: '🚨 Báo Động Đỏ: Thảm họa mất toàn bộ Storage'
course: 02-rman-backup-recovery
source: Oracle-Database-Backup-and-Recovery-using-RMAN/reviews_all/20260418_FireDrill_StorageCrash.md
---

# 🚨 Báo Động Đỏ: Thảm họa mất toàn bộ Storage

**Chế độ**: Fire Drill + Cross-Module (Kết hợp Module 9, 10, 14, 15)
**Ngày tạo**: 2026-04-18

## 1. Tình trạng sự cố
Server chính chạy database `PRODDB` vừa bị sập nguồn gây hỏng toàn bộ mảng đĩa cứng (SAN Storage). Hệ thống đã sập hoàn toàn.
* **Đã mất toàn bộ**: Control files, Data files, và Online Redo Logs của `PRODDB`.
* **May mắn**: Các bản backup RMAN được lưu trên một NFS Share (khác mảng đĩa) vẫn còn nguyên vẹn.

## 2. Dữ kiện Hệ thống (Kiến thức chéo)
Để đáp ứng chuẩn bảo mật, cấu hình backup của công ty bạn có các đặc điểm sau:
1. **Module 10 (Encryption)**: Tất cả các bản backup trên NFS Share đều được **mã hóa bằng mật khẩu** (Password-based Encryption). Mật khẩu là `OraP@ss123`.
2. **Module 9 (Recovery Catalog)**: Do Control file đã bay màu, toàn bộ lịch sử và siêu dữ liệu backup đang được lưu giữ trong một cơ sở dữ liệu **Recovery Catalog** (có tên TNS là `RCAT`).
3. **Module 15 (Duplication)**: Do Server chính không thể dùng được nữa, Giám đốc IT yêu cầu bạn khôi phục database này ngay lập tức lên một **Server dự phòng** (hoàn toàn trống) bằng kỹ thuật **Database Duplication**.

## 3. Nhiệm vụ của DBA (Action Plan)
Đóng vai trò là Senior DBA, hãy nêu các bước và các câu lệnh cần thiết để khôi phục hệ thống trên Server dự phòng. 

**Câu hỏi gợi ý xử lý:**
1. Trạng thái của instance trên Server dự phòng phải đang ở chế độ nào trước khi bắt đầu?
2. Câu lệnh RMAN nào bạn dùng để kết nối vào hệ thống trong trường hợp này?
3. Bạn phải gõ lệnh gì để RMAN có thể đọc được bản backup bị mã hóa?
4. Lệnh Duplicate cơ bản nhất bạn sẽ sử dụng là gì?

## 4. Hướng dẫn xử lý (Action Plan - Đáp án)
Dưới đây là các bước chuẩn xác nhất của một Senior DBA để giải cứu hệ thống kết hợp kiến thức từ các Module 9, 10, 14 và 15.

### Bước 1: Chuẩn bị Auxiliary Instance (Server dự phòng)
- Mount NFS Share chứa backup vào server dự phòng.
- Tạo một file PFILE tạm (ví dụ `initPRODDB.ora`) chứa ít nhất tham số `DB_NAME=PRODDB`.
- Bật Instance ở trạng thái **NOMOUNT**:
  ```sql
  SQL> STARTUP NOMOUNT PFILE='initPRODDB.ora';
  ```

### Bước 2: Kết nối RMAN (Mô hình Không Target)
Vì Server chính đã sập hoàn toàn (mất target DB), bạn KHÔNG THỂ dùng `connect target`. Phải kết nối vào **Recovery Catalog** và **Auxiliary Instance**:
```bash
$ rman CATALOG rcat_user/password@RCAT AUXILIARY /
```

### Bước 3: Cấu hình DBID & Mật khẩu giải mã
RMAN cần biết DBID của database gốc để tìm metadata trong Catalog, và cần mật khẩu để giải mã các file backup (Module 10):
```rman
RMAN> SET DBID 12345678;
RMAN> SET DECRYPTION IDENTIFIED BY 'OraP@ss123';
```

### Bước 4: Thực hiện Duplicate Database (Module 15)
Chạy lệnh Duplicate. RMAN sẽ tự động tìm các bản backup phù hợp trong Catalog, giải mã chúng và khôi phục lên server mới.
```rman
RMAN> RUN {
  # Nếu đường dẫn lưu trữ ở server mới khác server cũ, cần thêm các lệnh SET NEWNAME hoặc DB_FILE_NAME_CONVERT tại đây.
  
  DUPLICATE DATABASE PRODDB TO PRODDB;
}
```
**Kết quả:** RMAN sẽ tự động restore control file, restore data files, recover database đến thời điểm gần nhất có thể, và `OPEN RESETLOGS` để mở database hoàn toàn mới. Hệ thống đã được cứu!


---

!!! info "Nguồn gốc"
    `Oracle-Database-Backup-and-Recovery-using-RMAN/reviews_all/20260418_FireDrill_StorageCrash.md`
