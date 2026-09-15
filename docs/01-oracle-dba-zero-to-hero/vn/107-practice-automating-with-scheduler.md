---
title: 'Bài 107: Thực hành - Tự động hóa tác vụ với Scheduler'
course: 01-oracle-dba-zero-to-hero
source: Oracle-Database-Administration-from-Zero-to-Hero/VN/107-practice-automating-with-scheduler.md
---

# Bài 107: Thực hành - Tự động hóa tác vụ với Scheduler

## Mục tiêu
Trong bài thực hành này, bạn sẽ làm quen với việc:
- Sử dụng SQL Developer (công cụ đồ họa) để dễ dàng tạo và quản lý Jobs.
- Tạo một Scheduled Job độc lập chạy thủ tục PL/SQL lặp lại tự động mỗi phút.
- Xem nhật ký và lịch sử thực thi của Job (Job Run Details).
- Thay đổi cấu hình, vô hiệu hóa và chạy thử Job bằng tay.

## A. Tạo Job thông qua SQL Developer

**1.** Khởi động `srv1`, vào SQL Developer và kết nối tới `PDB1` bằng tài khoản quản trị (ví dụ `SYS` hoặc `SOE` nếu có quyền `CREATE JOB`).
**2.** Trong khung bên trái (Connections), kéo xuống dưới cùng tìm mục **Scheduler**. Mở rộng nó ra và chuột phải vào nhánh **Jobs** -> Chọn **New Job...**
**3.** Tại cửa sổ khởi tạo:
- **Name:** Điền `TEST_INSERT_JOB`.
- **Job Type:** Chọn `PLSQL_BLOCK`.
**4.** Trong hộp thoại `Job Action`, dán đoạn mã sau vào (Đoạn mã này làm nhiệm vụ chèn 1 dòng log thời gian vào một bảng test rỗng):
```sql
BEGIN
  INSERT INTO soe.test_table (run_time) VALUES (SYSDATE);
  COMMIT;
END;
```
*(Lưu ý: Bạn phải tạo trước bảng `soe.test_table` với cột `run_time DATE` trước đó).*
**5.** Mở tab **Schedule** để định nghĩa lịch chạy:
- Tích vào hộp kiểm `Enabled` để Job tự kích hoạt ngay khi tạo.
- Mục `Frequency`: Chọn **MINUTELY**.
- Mục `Interval`: Gõ `1` (Nghĩa là nó sẽ chạy lặp lại mỗi 1 phút).
**6.** Bấm **Apply** để tạo Job. Bạn có thể bấm vào tab **SQL** để xem đoạn script mà SQL Developer tự động sinh ra cho bạn. Nó sẽ gọi thủ tục `DBMS_SCHEDULER.CREATE_JOB`.

## B. Quan sát và Giám sát Job
Bây giờ, hãy ra ngoài làm một cốc cà phê nhỏ hoặc đợi khoảng 3 phút để cái vòng lặp mỗi phút của chúng ta được thi hành vài lần.

**7.** Query thử cái bảng `soe.test_table`:
```sql
SELECT TO_CHAR(run_time, 'DD-MON-YYYY HH24:MI:SS') FROM soe.test_table;
```
*(Nếu bạn thấy có 3 dòng dữ liệu, mỗi dòng cách nhau đúng 1 phút, có nghĩa là cái Job của chúng ta đang chạy ngầm trong máy chủ rất tốt).*

**8.** Bạn có thể kiểm tra nhật ký chạy chính thống của Scheduler:
Trở lại khung **Connections**, click vào tên Job bạn vừa tạo. Nó sẽ mở ra một cửa sổ properties. 
Click vào tab **Run Details**. Tại đây bạn sẽ thấy một danh sách log bao gồm: thời điểm bắt đầu, thời gian chạy mất bao lâu, và quan trọng nhất là cột **Status** có báo chữ `SUCCEEDED` hay không.

## C. Chạy thủ công và Dọn dẹp
Bây giờ, bạn muốn Job chạy ngay lập tức mà không phải ngồi đợi hết 1 phút.

**9.** Chạy thủ công bằng PL/SQL:
```sql
EXEC DBMS_SCHEDULER.RUN_JOB('TEST_INSERT_JOB');
```
**10.** Dừng không cho nó chạy lặp lại nữa bằng cách vô hiệu hóa nó:
```sql
EXEC DBMS_SCHEDULER.DISABLE('TEST_INSERT_JOB');
```
*(Truy vấn lại bảng `test_table`, bạn sẽ thấy Job không còn sinh ra dòng mới nào nữa, nó đã ngủ yên).*

**11.** Xóa sạch Job ra khỏi hệ thống để dọn dẹp môi trường:
```sql
EXEC DBMS_SCHEDULER.DROP_JOB('TEST_INSERT_JOB');
```
*(Sau bài thực hành, nhớ drop cả bảng `soe.test_table` nhé).*

---
## Câu hỏi ôn tập

**Câu 1: SQL Developer tạo Scheduler Job bằng cách nào ở phía sau nền hệ thống?**
- **Trả lời:** Giao diện đồ họa của SQL Developer chỉ là công cụ hỗ trợ trải nghiệm người dùng. Khi bạn bấm "Apply", nó sẽ sinh ra một lệnh gọi PL/SQL gói `DBMS_SCHEDULER.CREATE_JOB` và đẩy lên Database. Nó không dùng tính năng nào khác lạ cả.

**Câu 2: Nếu trong mục `Job Action` (đoạn PL/SQL) tôi gõ sai cú pháp (ví dụ thiếu dấu chấm phẩy), chuyện gì sẽ xảy ra khi bấm Apply?**
- **Trả lời:** Tùy phiên bản, Oracle có thể từ chối tạo Job ngay lúc đó vì biên dịch lỗi, HOẶC tạo Job thành công nhưng khi nó bắt đầu đến giờ chạy, nó sẽ văng lỗi `FAILED` trong phần Run Details.

**Câu 3: Mục Run Details (DBA_SCHEDULER_JOB_RUN_DETAILS) có lưu log mãi mãi không?**
- **Trả lời:** Không. Để tránh rác data dictionary, Scheduler sẽ tự động thanh lọc các log lịch sử thực thi của Job định kỳ sau khoảng thời gian mặc định (thường là 30 ngày) thông qua một cái Job nội bộ chuyên đi dọn dẹp log cũ của chính nó.

**Câu 4: Dùng lệnh `RUN_JOB('TEST_INSERT_JOB')`, hệ thống có bỏ qua hay ảnh hưởng gì đến lịch định sẵn 1 phút 1 lần kia không?**
- **Trả lời:** Không. Lệnh `RUN_JOB` là lệnh gọi tức thời (On-Demand). Nó chạy như một luồng hoàn toàn độc lập, tách biệt với chu kỳ lịch của Scheduler. Job vẫn sẽ đến hạn chạy tự động ở đúng số phút tiếp theo mà không bị sai lịch.

**Câu 5: Tại sao nên vô hiệu hóa (`DISABLE`) một Job thay vì xóa (`DROP`) nó luôn khi không cần dùng nữa?**
- **Trả lời:** Khi thiết kế một job đặc thù, bạn thường mất công viết mã PL/SQL và test cấu hình lịch chuẩn. Nếu Drop, bạn sẽ mất trắng những dòng code đó. Tốt nhất là Disable để lưu nó lại phòng hờ sau này cần dùng lại, chỉ việc gọi `ENABLE` là xong.


---

!!! info "Nguồn gốc"
    `Oracle-Database-Administration-from-Zero-to-Hero/VN/107-practice-automating-with-scheduler.md`
