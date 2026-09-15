---
title: '🛠️ Thử Thách Tối Ưu: Tái Cấu Trúc Script Backup Cho VLDB'
course: 02-rman-backup-recovery
source: Oracle-Database-Backup-and-Recovery-using-RMAN/reviews_all/20260418_Optimize_VLDBBackup.md
---

# 🛠️ Thử Thách Tối Ưu: Tái Cấu Trúc Script Backup Cho VLDB

**Chế độ**: Tối ưu & Tái cấu trúc (Optimization Challenge - Module 6, 8, 11)
**Ngày tạo**: 2026-04-18

## 1. Tình huống doanh nghiệp
Bạn vừa tiếp nhận hệ thống cơ sở dữ liệu `ERPDB` (Very Large Database - 5TB) từ một DBA cũ. Trong database này, có một Datafile đặc biệt (chứa bảng lịch sử giao dịch) nặng tới **1.5TB**.

Khách hàng đang phàn nàn gay gắt về 2 vấn đề:
1. **Quá chậm**: Job backup Full hàng ngày kéo dài hơn **18 tiếng**, chiếm dụng I/O làm hệ thống hoạt động ì ạch trong giờ hành chính.
2. **Tốn dung lượng**: Ổ đĩa SAN dành cho Backup (`/backup/`) đang cạn kiệt dung lượng cực kỳ nhanh.

## 2. Kịch bản Backup hiện tại (Script của DBA cũ)
Dưới đây là Script đang được lập lịch chạy mỗi đêm:

```rman
RUN {
  BACKUP DATABASE FORMAT '/backup/erpdb_%U.bkp';
  BACKUP ARCHIVELOG ALL FORMAT '/backup/arch_%U.bkp';
  DELETE NOPROMPT OBSOLETE;
}
```

## 3. Nhiệm vụ của bạn
Đóng vai trò là người tối ưu hóa hệ thống (Performance Tuner), hãy:
1. Chỉ ra ít nhất **3 điểm yếu cốt lõi** trong script trên khiến nó chạy chậm và tốn dung lượng.
2. **Viết lại đoạn Script RMAN trên** áp dụng các kỹ thuật tối ưu hóa bạn đã học (Ví dụ: Đa luồng, Nén, Xử lý file siêu lớn...).

## 4. Hướng dẫn xử lý (Action Plan - Đáp án)

### 4.1. Phân tích 4 điểm yếu cốt lõi của Script cũ:
1. **Hoạt động đơn luồng (Single Channel)**: Script không cấu hình `PARALLELISM`, RMAN sẽ chỉ dùng 1 channel để backup tuần tự toàn bộ 5TB, đây là nguyên nhân chính gây ra thời gian chạy 18 tiếng.
2. **Thắt cổ chai tại file 1.5TB**: RMAN có quy tắc "1 Datafile chỉ được xử lý bởi 1 Channel tại 1 thời điểm". Dù bạn có tăng số luồng (Channel) lên, thì file 1.5TB kia vẫn do 1 luồng backup từ đầu đến cuối một cách chậm chạp. Phải dùng `SECTION SIZE` (Module 8).
3. **Không Nén dữ liệu (No Compression)**: Việc copy thô 5TB ra đĩa gây tràn ổ cứng SAN rất nhanh. Cần dùng tính năng nén `AS COMPRESSED BACKUPSET`.
4. **Không dọn rác Archivelog**: Lệnh `BACKUP ARCHIVELOG ALL` backup xong nhưng không xóa bản gốc ở đĩa, gây lãng phí dung lượng gấp đôi. Cần thêm `DELETE ALL INPUT`.

### 4.2. Script RMAN Tối Ưu Mới
Dưới đây là Script đã được viết lại, áp dụng các kỹ thuật cao cấp từ Module 6, 8 và 11:

```rman
RUN {
  # 1. Khởi tạo đa luồng (Ví dụ 4 channels để tăng tốc I/O)
  ALLOCATE CHANNEL c1 DEVICE TYPE DISK;
  ALLOCATE CHANNEL c2 DEVICE TYPE DISK;
  ALLOCATE CHANNEL c3 DEVICE TYPE DISK;
  ALLOCATE CHANNEL c4 DEVICE TYPE DISK;
  
  # 2. Backup Database: Dùng NÉN (Compressed) và CHIA NHỎ file lớn (Section Size)
  BACKUP AS COMPRESSED BACKUPSET 
    SECTION SIZE 50G
    DATABASE 
    FORMAT '/backup/erpdb_data_%U.bkp';
    
  # 3. Backup Archivelog: Nén và XÓA BẢN GỐC sau khi backup xong
  BACKUP AS COMPRESSED BACKUPSET 
    ARCHIVELOG ALL 
    FORMAT '/backup/erpdb_arch_%U.bkp'
    DELETE ALL INPUT;
    
  # 4. Dọn dẹp các backup đã cũ theo Retention Policy
  DELETE NOPROMPT OBSOLETE;
}
```

**Kết quả đạt được**: 
- Nhờ `SECTION SIZE 50G`, file 1.5TB sẽ được băm nhỏ thành các mảnh 50GB và 4 luồng (channels) sẽ xúm vào xử lý đồng thời, giảm thời gian backup từ 18 tiếng xuống có thể chỉ còn 3-4 tiếng.
- Nhờ `COMPRESSED` và `DELETE ALL INPUT`, ổ đĩa SAN sẽ giải phóng được một lượng cực kỳ lớn dung lượng thừa.


---

!!! info "Nguồn gốc"
    `Oracle-Database-Backup-and-Recovery-using-RMAN/reviews_all/20260418_Optimize_VLDBBackup.md`
