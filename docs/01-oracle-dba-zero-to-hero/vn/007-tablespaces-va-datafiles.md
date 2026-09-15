---
title: 'Bài 07: Tablespaces và Datafiles trong Oracle Database'
course: 01-oracle-dba-zero-to-hero
source: Oracle-Database-Administration-from-Zero-to-Hero/VN/07-tablespaces-va-datafiles.md
---

# Bài 07: Tablespaces và Datafiles trong Oracle Database

## 🎯 Mục tiêu học tập
Trong bài học này, bạn sẽ hiểu rõ về cách Oracle Database lưu trữ dữ liệu, từ cấu trúc logic (ảo) đến cấu trúc vật lý (thực tế trên ổ cứng). Cụ thể, chúng ta sẽ tìm hiểu về **Tablespaces** và **Datafiles**.

---

## 1. Tablespace và Datafile là gì?

Để dễ hình dung, hãy tưởng tượng Database của bạn giống như một **Ngôi nhà kho lớn**:
- **Tablespace (Cấu trúc Logic)**: Giống như các *căn phòng* trong nhà kho (Phòng chứa đồ điện tử, Phòng chứa quần áo...). Nó không tồn tại về mặt vật lý, mà chỉ là cách ta phân chia không gian để dễ quản lý.
- **Datafile (Cấu trúc Vật lý)**: Giống như các *ngăn tủ, kệ sắt* có thật, nằm bên trong các căn phòng đó. Đây là nơi thực sự chứa hàng hóa (dữ liệu).

### Mối quan hệ giữa Tablespace và Datafile
- **1 Tablespace → Nhiều Datafiles**: Một căn phòng (Tablespace) có thể kê rất nhiều kệ sắt (Datafiles) để tăng sức chứa.
- **1 Datafile → Chỉ thuộc 1 Tablespace**: Một kệ sắt (Datafile) đã kê ở phòng nào thì chỉ thuộc về phòng đó, không thể chia sẻ cho phòng khác.

![Kiến trúc Database Server](014-014-database-tablespaces-and-datafiles/images/introducing-database-tablespac-01.jpeg)

> 💡 **Thực tế DBA:** Trong công việc, khi người dùng phàn nàn "không thể thêm dữ liệu do hết chỗ", DBA sẽ đi kiểm tra xem phòng nào (Tablespace) bị đầy, sau đó mua thêm kệ sắt (Add Datafile) để mở rộng dung lượng.

---

## 2. Phân cấp lưu trữ: Logic → Physical

Oracle quản lý dữ liệu theo một cấu trúc phân cấp chặt chẽ đi từ lớn đến nhỏ.

**Database → Tablespace → Segment → Extent → Data Block → OS Block**

### A. Data Block (Khối dữ liệu)
Là đơn vị nhỏ nhất mà Oracle có thể đọc/ghi, thường có kích thước mặc định là **8KB**.
- Ví dụ: Thay vì đọc từng byte dữ liệu, Oracle luôn lấy nguyên một cục 8KB lên để xử lý. Điều này giúp tối ưu hiệu suất.
- *Data Block (Logic) được ánh xạ xuống OS Block (Vật lý) của hệ điều hành.*

### B. Extent (Phân vùng)
Là một tập hợp các **Data Blocks liên tiếp nhau**.
- **Quy tắc vàng:** Một Extent KHÔNG BAO GIỜ vắt ngang qua 2 Datafile. Nó phải nằm trọn vẹn bên trong 1 Datafile duy nhất.
- Khi một bảng cần thêm chỗ chứa, Oracle sẽ cấp phát cho nó nguyên một "Extent" mới chứ không cho từng "Block" lẻ tẻ.

### C. Segment (Đối tượng dữ liệu)
Segment chính là các đối tượng tiêu thụ không gian lưu trữ thực tế trong database. Một Segment bao gồm nhiều Extents cộng lại.
Các loại Segment phổ biến:
- **Table Segment:** Chứa dữ liệu của một bảng.
- **Index Segment:** Chứa dữ liệu của chỉ mục (để tìm kiếm nhanh).
- **Undo Segment:** Chứa dữ liệu cũ để phục hồi lại nếu cần (Undo/Rollback).
- **Temp Segment:** Chứa dữ liệu tạm thời khi cần sắp xếp (Sort) dữ liệu lớn.

*Segment nằm trọn trong một Tablespace.*

---

## 3. Các Tablespace đặc biệt (Bắt buộc)

Khi vừa cài đặt xong Oracle Database, sẽ có 2 Tablespaces mặc định được tạo ra. Đây là "bộ não" của hệ thống và **bắt buộc phải luôn ONLINE**.

### 1. SYSTEM Tablespace
- **Chức năng:** Nơi chứa **Data Dictionary** (Từ điển dữ liệu) – lưu toàn bộ metadata của hệ thống như danh sách users, danh sách các bảng, quyền hạn, v.v.
- Không có SYSTEM, Database không thể hoạt động.

### 2. SYSAUX Tablespace
- **Chức năng:** Đây là "phòng phụ trợ" của SYSTEM. Nó chứa các thành phần mở rộng của Oracle như: AWR (Công cụ thu thập dữ liệu hiệu suất), Optimizer Stats (Thống kê giúp chạy SQL nhanh), v.v.
- Giúp giảm tải cho không gian của SYSTEM Tablespace.

> ⚠️ **CẢNH BÁO TỪ DBA:**
> **KHÔNG BAO GIỜ** tạo bảng hay lưu trữ dữ liệu của User (người dùng/ứng dụng) vào bên trong SYSTEM hoặc SYSAUX tablespace! Việc này có thể làm đầy "não" của Database, gây sập toàn bộ hệ thống. Luôn tạo Tablespace riêng biệt cho ứng dụng.

---

## 4. Tổng kết

- **Tablespace** là cấu trúc ảo (logical) dùng để gom nhóm dữ liệu.
- **Datafile** là file vật lý (physical) thực sự chứa dữ liệu trên ổ cứng.
- Cấu trúc lưu trữ nhỏ dần: Database > Tablespace > Segment > Extent > Data Block.
- Hệ thống luôn có **SYSTEM** và **SYSAUX** đóng vai trò cực kỳ quan trọng, tuyệt đối không lưu dữ liệu ứng dụng vào đây.

### ❓ Câu hỏi ôn tập

**1. Nếu một ổ cứng bị hỏng làm mất một Datafile, thì Tablespace chứa Datafile đó có bị ảnh hưởng không?**
> **Trả lời:**
> **Có, bị ảnh hưởng nghiêm trọng.**
> - Vì Tablespace là tập hợp logic của các Datafiles. Nếu một Datafile bị hỏng hoặc mất, toàn bộ các bảng, index hoặc các segment có extent nằm trên Datafile đó sẽ không thể truy xuất được (báo lỗi I/O hoặc media failure).
> - Trừ trường hợp tablespace có cấu hình Read-Only hoặc offline, thông thường trạng thái của cả Tablespace sẽ bị suy giảm (corrupted/inaccessible), đòi hỏi DBA phải restore và recover lại Datafile đó từ bản sao lưu RMAN.

**2. Tại sao Oracle lại cấp phát dung lượng theo từng Extent (nhiều blocks) thay vì từng Data Block lẻ?**
> **Trả lời:**
> - **Giảm thiểu phân mảnh và nghẽn Data Dictionary:** Nếu mỗi dòng dữ liệu chèn vào lại cấp phát từng block lẻ (8KB), Oracle sẽ phải liên tục cập nhật metadata trong từ điển dữ liệu (Space Allocation Table), gây nghẽn contention nghiêm trọng.
> - **Tăng tốc độ đọc tuần tự (Multi-block Read):** Cấp phát theo Extent (gồm các block liên tiếp nhau về mặt vật lý) cho phép Oracle thực hiện đọc nhiều block cùng lúc (`db_file_multiblock_read_count`) trong các tác vụ quét toàn bộ bảng (Full Table Scan), giúp tăng tốc độ xử lý I/O vượt trội.

**3. Điều gì xảy ra nếu bạn cố tình nhét bảng dữ liệu của ứng dụng vào SYSTEM tablespace?**
> **Trả lời:**
> - **Gây nghẽn hệ thống cốt lõi:** SYSTEM tablespace chứa Data Dictionary (từ điển dữ liệu) của toàn bộ database. Nếu bảng ứng dụng chèn/sửa/xóa liên tục trong SYSTEM, nó sẽ cạnh tranh I/O trực tiếp với các tác vụ nội bộ của Oracle, làm chậm toàn bộ database.
> - **Nguy cơ sập database khi hết chỗ:** Nếu bảng người dùng làm đầy (out-of-space) SYSTEM tablespace, database sẽ lập tức bị treo hoặc crash và không thể hoạt động được.
> - **Khó khăn trong quản trị và sao lưu:** Không thể offline, không thể di chuyển hoặc tách riêng dữ liệu nghiệp vụ ra khỏi dữ liệu hệ thống.


---

!!! info "Nguồn gốc"
    `Oracle-Database-Administration-from-Zero-to-Hero/VN/07-tablespaces-va-datafiles.md`
