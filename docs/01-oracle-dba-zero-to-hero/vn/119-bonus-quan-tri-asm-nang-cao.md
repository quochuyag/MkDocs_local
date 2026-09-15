---
title: 'Bài 119: Mở rộng - Quản trị ASM nâng cao với Tiện ích lệnh'
course: 01-oracle-dba-zero-to-hero
source: Oracle-Database-Administration-from-Zero-to-Hero/VN/119-bonus-quan-tri-asm-nang-cao.md
---

# Bài 119: Mở rộng - Quản trị ASM nâng cao với Tiện ích lệnh

## Mục tiêu
Bài học bổ trợ này sẽ cung cấp cho bạn kiến thức thực chiến để quản lý không gian đĩa ASM thông qua các Data Dictionary Views và công cụ dòng lệnh `asmcmd`.
- Thao tác gỡ và thêm đĩa vật lý (ALTER DISKGROUP).
- Giám sát thông số đĩa thông qua các view `V$ASM`.
- Các câu lệnh `asmcmd` quan trọng nhất.

## 1. Giám sát không gian ASM bằng View
Vì ASM Instance chạy độc lập, bạn phải đăng nhập vào nó (Ví dụ: `sqlplus / as sysasm`) để truy vấn các view quản trị:
- **`V$ASM_DISKGROUP`:** Chứa thông tin tổng quan về các nhóm đĩa (Tên, trạng thái, tổng dung lượng, dung lượng trống).
- **`V$ASM_DISK`:** Liệt kê toàn bộ các đĩa vật lý cấu thành nên nhóm đĩa, đường dẫn hệ điều hành (ví dụ `/dev/oracleasm/disks/DATA1`) và tình trạng sức khỏe của từng đĩa.
- **`V$ASM_OPERATION`:** Vô cùng quan trọng để theo dõi tiến độ (%) của các tiến trình Rebalance đang chạy ngầm khi bạn thao tác thêm/xóa ổ cứng.

## 2. Thao tác cấu hình ổ cứng
Trong môi trường thực tế, đĩa cứng bị hỏng hoặc đầy là chuyện thường ngày.

**Thêm đĩa mới vào cụm:**
```sql
ALTER DISKGROUP DATA ADD DISK '/dev/sde1' NAME DATA_003;
```
**Gỡ một đĩa hỏng ra khỏi cụm (ASM sẽ tự động rút dữ liệu ra đĩa khác trước khi ngắt đĩa):**
```sql
ALTER DISKGROUP DATA DROP DISK DATA_001;
```
**Chỉnh sửa dung lượng đĩa (Khi LUN trên SAN được mở rộng kích thước):**
```sql
ALTER DISKGROUP DATA RESIZE DISK DATA_002 SIZE 500G;
```

## 3. Quản trị bằng asmcmd
`asmcmd` là công cụ giả lập môi trường terminal. Bạn có thể gọi `asmcmd` từ Linux (bằng user `grid`).

**Nhóm lệnh xem không gian (Space Management):**
- `lsdg`: Hiển thị bảng tổng quát các Diskgroup và dung lượng trống. (Gọn gàng và dễ nhìn hơn query V$ASM_DISKGROUP).
- `lsdsk`: Liệt kê tất cả các đĩa vật lý đang dùng.

**Nhóm lệnh điều hướng (Navigation):**
- `ls`, `cd`, `pwd`: Duyệt các thư mục OMF của Database bên trong lõi ASM y hệt như đang dùng lệnh Linux bình thường.
- `rm`: Xóa các file rác (Ví dụ file archive log cũ hoặc file dump không dùng nữa). Cần đặc biệt cẩn thận!

**Nhóm lệnh Giám sát hiệu năng:**
- `iostat`: Giám sát tốc độ đọc ghi IOPS và lượng Byte đang luân chuyển trên từng đĩa theo thời gian thực (Giống lệnh `iostat` của Linux).

**Nhóm lệnh Metadata Backup:**
Cấu trúc cây thư mục và thông số của Disk Group rất quan trọng. Mất metadata có thể làm mất toàn bộ cấu trúc đĩa.
- `md_backup`: Xuất cấu hình metadata của toàn bộ ASM ra một file text an toàn.
- `md_restore`: Tạo lại cấu trúc Disk Group bằng cách đọc file metadata đó (sử dụng khi khôi phục sau thảm họa sập toàn bộ đĩa).

---
## Câu hỏi ôn tập

**Câu 1: Lệnh `ALTER DISKGROUP DATA DROP DISK DATA_001;` có làm gián đoạn các kết nối Database không?**
- **Trả lời:** Hoàn toàn không. Lệnh này chỉ đánh dấu đĩa `DATA_001` không được nhận dữ liệu mới, và kích hoạt tiến trình Rebalance chạy ngầm. Tiến trình này sẽ âm thầm sao chép các khối dữ liệu từ đĩa này sang các đĩa khác đang có trong cụm. Ứng dụng Database vẫn truy xuất bình thường.

**Câu 2: Dòng thông báo trạng thái `HANGING` trong cột State của `V$ASM_DISK` nghĩa là gì?**
- **Trả lời:** Điều này báo hiệu đĩa cứng đó đang bị rút cáp, mất nguồn, hoặc chết bộ điều khiển. ASM không thể giao tiếp I/O với đĩa cứng đó nữa, và nếu bạn cấu hình Normal/High Redundancy, nó sẽ tự động chuyển hướng I/O sang các ổ đĩa Mirror để duy trì hoạt động.

**Câu 3: Sự khác nhau giữa lệnh `ls` của Linux và `ls` của `asmcmd` là gì?**
- **Trả lời:** `ls` của Linux dùng thư viện nhân (Kernel OS) để đọc cấu trúc file system NTFS/Ext4. Lệnh `ls` của `asmcmd` thực chất là các gói lệnh gọi SQL ẩn chạy vào ASM Instance, dịch metadata để hiển thị cấu trúc ảo hóa OMF lên màn hình cho người dùng dễ hiểu.

**Câu 4: File sinh ra từ lệnh `md_backup` có chứa dữ liệu Database không?**
- **Trả lời:** KHÔNG. Tiện ích `md_backup` (Metadata Backup) chỉ lưu trữ "bản vẽ thiết kế": gồm tên các Diskgroup, số lượng đĩa, kích thước AU, và thông tin Failure Group. Nó không lưu dù chỉ một byte dữ liệu của Database (File data, bảng, hàng). Bạn dùng RMAN để sao lưu dữ liệu.

**Câu 5: User `oracle` có thể chạy `asmcmd` không?**
- **Trả lời:** Có thể (nếu được cấp quyền OS group `asmadmin`), nhưng thực tế không ai làm vậy. Tài khoản `oracle` chỉ nên quan tâm đến database. Việc chọc vào `asmcmd` để xóa sửa đĩa là trách nhiệm tối thượng của hạ tầng, dành riêng cho tài khoản OS `grid`.


---

!!! info "Nguồn gốc"
    `Oracle-Database-Administration-from-Zero-to-Hero/VN/119-bonus-quan-tri-asm-nang-cao.md`
