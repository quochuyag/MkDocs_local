---
title: '🚨 Fire Drill: Loss of UNDO Tablespace Datafile'
course: 09-dba-ai
source: dba_ai/oracle_rman/reviews_all/20260422_155001_FireDrill_LossOfUNDO.md
---

# 🚨 Fire Drill: Loss of UNDO Tablespace Datafile

**Chế độ**: Fire Drill (Troubleshooting - Module 15)
**Ngày tạo**: 2026-04-22 15:50:01

## 1. Tình huống sự cố
Hệ thống giám sát vừa báo động đỏ: Database Production đột ngột bị treo, các session của người dùng không thể thực hiện giao dịch (DML) và cuối cùng instance bị crash.
Bạn vào kiểm tra Alert Log và phát hiện một trong những ổ đĩa bị lỗi phần cứng, làm hỏng hoàn toàn datafile của tablespace `UNDOTBS1`.

## 2. Nhiệm vụ của bạn (DBA)
1. Xác định mức độ nghiêm trọng: Việc mất UNDO tablespace khi database đang hoạt động (crash) ảnh hưởng thế nào đến khả năng khởi động lại DB?
2. Lập Action Plan từng bước bằng RMAN để khôi phục lại Datafile bị mất và mở lại Database an toàn.

---

## 3. Hướng dẫn xử lý (Action Plan - Đáp án)

### Phân tích sự cố (Bắt bệnh)
- UNDO tablespace chứa dữ liệu chưa commit của các giao dịch. Nếu bị mất khi DB crash (instance failure), quá trình Crash Recovery (Roll backward) lúc khởi động DB sẽ bị thất bại vì Oracle không có thông tin UNDO để rollback các giao dịch chưa hoàn tất.
- Trạng thái DB hiện tại: DB đang ở trạng thái DOWN. Khi bạn cố gắng `STARTUP`, nó sẽ dừng lại ở trạng thái MOUNT và báo lỗi thiếu datafile của UNDO.

### Action Plan (Khắc phục sự cố)

**Bước 1: Khởi động DB ở trạng thái MOUNT**
Vì instance đã crash, ta cần đưa DB lên trạng thái MOUNT để RMAN có thể làm việc với Control file.
```sql
SQL> STARTUP MOUNT;
```

**Bước 2: Sử dụng RMAN để Restore và Recover Datafile UNDO**
Giả sử datafile bị lỗi là file số 3 (bạn có thể tìm số ID bằng `SELECT file#, name FROM v$datafile;`).
Khởi chạy RMAN và kết nối vào target database:
```rman
$ rman target /

RMAN> RESTORE DATAFILE 3;
RMAN> RECOVER DATAFILE 3;
```
*Ghi chú: Quá trình recover sẽ áp dụng Archive logs và Online Redo logs để khôi phục lại các thay đổi mới nhất cho UNDO datafile.*

**Bước 3: Mở lại Database**
Sau khi datafile đã được recover hoàn tất và đồng bộ (consistent), bạn có thể mở database cho người dùng.
```rman
RMAN> ALTER DATABASE OPEN;
```

### 💡 Bài học kinh nghiệm & Tối ưu:
- **Phân biệt rủi ro**: Mất UNDO khi DB đang chạy là rất nghiêm trọng (gây crash). Mất UNDO sau khi DB đã Shutdown Normal/Immediate ít nghiêm trọng hơn vì không còn giao dịch nào cần rollback lúc khởi động (có thể drop và tạo lại UNDO mới nếu offline).
- **Sao lưu định kỳ**: Đảm bảo UNDO tablespace luôn được đưa vào chiến lược full backup/incremental backup định kỳ.


---

!!! info "Nguồn gốc"
    `dba_ai/oracle_rman/reviews_all/20260422_155001_FireDrill_LossOfUNDO.md`
