---
title: '📘 Module 14: Vận Tải Dữ Liệu Xuyên Nền Tảng (Cross-Platform Data Transportation)'
course: 09-dba-ai
source: dba_ai/oracle_rman/modules/module_14_guide.md
---

# 📘 Module 14: Vận Tải Dữ Liệu Xuyên Nền Tảng (Cross-Platform Data Transportation)

> **Module**: 14/17
> **Phạm vi**: Bài 53 đến 60 (Lý thuyết + Thực hành Practice 19 & 20)
> **Giảng viên**: Ahmed Baraka
> **Thời gian học ước tính**: 3 - 4 giờ
> **Nguồn PDF**: `pdf_extracted/module_14/`

---

## 📑 Mục lục

- [Tổng quan về Vận tải Xuyên Nền tảng](#-tổng-quan-về-vận-tải-xuyên-nền-tảng-endian-format)
- [Phương pháp 1: Vận tải bằng Image Copies](#-phương-pháp-1-vận-tải-bằng-image-copies)
- [Phương pháp 2: Vận tải bằng Backupsets](#-phương-pháp-2-vận-tải-bằng-backupsets-từ-bản-121)
- [Thực hành Practice 19 & Practice 20](#-thực-hành-practice-19--practice-20)
- [Câu hỏi ôn tập Module 14](#-câu-hỏi-ôn-tập-module-14)

---

# 📖 Tổng quan về Vận tải Xuyên Nền tảng (Endian format)

Vận tải xuyên nền tảng (Cross-platform Data Transportation) là kĩ thuật chuyển đổi dữ liệu từ một Hệ điều hành này sang một Hệ điều hành khác (VD: Từ Linux sang Windows, từ AIX sang Solaris).

### 1. Rào cản lớn nhất: Endian Format ⭐⭐⭐
Các hệ điều hành lưu trữ Byte nhị phân theo các chiều ngược nhau:
- **Little Endian:** Linux (x86), Windows. (Lưu bit nhỏ trước).
- **Big Endian:** IBM AIX, HP-UX, Solaris. (Lưu bit lớn trước).

> Nếu Source & Target khác Endian -> Bắt buộc phải chạy tiến trình **CONVERT** cấu trúc Byte ở mức Datafile/Tablespace. 
> Kiểm tra hệ điều hành thuộc định dạng nào:
```sql
SELECT PLATFORM_NAME, ENDIAN_FORMAT FROM V$TRANSPORTABLE_PLATFORM;
```

### 2. Các cấp độ Vận tải
- **Chỉ chuyển Tablespace/Datafile:** Cho phép Source và Target *khác* Endian (Phải Convert bằng RMAN, bốc Datafile và một file DUMP Metadata bằng Data pump expdp sang máy mới ráp vô).
- **Chuyển Toàn bộ Database (Entire Database):** Bắt buộc Source và Target phải *cùng* định dạng Endian (Ví dụ: Linux x86 mang sang Windows x86 đều là Little Endian).

---

# 📖 Phương pháp 1: Vận tải bằng Image Copies

Image copy là copy xé lẻ từng tệp Datafile. Có 2 cách chọn nơi Convert:
1. **Convert tại nhà máy (Source Host):** Đóng gói xong, biến hình chuẩn với máy khách rồi mới chép file qua Mạng (Gây nặng tải cho máy gốc đang chạy Prod).
2. **Convert tại nhà đích (Destination Host):** Chép cục Data thô qua máy khách, mượn CPU máy khách để Convert (Nên ưu tiên cách này để máy gốc Production không bị áp lực CPU).

### Các bước chung (Transport Tablespace):
1. Check Tablespace có bị dính dáng rễ ra ngoài không: `exec DBMS_TTS.TRANSPORT_SET_CHECK('FIN,HR', TRUE,TRUE);`
2. Đọc khóa Tablespace: `ALTER TABLESPACE fin READ ONLY;`
3. Convert (Nếu ở Source): 
   ```sql
   RMAN> CONVERT TABLESPACE fin TO PLATFORM 'Linux IA (64-bit)' FORMAT '/tmp/%U';
   ```
4. Dùng lệnh `expdp` rút Metadata của Tablespace ra tệp Dump (`.dmp`).
5. Copy tệp Dump và Datafile qua máy mới.
6. Máy mới gọi lệnh `impdp` để cắm Datafile đó vào xài. 

---

# 📖 Phương pháp 2: Vận tải bằng Backupsets (Từ bản 12.1)

Trước Oracle 12, quá trình vận tải chỉ chơi với Image Copies (File không nén, rất bự). Từ bản 12c, Oracle cho phép dùng **Backupset** (Có nén, nhỏ gọn).
Đặc tính:
- Sinh ra tệp Backup không ghi vào Recovery Catalog (Nó sẽ là tệp ngoại lai Foreign backup).
- Dùng từ khóa `FOR TRANSPORT` hoặc `TO PLATFORM` trong câu lệnh BACKUP.

### Tuyệt kĩ: Minimum Read-only Period (Giảm thiểu thời gian Downtime) ⭐⭐⭐
Nếu chép 10TB Image Copy qua mạng, DB sẽ bị Read Only suốt 20 tiếng chép bài (Downtime 20 tiếng). Với kỹ thuật Backupset Incremental:
1. Thứ 2: Ta lấy **Level 0 Baseline Backup** sang máy mới Restore trước (Lúc này máy Prod vẫn Read-Write, đang kinh doanh bình thường).
2. Thứ 3: Ta lấy **Level 1 Incremental Backup** sang đắp thêm vào.
3. Thứ 4: Khi quyết định Cut-over, chuyển máy Prod sang `READ ONLY`. Tạo 1 bản Level 1 cuối cùng, đem chép qua và Apply vào là xong.
=> Downtime thực tế từ 20 tiếng gỡ xuống chỉ còn CHƯA TỚI 5 PHÚT. 

---

# 🎯 Thực hành Practice 19 & Practice 20

Đây là các bài Lab cực khủng yêu cầu bạn phải có cả 2 máy ảo: `srv1` (Linux) và `winsrv2` (Windows). 
*Lưu ý: Mẹo truyền dữ liệu khuyên dùng là Mount chung một Shared Folder của VirtualBox xuống 2 cái VM này để khỏi phải dùng FTP hay SCP chuyển file.*

### Phân tích Practice 19: Dùng Image Copies (Linux bắn sang Windows)
1. **Tablespace (soetbs):** Máy gốc Linux đặt Tablespace vào Read-Only -> Convert thẳng ở Windows -> Đóng `impdp` cái rộp là bên Windows xài được bảng `SOE.ORDERS` gốc Linux.
2. **Database (ORADB):** Export toàn bộ Database từ Linux. RMAN sẽ nhả ra 1 đống file (Datafiles + PFILE + 1 file Script cài đặt `transportscript.sql`). Sang Windows, bật Command Prompt, chạy script gõ tự động là Windows mọc lên con DB Y hệt Linux.

### Phân tích Practice 20: Dùng Backupsets Nén (Windows bắn ngược về Linux)
1. Ở trên Win, chạy: `BACKUP TO PLATFORM 'Linux x86 64-bit' TABLESPACE rc_tbs;` -> RMAN Windows sẽ tự động tạo file nén `.BCK` và tệp dmp của metadata.
2. Quăng mớ nén đó sang thư mục của Linux.
3. Linux RMAN dùng lệnh `RESTORE FOREIGN TABLESPACE rc_tbs TO NEW FROM BACKUPSET '/.../RC_TBS.BCK'` để xả nén phục hồi. Tiện lợi, dung lượng siêu nhẹ!

*(Nếu bị lỗi "Protocol Adapter Error" khi cắm DB trên Windows, hãy chắc chắn bạn đã gõ `oradim -NEW -SID ORADB2` và `set ORACLE_SID=ORADB2` thành công).*

---

# 🎯 Câu hỏi ôn tập Module 14

**1. Nếu bạn đang chạy hệ thống Core Banking trên Solaris (Big Endian) và sếp phân phó bốc TOÀN BỘ DATABASE sang Windows (Little Endian). Bạn thực hiện lệnh DB Transport thế nào?**
<details>
<summary>💡 Đáp án</summary>
Nhiệm vụ BẤT KHẢ THI. Cross-platform Entire Database Transport bắt buộc 2 nền tảng source và target phải CÙNG Endian Format. Tình huống này (Big sang Little) chỉ có thể dùng cách Transport nhặt rổ từng Tablespace/Datafile lẻ.
</details>

**2. Đội Network khuyên bạn nên nén file trước khi đẩy qua mạng vì băng thông đang nghẽn. Bạn nên chọn Image Copies hay Backupsets?**
<details>
<summary>💡 Đáp án</summary>
Chắc chắn là Backupsets (Tính năng mới nhất từ 12c). Backupset cho phép nén dữ liệu và dùng Incremental để cắt giảm tối đa thời gian Downtime hệ thống. Tham số đi kèm là `BACKUP FOR TRANSPORT FORMAT...`
</details>

**3. Tại sao khi chuyển Tablespace cross-platform, DBA bắt buộc phải lấy kèm tệp Dump (`expdp`) của Data Pump? Mang cái Datafile qua xài luôn không được à?**
<details>
<summary>💡 Đáp án</summary>
Datafile chỉ chứa "Thịt" (Data Blocks). Máy chủ mới cắm Datafile đó vào sẽ không hiểu nổi cái block này nằm ở Column nào, thuộc Table nào, tên Bảng là gì, Owner của nó là user nào. Vì vậy bắt buộc phải có DUMP File để mang "Khung xương" Metadata (Cấu trúc bảng/Dictionary) từ máy cũ sang cắm bảng định tuyến cho máy mới đọc thịt.
</details>

---

## ➡️ Bài tiếp theo
**Module 15: Đi xuyên Không gian và Thời gian với Oracle Flashback Technologies**
Sau khi học cách hồi sinh bằng các file vật lý nặng trịch (RESTORE), ở bài sau, chúng ta sẽ học một chiêu thức thanh thoát hơn: Undo Data ngược về quá khứ mà KHÔNG CẦN đụng tay tới một tệp Backup nào! Điển hình là việc Cứu Table vừa bị DROP mà không phải sập cả Database!

> Dạ Module 14 về Cross-Platform anh có thể vọc kĩ bài Lab có chia sẻ Shared Folder ảo giữa Windows và Linux nhé, quá trình build lại bằng tập tin transport_script.sql tự động rất phê đấy ạ. Khi nào anh review xong thì báo em để em làm tiếp **Module 15** siêu phẩm công nghệ Flashback luôn nha! 🚀


---

!!! info "Nguồn gốc"
    `dba_ai/oracle_rman/modules/module_14_guide.md`
