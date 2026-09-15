---
title: '🌉 Cross-Module: Active Database Duplication Qua Mạng'
course: 02-rman-backup-recovery
source: Oracle-Database-Backup-and-Recovery-using-RMAN/reviews_all/20260422_155004_CrossModule_ActiveDBDuplication.md
---

# 🌉 Cross-Module: Active Database Duplication Qua Mạng

**Chế độ**: Cross-Module (Architecture & Cloning - Module 13 & 14)
**Ngày tạo**: 2026-04-22 15:50:04

## 1. Tình huống sự cố
Đội phát triển (Dev) khẩn thiết yêu cầu một bản clone của database Production (`PRODDB`) sang máy chủ Development (`DEVDB`) để test tính năng mới.
Quy mô của database Production là 1TB. Máy chủ Production hiện đang chạy 24/7 và hệ thống storage không còn đủ không gian trống để chứa thêm một bản RMAN Full Backup nào cả. 

## 2. Nhiệm vụ của bạn (DBA)
1. Bạn không thể tạo backup disk/tape do thiếu storage. Phương pháp nào của RMAN cho phép clone database mà không cần tạo các files backup trung gian?
2. Viết quy trình (Action Plan) để thực hiện thủ thuật này. Cần chuẩn bị những gì ở máy đích (DEVDB)?

---

## 3. Hướng dẫn xử lý (Action Plan - Đáp án)

### Phân tích kiến trúc
Giải pháp lý tưởng ở đây là **RMAN Active Database Duplication**.
Kỹ thuật này cho phép RMAN kết nối đến cơ sở dữ liệu nguồn (Target) và cơ sở dữ liệu đích (Auxiliary) cùng một lúc. Nó sẽ copy trực tiếp các datafiles từ Production chuyển thẳng qua mạng (network) tới Development mà không cần ghi file backup set nào xuống đĩa của Production.

### Action Plan (Khắc phục sự cố)

**Bước 1: Chuẩn bị máy chủ đích (Auxiliary - DEVDB)**
1. **Cấu hình mạng**: Đảm bảo Listener trên DEVDB hoạt động và TNSNAMES ở cả 2 máy có thể ping được nhau (ví dụ: TNS `PROD` và `DEV`).
2. **Password file**: Copy password file từ PROD sang DEV (cần password của user SYS/SYSBACKUP phải giống nhau để kết nối qua mạng).
3. **PFILE sơ khai**: Tạo một init.ora (`initDEVDB.ora`) với cấu hình tối thiểu:
   ```text
   db_name=PRODDB
   db_unique_name=DEVDB
   sga_target=2G
   db_file_name_convert=('/u01/oradata/PROD/','/u01/oradata/DEV/')
   log_file_name_convert=('/u01/oradata/PROD/','/u01/oradata/DEV/')
   ```
4. **Khởi động nomount**:
   ```sql
   $ export ORACLE_SID=DEVDB
   $ sqlplus / as sysdba
   SQL> STARTUP NOMOUNT PFILE='initDEVDB.ora';
   ```

**Bước 2: Kết nối RMAN từ máy bất kỳ**
Kết nối đồng thời vào TARGET (Production) và AUXILIARY (Development).
```shell
$ rman TARGET sys/password@PROD AUXILIARY sys/password@DEV
```

**Bước 3: Chạy lệnh Duplicate**
Sử dụng mệnh đề `FROM ACTIVE DATABASE`. Bạn có thể phân bổ nhiều kênh (channels) để tận dụng băng thông mạng.
```rman
RMAN> DUPLICATE TARGET DATABASE TO DEVDB FROM ACTIVE DATABASE;
```
*Ghi chú: Lệnh này sẽ tự động: copy datafiles qua mạng, copy controlfile, cấp phát online redo logs mới, thực hiện apply archive logs để DB đồng nhất, và cuối cùng mở DEVDB với tham số RESETLOGS.*

### 💡 Lưu ý Cross-Module:
- Lệnh này sẽ gây áp lực lên băng thông mạng (network bandwidth) giữa PROD và DEV. Nên thực hiện ngoài giờ cao điểm.
- Trong Oracle 12c trở lên, bạn có thể thêm mệnh đề `USING BACKUPSET` trong Active Duplication nếu không muốn sử dụng Push-method (Target đẩy sang Aux) mà dùng Pull-method.


---

!!! info "Nguồn gốc"
    `Oracle-Database-Backup-and-Recovery-using-RMAN/reviews_all/20260422_155004_CrossModule_ActiveDBDuplication.md`
