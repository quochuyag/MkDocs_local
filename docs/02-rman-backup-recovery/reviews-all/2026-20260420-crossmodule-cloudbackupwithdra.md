---
title: '🔗 Kiến Trúc Chéo: Sửa Lỗi Block Bằng Cloud Backups'
course: 02-rman-backup-recovery
source: Oracle-Database-Backup-and-Recovery-using-RMAN/reviews_all/20260420_CrossModule_CloudBackupWithDRA.md
---

# 🔗 Kiến Trúc Chéo: Sửa Lỗi Block Bằng Cloud Backups

**Chế độ**: Kiến trúc chéo (Cross-Module: Module 13 + 17)
**Ngày tạo**: 2026-04-20

## 1. Tình huống doanh nghiệp
Database `SALESDB` của công ty hoạt động trên hệ thống On-Premise (máy chủ vật lý tại công ty). 
Tuy nhiên, công ty bạn ứng dụng thiết kế Hybrid Cloud: Không mua tủ đĩa lưu trữ Backup nội bộ, mà đẩy toàn bộ bản sao lưu RMAN thẳng lên Oracle Cloud (OCI Object Storage) thông qua plugin `Oracle Database Cloud Backup Module`.

Lúc 10:00 sáng, App báo lỗi:
`ORA-01578: ORACLE data block corrupted (file # 8, block # 10452)`
`ORA-01110: data file 8: '/oradata/SALESDB/sales_data01.dbf'`

## 2. Nhiệm vụ của bạn (DBA)
Bạn không muốn phải cày bừa document quá nhiều để tìm cách fix lỗi Data Block Corruption một cách thủ công. Bạn muốn nhờ trí tuệ của **Data Recovery Advisor (DRA)** để nó tự động lên kịch bản sửa block.
Tuy nhiên, vì backup nằm hoàn toàn trên Cloud (SBT_TAPE), làm thế nào để DRA có thể tự động đi lấy dữ liệu từ Cloud về và sửa lỗi?

Thiết kế Workflow giải quyết sự cố này.

---

## 3. Hướng dẫn xử lý (Action Plan - Đáp án)

Đây là ví dụ điển hình về khả năng tích hợp mạnh mẽ của Oracle RMAN với Cloud và các tính năng thông minh nội bộ. DRA hoàn toàn có khả năng điều khiển các kênh SBT để lôi dữ liệu từ Cloud về.

### Bước 1: Khai báo Kênh giao tiếp với Cloud (SBT Channel)
Vì bản thân DRA là một tính năng của RMAN, để nó có thể "với" tay lên Cloud, bạn phải cấp cho RMAN cấu hình mặc định (default configuration) cho thiết bị `SBT`.
```rman
RMAN> CONFIGURE DEFAULT DEVICE TYPE TO sbt;
RMAN> CONFIGURE CHANNEL DEVICE TYPE sbt 
      PARMS='SBT_LIBRARY=/opt/oracle/lib/libopc.so, SBT_PARMS=(OPC_PFILE=/opt/oracle/opcSALESDB.ora)';
```
*(Nếu bạn không cấu hình đoạn này, DRA sẽ bó tay vì nó tưởng backup chỉ nằm trên đĩa cứng nội bộ `DISK` và báo không có bản backup khả dụng).*

### Bước 2: Gọi chuyên gia phân tích Data Recovery Advisor
Báo cho DRA biết có sự cố để nó ghi nhận:
```rman
RMAN> LIST FAILURE;
```
*(DRA sẽ quét qua V$DATABASE_BLOCK_CORRUPTION và nhận diện lỗi ORA-01578 tại file 8 block 10452).*

Yêu cầu DRA đưa ra tư vấn (Advisement):
```rman
RMAN> ADVISE FAILURE;
```
*(Lúc này, DRA sẽ tính toán và đưa ra một Recovery Script. Nó sẽ báo rằng: "Tôi có thể sửa cái block này bằng cách dùng tính năng Block Media Recovery (BMR). Tôi thấy backup trên sbt, tôi sẽ lấy từ đó").*

### Bước 3: Ra lệnh thực thi tự động
Bạn chỉ việc ra lệnh chốt hạ để DRA chạy script nó vừa đẻ ra:
```rman
RMAN> REPAIR FAILURE;
```
*(Hậu trường: DRA sẽ tự động kích hoạt kênh `SBT`, kết nối lên Oracle Cloud, tải duy nhất cái Block 10452 khỏe mạnh từ file backup về, đắp đè lên block bị hỏng, sau đó tải các đoạn Archivelog cần thiết từ Cloud về để Recovery cái block đó tới thời điểm hiện tại).*

### Tổng kết:
Nhờ cấu hình khéo léo kết nối Cloud SBT, DRA đã giải quyết bài toán Block Corruption vô cùng tinh vi: Zero Downtime (chỉ block đó bị khóa tạm thời), tiết kiệm băng thông (không cần tải cả file 500GB về từ Cloud, chỉ tải đúng block bị hỏng).


---

!!! info "Nguồn gốc"
    `Oracle-Database-Backup-and-Recovery-using-RMAN/reviews_all/20260420_CrossModule_CloudBackupWithDRA.md`
