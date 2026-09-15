---
title: 'Bài 106: Tự động hóa với Oracle Scheduler'
course: 01-oracle-dba-zero-to-hero
source: Oracle-Database-Administration-from-Zero-to-Hero/VN/106-automating-tasks-with-scheduler.md
---

# Bài 106: Tự động hóa với Oracle Scheduler

## Mục tiêu
Trong bài học này, bạn sẽ học cách thực hiện các công việc sau:
- Khái niệm về Scheduler trong Oracle Database.
- Phân biệt giữa Program, Schedule và Job.
- Tạo và quản lý các tác vụ lặp lại (Jobs).
- Cách sử dụng DBMS_SCHEDULER để tự động hóa các tác vụ quản trị cơ sở dữ liệu và hệ điều hành.

## Tổng quan về Oracle Scheduler
Trong môi trường Database, có rất nhiều công việc lặp đi lặp lại như: backup dữ liệu, gom dọn rác, tính toán số liệu thống kê. Chạy bằng tay các tác vụ này rất tốn công. **Oracle Scheduler** là tính năng được tích hợp sẵn bên trong Database giúp lập lịch và thực thi các chương trình này tự động.

Nó mạnh mẽ và đáng tin cậy hơn các công cụ lập lịch ở cấp độ hệ điều hành như `cron` (Linux) hoặc `Task Scheduler` (Windows) vì nó biết rõ trạng thái của database và có thể ghi log trực tiếp vào Data Dictionary.

## Các thành phần chính (Scheduler Objects)

Để Scheduler hoạt động linh hoạt, Oracle chia nó thành 3 thành phần rời rạc. Việc chia tách này giúp tái sử dụng mã một cách hoàn hảo:
1. **Program (Làm cái gì?):** Khai báo đoạn mã PL/SQL, một thủ tục, hoặc một file script chạy trên hệ điều hành (`.sh` hoặc `.bat`). 
2. **Schedule (Khi nào làm?):** Định nghĩa tần suất và thời gian (ví dụ: Mỗi sáng chủ nhật lúc 2h).
3. **Job (Sự kết hợp):** Đây là nhân tố cuối cùng kết nối `Program` và `Schedule` lại với nhau, và gắn nó cho một người thực thi. Khi một Job được Enable, Scheduler sẽ canh thời gian để chạy Program.

*Lưu ý: Mặc dù chia thành 3 phần, bạn vẫn có thể tạo thẳng một Job độc lập mà không cần tạo Program hay Schedule trước (Job sẽ tự ôm trọn 3 thuộc tính đó vào mình luôn).*

## Cấu hình Scheduler với PL/SQL (`DBMS_SCHEDULER`)
Package `DBMS_SCHEDULER` là trái tim của hệ thống này. Tất cả các quản lý đều thông qua đây.

**1. Tạo một Job tự động chạy PL/SQL:**
```sql
BEGIN
  DBMS_SCHEDULER.CREATE_JOB (
    job_name        => 'UPDATE_SALARY_JOB',
    job_type        => 'PLSQL_BLOCK',
    job_action      => 'BEGIN UPDATE hr.employees SET salary = salary * 1.05; COMMIT; END;',
    start_date      => SYSTIMESTAMP,
    repeat_interval => 'FREQ=DAILY; BYHOUR=0; BYMINUTE=0;', -- Chạy mỗi 0h sáng
    enabled         => TRUE
  );
END;
/
```
**2. Tạo Job chạy Script hệ điều hành (Chạy lệnh BASH/CMD):**
```sql
BEGIN
  DBMS_SCHEDULER.CREATE_JOB (
    job_name        => 'BACKUP_SCRIPT_JOB',
    job_type        => 'EXECUTABLE',
    job_action      => '/home/oracle/scripts/backup.sh',
    enabled         => TRUE
  );
END;
/
```
*(Để chạy Executable, bạn cần phải cấu hình quyền hạn nghiêm ngặt ở OS cho external jobs).*

## Quản lý Jobs
Bạn có thể dễ dàng can thiệp vào vòng đời của một Job thông qua các thủ tục:
- Dừng Job đang chạy: `DBMS_SCHEDULER.STOP_JOB('JOB_NAME');`
- Xóa hẳn Job: `DBMS_SCHEDULER.DROP_JOB('JOB_NAME');`
- Bật/Tắt Job mà không cần xóa: `DBMS_SCHEDULER.ENABLE('JOB_NAME');` / `DBMS_SCHEDULER.DISABLE('JOB_NAME');`
- Chạy Job ngay lập tức (Test thử ngoài lịch): `DBMS_SCHEDULER.RUN_JOB('JOB_NAME');`

Bạn có thể theo dõi nhật ký thực thi của Job qua Data Dictionary View `DBA_SCHEDULER_JOB_RUN_DETAILS`. Nó sẽ chỉ ra chính xác lúc nào Job chạy thành công hay thất bại.

---
## Câu hỏi ôn tập

**Câu 1: Việc tách riêng Program và Schedule trong kiến trúc Scheduler mang lại lợi ích gì?**
- **Trả lời:** Giúp tính tái sử dụng cao. Bạn có thể có một "Schedule" duy nhất định nghĩa "cuối tháng". Rồi bạn tạo 5 "Job" khác nhau (Job xuất báo cáo, Job tính lương, Job dọn rác), và cả 5 Job này đều cùng trỏ vào một Schedule "cuối tháng" đó. Bạn chỉ việc sửa 1 chỗ khi lịch cuối tháng đổi ngày.

**Câu 2: Oracle Scheduler có thể được sử dụng để gọi một bash script bên ngoài Linux không?**
- **Trả lời:** Hoàn toàn được. Bằng cách định nghĩa `job_type` là `EXECUTABLE`, Oracle sẽ gọi thẳng file lệnh chạy trên nền Hệ điều hành thay vì mã PL/SQL. Tính năng này được xử lý thông qua tiện ích Extjob bảo mật.

**Câu 3: Nếu hệ thống đang offline vào thời điểm Job cần chạy, chuyện gì sẽ xảy ra?**
- **Trả lời:** Khi hệ thống khởi động lại, Scheduler sẽ kiểm tra các Job bị trễ. Tùy thuộc vào chính sách lịch trình (ví dụ các thuộc tính cửa sổ bảo trì hoặc catch-up), Job đó có thể tự động chạy bù hoặc bị bỏ qua để chờ kỳ sau.

**Câu 4: Mệnh đề `FREQ=DAILY; BYHOUR=0; BYMINUTE=0;` trong lịch được gọi là cú pháp gì?**
- **Trả lời:** Đây là cú pháp lịch lịch (Calendaring Syntax) độc quyền của Oracle. Nó mạnh và dễ đọc hơn rất nhiều so với cú pháp định vị `cron` của UNIX, cho phép chỉ định chính xác ngày làm việc cuối cùng của tháng, hoặc thứ sáu thứ 3 của tháng.

**Câu 5: Tại sao tôi đã chạy lệnh `CREATE_JOB` thành công rồi mà mãi không thấy đoạn mã được thực thi?**
- **Trả lời:** Vì theo mặc định, một Job sau khi tạo xong nếu không có tham số `enabled => TRUE` thì nó sẽ nằm ở trạng thái "DISABLED". Bạn phải gọi lệnh `DBMS_SCHEDULER.ENABLE()` thì nó mới thực sự bắt đầu canh đồng hồ để chạy.


---

!!! info "Nguồn gốc"
    `Oracle-Database-Administration-from-Zero-to-Hero/VN/106-automating-tasks-with-scheduler.md`
