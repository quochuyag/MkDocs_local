---
title: 'Bài 92: Nhân bản Database bằng RMAN (Phần II)'
course: 01-oracle-dba-zero-to-hero
source: Oracle-Database-Administration-from-Zero-to-Hero/VN/92-nhan-ban-database-p2.md
---

# Bài 92: Nhân bản Database bằng RMAN (Phần II)

## Mục tiêu
Trong bài học này, bạn sẽ học cách phân tích và thực thi các khối lệnh RMAN cụ thể cho:
- Active Database Duplication (Nhân bản trực tiếp).
- Backup-based Duplication (Nhân bản qua file backup) với các tùy chọn kết nối khác nhau.
- Nhân bản PDBs trong kiến trúc Multitenant.

## 1. Kịch bản Active Database Duplication
Kịch bản này rất phổ biến để tạo môi trường UAT/Staging từ Production nếu mạng nội bộ đủ mạnh.

**Mẫu lệnh:**
```rman
CONNECT TARGET sys@oradb1   -- Nguồn
CONNECT AUXILIARY sys@oradb2 -- Đích

RUN {
  DUPLICATE DATABASE TO oradb2
  FROM ACTIVE DATABASE
  PASSWORD FILE
  SPFILE
  SET DB_CREATE_FILE_DEST='+DATA2';
}
```
*(Ghi chú: Lệnh trên yêu cầu RMAN copy trực tiếp các block dữ liệu. Tùy chọn `PASSWORD FILE` và `SPFILE` giúp copy luôn các cấu hình này sang máy chủ mới mà không cần tạo bằng tay).*

**Bật nén dữ liệu (Compression):**
Để giảm tải băng thông mạng, bạn có thể nén luồng dữ liệu truyền đi:
```rman
DUPLICATE DATABASE TO oradb2
FROM ACTIVE DATABASE
USING COMPRESSED BACKUPSET;
```

## 2. Kịch bản Backup-based Duplication (Sử dụng file Backup)
Nếu không thể kết nối mạng trực tiếp tới Production, bạn có thể mang ổ cứng chứa file Backup sang máy mới để nhân bản.

**Trường hợp 2A: CÓ kết nối mạng tới Target Database (hoặc Catalog)**
- Ở chế độ này, RMAN tự động đọc Control File của máy gốc (hoặc Catalog) để biết file backup nào cần bung ra.
```rman
CONNECT TARGET sys@oradb
CONNECT AUXILIARY /

RUN {
  DUPLICATE DATABASE TO oradb1
  SPFILE
  NOFILENAMECHECK;
}
```
*(Lưu ý: `NOFILENAMECHECK` báo cho RMAN biết hãy bỏ qua việc kiểm tra đường dẫn trùng lặp nếu máy đích có cùng cấu trúc thư mục với máy gốc).*

**Trường hợp 2B: KHÔNG có kết nối mạng (hoàn toàn cách ly)**
- Chỉ có 1 máy chủ duy nhất (máy đích). Bạn cung cấp thư mục chứa file backup thông qua biến `BACKUP LOCATION`.
```rman
CONNECT AUXILIARY /

RUN {
  SET NEWNAME FOR DATABASE TO '/u01/oradb2/%b';
  DUPLICATE DATABASE 'oradb1' TO 'oradb2'
  BACKUP LOCATION '/tmp/db_files';
}
```

## 3. Nhân bản PDBs (Pluggable Databases)
RMAN cho phép nhân bản một hoặc nhiều PDB cụ thể từ một CDB này sang CDB khác, hoặc nhân bản cả CDB gốc nhưng bỏ qua (skip) vài PDB.

- **Chỉ định cụ thể PDB cần nhân bản:**
  ```rman
  DUPLICATE DATABASE TO cdb2 PLUGGABLE DATABASE pdb1;
  DUPLICATE DATABASE TO cdb2 PLUGGABLE DATABASE pdb1, pdb3;
  ```
- **Nhân bản toàn bộ CDB nhưng bỏ qua PDB rác:**
  ```rman
  DUPLICATE DATABASE TO cdb2 SKIP PLUGGABLE DATABASE pdb_test;
  ```

## 4. Xử lý khi quá trình Duplication bị lỗi (Restarting a Failed Duplication)
Nếu quá trình tốn hàng giờ đồng hồ bị gián đoạn (do đứt mạng, đầy ổ cứng...):
1. Ép tắt instance đích (Abort).
2. Xử lý triệt để nguyên nhân gốc rễ (ví dụ: cắm thêm ổ cứng).
3. Xóa toàn bộ các file rác mà quá trình cũ đang tạo dở.
4. Chạy lại lệnh `DUPLICATE` từ đầu.

---
## Câu hỏi ôn tập

**Câu 1: Từ khóa nào trong khối lệnh chỉ định RMAN thực hiện việc nhân bản trực tiếp qua mạng thay vì dùng file backup?**
- **Trả lời:** Đó là từ khóa `FROM ACTIVE DATABASE`.

**Câu 2: Tùy chọn `USING COMPRESSED BACKUPSET` trong Active Duplication mang lại lợi ích gì?**
- **Trả lời:** Nó giúp nén các luồng dữ liệu (blocks) trên máy chủ nguồn trước khi truyền qua mạng. Việc này tiết kiệm được đáng kể lượng băng thông mạng tiêu thụ, mặc dù có thể làm tăng mức sử dụng CPU.

**Câu 3: Mục đích của tùy chọn `NOFILENAMECHECK` là gì?**
- **Trả lời:** Tùy chọn này ép RMAN bỏ qua bước kiểm tra đường dẫn trùng lặp. Nó thường được sử dụng khi máy chủ đích có kiến trúc thư mục vật lý (path) giống hệt 100% với máy chủ nguồn (hoặc khi nhân bản giữa 2 host vật lý hoàn toàn cách ly).

**Câu 4: Khi dùng phương pháp Backup-based mà máy chủ đích hoàn toàn bị cô lập khỏi mạng của máy nguồn, ta phải dùng tùy chọn nào để chỉ đường dẫn file backup?**
- **Trả lời:** Cần phải sử dụng tùy chọn `BACKUP LOCATION '<thư_mục>'` trong khối lệnh RUN để trỏ RMAN tới ổ cứng/thư mục chứa file backup thủ công.

**Câu 5: Nếu tôi chỉ muốn clone một PDB duy nhất (tên là `pdb_dev`) từ CDB nguồn, câu lệnh sẽ chứa từ khóa gì?**
- **Trả lời:** Cần thêm cấu trúc: `PLUGGABLE DATABASE pdb_dev` vào phía sau lệnh `DUPLICATE DATABASE TO <tên_cdb_đích>`.


---

!!! info "Nguồn gốc"
    `Oracle-Database-Administration-from-Zero-to-Hero/VN/92-nhan-ban-database-p2.md`
