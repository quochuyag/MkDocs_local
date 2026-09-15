---
title: 'Bài 101: Thực hành - Sử dụng Oracle Data Pump'
course: 01-oracle-dba-zero-to-hero
source: Oracle-Database-Administration-from-Zero-to-Hero/VN/101-practice-oracle-data-pump.md
---

# Bài 101: Thực hành - Sử dụng Oracle Data Pump

## Mục tiêu
Trong bài thực hành này, bạn sẽ làm quen với việc:
- Sử dụng tiện ích Data Pump Export/Import để di chuyển schema `SOE` từ máy chủ `srv1` sang máy chủ `winsrv`.
- Thực hiện remapping Tablespace.
- Chuyển dữ liệu trực tiếp bằng Network Link.

## A. Chuyển dữ liệu bằng Dump File (.dmp)

**1.** Vào Linux (`srv1`), lấy đường dẫn của thư mục Data Pump mặc định:
```sql
conn / as sysdba
SELECT DIRECTORY_PATH FROM DBA_DIRECTORIES WHERE DIRECTORY_NAME='DATA_PUMP_DIR';
```
**2.** Tạo một thư mục riêng biệt để chứa dump file và trỏ Directory Object tới nó:
```sql
ALTER SESSION SET CONTAINER=PDB1;
CREATE DIRECTORY DUMPDIR AS '/media/sf_staging/dump';
GRANT READ, WRITE ON DIRECTORY DUMPDIR TO SOE;
```
**3.** Thoát SQL*Plus, ước tính dung lượng file dump mà không xuất thật:
```bash
expdp SOE/password@pdb1 DIRECTORY=DUMPDIR ESTIMATE_ONLY=Y ESTIMATE=STATISTICS
```
**4.** Tiến hành Export thật schema SOE:
```bash
expdp SOE/password@pdb1 DIRECTORY=DUMPDIR DUMPFILE=SOE.dmp LOGFILE=SOE.log LOGTIME=ALL METRICS=YES
```
*(Tiến trình xuất file diễn ra. Sau đó, bạn copy file `SOE.dmp` sang máy chủ Windows `winsrv` vào ổ đĩa `D:\temp`).*

**5.** Sang máy chủ Windows (`winsrv`), khai báo thư mục đó cho Database đích:
```sql
sqlplus sys/password@orawindb as sysdba
CREATE OR REPLACE DIRECTORY DUMPDIR AS 'D:\temp';
GRANT READ, WRITE ON DIRECTORY DUMPDIR TO SOE;
```
**6.** Dùng `impdp` để nhồi dữ liệu vào, nhưng vì máy đích có Tablespace tên khác, ta phải dùng `REMAP_TABLESPACE`:
```cmd
impdp SOE/password@orawindb DIRECTORY=DUMPDIR DUMPFILE=SOE.dmp LOGFILE=SOEimport.log REMAP_TABLESPACE=SOETBS:WINSOE LOGTIME=ALL METRICS=YES
```
**7.** Import hoàn tất. Đôi khi PL/SQL package bị invalid, bạn chạy lệnh biên dịch lại:
```sql
ALTER PACKAGE "SOE"."ORDERENTRY" COMPILE;
```

## B. Chuyển dữ liệu bằng Network Link (Không dùng file .dmp)
Bây giờ ta sẽ chuyển dữ liệu mà không cần tạo file `SOE.dmp` nữa. Ta sẽ kéo thẳng dữ liệu từ máy Linux sang máy Windows.

**8.** Trên máy Windows (`winsrv`), tạo lại user SOE trống và cấp quyền tạo DB Link:
```sql
GRANT CREATE DATABASE LINK TO SOE;
```
**9.** Trong user SOE (trên Windows), tạo kết nối mạng trỏ ngược về máy Linux:
```sql
CREATE DATABASE LINK PDB1.LOCALDOMAIN 
CONNECT TO SOE IDENTIFIED BY password USING 'soesrv1';
```
*(Hãy test thử bằng lệnh: `SELECT SYSDATE FROM DUAL@PDB1.LOCALDOMAIN;` Nếu thành công nghĩa là hai máy đã thông với nhau qua DB Link).*

**10.** Ra ngoài môi trường Command Prompt của Windows, chạy lệnh `impdp` kéo dữ liệu thẳng qua mạng:
```cmd
impdp SOE/password NETWORK_LINK=PDB1.LOCALDOMAIN DIRECTORY=DUMPDIR LOGFILE=SOE_net.log REMAP_TABLESPACE=SOETBS:WINSOE LOGTIME=ALL METRICS=YES
```
*(Data Pump sẽ đọc dữ liệu từ máy nguồn qua đường mạng và nhồi trực tiếp vào máy đích).*

## C. Dọn dẹp
**11.** Drop user SOE trên `winsrv` và xóa các file rác trong thư mục dump. Tắt máy ảo và revert snapshot về trạng thái sạch.

---
## Câu hỏi ôn tập

**Câu 1: Lệnh cấp quyền `GRANT READ, WRITE ON DIRECTORY DUMPDIR TO SOE;` có bắt buộc không?**
- **Trả lời:** Có. Mặc dù SOE là chủ sở hữu của chính dữ liệu đó, nhưng để tiến trình máy chủ được phép ghi file `.dmp` và `.log` xuống ổ cứng thông qua đối tượng thư mục, user SOE phải được phân quyền rõ ràng trên cái Directory Object đó.

**Câu 2: Tại sao khi import trên máy chủ đích lại phát sinh cảnh báo ORA-39082 về "Package Body compiled with warnings"?**
- **Trả lời:** Vì khi import các đối tượng thủ tục (Package, Procedure), hệ thống đích có thể bị phụ thuộc, thiếu quyền hoặc thứ tự khởi tạo bảng chưa chuẩn, dẫn đến lỗi biên dịch. Ta chỉ cần chạy lệnh `COMPILE` lại bằng tay sau đó là xong. Hoặc dùng script `@utlrp.sql` để biên dịch tự động.

**Câu 3: Mục đích của cụm tham số `LOGTIME=ALL METRICS=YES` là gì?**
- **Trả lời:** Để làm cho file log được chi tiết hơn. `LOGTIME=ALL` in ra thời gian (timestamp) cụ thể cho từng dòng log để theo dõi tiến độ. `METRICS=YES` in ra các thông số về hiệu suất, số đối tượng xử lý, giúp DBA phân tích báo cáo thời gian chạy của job.

**Câu 4: Ở Kịch bản B, tại sao lệnh `impdp` không có tham số `DUMPFILE=`?**
- **Trả lời:** Vì Kịch bản B dùng phương thức Network Link. Dữ liệu được truyền thẳng vào RAM qua kết nối TNS thay vì phải đọc từ ổ cứng. Do đó, tham số `DUMPFILE` bị bỏ qua.

**Câu 5: Dù không dùng Dump file ở kịch bản Network Link, tại sao vẫn phải cấu hình tham số `DIRECTORY=DUMPDIR`?**
- **Trả lời:** Vì Data Pump vẫn luôn cần ghi lại nhật ký toàn bộ quá trình chạy ra một file text. Tham số DIRECTORY khai báo nơi nó sẽ lưu cái file `SOE_net.log` đó.


---

!!! info "Nguồn gốc"
    `Oracle-Database-Administration-from-Zero-to-Hero/VN/101-practice-oracle-data-pump.md`
