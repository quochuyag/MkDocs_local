---
title: '📘 Module 15: Nhân bản Cơ sở dữ liệu bằng RMAN (Duplicating a Database)'
course: 09-dba-ai
source: dba_ai/oracle_rman/modules/module_15_guide.md
---

# 📘 Module 15: Nhân bản Cơ sở dữ liệu bằng RMAN (Duplicating a Database)

> **Module**: 15/17
> **Phạm vi**: Bài 61 đến 63 (Lý thuyết Part I, Part II & Practice 21)
> **Giảng viên**: Ahmed Baraka
> **Thời gian học ước tính**: 2.5 - 3 giờ
> **Nguồn PDF**: `pdf_extracted/module_15/`

---

## 📑 Mục lục

- [Kiến trúc & Tiền điều kiện để Nhân bản DB](#-kiến-trúc--tiền-điều-kiện-để-nhân-bản-db)
- [Phương pháp 1: Active Database Duplication (Nhân bản Trực tiếp)](#-phương-pháp-1-active-database-duplication-nhân-bản-trực-tiếp)
- [Phương pháp 2: Backup-Based Duplication (Nhân bản qua File Backup)](#-phương-pháp-2-backup-based-duplication-nhân-bản-qua-file-backup)
- [Thực hành Practice 21: Bốn cách Clone DB trên cùng Server l](#-thực-hành-practice-21-bốn-cách-clone-db-trên-cùng-server)
- [Câu hỏi ôn tập Module 15](#-câu-hỏi-ôn-tập-module-15)

---

# 📖 Kiến trúc & Tiền điều kiện để Nhân bản DB

Trong đời sống DBA, việc tạo ra một bản Copy (Clone) của hệ thống Production để làm môi trường Dev/Test/UAT là công việc lặp đi lặp lại hàng tuần. RMAN cung cấp lệnh `DUPLICATE` để nhân bản một cách hoàn hảo và an toàn toàn bộ kiến trúc DB.

### 1. Kiến trúc Duplication (Auxiliary Instance)
Oracle định nghĩa khái niệm **Auxiliary Instance (Instance phụ/nháp)**. Chu trình RMAN làm việc như sau:
1. DBA dựng sẵn cấu trúc thư mục rỗng và một tệp `init.ora` siêu cơ bản cho DB nháp.
2. Khởi động DB nháp ở chế độ `NOMOUNT`.
3. RMAN kết nối vào DB Nháp với quyền `AUXILIARY`. Tự động cấp channel và bơm data thẳng từ Database Gốc (Source) hoặc từ File Backup vào DB nháp.
4. RMAN tự động Recovery (nếu Copy lúc Prod đang bật) -> RMAN tự đổi `DBID` -> RMAN tự động `OPEN RESETLOGS`.

### 2. Tiền điều kiện quan trọng:
- Source và Auxiliary Database bắt buộc phải **CHUNG NỀN TẢNG (Platform)**. (Cùng Windows, hoặc cùng Linux). *Lưu ý: Nếu khác nền tảng, mời quay lại dùng chiêu Vận tải Cross-Platform ở Module 14!*
- Nếu nhân bản sang máy chủ khác, Auxiliary DB phải được khai báo cứng (Statically registered) trong file `listener.ora`.

---

# 📖 Phương pháp 1: Active Database Duplication (Nhân bản Trực tiếp)

Không cần qua trung gian File Backup nào! RMAN sẽ mở đường hầm mạng kết nối Database Đích và Database Nguồn, bơm Datafiles thẳng thông qua Network.
- **Có 2 cơ chế bắn:**
  - **Dùng Image Copies (Push):** Các kênh Target Chanel của máy Gốc sẽ đọc và bơm sang máy Đích.
  - **Dùng Backupsets (Pull):** Khuyên dùng! RMAN cấp Auxiliary Chanel ở máy Đích tự kéo dữ liệu, cho phép nén trực tiếp ngay trên đường truyền `USING COMPRESSED BACKUPSET` giúp tiết kiệm băng thông mạng công ty.

```sql
RMAN> CONNECT TARGET sys@oradb_prod
RMAN> CONNECT AUXILIARY sys@oradb_dev

RMAN> RUN {
  DUPLICATE DATABASE TO oradb_dev
  FROM ACTIVE DATABASE
  PASSWORD FILE
  SPFILE
  SET DB_CREATE_FILE_DEST='/oracle/oradata/dev';
}
```

---

# 📖 Phương pháp 2: Backup-Based Duplication (Nhân bản qua File Backup)

Nếu băng thông mạng giữa Data Center A và Data Center B rất dở, việc nhân bản trực tiếp bằng mạng sẽ khiến Production bị giật lag. Phương pháp Backup-based là dùng ổ cứng chứa file Backup có sẵn để dựng lại.

Có 3 nhánh nhỏ:
1. **Có kết nối tới Target DB (`TARGET` + `AUXILIARY`):** RMAN xem Control File ở Prod DB để biết lôi File Backup nào ra xài.
2. **Không có Target, nhưng có Recovery Catalog (`CATALOG` + `AUXILIARY`):** DB gốc đã bị cháy/hoặc không cho phép ping tới. RMAN đọc Catalog để dò đường dẫn lấy file Backup.
3. **Mù thông tin hoàn toàn (Chỉ có `AUXILIARY`):** Bạn vác cái ổ cứng chứa file Backup chép ra thư mục `C:\backup`. Khi gõ lệnh Duplicate phải tự chỉ định ngõ vào `BACKUP LOCATION`.

```sql
-- Kịch bản Mù thông tin hoàn toàn:
RMAN> CONNECT AUXILIARY /
RMAN> RUN {
  DUPLICATE DATABASE TO oradb_dev
  SPFILE
  BACKUP LOCATION '/tmp/db_files'; -- Tự Oracle vô lục lọi Backup trong này
}
```

---

# 🎯 Thực hành Practice 21: Bốn cách Clone DB trên cùng Server

Bài Lab cực kỳ chi tiết! Bạn sẽ nhân bản `ORADB` tạo ra DB mới mang tên `ORADB2` ngay trên cùng 1 server ảo (srv1 của Linux).

**Công việc chuẩn bị máy Nháp (Auxiliary):**
1. `mkdir /.../ORADB2` chuẩn bị ổ đĩa.
2. Ghi mỗi 1 dòng `DB_NAME='ORADB2'` vào file `initORADB2.ora`.
3. Sửa `tnsnames.ora` và `listener.ora` khai báo cấu hình.
4. Copy file password: `cp orapwORADB orapwORADB2`.
5. Đăng nhập SQL*Plus `STARTUP NOMOUNT`. (Phải gõ `export ORACLE_SID=ORADB2`).

**Sau đó RMAN sẽ "gõ cửa" test 4 kiểu Nhân bản theo thứ tự sau:**
- **Thử nghiệm 1:** `FROM ACTIVE DATABASE`. Target DB đang chạy song song, RMAN bắn Data ngay tại chỗ tạo ra Dev DB. Check lại `SELECT COUNT(*)` thấy khớp.
- **Thử nghiệm 2:** `DUPLICATE` thông thường từ Backup, Target vẫn nối dây. (Đơn giản bỏ tham số `ACTIVE`).
- **Thử nghiệm 3:** Tắt Target. Chỉ để Catalog và Auxiliary mở. Nhân bản thành công.
- **Thử nghiệm 4:** Tắt Target, tắt Catalog. Chỉ dùng Auxiliary. Khai báo `BACKUP LOCATION '/media/sf_extdisk/backup'`. Nhấn Enter, Database vẫn được tạo mới nguyên vẹn. Thật kỳ diệu!

---

# 🎯 Câu hỏi ôn tập Module 15

**1. Trong kịch bản nhân bản vào MỘT CÙNG MỘT Server (Duplicate to Same Host), nếu Quên tham số `DB_FILE_NAME_CONVERT` thì hậu quả là gì?**
<details>
<summary>💡 Đáp án</summary>
Tai họa! RMAN sẽ ném đường dẫn mặc định từ Control File sang, điều này làm cho Auxiliary Instance đi TƯỚC đoạt và Ghi ĐÈ (Overwrite) trực tiếp lên Datafiles của Production Database đang chạy, làm hỏng hoặc xóa sạch Datafiles thật. Always map kĩ parameter đổi tên cấu trúc thư mục!
</details>

**2. Để tăng tốc độ Duplicate khi dùng `FROM ACTIVE DATABASE` vì Data quá lớn (5TB), mạng lại yếu, thì DBA dùng cụm từ gì trong Run Block?**
<details>
<summary>💡 Đáp án</summary>
Dùng cụm từ `USING COMPRESSED BACKUPSET`. Thuật toán này sẽ nén dữ liệu nóng trên nguồn (Push mode) hoặc đích (Pull mode) trước khi bay qua đường mạng, băng thông truyền tải có thể giảm tới 3-5 lần!
</details>

**3. Clone DB xong thì DBID của bản DB Clone có giống bản Gốc không?**
<details>
<summary>💡 Đáp án</summary>
Không! Điểm khác biệt giữa `RESTORE` và `DUPLICATE` là: Duplicate luôn tự động reset một `DBID` hoàn toàn mới toanh. Do đó bản clone sống độc lập và bạn có thể an toàn Add/Register bản Clone này vào cái Recovery Catalog mà không lo bị trùng lặp ID với ông bố Production của nó.
</details>

---

## ➡️ Bài tiếp theo
**Module 16: RMAN Performance Tuning & Troubleshooting**
Sau khi đã giỏi Backup và Recovery, điều tiếp theo là trở thành chuyên gia tinh chỉnh (Tuning). Ở bài sau, bạn sẽ học cách chia Channel đa luồng, tuning tham số bộ nhớ Large Pool, MAXPIECESIZE để tối đa hoá thông lượng IO giúp Backup chạy với tốc độ tên lửa, và cách đọc Alert Log khắc phục lỗi hóc búa của RMAN.

> **Ghi chú về tên Module:** Anh ơi, Course này Module 15 trong giáo trình PDF tên đúng là **Duplicating a Database using RMAN**, chứ không phải khoá học về "Oracle Flashback" như em đã lỡ dự báo ở bài trước ạ (Có lẽ Flashback được xếp ở giáo trình khoá nâng cao mất rồi). 
> 
> Đặc biệt lúc nãy hệ thống Windows của Sandbox bên em không có hỗ trợ chạy lệnh cài đặt Powershell CLI tool (`irm https://claude.ai/install.ps1 | iex`) nên tiến trình install không chạy được trong Terminal ảo, anh hãy mở Command Line trên máy tính cá nhân chạy thủ công nha! Mời anh xem qua bài Cẩm nang Nhân bản siêu cấp này xong thì báo em để bước tiếp vào **Module 16** nha! 🚀


---

!!! info "Nguồn gốc"
    `dba_ai/oracle_rman/modules/module_15_guide.md`
