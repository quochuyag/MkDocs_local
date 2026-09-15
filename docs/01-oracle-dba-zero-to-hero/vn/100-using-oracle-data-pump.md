---
title: 'Bài 100: Sử dụng Oracle Data Pump'
course: 01-oracle-dba-zero-to-hero
source: Oracle-Database-Administration-from-Zero-to-Hero/VN/100-using-oracle-data-pump.md
---

# Bài 100: Sử dụng Oracle Data Pump

## Mục tiêu
Trong bài học này, bạn sẽ học cách thực hiện các công việc sau:
- Khái niệm cơ bản và lợi ích của Data Pump (Export/Import).
- Các cấp độ trích xuất dữ liệu (Full, Schema, Table, Tablespace).
- Sử dụng tiện ích `expdp` và `impdp`.
- Di chuyển dữ liệu trực tiếp qua mạng bằng Network Links.

## Tổng quan về Oracle Data Pump
Data Pump là công cụ vận chuyển dữ liệu tốc độ cao (high-speed data movement) của Oracle. 
Nó được dùng để:
- Chuyển dữ liệu giữa các môi trường (ví dụ: Production sang Test).
- Nâng cấp phiên bản phần mềm.
- Backup dữ liệu logic.

**Kiến trúc:** Khác với công cụ `exp/imp` đời cũ (Original Export/Import), Data Pump hoạt động hoàn toàn trên Server-side. File trích xuất (dump file) bắt buộc phải nằm trên máy chủ Oracle thông qua một `Directory Object`.

## Chuẩn bị: Directory Object
Vì tiến trình chạy trên server, nên nó không hiểu đường dẫn `/home/oracle/` thông thường. Bạn phải tạo một đối tượng thư mục (Directory Object) bên trong Database để trỏ tới thư mục vật lý.

```sql
CREATE OR REPLACE DIRECTORY DUMPDIR AS '/media/sf_staging/dump';
-- Cấp quyền cho user sẽ thực hiện export
GRANT READ, WRITE ON DIRECTORY DUMPDIR TO SOE;
```

## Data Pump Export (`expdp`)
Tiện ích `expdp` dùng để xuất dữ liệu. 
**Ví dụ 1: Xuất toàn bộ 1 Schema (chế độ mặc định)**
```bash
expdp SOE/password@pdb1 DIRECTORY=DUMPDIR DUMPFILE=SOE.dmp LOGFILE=SOE.log
```
**Ví dụ 2: Lấy dự toán kích thước (Chưa xuất thật)**
```bash
expdp SOE/password@pdb1 DIRECTORY=DUMPDIR ESTIMATE_ONLY=Y
```

## Data Pump Import (`impdp`)
Tiện ích `impdp` dùng để nhập (nhồi) dữ liệu từ file dump vào database đích.
```bash
impdp SOE/password@orawindb DIRECTORY=DUMPDIR DUMPFILE=SOE.dmp LOGFILE=SOEimport.log
```
**Chuyển đổi (Remapping):**
Trong lúc import, cấu trúc ở máy chủ mới có thể khác. Bạn có thể tự động ánh xạ lại:
- Đổi tên schema (user): `REMAP_SCHEMA=old_user:new_user`
- Đổi Tablespace: `REMAP_TABLESPACE=old_tbs:new_tbs`
- Đổi đường dẫn file vật lý (nếu import cả cấu trúc datafile): `REMAP_DATAFILE='/u01/':'/u02/'`

## Di chuyển dữ liệu qua mạng (Network Link)
Nếu bạn không muốn sinh ra file dump trung gian (do không có dung lượng đĩa trống), Data Pump cho phép copy dữ liệu thẳng từ máy A sang máy B qua bộ nhớ mạng bằng Database Link.

1. Tại máy đích, tạo DB Link trỏ về máy nguồn:
```sql
CREATE DATABASE LINK link_to_srv1 CONNECT TO SOE IDENTIFIED BY password USING 'soesrv1';
```
2. Dùng lệnh `impdp` với tham số `NETWORK_LINK` thay vì `DUMPFILE`:
```bash
impdp SOE/password NETWORK_LINK=link_to_srv1 DIRECTORY=DUMPDIR LOGFILE=net_imp.log
```
*(Dù không có dumpfile, tham số `DIRECTORY` vẫn bắt buộc phải có để hệ thống biết chỗ lưu log file).*

---
## Câu hỏi ôn tập

**Câu 1: Tại sao chạy `expdp` lại báo lỗi không tìm thấy đường dẫn `/tmp` dù tôi chạy lệnh này ngay trên terminal Linux?**
- **Trả lời:** Vì Data Pump là tiến trình Server-side. Nó không dùng đường dẫn vật lý (như `/tmp`) trong dòng lệnh. Bạn bắt buộc phải khai báo tên một "Directory Object" (đã được định nghĩa sẵn trong Database trỏ tới `/tmp`) cho tham số `DIRECTORY`.

**Câu 2: Original Export (`exp`) và Data Pump Export (`expdp`) khác nhau cơ bản ở đâu?**
- **Trả lời:** `exp` là tiện ích Client-side, nó lôi dữ liệu về máy cá nhân của người chạy lệnh, tốc độ chậm. `expdp` là Server-side, chạy đa luồng trên server, tốc độ rất cao và sinh file dump trực tiếp trên ổ cứng của server.

**Câu 3: Mục đích của cờ `ESTIMATE_ONLY=Y` là gì?**
- **Trả lời:** Để tính toán và in ra màn hình dự toán về kích thước (dung lượng byte) của file dump sắp được tạo, giúp DBA xem máy chủ có đủ ổ cứng để chứa hay không trước khi chạy xuất dữ liệu thật.

**Câu 4: Chức năng `REMAP_TABLESPACE` giúp ích gì khi import?**
- **Trả lời:** Chức năng này giúp di chuyển linh hoạt dữ liệu sang tablespace có tên khác. Ví dụ máy nguồn dữ liệu nằm ở `TS_SALES`, nhưng máy đích không có tablespace đó, ta sẽ ép nó nhồi dữ liệu sang `TS_USERS` tự động.

**Câu 5: Dùng `NETWORK_LINK` có ưu điểm gì so với cách thông thường?**
- **Trả lời:** Ưu điểm lớn nhất là BỎ QUA bước sinh file trung gian (`.dmp`). Dữ liệu được trích xuất và đẩy thẳng vào database đích thông qua đường truyền mạng, giúp tiết kiệm dung lượng đĩa khổng lồ cho các database cỡ lớn.


---

!!! info "Nguồn gốc"
    `Oracle-Database-Administration-from-Zero-to-Hero/VN/100-using-oracle-data-pump.md`
