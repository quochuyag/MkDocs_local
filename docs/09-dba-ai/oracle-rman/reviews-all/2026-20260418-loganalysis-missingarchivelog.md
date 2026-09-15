---
title: '🕵️ Phân tích Log: Sự cố mất Archivelog'
course: 09-dba-ai
source: dba_ai/oracle_rman/reviews_all/20260418_LogAnalysis_MissingArchivelog.md
---

# 🕵️ Phân tích Log: Sự cố mất Archivelog

**Chế độ**: Phân tích Log & Khắc phục sự cố (Troubleshooting - Module 7, 16)
**Ngày tạo**: 2026-04-18

## 1. Tình huống sự cố
Khách hàng liên hệ với bạn vào sáng sớm, thông báo rằng Job Backup đêm qua bị **FAILED**. Mọi tiến trình backup đang bị đình trệ. Khách hàng gửi cho bạn một đoạn Log trích xuất từ RMAN.

### 📜 Đoạn Log Lỗi:
```text
RMAN> BACKUP ARCHIVELOG ALL;
Starting backup at 18-APR-26
current log archived
allocated channel: ORA_DISK_1
channel ORA_DISK_1: SID=45 device type=DISK
RMAN-03002: failure of backup command at 04/18/2026 02:30:00
RMAN-06059: expected archivelog not found, loss of archived log compromises recoverability
ORA-19625: error identifying file /u01/app/oracle/fast_recovery_area/PRODDB/archivelog/2026_04_17/o1_mf_1_152_abcde.arc
ORA-27037: unable to obtain file status
Linux-x86_64 Error: 2: No such file or directory
Additional information: 3
```

---

## 2. Hướng dẫn xử lý (Action Plan & Phân tích)

Là một Senior DBA, khi đọc đoạn log trên, bạn sẽ lập tức nhận ra vấn đề và đưa ra hướng xử lý như sau:

### 🔍 2.1. Phân tích nguyên nhân cốt lõi (Root Cause)
1. Dòng `Linux-x86_64 Error: 2: No such file or directory` cho biết hệ điều hành Linux không thể tìm thấy file.
2. Dòng `RMAN-06059` và `ORA-19625` xác nhận rằng RMAN đang cố gắng backup file archivelog số `152` nhưng file này đã "không cánh mà bay".
3. **Kết luận**: Khả năng 99% là một quản trị viên hệ thống (hoặc một cronjob nào đó) thấy phân vùng đĩa bị đầy nên đã dùng lệnh Linux `rm -rf` để xóa thủ công các file Archivelog cũ. Hậu quả là RMAN không biết việc này, metadata trong Control File vẫn ghi nhận file tồn tại, khiến lệnh Backup tìm file không thấy và báo lỗi.

### 🛠️ 2.2. Kế hoạch khắc phục (Action Plan)
Để RMAN có thể chạy backup bình thường tiếp, ta cần "dạy" lại cho RMAN biết những file nào thực sự đã bị xóa, thông qua các bước:

**Bước 1: Đồng bộ hóa (Crosscheck)**
Kiểm tra chéo giữa metadata của RMAN và thực tế trên đĩa cứng. RMAN sẽ tự phát hiện file thiếu và đánh dấu trạng thái là `EXPIRED`.
```rman
RMAN> CROSSCHECK ARCHIVELOG ALL;
```

**Bước 2: Dọn dẹp metadata**
Xóa toàn bộ các bản ghi `EXPIRED` ra khỏi Control File/Catalog để RMAN bỏ qua chúng trong các lần backup sau.
```rman
RMAN> DELETE NOPROMPT EXPIRED ARCHIVELOG ALL;
```

**Bước 3: Chạy lại Job Backup**
Lúc này RMAN sẽ chỉ backup những Archivelog thực sự còn tồn tại trên đĩa.
```rman
RMAN> BACKUP ARCHIVELOG ALL;
```

### 💡 2.3. Lời khuyên cho khách hàng (Best Practice)
Cảnh báo khách hàng **tuyệt đối KHÔNG DÙNG lệnh OS (`rm`)** để xóa bất kỳ file nào của Oracle (Datafile, Controlfile, Archivelog). 
Nếu ổ cứng sắp đầy và cần dọn Archivelog, hãy cấu hình RMAN tự dọn tự động, hoặc dùng lệnh RMAN:
```rman
RMAN> DELETE ARCHIVELOG ALL COMPLETED BEFORE 'SYSDATE-2';
```


---

!!! info "Nguồn gốc"
    `dba_ai/oracle_rman/reviews_all/20260418_LogAnalysis_MissingArchivelog.md`
