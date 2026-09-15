---
title: 'Bài 97: Thực hành - Sử dụng Data Recovery Advisor'
course: 01-oracle-dba-zero-to-hero
source: Oracle-Database-Administration-from-Zero-to-Hero/VN/97-thuc-hanh-recovery-advisor.md
---

# Bài 97: Thực hành - Sử dụng Data Recovery Advisor

## Mục tiêu
Trong bài thực hành này, bạn sẽ sử dụng công cụ Data Recovery Advisor (DRA) để phát hiện sự cố mất datafile và nhờ nó tự động đưa ra giải pháp sửa chữa.

## A. Chuẩn bị: Tạo sự cố mất Datafile giả lập
**1.** Bật máy chủ `srv1` (Chế độ non-CDB) và đăng nhập bằng tài khoản `oracle`.
**2.** Truy cập vào RMAN và lấy một bản Full Backup:
```rman
rman target "'/ as SYSBACKUP'"
BACKUP DATABASE TAG 'FULL_DB';
```
**3.** Chạy lệnh SQL để lấy đường dẫn thực tế của datafile thuộc tablespace USERS:
```sql
SELECT FILE_NAME FROM DBA_DATA_FILES WHERE TABLESPACE_NAME='USERS';
```
**4.** Thoát ra dấu nhắc hệ điều hành và xóa file đó để tạo lỗi vật lý (Giả sử thư mục oradata):
```bash
rm /u01/app/oracle/oradata/ORADB/datafile/*_users_*.dbf
```
**5.** Chạy lệnh kiểm tra sự vắng mặt của file để chắc chắn bạn đã xóa nó:
```bash
ls /u01/app/oracle/oradata/ORADB/datafile/*_users_*.dbf
```
*(Hệ điều hành sẽ báo lỗi "No such file or directory").*

## B. Chẩn đoán và Tự động Sửa chữa bằng DRA
Bây giờ database đang bị hỏng. Bạn sẽ đóng vai trò một DBA đang tìm cách xử lý mà không cần phải gõ tay các lệnh khôi phục dài dòng.

**6.** Trong RMAN, chạy lệnh liệt kê lỗi để xem Advisor có phát hiện ra sự cố chưa:
```rman
LIST FAILURE;
```
*(Nếu nó trả về "no failures found", có nghĩa là health monitor chưa kịp quét tới bảng này. Hãy chạy lệnh `VALIDATE DATABASE;` để ép nó quét ngay lập tức, sau đó gõ lại `LIST FAILURE;`)*.

Bạn sẽ thấy RMAN báo một lỗi có trạng thái OPEN với mô tả "One or more non-system datafiles are missing".

**7.** Nhờ Oracle đưa ra lời khuyên (Kịch bản vá lỗi):
```rman
ADVISE FAILURE;
```
*(Kết quả trên màn hình sẽ đưa ra chiến lược khôi phục: Oracle đề xuất thực hiện "restore and recover datafile...". Nó cũng cho bạn một đường dẫn tới file kịch bản `.hm` nằm trong máy tính).*

**8.** Thực thi giải pháp khôi phục tự động của Oracle:
```rman
REPAIR FAILURE;
```
*(Màn hình sẽ in ra các lệnh SQL và RMAN mà Oracle dự định chạy (như `alter database datafile... offline`, `restore datafile`, `recover datafile`...). RMAN sẽ hỏi bạn: `Do you really want to execute the above repair (enter YES or NO)?`)*.

**9.** Gõ `YES` và nhấn Enter.
Oracle sẽ tự động chạy toàn bộ các lệnh đó. Bạn chỉ cần ngồi chờ nó khôi phục xong.

**10.** Kiểm tra lại kết quả. Bạn hãy ra lệnh quét lại toàn bộ database:
```rman
VALIDATE DATABASE;
```
*(Nếu mọi thông báo lỗi đã biến mất và kết quả báo OK toàn bộ, nghĩa là bạn đã khôi phục thành công bằng sự hỗ trợ của DRA).*

## C. Dọn dẹp
**11.** Tắt máy chủ `srv1` và Restore lại bản Snapshot "non-CDB" sạch để chuẩn bị cho các bài lab sau.

---
## Câu hỏi ôn tập

**Câu 1: Điều kiện tiên quyết để Data Recovery Advisor có thể tự động khôi phục datafile bị xóa là gì?**
- **Trả lời:** Bạn phải có sẵn các file Backup (.bkp hoặc image copies) chứa dữ liệu của cái datafile bị hỏng đó được lưu ở máy hoặc FRA. Nếu không có backup, DRA cũng không thể sinh ra script để "bịa" lại dữ liệu.

**Câu 2: Tại sao khi vừa xóa file xong, gõ `LIST FAILURE` đôi khi hệ thống lại báo "No failures found"?**
- **Trả lời:** Vì background process (tiến trình nền) của hệ thống Health Monitor chưa tới lịch để quét định kỳ khu vực đó. Bạn phải mồi nó bằng lệnh `VALIDATE DATABASE` để nó lập tức quét đĩa vật lý và nhận diện lỗi vắng mặt file.

**Câu 3: Kết quả của câu lệnh `ADVISE FAILURE` mang lại những thông tin gì?**
- **Trả lời:** Nó chia thành 2 phần: Manual Actions (Các thao tác bắt buộc quản trị viên phải làm bằng tay - ví dụ: file bị đổi tên thì hãy đổi lại) và Automated Repair Options (Kế hoạch sửa tự động bằng mã RMAN kèm theo đường dẫn file chứa script đó).

**Câu 4: Chuyện gì xảy ra nếu bạn trả lời `NO` khi lệnh `REPAIR FAILURE` hỏi xác nhận?**
- **Trả lời:** Quá trình tự động vá lỗi sẽ bị hủy bỏ ngay lập tức (Abort). Cấu trúc database và file của bạn vẫn giữ nguyên hiện trạng bị hỏng.

**Câu 5: Tại sao Data Recovery Advisor lại là một tính năng cực kỳ đắc lực trong các môi trường có áp lực cao?**
- **Trả lời:** Trong một thảm họa, các DBA thường chịu áp lực tâm lý rất lớn nên dễ gõ sai cú pháp RMAN hoặc phục hồi nhầm thời điểm, nhầm file. DRA loại bỏ yếu tố rủi ro của con người bằng cách cung cấp quy trình chuẩn xác 100% bằng máy móc.


---

!!! info "Nguồn gốc"
    `Oracle-Database-Administration-from-Zero-to-Hero/VN/97-thuc-hanh-recovery-advisor.md`
