---
title: '🔗 Kiến Trúc Chéo: Nhân Bản Backup (Duplex) Ra Đĩa & Đám Mây Cùng Lúc'
course: 09-dba-ai
source: dba_ai/oracle_rman/reviews_all/20260420_133504_CrossModule_DuplexCloudAndDisk.md
---

# 🔗 Kiến Trúc Chéo: Nhân Bản Backup (Duplex) Ra Đĩa & Đám Mây Cùng Lúc

**Chế độ**: Kiến trúc chéo (Cross-Module: Module 8 + 17)
**Ngày tạo**: 2026-04-20 13:35:04

## 1. Tình huống doanh nghiệp
Quy định bảo mật mới (Quy tắc 3-2-1) của ngân hàng quy định: Đối với database cốt lõi `BANKDB`, mọi bản backup hàng ngày phải tồn tại **2 bản sao vật lý cùng một lúc**:
1. Một bản lưu trên SAN nội bộ (DISK) để có thể khôi phục tốc độ cao khi có sự cố nhỏ.
2. Một bản đẩy trực tiếp lên hệ thống Oracle Cloud Infrastructure (SBT_TAPE) để đề phòng thảm họa nổ trung tâm dữ liệu.

## 2. Nhiệm vụ của bạn (DBA)
Thay vì chạy lệnh backup 2 lần (gấp đôi tải I/O lên hệ thống), hãy viết kịch bản sử dụng tính năng **Backup Duplexing** (Nhân bản dự phòng) của RMAN kết hợp 2 loại Device Type (`DISK` và `SBT`) trong một khối lệnh `RUN` duy nhất.

---

## 3. Hướng dẫn xử lý (Action Plan - Đáp án)

Đây là kỹ thuật nâng cao kết hợp giữa tính năng Duplex (Module 8) và Cloud Backup (Module 17). 
Thông thường lệnh `BACKUP COPIES 2` chỉ đẩy ra 2 file trên CÙNG một loại thiết bị (DISK). Để đẩy ra 2 thiết bị KHÁC NHAU, ta dùng lệnh `BACKUP ... DESTINATION`.

Nhưng cách truyền thống và linh hoạt nhất trong kịch bản này là chia nhóm channel hoặc backup thẳng ra disk rồi tạo copy thứ 2 lên cloud. Tuy nhiên, cách siêu việt nhất trong Oracle 12c+ để backup ra nhiều đích là dùng `BACKUP ... FORMAT`.

### Kịch bản (Workflow Script)

**Bước 1: Cấu hình tham số cho Cloud (SBT)**
```rman
RMAN> CONFIGURE DEFAULT DEVICE TYPE TO sbt;
RMAN> CONFIGURE CHANNEL DEVICE TYPE sbt 
      PARMS='SBT_LIBRARY=/opt/oracle/lib/libopc.so, SBT_PARMS=(...)';
```

**Bước 2: Sử dụng lệnh BACKUP với nhiều COPIES và FORMAT phân tách**
```rman
RUN {
  -- Yêu cầu RMAN tạo ra 2 bản sao cho mỗi file backup
  SET BACKUP COPIES 2;
  
  -- Phân bổ channel cho DISK
  ALLOCATE CHANNEL c_disk DEVICE TYPE DISK;
  
  -- Phân bổ channel cho TAPE (Cloud)
  ALLOCATE CHANNEL c_cloud DEVICE TYPE sbt;
  
  -- Lệnh Backup 1 phát ăn 2
  BACKUP DATABASE
    FORMAT '/backup/san/bankdb_%U.bkp', -- Copy 1 sẽ rơi vào DISK channel
           '%U';                        -- Copy 2 sẽ được điều hướng vào SBT channel
}
```

**Cách 2 (Thực tế và an toàn hơn cho I/O): Backup BackupSet**
Nếu đẩy lên Cloud chậm làm nghẽn tiến trình DISK, phương pháp tốt nhất là:
```rman
RUN {
  -- 1. Backup siêu tốc ra DISK trước
  BACKUP AS COMPRESSED BACKUPSET DEVICE TYPE DISK DATABASE FORMAT '/backup/san/%U';
  
  -- 2. Đẩy các bản sao lưu từ DISK lên TAPE (Cloud) từ từ mà không ép I/O lên Database gốc
  BACKUP BACKUPSET ALL DEVICE TYPE sbt;
}
```
*Cách 2 (Backup Backupset) thường được ưa chuộng hơn trong Production vì nó cô lập được hiệu năng của Database gốc với độ trễ của mạng Cloud.*


---

!!! info "Nguồn gốc"
    `dba_ai/oracle_rman/reviews_all/20260420_133504_CrossModule_DuplexCloudAndDisk.md`
