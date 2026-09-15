---
title: 'Bài 98: Tính năng Flashback Database'
course: 01-oracle-dba-zero-to-hero
source: Oracle-Database-Administration-from-Zero-to-Hero/VN/98-flashback-database.md
---

# Bài 98: Tính năng Flashback Database

## Mục tiêu
Trong bài học này, bạn sẽ học cách thực hiện các công việc sau:
- Mô tả nguyên lý hoạt động và cách cấu hình Flashback Database.
- Thực hiện các thao tác đảo ngược dữ liệu với Flashback Database.
- Phân biệt, tạo và quản lý các loại Restore Points (Điểm khôi phục).

## Tổng quan về Flashback Database
Flashback Database hoạt động giống hệt như một nút "Rewind" (Tua lại) cho toàn bộ cơ sở dữ liệu.
Nó thường được sử dụng để:
- Sửa lỗi do thao tác logic sai lầm nghiêm trọng của người dùng (ví dụ: vô tình DROP một loạt user/bảng).
- Đảo ngược hệ thống về trạng thái cũ sau khi nâng cấp phần mềm bị lỗi.
- Đảo ngược dữ liệu trong các môi trường Kiểm thử (Testing) để test lặp đi lặp lại một kịch bản.

**Kiến trúc:**
Khi tính năng này được bật, Oracle khởi động một tiến trình nền là `RVWR` (Recovery Writer). Tiến trình này sẽ liên tục chụp lại "ảnh trước khi sửa" (Before Images) của các block dữ liệu và ghi vào một bộ nhớ đệm `Flashback buffer`, sau đó xả xuống các file `Flashback logs` nằm trong vùng Fast Recovery Area (FRA).

## Cấu hình Flashback Database
Tính năng này yêu cầu Database phải đang ở chế độ **ARCHIVELOG** và đã cấu hình vùng FRA.

**1. Đặt giới hạn lưu trữ thời gian (Retention Target - tính bằng phút):**
```sql
-- Ví dụ: Giữ lại block ảnh cũ trong 2880 phút (48 tiếng)
ALTER SYSTEM SET DB_FLASHBACK_RETENTION_TARGET=2880 SCOPE=BOTH;
```
**2. Bật tính năng Flashback (Database phải ở trạng thái MOUNT hoặc OPEN tùy bản Oracle):**
```sql
ALTER DATABASE FLASHBACK ON;
```
**3. Kiểm tra trạng thái:**
```sql
SELECT FLASHBACK_ON FROM V$DATABASE;
```

## Thực thi lệnh Flashback (Tua ngược) Toàn bộ Database
Bạn phải để database ở chế độ `MOUNT` trước khi thực thi.

```rman
-- Tua về một thời điểm cụ thể (Timestamp)
RMAN> FLASHBACK DATABASE TO TIME "TO_DATE('2022-06-20 15:00:00','YYYY-MM-DD HH24:MI:SS')";

-- Tua lùi lại chính xác 30 phút trước
RMAN> FLASHBACK DATABASE TO BEFORE TIME (SYSTIMESTAMP - INTERVAL '30' MINUTE);

-- Tua về một số SCN cụ thể
RMAN> FLASHBACK DATABASE TO SCN 23565;

-- Tua về một Điểm khôi phục (Restore Point)
RMAN> FLASHBACK DATABASE TO RESTORE POINT 'BEFORE_UPDATE';
```
Sau khi chạy xong, hãy mở database ở chế độ **READ ONLY** để kiểm tra xem dữ liệu tua lại đã đúng ý bạn chưa. Nếu đúng, bạn mở lại quyền ghi bằng lệnh `ALTER DATABASE OPEN RESETLOGS;`.

## Flashback một PDB (Pluggable Database)
Trong kiến trúc Multitenant, việc tua lại một PDB KHÔNG ảnh hưởng đến các PDB khác.
1. Kết nối vào Root bằng tài khoản `SYSDBA` hoặc `SYSBACKUP`.
2. Đóng PDB đó lại (`ALTER PLUGGABLE DATABASE my_pdb CLOSE`).
3. Chạy lệnh:
```rman
FLASHBACK PLUGGABLE DATABASE my_pdb TO SCN 24368;
-- Hoặc
FLASHBACK PLUGGABLE DATABASE my_pdb TO RESTORE POINT guar_rp;
```
4. Mở lại PDB: `ALTER PLUGGABLE DATABASE my_pdb OPEN RESETLOGS;`.

## Lưu ý (Considerations)
Bạn KHÔNG THỂ dùng Flashback Database để thay thế cho khôi phục hỏng hóc vật lý (Media Recovery) trong các trường hợp sau:
- Mất/hỏng Control file và phải khởi tạo lại.
- Bị xóa mất (Drop) một Tablespace hoặc Datafile.
- Datafile bị co lại (Shrink).
Tất cả các trường hợp bị lỗi cấu trúc vật lý này đều làm đứt đoạn chuỗi dữ liệu Flashback.

## Restore Points (Điểm khôi phục)
Restore Point là một cái tên thân thiện (Alias) đại diện cho một mốc SCN. Có 2 loại:
- **Normal Restore Point:** Chỉ là cái nhãn dán cho dễ nhớ. Nó có thể bị xóa mất nếu dung lượng log xoay vòng cạn kiệt.
  ```sql
  CREATE RESTORE POINT b4_batch;
  ```
- **Guaranteed Restore Point (GRP):** Ép buộc (Bảo hành) Oracle phải giữ lại toàn bộ Flashback logs tính từ mốc này cho tới hiện tại bằng mọi giá, không được xóa, để đảm bảo BẮT BUỘC có thể tua lại được.
  ```sql
  CREATE RESTORE POINT b4_upgrade GUARANTEE FLASHBACK DATABASE;
  ```

---
## Câu hỏi ôn tập

**Câu 1: Kiến trúc Flashback Database lưu trữ các "ảnh trước khi sửa" (Before Images) vào các file nào?**
- **Trả lời:** Nó lưu vào các file đặc thù gọi là **Flashback Logs**. Các file này được quản lý xoay vòng vòng (circular) và bắt buộc phải nằm bên trong vùng Fast Recovery Area (FRA).

**Câu 2: Tại sao người ta lại phải mở Database ở chế độ `READ ONLY` sau khi chạy lệnh Flashback?**
- **Trả lời:** Để làm thao tác xác minh. Việc mở Read-Only cho phép bạn truy vấn các bảng dữ liệu để xem mình đã "tua" về đúng thời điểm cần thiết chưa mà không sợ làm ghi đè hay sinh thêm log rác. Nếu chưa đúng, bạn lại tiếp tục Flashback về giờ khác.

**Câu 3: Tôi lỡ tay DROP một Datafile hệ thống, tôi có thể dùng Flashback Database để lấy lại được không?**
- **Trả lời:** Không thể. Flashback Database chỉ là công cụ để giải quyết các lỗi hỏng hóc Logic (sửa đổi dữ liệu, drop table). Nó không có khả năng sửa chữa và khôi phục các hỏng hóc về cấu trúc vật lý (Physical recovery) như mất Datafile hay hỏng Control file.

**Câu 4: Mức độ rủi ro lớn nhất của việc sử dụng Guaranteed Restore Point (GRP) là gì?**
- **Trả lời:** Vì GRP ép Oracle KHÔNG ĐƯỢC PHÉP xóa bất kỳ Flashback log nào kể từ mốc thời gian đó, nếu bạn quên xóa GRP sau khi dùng xong, các file log sẽ phình to liên tục cho đến khi làm đầy 100% dung lượng đĩa FRA, dẫn tới sập Database (Database hangs).

**Câu 5: Nếu tôi chỉ chạy Flashback trên riêng một PDB, tôi có bắt buộc phải Resetlogs toàn bộ hệ thống (CDB) không?**
- **Trả lời:** Không. Oracle hỗ trợ thực thi `ALTER PLUGGABLE DATABASE <tên> OPEN RESETLOGS;` để chỉ Resetlogs riêng dòng thời gian của PDB đó mà không hề động tới Root hay các PDB khác trong hệ thống.


---

!!! info "Nguồn gốc"
    `Oracle-Database-Administration-from-Zero-to-Hero/VN/98-flashback-database.md`
