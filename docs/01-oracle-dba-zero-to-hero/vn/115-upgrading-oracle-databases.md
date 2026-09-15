---
title: 'Bài 115: Nâng cấp Oracle Databases'
course: 01-oracle-dba-zero-to-hero
source: Oracle-Database-Administration-from-Zero-to-Hero/VN/115-upgrading-oracle-databases.md
---

# Bài 115: Nâng cấp Oracle Databases

## Mục tiêu
Trong bài học này, bạn sẽ học cách thực hiện các công việc sau:
- Khái niệm về Nâng cấp cơ sở dữ liệu (Upgrading).
- Hiểu các phương pháp để thực hiện việc nâng cấp.
- Giới thiệu công cụ AutoUpgrade của Oracle.

## Tổng quan về Nâng cấp (Upgrade)
Khác với Cập nhật bản vá (Patching - RU/RUR) là thay đổi nhỏ bên trong cùng 1 phiên bản. Nâng cấp (Upgrading) là việc chuyển toàn bộ dữ liệu và Data Dictionary sang một thế hệ phần mềm hoàn toàn mới. Ví dụ: nâng cấp từ phiên bản **11g / 12c / 18c** lên phiên bản lõi **19c / 21c**.

Khi nâng cấp, cấu trúc của các bảng hệ thống, các đối tượng ẩn của Oracle, múi giờ (Timezone) đều thay đổi lớn. Hỗ trợ cho các tính năng cũ (Deprecated) sẽ bị xóa bỏ.

## Các phương pháp nâng cấp

**1. Database Upgrade Assistant (DBUA)**
Đây là giao diện đồ họa (GUI) truyền thống được sử dụng từ các đời 11g, 12c. DBA bật giao diện lên và bấm Next, cấu hình thông qua các menu thân thiện. Tuy nhiên, ở phiên bản Oracle 19c trở đi, phương pháp GUI DBUA bị Oracle chê là chậm, kém ổn định và khuyến cáo người dùng không nên sử dụng nữa. Kể từ bản Oracle 21c, **DBUA đã bị loại bỏ hoàn toàn**.

**2. Công cụ Dòng lệnh Tự động hóa (AutoUpgrade Utility)**
Kể từ Oracle 19c, Oracle giới thiệu một tiện ích java bằng dòng lệnh cực kỳ mạnh mẽ mang tên **AutoUpgrade**. Khác với tên gọi có vẻ nhàm chán, AutoUpgrade là tiêu chuẩn mới bắt buộc của thế giới Oracle hiện đại.
- Nó có thể nâng cấp hàng chục, hàng trăm database cùng lúc (Parallel).
- Nó tự động làm toàn bộ mọi việc: Phân tích trước khi nâng, chạy script nâng cấp, backup Flashback, tự sửa lỗi tương thích múi giờ, chạy hậu xử lý.
- Cấu hình chỉ bằng 1 file text dạng key-value.

**3. Data Pump (Export / Import)**
Bạn dùng `expdp` rút toàn bộ dữ liệu ở máy chủ cũ, sau đó cài một phần mềm máy chủ phiên bản 21c mới toanh, rồi dùng `impdp` nhồi dữ liệu vào. Phù hợp cho những hệ thống siêu cũ không được hỗ trợ nâng cấp trực tiếp (như Oracle 10g), nhưng cần thời gian bảo trì (Downtime) cực kỳ lớn.

## Tiện ích AutoUpgrade
Bạn cần tải bản file `autoupgrade.jar` mới nhất từ My Oracle Support (MOS).

Cấu trúc file cấu hình (ví dụ `upgrade.cfg`) sẽ có dạng cơ bản như sau:
```properties
upg1.source_home=/u01/app/oracle/product/19.0.0/dbhome_1
upg1.target_home=/u01/app/oracle/product/21.0.0/dbhome_1
upg1.sid=ORCL
```

Quá trình AutoUpgrade có nhiều chế độ hoạt động (modes):
- **ANALYZE:** Chỉ quét cấu trúc DB cũ, xuất ra báo cáo HTML phân tích các điểm nghẽn, các lỗi tương thích có thể xảy ra khi nâng cấp (Pre-check).
- **FIXUPS:** Sửa các lỗi tương thích được tìm thấy ở vòng Analyze.
- **DEPLOY:** Làm nhiệm vụ Analyze, Fixups, Upgrade, tự tạo Flashback restore point, và dọn dẹp hậu kiểm (Post-upgrade). Trọn bộ!

---
## Câu hỏi ôn tập

**Câu 1: Patching và Upgrading khác nhau chỗ nào?**
- **Trả lời:** Patching (Cập nhật RU) chỉ là sửa lỗi nhỏ, bổ sung bản vá bảo mật mà không thay đổi cấu trúc phiên bản cốt lõi. (Ví dụ 19.3 lên 19.16). Upgrading là chuyển đổi sang một kiến trúc phần mềm mới hoàn toàn (Ví dụ 19c lên 21c), gây thay đổi lớn về cách tối ưu hóa và các tham số kỹ thuật.

**Câu 2: Tại sao Oracle lại loại bỏ DBUA (giao diện đồ họa) ở các phiên bản gần đây?**
- **Trả lời:** Vì DBUA không phù hợp cho các kịch bản đám mây (Cloud) hoặc môi trường lớn có hàng trăm database. Nó đòi hỏi DBA phải ngồi click bằng tay. AutoUpgrade ra đời cho phép làm mọi thứ thông qua script dòng lệnh, tự động hóa cao và chạy song song (multithreading) rất nhanh.

**Câu 3: Tính năng "ANALYZE" của AutoUpgrade mang lại lợi ích gì?**
- **Trả lời:** Tính năng này cho phép DBA chạy một bài kiểm tra "khám sức khỏe" tổng quát trên hệ thống cũ. Nó đọc cấu trúc dữ liệu và sinh ra một bản báo cáo bằng HTML đẹp mắt, liệt kê chi tiết các sự cố chắc chắn sẽ làm hỏng quá trình nâng cấp, để DBA chủ động sửa trước (như đầy đĩa, chưa tắt dịch vụ rác).

**Câu 4: Tôi có thể dùng AutoUpgrade để nâng cấp từ Oracle 9i lên Oracle 21c không?**
- **Trả lời:** Thường là không. Oracle chỉ hỗ trợ đường dẫn nâng cấp trực tiếp (Direct upgrade paths) qua vài thế hệ (ví dụ từ 12c, 18c, 19c lên 21c). Nếu phiên bản quá cũ, bạn phải nâng cấp trung gian qua nhiều bản (ví dụ 9i -> 11g -> 19c) HOẶC sử dụng Data Pump (Export/Import) để chuyển dữ liệu sang thẳng.

**Câu 5: Trong môi trường PDB/CDB, AutoUpgrade nâng cấp cái gì?**
- **Trả lời:** AutoUpgrade thông minh đủ để tự nhận dạng đó là CDB. Nó sẽ nâng cấp CDB Root trước, rải các thay đổi vào Seed, sau đó tiến hành nâng cấp song song đồng loạt tất cả các PDB đang gắn trên CDB đó. DBA không phải cấu hình cho từng PDB.


---

!!! info "Nguồn gốc"
    `Oracle-Database-Administration-from-Zero-to-Hero/VN/115-upgrading-oracle-databases.md`
