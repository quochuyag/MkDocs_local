---
title: 'Bài 102: Giới thiệu và Sử dụng SQL*Loader'
course: 01-oracle-dba-zero-to-hero
source: Oracle-Database-Administration-from-Zero-to-Hero/VN/102-using-sql-loader.md
---

# Bài 102: Giới thiệu và Sử dụng SQL*Loader

## Mục tiêu
Trong bài học này, bạn sẽ học cách thực hiện các công việc sau:
- Khái niệm về công cụ SQL*Loader.
- Cách thiết lập Control File để chỉ định cách nạp dữ liệu.
- Các phương pháp nhận diện trường dữ liệu (Delimited vs Fixed Position).
- Cấu trúc và cú pháp cơ bản của quá trình nạp (Loading Methods).

## Tổng quan về SQL*Loader
SQL*Loader là tiện ích dòng lệnh kinh điển của Oracle, được thiết kế để nạp hàng loạt dữ liệu (Bulk Load) từ các file văn bản (ví dụ `.csv`, `.txt`, `.dat`) từ môi trường bên ngoài vào bên trong các bảng cơ sở dữ liệu Oracle.

**Thành phần chính khi chạy SQL*Loader:**
1. **Data Files (Input):** Các file chứa dữ liệu thô. (Có thể gộp chung vào Control File).
2. **Control File (`.ctl`):** File cấu hình văn bản, cho SQL*Loader biết định dạng dữ liệu là gì, nằm ở đâu, và sẽ đổ vào bảng nào.
3. **Log File (Output):** Chứa kết quả chi tiết của quá trình nạp (số dòng thành công, số dòng lỗi, nguyên nhân lỗi).
4. **Bad File (Output):** Chứa các dòng dữ liệu bị LỖI không nạp được (Ví dụ: sai kiểu dữ liệu, sai format, vi phạm ràng buộc khóa chính).
5. **Discard File (Output):** Chứa các dòng dữ liệu KHÔNG thỏa mãn điều kiện lọc chủ động (Ví dụ: bạn chỉ muốn nạp nhân viên phòng số 10, các phòng khác sẽ bị vứt vào Discard file).

## Các phương pháp đổ dữ liệu (Loading Methods)
Trong Control File, bạn phải khai báo cách SQL*Loader đối xử với bảng đích hiện tại:
- **`INSERT`:** (Mặc định). Bảng phải đang rỗng 100%. Nếu bảng có dữ liệu, nó sẽ báo lỗi.
- **`APPEND`:** Thêm dữ liệu mới nối tiếp vào bảng đang có sẵn dữ liệu mà không xóa gì cả.
- **`REPLACE`:** XÓA TOÀN BỘ dữ liệu cũ trong bảng bằng lệnh `DELETE` rồi mới nạp dữ liệu mới vào.
- **`TRUNCATE`:** XÓA TOÀN BỘ dữ liệu cũ bằng lệnh `TRUNCATE` (Nhanh hơn `REPLACE`) rồi mới nạp dữ liệu mới vào.

## Hai phương pháp phân tích trường (Field Specifications)

**1. Trường phân tách bằng ký tự (Delimited Fields)**
Dùng cho các file dạng CSV. Các trường dữ liệu bị ngăn cách bởi dấu phẩy, dấu chấm phẩy, hoặc dấu Tab.
```sql
-- Ví dụ trong Control File
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
( 
  ORDER_ID, 
  ORDER_DATE DATE(21) 'DD-MM-YYYY HH24:MI:SS', 
  CUSTOMER_ID
)
```

**2. Trường cố định theo vị trí (Fixed Position)**
Dùng cho các file dạng Text cứng, không có dấu phân cách, mà mỗi trường dữ liệu chiếm đúng X ký tự cố định.
```sql
-- Ví dụ trong Control File
( 
  CUSTOMER_ID POSITION(01:11) INTEGER EXTERNAL,
  CUST_NAME   POSITION(13:42) CHAR,
  EMAIL       POSITION(44:73) CHAR
)
```

## Chuyển đổi dữ liệu khi nạp
SQL*Loader cho phép bạn dùng các hàm xử lý chuỗi và số cơ bản của Oracle ngay trong Control File để "gọt" dữ liệu trước khi đẩy vào DB.
Ví dụ: 
- `UPPER(:CUST_NAME)` -> Đổi tên thành in hoa.
- `TO_NUMBER(:TOTAL_SALES,'$999,999,999')` -> Cắt bỏ ký hiệu tiền tệ để nạp thành dạng số.
- Đặt hàm bốc số tự động: `LOADSEQ SEQUENCE(MAX,1)` -> Lấy giá trị cao nhất đang có trong cột đó, cộng dồn thêm 1 cho dòng tiếp theo (Autoincrement).

---
## Câu hỏi ôn tập

**Câu 1: Tôi có một file log dữ liệu thô khổng lồ, một vài dòng bị hỏng định dạng. Khi chạy SQL*Loader, quá trình có bị sụp đổ toàn bộ không?**
- **Trả lời:** Không. SQL*Loader sẽ tiếp tục nạp các dòng chuẩn. Những dòng hỏng định dạng hoặc lỗi kiểu dữ liệu sẽ bị "tách" ra và ghi vào một file riêng gọi là **Bad File**. Nhờ đó bạn có thể mở Bad File ra sửa rồi chạy lại chỉ những dòng đó.

**Câu 2: "Discard File" khác với "Bad File" ở chỗ nào?**
- **Trả lời:** Bad file chứa các dòng bị hệ thống **từ chối do LỖI** (vi phạm khóa, sai kiểu dữ liệu). Discard file chứa các dòng hoàn toàn hợp lệ nhưng bị hệ thống **chủ động loại bỏ** (Bỏ qua vì chúng không khớp với mệnh đề `WHEN` điều kiện mà bạn cố tình lọc trong Control File).

**Câu 3: Tôi muốn xóa sạch dữ liệu cũ trong bảng để nạp file báo cáo mới tinh, tôi nên dùng phương pháp nạp nào?**
- **Trả lời:** Nên dùng `TRUNCATE`. Nó xóa sạch dữ liệu cũ nhanh nhất mà không sinh ra Undo logs như `REPLACE` (dùng DELETE).

**Câu 4: `OPTIONALLY ENCLOSED BY '"'` nghĩa là gì trong Control file?**
- **Trả lời:** Nghĩa là nếu giá trị của trường đó có chứa dấu phân cách (như dấu phẩy bên trong 1 câu văn), hệ thống khai báo rằng toàn bộ chuỗi đó sẽ được bao bọc bên trong dấu ngoặc kép `" "` để SQL*Loader biết đường bỏ qua, không bị hiểu lầm thành dấu ngăn cách cột.

**Câu 5: Trong Fixed Position method, từ khóa `INTEGER EXTERNAL` biểu thị điều gì?**
- **Trả lời:** Chữ "External" báo hiệu rằng dù dữ liệu đầu vào là các ký tự văn bản (String characters) chứa chữ số, SQL*Loader phải ngầm hiểu và tự động biến đổi chuỗi văn bản đó thành dạng số `NUMBER` khi đưa vào cơ sở dữ liệu.


---

!!! info "Nguồn gốc"
    `Oracle-Database-Administration-from-Zero-to-Hero/VN/102-using-sql-loader.md`
