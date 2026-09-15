---
title: 'Bài 105: Thực hành - Sử dụng External Tables'
course: 01-oracle-dba-zero-to-hero
source: Oracle-Database-Administration-from-Zero-to-Hero/VN/105-practice-using-external-tables.md
---

# Bài 105: Thực hành - Sử dụng External Tables

## Mục tiêu
Trong bài thực hành này, bạn sẽ làm quen với việc:
- Định nghĩa một bảng ngoài đọc dữ liệu từ file văn bản (.csv) với trình điều khiển `ORACLE_LOADER`.
- Kiểm tra tính tương tác của cơ sở dữ liệu khi file văn bản bên ngoài bị sửa đổi bằng tay.
- Sử dụng trình điều khiển `ORACLE_DATAPUMP` để xuất một báo cáo thẳng ra định dạng dump.

## A. External Table với trình điều khiển ORACLE_LOADER

**1.** Trong Linux (PDB1), hãy xuất 100 dòng dữ liệu từ bảng ORDERS ra thành file `extorders.csv`. Chép file CSV này từ máy chủ `srv1` sang máy chủ `winsrv` và đặt nó vào thư mục `D:\temp`.
**2.** Trên máy `winsrv`, tạo Directory object và cấp quyền:
```sql
sqlplus sys/password@orawindb as sysdba
CREATE OR REPLACE DIRECTORY EXTDIR AS 'D:\temp';
GRANT READ, WRITE ON DIRECTORY EXTDIR TO HR;
```
**3.** Vào tài khoản HR, tạo một External Table trỏ tới thư mục và file `.csv` đó:
```sql
CREATE TABLE ext_orders
 (ORDER_ID       NUMBER(12),
  ORDER_DATE     DATE,
  CUSTOMER_ID    NUMBER(12),
  ORDER_STATUS   NUMBER(2),
  DELIVERY_TYPE  VARCHAR2(15),
  ORDER_TOTAL    NUMBER(8,2)
 )
ORGANIZATION EXTERNAL
 ( TYPE ORACLE_LOADER
   DEFAULT DIRECTORY extdir
   ACCESS PARAMETERS
   ( RECORDS DELIMITED BY NEWLINE
     BADFILE EXTDIR:'extorders.bad'
     LOGFILE EXTDIR:'extorders.log'
     FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
     MISSING FIELD VALUES ARE NULL
     ( ORDER_ID,
       ORDER_DATE DATE MASK 'DD-MM-YYYY HH24:MI:SS',
       CUSTOMER_ID,
       ORDER_STATUS,
       DELIVERY_TYPE,
       ORDER_TOTAL
      )
   )
   LOCATION ('extorders.csv')
  )
REJECT LIMIT UNLIMITED;
```
**4.** Truy vấn bảng. Bạn sẽ thấy ngày tháng hiển thị theo định dạng mặc định (NLS) của phiên chứ không phải định dạng DD-MM-YYYY của file text. 
```sql
SELECT * FROM ext_orders;
```
*(Điều này chứng tỏ Oracle đã ngầm hiểu và tự ép kiểu dữ liệu từ Text sang DATE khi đẩy lên RAM).*

**5.** Ra ngoài thư mục Windows `D:\temp`, bạn mở file `extorders.csv` lên, phá hỏng dữ liệu một dòng bất kỳ (Ví dụ gõ chữ thay vì số). Lưu file lại.
**6.** Trong SQL Developer, chạy lại lệnh `SELECT * FROM ext_orders`. Sẽ chỉ còn 99 dòng được trả về. Mở thư mục `D:\temp` lên, bạn sẽ thấy hệ thống tự động sinh ra file `extorders.bad` chứa cái dòng bạn vừa sửa.

## B. External Table với trình điều khiển ORACLE_DATAPUMP
Driver này biến câu lệnh `SELECT` thành một file vật lý trên đĩa cứng để lưu trữ nhanh.

**7.** Tại Linux `srv1`, tạo thư mục và cấp quyền cho user `SOE` (PDB1).
**8.** Kết nối `SOE`, tạo một bảng ngoài và đổ thẳng dữ liệu truy vấn ra đĩa bằng mệnh đề `AS SELECT`:
```sql
CREATE TABLE ext_orders_dump
ORGANIZATION EXTERNAL
  (
    TYPE ORACLE_DATAPUMP
    DEFAULT DIRECTORY extdir
    LOCATION ('orders.dmp')
  )
AS
SELECT ORDER_ID, ORDER_DATE, CUSTOMER_ID, ORDER_STATUS, DELIVERY_TYPE, ORDER_TOTAL
FROM ORDERS FETCH FIRST 100 ROWS ONLY;
```
**9.** Kiểm tra thư mục vật lý ở đĩa mềm, bạn sẽ thấy file nhị phân `orders.dmp` và file nhật ký.
**10.** Dùng lệnh `SELECT * FROM ext_orders_dump;`. Bảng này bây giờ không truy vấn bảng `ORDERS` thật nữa, nó lấy dữ liệu lên từ file `orders.dmp`!
**11.** Thử lệnh `DELETE EXT_ORDERS;` và xem Oracle báo lỗi cấm chỉnh sửa.
*(Sau bài thực hành, nhớ dọn dẹp các bảng và file dump vừa tạo).*

---
## Câu hỏi ôn tập

**Câu 1: Lệnh `CREATE TABLE ... AS SELECT` có thể dùng cho `ORACLE_LOADER` để sinh ra file Text (CSV) không?**
- **Trả lời:** Không thể. Bảng ngoài kiểu `ORACLE_LOADER` chỉ là công cụ read-only, bạn không thể ép Database tự ghi ra file định dạng chữ phẳng. Nếu muốn tự sinh ra file dump nhị phân, phải dùng `ORACLE_DATAPUMP`.

**Câu 2: Tại sao khi có lỗi trong file CSV, toàn bộ quá trình SELECT của tôi không bị đứng im mà vẫn ra kết quả?**
- **Trả lời:** Bởi vì tùy chọn `REJECT LIMIT UNLIMITED` được định nghĩa trong lúc khai báo bảng ngoài. Nó báo hệ thống đừng bao giờ văng lỗi phá vỡ Transaction khi SELECT, chỉ cần âm thầm bỏ các dòng rác đó vào Bad File là đủ.

**Câu 3: Bảng `ext_orders_dump` có chiếm không gian lưu trữ (Segment) trong Tablespace không?**
- **Trả lời:** Không. Bất cứ External table nào dù là Datapump hay Loader đều không dùng Block của Database để lưu trữ. Chúng hoàn toàn lưu trữ trên ổ đĩa vật lý của máy chủ. Nó chỉ lưu thông tin metadata trong System Tablespace.

**Câu 4: Bảng External Table có thể bị DROP như bảng thường không? Phải chăng file CSV cũng sẽ bị xóa theo?**
- **Trả lời:** Có thể thực hiện lệnh `DROP TABLE ext_orders;`. Lúc này Database sẽ xóa bỏ cấu trúc bảng và metadata bên trong Oracle, nhưng **file vật lý (CSV, Dump) vẫn an toàn nằm nguyên vẹn** trên đĩa cứng hệ điều hành.

**Câu 5: Nếu tôi chỉ định Datatype của cột trong `ORACLE_DATAPUMP` (Kịch bản B), có cần thiết không?**
- **Trả lời:** Khi tạo bằng cú pháp `AS SELECT`, Oracle sẽ tự động nội suy Datatype của cột từ câu truy vấn đích, bạn không cần (và không nên) khai báo trước Datatype. (Bạn chỉ cần khai báo Datatype khi mang cái file dump đó sang máy mới để gắn nó vào một cái External Table có sẵn).


---

!!! info "Nguồn gốc"
    `Oracle-Database-Administration-from-Zero-to-Hero/VN/105-practice-using-external-tables.md`
