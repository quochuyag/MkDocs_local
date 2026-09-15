---
title: 'Bài 79: Thực hành - Thực hiện Incremental Backups'
course: 01-oracle-dba-zero-to-hero
source: Oracle-Database-Administration-from-Zero-to-Hero/VN/79-thuc-hanh-incremental-backups.md
---

# Bài 79: Thực hành - Thực hiện Incremental Backups

## Mục tiêu
Trong bài thực hành này, bạn sẽ có được kinh nghiệm thực tế về việc thực hiện các công việc sau:
- Thực hiện Incremental Backups (differential và cumulative).
- Bật tính năng Block Change Tracking (BCT) trong database.
- Triển khai Database Incrementally Updated Backup.

## A. Thực hiện các bản Incremental Backups

**1.** Mở terminal (Putty) và đăng nhập vào `srv1` với quyền `oracle`.

**2.** Truy cập RMAN và kết nối với target database.
```bash
rman target /
```

**3.** Tạo một bản Full Level 0 Incremental Backup và gắn thẻ (tag).
```rman
BACKUP INCREMENTAL LEVEL 0 DATABASE TAG 'DBLVL0';
```
*Ghi chú lại thời gian cần thiết để tạo bản backup này để so sánh sau.*

**4.** Liệt kê các backupset của database.
```rman
LIST BACKUP OF DATABASE;
```

**5.** Thoát khỏi RMAN và mở SQL*Plus.
```bash
sqlplus hr/hr
```

**6.** Tạo một script PL/SQL để thay đổi một lượng lớn dữ liệu ngẫu nhiên trong vòng 3 phút (giả lập người dùng sử dụng).
```sql
CREATE TABLE EMP AS SELECT * FROM EMPLOYEES;
DECLARE
 N NUMBER;
 B DATE;
BEGIN
 B := SYSDATE;
 N :=1;
 WHILE TRUE LOOP
  UPDATE EMP SET SALARY = DBMS_RANDOM.VALUE(1000,10000) WHERE EMPLOYEE_ID=ROUND(DBMS_RANDOM.VALUE(100,206));
  IF MOD(N,100)=0 THEN COMMIT; END IF;
  IF ((SYSDATE-B)* 24 * 60) >=3 THEN COMMIT; EXIT; END IF;
 END LOOP;
END;
/
DROP TABLE EMP PURGE;
EXIT;
```

**7.** Chuyển đổi redo log (Switch log) trong SQL*Plus (với quyền `sysdba`).
```sql
ALTER SYSTEM SWITCH LOGFILE;
```

**8.** Quay lại RMAN, thực hiện Differential Level 1 Incremental Backup.
```rman
BACKUP INCREMENTAL LEVEL 1 DATABASE TAG 'DBLVL1';
```
*(Đây là differential vì không có từ khóa `CUMULATIVE`)*. So sánh thời gian và kích thước so với bản Level 0. Bản Level 1 sẽ nhỏ hơn và nhanh hơn rất nhiều vì nó chỉ chứa các thay đổi từ 3 phút trước.

**9.** Tiếp tục thực hiện một bản Level 1 Incremental Backup khác.
```rman
BACKUP INCREMENTAL LEVEL 1 DATABASE TAG 'DBLVL1';
```
*(Lần này cực nhanh vì gần như không có thay đổi nào giữa 2 lần Level 1)*.

**10.** Thực hiện một Cumulative Level 1 Incremental Backup.
```rman
BACKUP INCREMENTAL LEVEL 1 CUMULATIVE DATABASE TAG 'DBLVL1';
```
*(Bản cumulative này sẽ có kích thước tương đương bản Level 1 đầu tiên, vì nó tính từ bản Level 0)*.

## B. Bật Block Change Tracking (BCT)

**11.** Kiểm tra xem BCT đã được bật chưa trong SQL*Plus.
```sql
SELECT STATUS, FILENAME FROM V$BLOCK_CHANGE_TRACKING;
```

**12.** Bật tính năng BCT.
*(Lưu ý: RMAN không hỗ trợ backup file BCT, kể cả khi lưu trong FRA)*.
```sql
ALTER SESSION SET DB_CREATE_FILE_DEST='/u01/app/oracle/fast_recovery_area';
ALTER DATABASE ENABLE BLOCK CHANGE TRACKING;
```

**13.** Xác nhận lại BCT.
```sql
SELECT status, filename FROM V$BLOCK_CHANGE_TRACKING;
```

**14.** Thực hiện Level 1 Incremental Backup trong RMAN.
```rman
BACKUP INCREMENTAL LEVEL 1 DATABASE TAG 'DBLVL1';
```

**15.** Kiểm tra xem quá trình backup vừa rồi có sử dụng BCT không (trong SQL*Plus).
```sql
SELECT USED_CHANGE_TRACKING, FILE#, AVG(DATAFILE_BLOCKS), AVG(BLOCKS_READ)
FROM   V$BACKUP_DATAFILE
WHERE  INCREMENTAL_LEVEL > 0
GROUP  BY USED_CHANGE_TRACKING, FILE# ORDER BY 1;
```
*(Cột `USED_CHANGE_TRACKING` phải mang giá trị `YES`)*.

**16.** Dọn dẹp các backup set.
```rman
DELETE BACKUPSET;
```

## C. Khởi tạo Database Incrementally Updated Backup

**17.** Thực thi khối lệnh sau trong RMAN:
```rman
RUN {
 RECOVER COPY OF DATABASE WITH TAG 'incr_update';
 BACKUP INCREMENTAL LEVEL 1 FOR RECOVER OF COPY WITH TAG 'incr_update' DATABASE;
}
```
*Lần chạy đầu tiên*: Lệnh RECOVER không làm gì, còn BACKUP tạo các file Image Copies của database (Vì chưa có bản sao Level 0 nào trước đó).

**18.** Kiểm tra image copies:
```rman
LIST COPY OF DATABASE;
```

**19.** Tạo một vài giao dịch ngẫu nhiên (Switch log vài lần):
```sql
ALTER SYSTEM SWITCH LOGFILE;
```

**20.** Chạy lại khối lệnh `RUN {...}` (Lần 2).
*Lần chạy thứ hai*: RECOVER vẫn không có file thay đổi để áp dụng, BACKUP tạo ra một bản Incremental Level 1 Backup thực sự chứa các block vừa mới thay đổi.

**21.** Tiếp tục thay đổi dữ liệu (Switch log) và chạy lại khối lệnh `RUN {...}` (Lần 3).
*Lần chạy thứ ba*: RECOVER lấy bản Level 1 vừa tạo ở lần 2 đập thẳng vào Image Copies (Level 0) để cập nhật. Sau đó, BACKUP lại tạo ra một bản Incremental Level 1 mới chứa các thay đổi từ lần 2 đến hiện tại.

**22.** Kiểm tra sự thay đổi của Image Copy:
```rman
LIST COPY OF DATABASE;
```
*(Bạn sẽ thấy giá trị SCN "Ckp SCN" của các file image copies tăng lên, chứng tỏ chúng đã được update)*.

**23.** Dọn dẹp hệ thống.
```rman
DELETE COPY OF DATABASE;
DELETE BACKUPSET;
```

---
## Câu hỏi ôn tập

**Câu 1: Làm thế nào để biết một bản Level 1 Backup là Differential hay Cumulative?**
- **Trả lời:** Nếu câu lệnh không ghi rõ `CUMULATIVE`, thì RMAN mặc định tạo ra bản Differential. Bản Differential tính từ lần incremental gần nhất, còn Cumulative tính từ lần Level 0 gần nhất.

**Câu 2: Kiểm tra trạng thái của Block Change Tracking (BCT) bằng câu lệnh SQL nào?**
- **Trả lời:** Chạy truy vấn `SELECT STATUS, FILENAME FROM V$BLOCK_CHANGE_TRACKING;` để xem BCT đã được `ENABLED` hay `DISABLED` và lưu ở file nào.

**Câu 3: Làm sao để kiểm chứng việc Incremental Backup đã thực sự sử dụng BCT?**
- **Trả lời:** Bằng cách kiểm tra view `V$BACKUP_DATAFILE`, truy vấn cột `USED_CHANGE_TRACKING`. Nếu giá trị là `YES` thì RMAN đã tối ưu qua file BCT.

**Câu 4: Khi chạy khối lệnh Incrementally Updated Backups lần đầu tiên, RMAN làm gì?**
- **Trả lời:** Lần đầu chạy, do RMAN không tìm thấy bản copy nào trước đó để recover, nó sẽ tiến hành tạo mới một bộ datafiles image copy hoàn chỉnh thay vì tạo một bản Level 1.

**Câu 5: Tại sao Incrementally Updated Backups lại hữu ích trong môi trường thực tế?**
- **Trả lời:** Phương pháp này giữ cho bạn luôn có một bản copy cập nhật cực kỳ gần với thực trạng database hiện tại. Khi có sự cố, bạn chỉ cần thay file gốc bằng file copy này thay vì phải bung file Level 0 ra rồi apply hằng tá file Level 1, giảm rủi ro thời gian downtime.


---

!!! info "Nguồn gốc"
    `Oracle-Database-Administration-from-Zero-to-Hero/VN/79-thuc-hanh-incremental-backups.md`
