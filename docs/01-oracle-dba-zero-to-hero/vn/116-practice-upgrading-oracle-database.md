---
title: 'Bài 116: Thực hành - Nâng cấp Oracle Database (19c lên 21c)'
course: 01-oracle-dba-zero-to-hero
source: Oracle-Database-Administration-from-Zero-to-Hero/VN/116-practice-upgrading-oracle-database.md
---

# Bài 116: Thực hành - Nâng cấp Oracle Database (19c lên 21c)

## Mục tiêu
Trong bài thực hành này, bạn sẽ tiến hành quá trình tự động nâng cấp cơ sở dữ liệu Oracle Database từ phiên bản 19c (19.3) lên 21c (21.3) sử dụng tiện ích **AutoUpgrade**.

## A. Cài đặt môi trường mới
**1.** Máy chủ cần có RAM khoảng 8GB (vì sẽ chạy 2 tiến trình DB cùng lúc trong lúc vá). Khởi động `srv1`.
**2.** Tải file cài đặt phần mềm **Oracle Database 21c** (khoảng 2.8GB).
**3.** Tạo một thư mục `ORACLE_HOME` mới riêng biệt cho 21c:
```bash
mkdir -p /u01/app/oracle/product/21.0.0/db_1
```
**4.** Giải nén phần mềm 21c thẳng vào thư mục vừa tạo. Chạy file `./runInstaller` để cài đặt **Chỉ phần mềm** (Software Only), tuyệt đối KHÔNG chọn tùy chọn tạo Database. Hệ thống sẽ cấp một ORACLE_HOME hoàn toàn sạch.

## B. Phân tích trước khi nâng cấp (Analyze Mode)
**5.** Tải file công cụ nâng cấp mới nhất `autoupgrade.jar` (thường được gắn ở My Oracle Support) và chép vào máy `srv1`.
**6.** Tạo thư mục chứa file cấu hình và sinh ra file `upgrade21c.cfg`:
```bash
mkdir ~/autoupgrade
cd ~/autoupgrade
vi upgrade21c.cfg
```
Nội dung file:
```properties
global.autoupg_log_dir=/home/oracle/autoupgrade
19c21c.source_home=/u01/app/oracle/product/19.0.0/db_1
19c21c.target_home=/u01/app/oracle/product/21.0.0/db_1
19c21c.sid=oradb
```
**7.** Lấy Java từ Home mới (21c) và chạy AutoUpgrade ở chế độ **ANALYZE**:
```bash
export ORACLE_HOME=/u01/app/oracle/product/21.0.0/db_1
$ORACLE_HOME/jdk/bin/java -jar ~/autoupgrade.jar -config upgrade21c.cfg -mode ANALYZE
```
*(Tiến trình sẽ mở giao diện console nội bộ. Dùng lệnh `status` để xem trạng thái và `lsj` để liệt kê các Job. Sau khi xong 100%, bạn dùng lệnh `exit` để thoát).*

**8.** Mở file báo cáo HTML (được sinh ra tại `/home/oracle/autoupgrade/cfgtoollogs/upgrade/auto/status/status.html`) bằng trình duyệt Firefox trong VNC. Báo cáo sẽ hiển thị các vấn đề (nếu có).

## C. Thực thi nâng cấp (Deploy Mode)
*Lưu ý: Bạn phải sửa hết các lỗi nghiêm trọng (Errors) báo đỏ trong file HTML trước khi Deploy, nếu không quá trình sẽ thất bại.*

**9.** Chạy lại AutoUpgrade nhưng ở chế độ **DEPLOY**:
```bash
$ORACLE_HOME/jdk/bin/java -jar ~/autoupgrade.jar -config upgrade21c.cfg -mode DEPLOY
```
*(Lệnh này làm mọi thứ từ A đến Z. Nó sẽ tự tạo điểm khôi phục (Restore Point), tự tắt database ở thư mục cũ 19c, khởi động lại nó bằng thư mục mới 21c, cập nhật toàn bộ cấu trúc Data Dictionary, thay đổi timezone, tắt tính năng lỗi thời, biên dịch lại các hàm Invalid, và xóa Restore Point. Rất tốn thời gian, có thể từ 30 đến 60 phút).*

**10.** Trong console của autoupgrade, bạn thỉnh thoảng gõ `lsj` và xem nó chuyển qua các giai đoạn: `SETUP -> PREFIXUPS -> DRAIN -> UPGRADE -> POSTCHECKS`.
**11.** Khi trạng thái cuối báo 100% DONE, nâng cấp hoàn tất!
**12.** Cập nhật file `.bash_profile` của user `oracle` để trỏ biển `ORACLE_HOME` vĩnh viễn sang thư mục `21.0.0` mới. Và bạn đã sở hữu Database 21c hoàn chỉnh.

---
## Câu hỏi ôn tập

**Câu 1: Tôi có nên cài đè (overwrite) phần mềm 21c lên chung thư mục 19c cũ để nâng cấp cho nhanh không?**
- **Trả lời:** TUYỆT ĐỐI KHÔNG. Kiến trúc Out-of-place Upgrade của Oracle bắt buộc bạn phải cài phần mềm mới (Binaries) vào một `ORACLE_HOME` hoàn toàn trống rỗng và riêng biệt. Tránh làm hỏng hệ thống và đảm bảo bạn có thể bật lại phần mềm cũ bất cứ lúc nào nếu nâng cấp thất bại.

**Câu 2: Nếu tôi gõ thiếu đuôi `.jar` trong tên file thì sao? Lệnh java báo lỗi gì?**
- **Trả lời:** Máy ảo Java (JVM) sẽ báo lỗi không tìm thấy hoặc không định dạng được file thực thi. Lệnh chạy phải chính xác là `java -jar autoupgrade.jar`. 

**Câu 3: Báo cáo Analyze cảnh báo rằng Fast Recovery Area của tôi không đủ chỗ trống. Việc này có nghiêm trọng không?**
- **Trả lời:** Có, rất nghiêm trọng. Chế độ DEPLOY yêu cầu phải bật Guaranteed Restore Point để có thể tự lùi lại nếu nâng cấp lỗi. Restore Point này sẽ tốn rất nhiều chỗ trống trong đĩa FRA. Nếu FRA bị đầy, quá trình nâng cấp sẽ bị dừng cứng (Hang).

**Câu 4: Lệnh `status` và `lsj` trong màn hình console của AutoUpgrade dùng để làm gì?**
- **Trả lời:** Do tiến trình nâng cấp chạy ẩn dưới nền tảng đa luồng, màn hình terminal thường không chạy cuộn văn bản lên liên tục. `lsj` (List Jobs) liệt kê các Database đang được nâng cấp song song, còn `status` sẽ in ra tiến trình (%) và số job đang chạy.

**Câu 5: Nếu đến đoạn UPGRADE hệ thống bị tắt điện, tôi phải làm sao?**
- **Trả lời:** Nhờ tính năng tự động Guaranteed Restore Point sinh ra ở bước trước, sau khi có điện lại, bạn chỉ cần mở thủ công Database lên và chạy lệnh `FLASHBACK DATABASE` trở lại cái Restore Point đó. Database sẽ trở về đúng trạng thái nguyên vẹn ở bản 19c như chưa hề có cuộc nâng cấp nào.


---

!!! info "Nguồn gốc"
    `Oracle-Database-Administration-from-Zero-to-Hero/VN/116-practice-upgrading-oracle-database.md`
