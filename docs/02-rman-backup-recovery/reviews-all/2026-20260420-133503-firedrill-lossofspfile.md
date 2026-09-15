---
title: '🚨 Báo Động Đỏ: Khởi Động Thất Bại Vì Mất SPFILE'
course: 02-rman-backup-recovery
source: Oracle-Database-Backup-and-Recovery-using-RMAN/reviews_all/20260420_133503_FireDrill_LossOfSPFILE.md
---

# 🚨 Báo Động Đỏ: Khởi Động Thất Bại Vì Mất SPFILE

**Chế độ**: Fire Drill (Diễn tập sự cố khẩn cấp - Module 12)
**Ngày tạo**: 2026-04-20 13:35:03

## 1. Tình trạng sự cố
Sau đợt bảo trì vá lỗi OS đêm qua, server chứa database `BILLINGDB` đã khởi động lại.
Khi bạn vào kiểm tra và gõ `STARTUP`, SQL*Plus báo lỗi sập mặt:
```text
SQL> STARTUP;
ORA-01078: failure in processing system parameters
LRM-00109: could not open parameter file '/u01/app/oracle/product/12.1.0/dbhome_1/dbs/initBILLINGDB.ora'
```

Kiểm tra thư mục `dbs` (hoặc `database` trên Windows), bạn phát hiện toàn bộ thư mục này bị trống trơn. Cả `SPFILE` lẫn `PFILE` đều đã bốc hơi! Database hiện không thể lên nổi trạng thái NOMOUNT.
Tuy nhiên, cấu hình Autobackup của RMAN vẫn luôn được bật trước đây.

## 2. Nhiệm vụ của bạn (DBA)
Viết các lệnh chính xác để RMAN có thể "tự cứu lấy chính mình", khôi phục lại SPFILE từ Autobackup và đưa DB lên trạng thái OPEN bình thường.

---

## 3. Hướng dẫn xử lý (Action Plan - Đáp án)

Đây là bài test kinh điển về khả năng xử lý nghịch lý: "Cần SPFILE để khởi động RMAN, nhưng lại cần RMAN để khôi phục SPFILE".

### Bước 1: Khởi tạo một Dummy PFILE để mồi lửa
Để vào được RMAN và chạy lệnh, database BẮT BUỘC phải ở trạng thái NOMOUNT. Vì mất PFILE, ta phải tạo một cái PFILE siêu đơn giản chỉ với 1 dòng.
- Tạo file text: `init_dummy.ora` ở bất kỳ đâu (vd `/tmp`).
- Ghi vào file nội dung: `DB_NAME=BILLINGDB`
Sau đó vào SQL*Plus khởi động bằng file mồi này:
```sql
SQL> STARTUP NOMOUNT PFILE='/tmp/init_dummy.ora';
```

### Bước 2: Thiết lập DBID cho RMAN
Vào RMAN. RMAN hiện đang kết nối tới một DB không có Controlfile, không có SPFILE gốc, nên nó không biết DBID. Bạn phải nạp DBID cho nó.
```rman
RMAN> SET DBID 987654321; -- (Tìm DBID trong file tên autobackup hoặc log cũ)
```

### Bước 3: Khôi phục SPFILE từ Autobackup
Bây giờ RMAN đã biết nó là ai (qua DBID), hãy ra lệnh cho nó đi tìm autobackup để moi SPFILE ra.
```rman
RMAN> RESTORE SPFILE FROM AUTOBACKUP;
```
*Lưu ý: Nếu RMAN không tìm thấy ở thư mục mặc định, bạn phải cấu hình đường dẫn `SET CONTROLFILE AUTOBACKUP FORMAT FOR DEVICE TYPE DISK TO '/đường_dẫn_backup/%F';`*

### Bước 4: Khởi động lại bằng SPFILE thật
SPFILE xịn đã được trả về đúng chỗ. Giờ ta tắt cái instance dùng PFILE mồi đi và bật lại bằng SPFILE thật.
```rman
RMAN> SHUTDOWN ABORT;
RMAN> STARTUP;
```
Hệ thống sẽ chạy một mạch lên OPEN thành công!


---

!!! info "Nguồn gốc"
    `Oracle-Database-Backup-and-Recovery-using-RMAN/reviews_all/20260420_133503_FireDrill_LossOfSPFILE.md`
