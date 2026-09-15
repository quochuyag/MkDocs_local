---
title: 'Bài 104: Sử dụng External Tables (Bảng Ngoài)'
course: 01-oracle-dba-zero-to-hero
source: Oracle-Database-Administration-from-Zero-to-Hero/VN/104-using-external-tables.md
---

# Bài 104: Sử dụng External Tables (Bảng Ngoài)

## Mục tiêu
Trong bài học này, bạn sẽ học cách thực hiện các công việc sau:
- Hiểu khái niệm và chức năng của External Tables.
- Cấu hình và tạo External Table sử dụng trình điều khiển `ORACLE_LOADER`.
- Cấu hình và tạo External Table sử dụng trình điều khiển `ORACLE_DATAPUMP`.
- Nắm bắt được những mặt hạn chế của External Table so với bảng thông thường.

## Khái niệm External Tables
Bảng ngoài (External Table) là một đối tượng cơ sở dữ liệu cho phép Oracle truy cập các file dữ liệu (thường là file văn bản, csv) nằm bên ngoài ổ đĩa máy chủ hệ điều hành như thể chúng là một bảng (table) thực thụ trong database. 

- Không có bất kỳ dữ liệu nào được lưu trong Database, nó chỉ chứa metadata (cấu trúc bảng). 
- Khi bạn chạy lệnh `SELECT * FROM external_table`, tiến trình nền của Oracle sẽ ra ổ đĩa đọc file text đó lên và trả kết quả dưới dạng bảng.
- Bạn KHÔNG THỂ thực hiện các thao tác DML như `INSERT`, `UPDATE`, `DELETE` hoặc tạo Index trên External Table.

## Kiến trúc Access Drivers
Oracle hỗ trợ 2 loại trình điều khiển truy cập để cấu hình External Tables:
1. **ORACLE_LOADER:** Chỉ cho phép đọc liệu từ bên ngoài ổ cứng. Dữ liệu bên ngoài thường là các file dạng CSV hoặc Fixed-length Text. (Dùng cú pháp y hệt như SQL*Loader Control File).
2. **ORACLE_DATAPUMP:** Hỗ trợ đọc VÀ GHI ra ngoài ổ cứng, nhưng dữ liệu nằm ở ngoài phải là dạng nhị phân dump (`.dmp`) riêng biệt của Oracle (không phải file chữ text đọc bằng mắt thường).

## Khai báo External Table với ORACLE_LOADER
Yêu cầu bắt buộc là bạn phải có một Directory Object trỏ tới thư mục chứa file.
```sql
CREATE TABLE ext_orders
 (ORDER_ID       NUMBER(12),
  ORDER_DATE     DATE,
  ORDER_TOTAL    NUMBER(8,2)
 )
ORGANIZATION EXTERNAL
 ( 
   TYPE ORACLE_LOADER
   DEFAULT DIRECTORY extdir
   ACCESS PARAMETERS
   ( RECORDS DELIMITED BY NEWLINE
     BADFILE EXTDIR:'extorders.bad'
     LOGFILE EXTDIR:'extorders.log'
     FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
     MISSING FIELD VALUES ARE NULL
     ( ORDER_ID,
       ORDER_DATE DATE MASK 'DD-MM-YYYY HH24:MI:SS',
       ORDER_TOTAL
      )
   )
   LOCATION ('extorders.csv')
  )
REJECT LIMIT UNLIMITED;
```
Bạn chỉ cần thực hiện truy vấn `SELECT * FROM ext_orders;`. Mọi dữ liệu không chuẩn sẽ bị tống vào file `.bad` đã quy định.

## Khai báo External Table với ORACLE_DATAPUMP
Driver này có tính năng thú vị hơn: Nó cho phép bạn truy vấn dữ liệu từ các bảng trong database rồi "xuất" thẳng ra thành một file dump (`.dmp`) nằm trên ổ cứng bằng câu lệnh `CREATE TABLE ... AS SELECT`.
```sql
CREATE TABLE ext_orders_dump
ORGANIZATION EXTERNAL
  (
    TYPE ORACLE_DATAPUMP
    DEFAULT DIRECTORY extdir
    LOCATION ('orders_output.dmp')
  )
AS
SELECT ORDER_ID, ORDER_DATE, ORDER_TOTAL FROM ORDERS;
```
Và sau đó, bạn có thể bê file `orders_output.dmp` sang một máy chủ Oracle khác và tạo bảng External Table (Datapump) để truy vấn luôn dữ liệu từ đó.

---
## Câu hỏi ôn tập

**Câu 1: External Tables và công cụ SQL*Loader có điểm chung lớn nhất là gì?**
- **Trả lời:** Cả hai đều có chung bộ nền tảng xử lý dữ liệu và cú pháp định dạng trường (`ACCESS PARAMETERS` của External Table thực chất dùng chung engine và ngữ pháp với Control File của SQL*Loader).

**Câu 2: Tại sao chúng ta không thể chạy lệnh `UPDATE` hay `INSERT` lên một External Table loại `ORACLE_LOADER`?**
- **Trả lời:** Vì dữ liệu thực chất nằm trên một file văn bản phẳng ngoài hệ điều hành. Oracle Database chỉ cung cấp công cụ "đọc" trực tiếp chứ không cung cấp công cụ sửa chữa (write) lên các file dạng text do nó không thể đảm bảo tính toàn vẹn và Transaction (ACID) như file `.dbf`.

**Câu 3: Mục đích của `REJECT LIMIT UNLIMITED` là gì khi tạo External Table?**
- **Trả lời:** Nó cho phép tiến trình đọc file không bị sụp đổ (abort) ngay lập tức khi phát hiện lỗi dữ liệu. Dù cho file nguồn có tới hàng ngàn dòng bị lỗi (định dạng sai, sai kiểu), hệ thống cứ việc tống hết chúng vào file Bad mà vẫn trả về các dòng thành công cho câu lệnh SELECT.

**Câu 4: Bạn có thể tạo Index trên External Table để tăng tốc độ Select không?**
- **Trả lời:** Không thể. Bảng ngoài không quản lý lưu trữ (Blocks, Segments) nên không thể gắn Index. Mỗi lần bạn chạy `SELECT`, nó bắt buộc phải quét (Full Scan) toàn bộ file văn bản đó. Trừ phi bạn tự nạp kết quả đó vào bảng Internal.

**Câu 5: Trong kịch bản Datapump External Table, tôi tạo bảng bằng `AS SELECT...`. Nếu bảng gốc thay đổi dữ liệu, file `.dmp` có tự cập nhật không?**
- **Trả lời:** Không. Câu lệnh `AS SELECT` ở thời điểm đó chỉ chụp lại một bản sao (Snapshot) của kết quả rồi ghi cứng ra file nhị phân. Các thay đổi sau này trong bảng gốc sẽ không truyền xuống file `.dmp`.


---

!!! info "Nguồn gốc"
    `Oracle-Database-Administration-from-Zero-to-Hero/VN/104-using-external-tables.md`
