---
title: '📘 Module 07: Reporting & Monitoring RMAN Backups'
course: 02-rman-backup-recovery
source: Oracle-Database-Backup-and-Recovery-using-RMAN/modules/module_07/module_07_guide.md
---

# 📘 Module 07: Reporting & Monitoring RMAN Backups

> **Phạm vi**: Bài 19 - 23 (Reporting, Monitoring & Practice 7)
> **Thời gian học ước tính**: 3 giờ
> **Tiền điều kiện**: Hoàn thành phần thiết lập Backup (Module 04, 05, 06) để có data query.

---

## 📑 Mục lục
- [Bài 19-20: RMAN Reporting Commands & Views](#-bài-19-20-rman-reporting-commands--views)
- [Bài 21-23: Thực hành (Practice 7) Reporting & Monitoring](#-bài-21-23-thực-hành-practice-7-reporting--monitoring)
- [Bảng tổng hợp & Cú pháp](#-bảng-tổng-hợp--cú-pháp)
- [Câu hỏi ôn tập tổng hợp](#-câu-hỏi-ôn-tập-tổng-hợp)

---

# 📖 Bài 19-20: RMAN Reporting Commands & Views

## 🎯 Mục tiêu bài học
Sau khi hoàn thành bài này, bạn sẽ:
- ✅ Dùng lệnh `LIST` và `REPORT` để kết xuất báo cáo chuẩn xác về tồn kho Backup.
- ✅ Khai thác quyền lực của Dynamic `V$` Views để lấy những số liệu mà RMAN Prompt không hiển thị chi tiết (như Tốc độ Backup Mbps, Mức độ nén).
- ✅ Đồng bộ hóa (Crosscheck) giữa Kho dữ liệu Metadata RMAN và Ổ cứng thực tế OS.
- ✅ Giám sát siêu realtime tiến độ 1% - 100% của một Job RMAN đang chạy.

## 💡 Ý tưởng cốt lõi (Memory Hack)
- **LIST là "Xem Kho"**: Cứ muốn biết có tồn tại bao nhiêu file, file ở đâu, loại nào → Dùng `LIST`. (VD: Liệt kê hàng hóa kho xuất nhập khẩu).
- **REPORT là "Phân Tích Báo Cáo Hành Động"**: Hỏi các câu như "File nào Đang Thiếu Backup?", "File nào Hết Hạn Phải Xóa Mất Rồi?" → Dùng `REPORT`. (VD: Bản báo cáo công việc của quản lý kho).

---

## 📋 Nội dung chính

### 1. Phân quyền và Lệnh LIST (Inventory Query)

Dùng để liệt kê file ảnh, archive log, backupsets có trong Metadata.

**Lệnh RMAN thực thi:**
```sql
RMAN> LIST BACKUP SUMMARY;
RMAN> LIST COPY OF TABLESPACE USERS;
```

**Output mẫu của lệnh LIST ARCHIVELOG:**
```text
List of Archived Log Copies
Key     Thrd Seq     S Low Time
------- ---- ------- - ---------
123     1    452     A 16-APR-26
        Name: /u01/app/oracle/fra/ORADB/archivelog/o1_mf_1_452_abc.arc
```
*Giải thích*: Cột S (Status) báo 'A' (Available). Thrd (Thread) báo node xử lý RAC. RMAN rà soát trên metadata. Rất nhanh, nhưng sẽ sai nếu bạn đã ra OS và ... Shift+Delete thủ công file đó!

### 2. CROSSCHECK - Thám tử xác minh chéo ⭐⭐⭐

> [!CAUTION]
> Tội lỗi kinh điển của System Admin: Giải phóng ổ đĩa bằng lệnh `rm -rf *.bkp` ngoài hệ điều hành OS nhưng RMAN trong Database vẫn ngây thơ lưu Metadata "Mọi thứ File này vẫn đang ở đây và an toàn (A)". 

**CROSSCHECK** là lệnh yêu cầu RMAN đích thân xuống ổ đĩa vật lý check coi file có tồn tại thật hay không. Nếu bị mất vật lý, RMAN đổ Status S thành 'EXPIRED'.

**Cơ chế Workflow:**
```text
(1) System Admin "Xóa lén" File X ngoài OS.
(2) DBA gõ `LIST BACKUP` -> RMAN vẫn báo STATUS = 'A' (Available) vì nó chỉ query Metadata.
(3) DBA gõ `CROSSCHECK BACKUP;` -> RMAN phát hiện bị lừa mất file vật lý -> Update Status File X thành 'EXPIRED' (Tức là đã 'chết').
(4) DBA gõ `DELETE EXPIRED BACKUP;` -> Thanh trừng File bị mất ảo ra khỏi bộ nhớ Metadata.
```

### 3. Sức mạnh phân tích của REPORT

Công cụ của DBA dùng báo cáo với sếp cuối năm. 

**Câu lệnh phân tích "Nợ Backup" (REPORT NEED BACKUP):**
```sql
-- "Những datafile nào hiện tại chỉ có MỘT bản sao trong kho?"
RMAN> REPORT NEED BACKUP REDUNDANCY 2;
```
*Tình huống Thực tế:* RMAN trả về File System01. Điều đó chứng tỏ hôm qua Job Backup Datafile 01 bị fail, dẫn đến bạn chưa kịp hoàn tất chuẩn "Giữ 2 bản (Redundancy 2)" cho riêng nó. Chỉ huy ngay `BACKUP DATAFILE 1;`.

**Câu lệnh "Hàng hết đát" (REPORT OBSOLETE):**
```sql
-- Dựa trân config Retention Window/Redundancy hiện tại, file nào được phép vứt đi?
RMAN> REPORT OBSOLETE;
RMAN> DELETE OBSOLETE; -- Hành hình vứt đi!
```

**Câu lệnh "Nỗi sợ hãi" (REPORT UNRECOVERABLE):**
Xảy ra khi Developer gõ lệnh `CREATE TABLE ... NOLOGGING;`. Vì "hủy kích hoạt sinh Log" nên mất điện lúc đó thì chả có ArchiveLog để Recover. `REPORT UNRECOVERABLE` sẽ báo động Datafile nào chứa đoạn dữ liệu này, yêu cầu bạn Backup toàn bộ File đó lại bằng tay liền nếu không muốn sa thải do mất Transaction này.

### 4. Giám sát siêu ngầm V$ Views

RMAN màn hình đen thui không thể nói cho sếp biết Tiến độ (Progress %) là bao nhiêu?
RMAN Job là một phiên chạy ngầm trong Database, hoàn toàn dùng ngôn ngữ SQL Dynamic Views để khai thác!

---

# 💻 Bài 21-23: Thực hành (Practice 7) Reporting & Monitoring

> **Mục tiêu**: Bơm lệnh trực tiếp bằng Terminal 2 cửa sổ: Bịt mắt SQLPlus và tung chiêu RMAN ngầm.

## Tình huống 1: RMAN đe dọa với "Unrecoverable" NOLOGGING
Ta ra cửa sổ SQLPlus (vào vai Developer phá hoại) và gõ thẳng:
```sql
SQL> CREATE TABLE testme NOLOGGING TABLESPACE USERS AS SELECT * FROM USER_TABLES;
```
Bởi vì NOLOGGING, hệ thống Oracle bỏ qua Redo để chạy Load siêu nhanh. 

Trở lại cửa sổ RMAN Session của quản trị viên:
```sql
RMAN> REPORT UNRECOVERABLE;
```
**Output RMAN báo rủi ro đỏ:**
```text
Report of files that need backup due to unrecoverable operations
File Type of Backup Required Name
---- ----------------------- -----------------------------------
4    full or incremental     /u01/app/.../users01.dbf
```
*Giải quyết:* Gõ ngay `BACKUP TABLESPACE USERS;` để chép data vật lý tĩnh lưu lại vì Log không ghi nhận mớ này! Khắc phục rủi ro mất job test.

## Tình huống 2: Soi Tiến độ 1-100% thời gian thực (Realtime LONGOPS)
Đang gõ lệnh trích xuất DataWarehouse 5TB, màn hình RMAN sẽ đứng im không hiển thị vệt sóng loading... Làm sao biết khi nào về nhà?
Mở 1 màn hình SQLPlus khác:
```sql
SELECT SID, SERIAL#, CONTEXT, SOFAR, TOTALWORK,
       ROUND(SOFAR/TOTALWORK*100,2) "%_COMPLETE"
FROM V$SESSION_LONGOPS
WHERE OPNAME LIKE 'RMAN%' AND TOTALWORK != 0 AND SOFAR <> TOTALWORK;
```
**Output Trả về Rực Rỡ:**
```text
SID SERIAL#   CONTEXT   SOFAR TOTALWORK %_COMPLETE
--- ------- --------- ------- --------- ----------
 18   12345         1   45000     89000      50.56
```
Sếp hỏi: "Xong chưa?" -> DBA: "Dạ 50.56% rồi ạ!".

## Tình huống 3: Mổ xẻ KPI Job Backup (V$RMAN_BACKUP_JOB_DETAILS)
Làm sao thống kê Tốc độ MB/s của từng đêm backup hôm qua? (RMAN view JOB)
```sql
SELECT TO_CHAR(SESSION_KEY) S_KEY, INPUT_TYPE, STATUS, 
       ELAPSED_SECONDS/60 MINS,
       INPUT_BYTES_PER_SEC_DISPLAY IN_SPEED, OUTPUT_BYTES_PER_SEC_DISPLAY OUT_SPEED
FROM V$RMAN_BACKUP_JOB_DETAILS ORDER BY SESSION_KEY;
```
**Output Mẫu Báo cáo System Metric Insight:**
```text
S_KEY INPUT_TYPE STATUS    MINS    IN_SPEED  OUT_SPEED
----- ---------- --------- ------- --------- ---------
 40   DB FULL    COMPLETED     5.2 120.00M   45.00M
```
*Điều tra Cột Mốc*: Chú ý dòng In/Out speed. Tại sao đọc đĩa `120MB/s` mà tốc độ xuất ổ sao lưu ghi ra chỉ `45MB/s`? À vì ta vừa dùng `COMPRESSION MEDIUM`. CPU đọc mướt nhưng tốn xử lý nén file lại rồi mới xì ra! Dữ liệu của DBA!

---

# 📊 Bảng tổng hợp & Cú pháp

| Mục đích Quản trị | Lệnh thao tác RMAN/SQL | Phân tích chức năng hệ thống |
|----------|-------------------|--------------------------------------|
| **Cảnh báo Lỗ hổng Database** | `REPORT UNRECOVERABLE;` | Kiểm tra Datafile vướng NOLOGGING. Mất điện là bay sạch data đoạn đó. |
| **Dọn Rác Chuẩn (Quy trình OS)** | `CROSSCHECK ...;` rồi `DELETE EXPIRED;` | Khi file vật lý ra đi ngoài ý muốn (OS rm). Crosscheck gạch tên nó trên ControlFile RMAN. |
| **Dọn Rác Cổ Xưa (Hết Date)** | `REPORT OBSOLETE;` rồi `DELETE OBSOLETE;` | Dọn rác vì quá cũ, vi phạm luật (Retention Window/Redundancy), dọn cho trống FRA hợp pháp. |
| **Xem Progress Bar %** | `SELECT ... V$SESSION_LONGOPS` | Thấy RMAN chạy lâu quá treo? Nhìn cột `%_COMPLETE` để biết nó treo thật hay đang chép 10TB. |
| **KPI tốc độ chép Data In/Out** | `SELECT ... V$RMAN_BACKUP_JOB_DETAILS` | Đánh giá nghẽn cổ chai Bottleneck (Đọc chậm do Source Storage lỗi, hay Write ra mạng Tape chậm). |

---

# 🎯 Câu hỏi ôn tập tổng hợp

1. Nêu sự khác biệt sống còn của Status trạng thái `EXPIRED` và `OBSOLETE`. Bạn có thể sử dụng cơ chế thủ công xóa `rm -rf` Linux lên một nhóm file `OBSOLETE` nằm trong ổ đĩa FRA mà an toàn cho RMAN không? Tại sao?
2. Trong lệnh theo dõi Longops, có phải mọi câu lệnh `BACKUP TABLESPACE` 1MB đều hiện trên đó không? (Gợi ý: Cụm từ Long-Ops (Hoạt động dài kì)).
3. Một Developer gõ `CREATE INDEX .. NOLOGGING`. Sáng hôm sau bạn RMAN gõ `REPORT UNRECOVERABLE`. Liệu cái file lưu Index đó có được List ra màn hình không nếu hôm trước bạn vừa Full Backup xong?
4. View `V$RMAN_BACKUP_JOB_DETAILS` định nghĩa một đơn vị "JOB" có phải là 1 câu lệnh Backup không? Chuyện gì xảy ra nếu 1 `RUN {}` block chạy cả FULL DB và COPY ARCHIVE? Nó nằm trên mấy dòng của View này?

---
## ➡️ Bài tiếp theo
Đỉnh cao của giám sát đã nắm được. Bây giờ chúng ta bước vào vương quốc tối ưu thời gian nghẽn cổ chai vật lý của hệ thống: **Module 08: Improving Backups**. Nơi bạn sẽ rạch nát cái Datafile khổng lồ 5TB ra cắt cho 8 luồng CPU nhai cùng lúc bằng `MULTISECTION` và công nghệ `NULL BLOCK COMPRESSION`! 🚀
Bạn muốn kiểm tra xem có File Extinct nào để dọn rác FRA chừng 5 phút không, hay nhắm mắt qua luôn Module 08?


---

!!! info "Nguồn gốc"
    `Oracle-Database-Backup-and-Recovery-using-RMAN/modules/module_07/module_07_guide.md`
