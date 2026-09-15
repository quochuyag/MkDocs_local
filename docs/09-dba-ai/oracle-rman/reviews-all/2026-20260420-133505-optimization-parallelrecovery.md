---
title: '🛠️ Thử Thách Tối Ưu: Tăng Tốc Phục Hồi Dữ Liệu (Parallel Recovery)'
course: 09-dba-ai
source: dba_ai/oracle_rman/reviews_all/20260420_133505_Optimization_ParallelRecovery.md
---

# 🛠️ Thử Thách Tối Ưu: Tăng Tốc Phục Hồi Dữ Liệu (Parallel Recovery)

**Chế độ**: Tối ưu & Tái cấu trúc (Optimization Challenge - Module 16)
**Ngày tạo**: 2026-04-20 13:35:05

## 1. Tình huống doanh nghiệp
Sau sự cố sập nguồn, database `COREDB` (kích thước 8TB) đang phải thực hiện Crash Recovery. Số lượng lượng Archivelog cần áp dụng (apply) là rất lớn (hơn 500 file log do lượng giao dịch khủng bị rớt lại).
Khi bạn chạy lệnh `RECOVER DATABASE;`, bạn thấy RMAN làm việc vô cùng chậm chạp. CPU server có 64 nhân nhưng lệnh Recover chỉ dùng đúng 1 nhân CPU (đạt 100% Core 1, 63 Core còn lại rảnh rỗi), việc apply log chạy lề mề với tốc độ 50MB/s.
Sếp đang đứng bấm giờ, mỗi phút hệ thống down công ty mất 10,000 USD.

## 2. Nhiệm vụ của bạn (DBA)
Sử dụng kiến thức Performance Tuning RMAN (Module 16), hãy ép quá trình RECOVER phải sử dụng nhiều nhân CPU hơn để tăng tốc độ apply log lên mức tối đa.

---

## 3. Hướng dẫn xử lý (Action Plan - Đáp án)

### Phân tích vấn đề:
Mặc định, lệnh `RECOVER DATABASE` trong Oracle có thể đang bị chạy đơn luồng (Serial Media Recovery). Nó chỉ dùng một process duy nhất để đọc file log từ đĩa và áp dụng các thay đổi (redo) vào datafiles. Với máy chủ 64 nhân, đây là sự lãng phí tài nguyên khủng khiếp trong lúc nguy cấp.

### Giải pháp Tối ưu: Parallel Media Recovery
Bạn cần kích hoạt tính năng phục hồi song song. Lúc này, Oracle sẽ chia việc ra: 1 process chuyên đi đọc file Log, và N process con chuyên đi ghi dữ liệu vào các Datafile khác nhau.

### Kịch bản Tái cấu trúc (Lệnh thực thi):

**Trong môi trường RMAN:**
Hãy phân bổ channel cụ thể và yêu cầu RMAN dùng song song.
Nhưng quan trọng nhất là truyền tham số Parallel vào tận lệnh SQL Recovery nội tại:
```rman
RMAN> RECOVER DATABASE PARALLEL 32;
```
*(Tham số `PARALLEL 32` ép RMAN khởi tạo 32 tiến trình con (slave processes) để apply các redo log. Đừng cấp hết 64 nhân để tránh OS bị treo).*

**Trong môi trường SQL*Plus (Nếu không dùng RMAN):**
```sql
SQL> RECOVER DATABASE PARALLEL 32;
```

> [!TIP]
> Bạn có thể kiểm tra xem hệ thống có đang thực sự chạy Parallel Recovery hay không bằng câu query thần thánh này ở một tab SQL*Plus khác:
> ```sql
> SELECT * FROM v$recovery_progress;
> ```
> Tại đây, bạn sẽ thấy tiến độ apply MB/s tăng vọt!


---

!!! info "Nguồn gốc"
    `dba_ai/oracle_rman/reviews_all/20260420_133505_Optimization_ParallelRecovery.md`
