---
title: 'Bài 103: Thực hành - Sử dụng SQL*Loader'
course: 01-oracle-dba-zero-to-hero
source: Oracle-Database-Administration-from-Zero-to-Hero/VN/103-practice-using-sql-loader.md
---

# Bài 103: Thực hành - Sử dụng SQL*Loader

## Mục tiêu
Trong bài thực hành này, bạn sẽ làm quen với việc:
- Nạp dữ liệu từ một file CSV (Delimited).
- Xử lý lỗi ngắt dòng của CSV khi đưa từ môi trường Windows vào Linux.
- Nạp dữ liệu từ một file văn bản với các trường cố định vị trí (Fixed Position).
- Cấu hình Control File để tự động điền tăng dần Sequence và xử lý hàm chuỗi.

## A. Nạp dữ liệu từ file Delimited (CSV)
**1.** Dùng SQL Developer xuất thử 20 dòng từ bảng `ORDERS` ra thành một file `orders2.csv`.
**2.** Trong SQL*Plus, kết nối vào `PDB1` với user `SOE` và tạo một bảng đích:
```sql
CREATE TABLE ORDERS2 (
 ORDER_ID NUMBER(12) NOT NULL,
 ORDER_DATE DATE,
 CUSTOMER_ID NUMBER(12) NOT NULL,
 ORDER_STATUS NUMBER(2),
 DELIVERY_TYPE VARCHAR2(15),
 ORDER_TOTAL NUMBER(8,2)
);
```
**3.** Tạo một file cấu hình nạp dữ liệu tên là `orders2.ctl`:
```text
LOAD DATA
INFILE 'orders2.csv'
TRUNCATE
INTO TABLE ORDERS2
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
( 
  ORDER_ID,
  ORDER_DATE DATE(21) 'DD-MM-YYYY HH24:MI:SS',
  CUSTOMER_ID,
  ORDER_STATUS,
  DELIVERY_TYPE,
  ORDER_TOTAL
)
```
**4.** Chạy lệnh SQL*Loader từ Linux:
```bash
sqlldr soe/password@pdb1 control=orders2.ctl log=orders2.log
```
*(Nếu bạn lấy file từ Windows chuyển sang, bạn có thể bị lỗi ORA-01722 (invalid number) ở cột ORDER_TOTAL vì Windows dùng `\r\n` để ngắt dòng, trong khi Linux dùng `\n`. Khi đó cột số cuối cùng bị dính theo ký tự `\r` rác).*
**5.** Để khắc phục lỗi ngắt dòng Windows, bạn sửa dòng 2 của `orders2.ctl` thành:
```text
INFILE 'orders2.csv' "str '\r\n'"
```
**6.** Chạy lại lệnh `sqlldr` và kiểm tra database, dữ liệu sẽ nạp thành công 100%.

## B. Nạp dữ liệu theo vị trí cố định (Fixed Position)
Giả sử bạn có một file `customers.dat` do máy Mainframe tạo ra, các chữ cái dính liền vào nhau ở các vị trí tọa độ cố định.

**7.** Dùng lệnh tạo cấu trúc bảng đích `CUSTOMERS2`:
```sql
CREATE TABLE CUSTOMERS2 (
 CUSTOMER_ID NUMBER(12) NOT NULL,
 CUST_NAME VARCHAR2(81),
 EMAIL VARCHAR2(100),
 TOTAL_SALES NUMBER(9),
 LOADSEQ NUMBER(4)
);
```
**8.** Viết Control File `customers2.ctl`:
```text
LOAD DATA
INFILE 'customers.dat'
APPEND
INTO TABLE CUSTOMERS2
( 
  CUSTOMER_ID POSITION(01:11) INTEGER EXTERNAL,
  CUST_NAME   POSITION(13:42) CHAR "UPPER(:CUST_NAME)",
  EMAIL       POSITION(44:73) CHAR,
  TOTAL_SALES POSITION(75:88) CHAR "TO_NUMBER(:TOTAL_SALES,'$999,999,999')",
  LOADSEQ     SEQUENCE(MAX,1)
)
```
*(File này yêu cầu: In hoa toàn bộ Tên khách hàng, Ép kiểu định dạng Tiền tệ thành dạng số học thuần túy, và Tự động điền cột thứ tự LOADSEQ tăng dần bắt đầu từ số MAX).*
**9.** Chạy lệnh `sqlldr` và xác minh tính đúng đắn của dữ liệu. Cột tên đã bị in hoa, cột Loadseq đã được điền.

## C. Nạp 1 file vào nhiều bảng (Bonus)
SQL*Loader còn hỗ trợ lấy chung một file đầu vào nhưng tách ra làm 2 bảng khác nhau thông qua nhiều thẻ `INTO TABLE` kết hợp với mệnh đề `WHEN`. (Bạn có thể xem chi tiết ở bài thực hành đầy đủ của khóa học).

---
## Câu hỏi ôn tập

**Câu 1: Tôi kiểm tra terminal, thấy báo `sqlldr` trả về "0 Rows successfully loaded". Tôi tìm file Bad file ở đâu?**
- **Trả lời:** Theo mặc định, nếu trong quá trình nạp xảy ra lỗi từ chối dữ liệu, SQL*Loader sẽ tự động sinh ra một file `.bad` có tên trùng với tên file Control (ví dụ `orders2.bad`) đặt ngay tại thư mục hiện tại của bạn. Bạn mở nó bằng công cụ text editor để xem những dòng lỗi.

**Câu 2: Dòng khai báo `INFILE 'orders2.csv' "str '\r\n'"` có tác dụng giải quyết vấn đề gì?**
- **Trả lời:** Cờ báo `str '\r\n'` báo cho hệ thống SQL*Loader ở môi trường Linux (vốn chỉ nhận dạng dòng mới bằng ký tự Line Feed `\n`) biết rằng file đầu vào được sinh ra từ môi trường Windows, kết thúc dòng bằng cụm Carriage Return + Line Feed (`\r\n`). Nó sẽ tự động cắt bỏ chữ `\r` rỗng đó để cột cuối cùng không bị dính ký tự rác.

**Câu 3: Thuộc tính `TRUNCATE` khai báo trong Control file ở Kịch bản A có tác dụng gì?**
- **Trả lời:** Nó yêu cầu SQL*Loader thực hiện xóa sạch hoàn toàn mọi dữ liệu cũ đang tồn tại trong bảng `ORDERS2` trước khi nạp dữ liệu từ file CSV vào.

**Câu 4: Làm thế nào SQL*Loader có thể đếm và tự động sinh thứ tự (sequence) cho cột dữ liệu nếu tôi không có giá trị từ file thô?**
- **Trả lời:** Bạn có thể dùng hàm khai báo `SEQUENCE(MAX,1)` tại một cột trong Control File. SQL*Loader sẽ tự động truy vấn tìm ra số lớn nhất hiện tại của cột đó trong database, và mỗi lần nạp một dòng mới nó sẽ cộng thêm 1 đơn vị.

**Câu 5: Tại sao trong Kịch bản B (Fixed Position), cột CUST_NAME lại được gán hàm `"UPPER(:CUST_NAME)"`?**
- **Trả lời:** Hàm này là một hàm xử lý chuỗi trực tiếp của Oracle Database. SQL*Loader cho phép áp dụng các hàm SQL cơ bản để "chuyển đổi" dữ liệu thô (in hoa tất cả chữ cái) ngay khi nó được đọc từ đĩa cứng và đẩy vào database, giúp tiết kiệm công sức phải chạy lệnh UPDATE sau này.


---

!!! info "Nguồn gốc"
    `Oracle-Database-Administration-from-Zero-to-Hero/VN/103-practice-using-sql-loader.md`
