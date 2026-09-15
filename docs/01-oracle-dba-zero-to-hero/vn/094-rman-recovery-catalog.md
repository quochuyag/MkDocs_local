---
title: 'Bài 94: Sử dụng RMAN Recovery Catalog Database'
course: 01-oracle-dba-zero-to-hero
source: Oracle-Database-Administration-from-Zero-to-Hero/VN/94-rman-recovery-catalog.md
---

# Bài 94: Sử dụng RMAN Recovery Catalog Database

## Mục tiêu
Trong bài học này, bạn sẽ học cách thực hiện các công việc sau:
- So sánh giữa việc lưu trữ thông tin RMAN tại Control file và Recovery Catalog.
- Tạo và quản trị hệ thống Recovery Catalog.
- Đồng bộ hóa thủ công (Resynchronize) dữ liệu Catalog.
- Biên mục (Cataloging) các file lưu trữ bên ngoài vào RMAN repository.
- Tạo và quản lý các kịch bản RMAN lưu sẵn (Stored Scripts).

## Control File vs Recovery Catalog Database
Theo mặc định, RMAN lưu toàn bộ lịch sử sao lưu vào bên trong **Control file** của database bị sao lưu. 
Việc sử dụng **Recovery Catalog** (Một database tập trung chuyên chứa dữ liệu backup) mang lại những lợi ích vượt trội so với Control file:

| Tiêu chí | Control File | Recovery Catalog Database |
|----------|--------------|---------------------------|
| **Lịch sử lưu trữ** | Giới hạn tối đa khoảng 1 năm (bị xoay vòng ghi đè) | Lưu trữ lâu dài vĩnh viễn |
| **Phạm vi** | Chỉ chứa dữ liệu của 1 database cục bộ | Có thể quản lý tập trung hàng trăm Target Databases |
| **Kịch bản (Scripts)**| KHÔNG cho phép lưu trữ Scripts | CHOP PHÉP lưu trữ Scripts (Stored Scripts) để dùng chung |
| **Độ phức tạp** | Rất đơn giản, không cần thiết lập | Phức tạp, phải duy trì thêm một Database riêng |
| **Cấu trúc lịch sử** | Không lưu lại cấu trúc vật lý cũ | Có thể truy xuất lịch sử thay đổi cấu trúc vật lý của database |
| **Khuyến nghị** | Dành cho các hệ thống nhỏ, đơn giản | Dành cho hệ thống Doanh nghiệp lớn, quản lý phức tạp |

## 3 Bước tạo Recovery Catalog Database
Bạn cần một Database thứ 2 độc lập (gọi là `catdb`) để làm Catalog.
**Bước 1: Tạo Tablespace chứa Catalog:**
```sql
CREATE TABLESPACE rcat_tbs DATAFILE 'rcat.dbf' SIZE 15M;
```
**Bước 2: Tạo User (Chủ sở hữu) Catalog và cấp quyền:**
```sql
CREATE USER rcowner IDENTIFIED BY password
DEFAULT TABLESPACE rcat_tbs QUOTA UNLIMITED ON rcat_tbs;

GRANT RECOVERY_CATALOG_OWNER TO rcowner;
```
**Bước 3: Khởi tạo Catalog (Trong RMAN):**
```rman
rman
RMAN> CONNECT CATALOG rcowner/password@catdb
RMAN> CREATE CATALOG;
```

## Quản lý Target Database
Sau khi tạo Catalog, bạn cần "Đăng ký" (Register) database của mình vào hệ thống đó:
```rman
rman TARGET / CATALOG rcowner/password@catdb
RMAN> REGISTER DATABASE;
```
Để hủy đăng ký (Xóa dữ liệu database đó khỏi Catalog):
```rman
RMAN> UNREGISTER DATABASE;
```

## Đồng bộ hóa Recovery Catalog (Resynchronization)
RMAN tự động đồng bộ (đẩy dữ liệu từ Control File lên Catalog) mỗi khi bạn chạy backup. Tuy nhiên, bạn nên đồng bộ thủ công (`RESYNC CATALOG`) trong các trường hợp:
- Lâu ngày bạn không thực hiện backup.
- Vừa có sự thay đổi cấu trúc vật lý (Thêm/xóa datafiles).
- Server Catalog vừa bị sập mạng lúc đang chạy backup.

```rman
RMAN> RESYNC CATALOG;
```

## Cataloging (Biên mục file thủ công)
Nếu bạn lỡ tay chép các file backup từ server khác về bằng lệnh copy của Linux (OS utility), RMAN sẽ không biết sự tồn tại của chúng. Bạn phải "Cataloging" để cập nhật chúng vào RMAN repository:
```rman
-- Cập nhật toàn bộ file backup trong 1 thư mục
CATALOG START WITH '/fs1/datafiles/';

-- Cập nhật dữ liệu từ thư mục FRA
CATALOG RECOVERY AREA;

-- Cập nhật một file lẻ
CATALOG DATAFILECOPY '/tmp/users01.dbf';
```

## Stored Scripts (Kịch bản lưu sẵn)
Recovery Catalog cho phép bạn viết và lưu thẳng script RMAN vào database (như Stored Procedure) thay vì viết ra file text bên ngoài. Có 2 loại:
- **Local:** Chỉ chạy được trên Target database gắn với nó.
- **Global:** Có thể chạy áp dụng chung cho toàn bộ các database khác đang đăng ký trong Catalog.

```rman
-- Tạo Script
CREATE SCRIPT my_backup_script {
  BACKUP DATABASE;
}

-- Chạy Script
RUN { EXECUTE SCRIPT my_backup_script; }
```

---
## Câu hỏi ôn tập

**Câu 1: Recovery Catalog mang lại lợi ích gì so với Control file khi xét về không gian quản lý?**
- **Trả lời:** Recovery Catalog có thể quản lý lịch sử sao lưu của hàng chục hoặc hàng trăm (multiple) Target Databases từ một máy chủ tập trung duy nhất, thay vì mỗi Database phải tự quản lý thông tin rời rạc trong Control file của mình.

**Câu 2: Quyền hệ thống nào là bắt buộc phải cấp cho Database User để user đó có thể quản trị Recovery Catalog?**
- **Trả lời:** Quyền `RECOVERY_CATALOG_OWNER` là quyền đặc biệt (role) bắt buộc phải cấp cho user.

**Câu 3: Nếu bạn dùng lệnh `cp` của Linux để sao chép một file backup RMAN từ máy A sang máy B, RMAN trên máy B có dùng được file đó ngay lập tức không?**
- **Trả lời:** Không. RMAN trên máy B chưa lưu siêu dữ liệu về file đó. Bạn bắt buộc phải chạy lệnh `CATALOG DATAFILECOPY '<đường_dẫn>'` hoặc `CATALOG START WITH '<thư_mục>'` để đăng ký (biên mục) file đó vào kho lưu trữ của máy B.

**Câu 4: Quá trình "Resynchronize" (Đồng bộ) thực hiện việc đẩy dữ liệu theo chiều nào?**
- **Trả lời:** Nó cập nhật bằng cách đọc thông tin từ Control File (của Target Database) và đẩy (ghi chép) dữ liệu lên Recovery Catalog (Cơ sở dữ liệu tập trung).

**Câu 5: Global Script khác với Local Script trong Recovery Catalog ở điểm nào?**
- **Trả lời:** Global Script có thể được gọi và thực thi bởi BẤT KỲ Target Database nào đã đăng ký trong Recovery Catalog đó. Trong khi Local Script bị gắn chặt và chỉ có thể được gọi bởi một Target Database cụ thể đã tạo ra nó.


---

!!! info "Nguồn gốc"
    `Oracle-Database-Administration-from-Zero-to-Hero/VN/94-rman-recovery-catalog.md`
