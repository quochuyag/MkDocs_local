---
title: '🚨 Báo Động Đỏ: Lô Batch Job Bơm Sai Dữ Liệu'
course: 09-dba-ai
source: dba_ai/oracle_rman/reviews_all/20260420_133508_FireDrill_IncompleteRecoveryUntilTime.md
---

# 🚨 Báo Động Đỏ: Lô Batch Job Bơm Sai Dữ Liệu

**Chế độ**: Fire Drill (Diễn tập sự cố khẩn cấp - Module 12)
**Ngày tạo**: 2026-04-20 13:35:08

## 1. Tình trạng sự cố
Tại công ty Chứng khoán, vào lúc 16:00 chiều sau khi đóng phiên giao dịch, một luồng tự động (Batch Job) tính toán hoa hồng môi giới được chạy.
Lẽ ra Batch Job phải nhân hệ số hoa hồng là `0.15`, nhưng do lỗi cấu hình, nó đã nhân với `15.0` và UPDATE (thay đổi) sai lệch toàn bộ số dư của 100,000 khách hàng trong database `TRADINGDB`.

Lệnh UPDATE sai hoàn tất vào lúc 16:05:00 và đã lỡ COMMIT.
Ban giám đốc ra lệnh: "Database đã bị bôi bẩn hoàn toàn. Dừng ngay toàn bộ hệ thống giao dịch, khôi phục Database về đúng thời điểm 15:59:00 (ngay trước khi chạy Job lỗi)".

## 2. Nhiệm vụ của bạn (DBA)
Thực hiện quá trình **DBPITR (Database Point-In-Time Recovery)** để tua ngược toàn bộ Database về đúng giây phút `15:59:00`.
Viết chi tiết các lệnh từ lúc tắt DB đến lúc mở lại.

---

## 3. Hướng dẫn xử lý (Action Plan - Đáp án)

Khôi phục toàn bộ Database về một thời điểm trong quá khứ là thao tác Incomplete Recovery cổ điển và mạnh mẽ nhất của Oracle. Bất kỳ thay đổi nào sau 15:59:00 sẽ bị ném đi.

### Bước 1: Đóng cửa Database và đưa về Mount
Để restore toàn bộ, Database không được phép OPEN.
```sql
SQL> SHUTDOWN IMMEDIATE;
SQL> STARTUP MOUNT;
```

### Bước 2: Dùng RMAN chạy DBPITR
Kết nối vào RMAN. Cú pháp tối ưu nhất cho việc này là gộp lệnh SET UNTIL TIME vào trong một khối RUN, để nó áp dụng tự động cho cả lệnh RESTORE và RECOVER.

```rman
RUN {
  -- Báo cho RMAN biết mốc thời gian muốn tua ngược
  SET UNTIL TIME "TO_DATE('2026-04-20 15:59:00', 'YYYY-MM-DD HH24:MI:SS')";
  
  -- RMAN sẽ tìm bản backup full gần nhất TRƯỚC 15:59 đắp vào
  RESTORE DATABASE;
  
  -- RMAN sẽ apply tuần tự các file archivelog cho đến ĐÚNG giây 15:59:00 thì DỪNG CÁI KÉT
  RECOVER DATABASE;
}
```

### Bước 3: Đưa hệ thống lên lại
Vì Database bị bẻ ngoặt về quá khứ (cắt đứt dòng thời gian / SCN hiện tại), quy tắc vàng là BẮT BUỘC phải mở Database bằng chế độ khởi tạo dòng thời gian mới (Resetlogs).
```rman
RMAN> ALTER DATABASE OPEN RESETLOGS;
```

> [!CAUTION]
> Tương tự mọi pha Resetlogs khác, sau khi mở lại thành công, dòng thời gian cũ (Incarnation) đã bị vứt bỏ. Bản backup từ hôm qua sẽ không còn liền mạch với dòng thời gian hiện tại nữa. 
> Việc đầu tiên bạn PHẢI LÀM ngay lập tức là gõ lệnh `BACKUP DATABASE;` full một lần nữa để làm điểm neo cho tương lai.


---

!!! info "Nguồn gốc"
    `dba_ai/oracle_rman/reviews_all/20260420_133508_FireDrill_IncompleteRecoveryUntilTime.md`
