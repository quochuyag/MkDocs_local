---
title: '📘 Module 12: Khôi phục Mọi Cấp Độ (Performing Recovery)'
course: 09-dba-ai
source: dba_ai/oracle_rman/modules/module_12_guide.md
---

# 📘 Module 12: Khôi phục Mọi Cấp Độ (Performing Recovery)

> **Module**: 12/17
> **Phạm vi**: Từ Bài 35 đến Bài 48 (6 phần Lý thuyết + 6 phần Thực hành tương ứng)
> **Giảng viên**: Ahmed Baraka
> **Thời gian học ước tính**: 5 - 6 giờ
> **Tiền điều kiện**: Đã hoàn thành toàn bộ các kỹ năng Backup ở 11 module trước.
> **Nguồn PDF**: `pdf_extracted/module_12/`

---

## 📑 Mục lục

- [Giới thiệu tư duy RESTORE và RECOVER](#-giới-thiệu-tư-duy-restore-và-recover)
- [Phần I: Khôi phục Toàn bộ Hệ thống (Full Recovery)](#-phần-i-khôi-phục-toàn-bộ-hệ-thống-full-recovery)
- [Phần II: Chuyển đổi Datafile (Switch) và PITR Cấp Database](#-phần-ii-chuyển-đổi-datafile-switch-và-pitr-cấp-database)
- [Phần III: PITR Cấp Tablespace & Bảng (TSPITR & Table PITR)](#-phần-iii-pitr-cấp-tablespace--bảng-tspitr--table-pitr)
- [Phần IV: Khôi phục Control File, SPFILE và Lỗi NOLOGGING](#-phần-iv-khôi-phục-control-file-spfile-và-lỗi-nologging)
- [Phần V: Thảm họa mất Redo Log Files](#-phần-v-thảm-họa-mất-redo-log-files)
- [Phần VI: Các tình huống phụ trợ (Password, Temp, New Host)](#-phần-vi-các-tình-huống-phụ-trợ-password-temp-new-host)
- [Câu hỏi ôn tập Module 12](#-câu-hỏi-ôn-tập-module-12)

---

# 📖 Giới thiệu tư duy RESTORE và RECOVER

Trong Oracle RMAN, **khôi phục** là quy trình 2 bước:
1. `RESTORE`: Đi lấy đồ dự phòng đắp vào. (Tạo lại datafile từ bản Backupsets/Image copies).
2. `RECOVER`: Bôi trơn đồ mới cho khớp hiện tại. (Áp dụng các thay đổi từ Redo logs và Archive logs vào file vừa đắp để đẩy dữ liệu tiến tới thời điểm mong muốn).

- **Complete Recovery:** Áp dụng TẤT CẢ sự thay đổi (Redo). Dữ liệu phục hồi 100% đến khoảnh khắc sập.
- **Incomplete Recovery / Point-In-Time (PITR):** Chỉ áp dụng MỘT PHẦN sự thay đổi. Trả dữ liệu về một thời điểm ở quá khứ (Ví dụ: Lúc 9h sáng) - Phải mở DB bằng lệnh `RESETLOGS`.

---

# 🎯 Phần I: Khôi phục Toàn bộ Hệ thống (Full Recovery)
*(Lý thuyết Bài 36 + Thực hành Practice 11)*

### 1. Chuẩn bị / Diagnostic trước thảm họa
- Kiểm tra lỗi: `RMAN> VALIDATE DATABASE;`
- List bản backup xem có dùng được không: `RESTORE DATABASE PREVIEW;`
- Lấy **DBID**: Rất quan trọng khi mất Control File (tìm trong chuỗi autobackup `c-DBID-YYYYMMDD-QQ`).

### 2. Các lệnh Khôi phục Cốt lõi
- **Trường hợp DB ở NOARCHIVELOG (Chỉ có Full Backup, không có Redo log):**
  ```sql
  STARTUP MOUNT;
  RESTORE DATABASE;
  RECOVER DATABASE;
  ALTER DATABASE OPEN RESETLOGS;
  ```
- **Trường hợp DB ở ARCHIVELOG (Mất Datafile nhưng Redo log còn nguyên):**
  ```sql
  STARTUP MOUNT;
  RESTORE DATABASE;
  RECOVER DATABASE;
  ALTER DATABASE OPEN; -- Khôi phục trọn vẹn, không cần Resetlogs
  ```
- **Trường hợp Khôi phục Datafile ra ổ cứng mới (Do đĩa cũ cháy):**
  ```sql
  RUN {
    SET NEWNAME FOR DATAFILE 2 TO '/newdisk/df1.dbf';
    RESTORE DATABASE;
    SWITCH DATAFILE ALL;
    RECOVER DATABASE;
  }
  ```

> 🛠️ **Thực hành Practice 11:** 
> Rất thú vị! Cài đặt công cụ `CrashSimulator_Low.sh.x` của Francisco Alvarez để phá hoại DB (tự động xóa datafiles, gỡ tablespace). 
> Sau đó tiến hành thao tác `RESTORE TABLESPACE users` khi Database đang online. Bắt đầu làm quen với việc dùng DBID để recovery.

---

# 🎯 Phần II: Chuyển đổi Datafile (Switch) và PITR Cấp Database
*(Lý thuyết Bài 38 + Thực hành Practice 12)*

### 1. Phục hồi tốc độ chớp mắt bằng Image Copies
Thay vì phải xả nén lâu lắc bằng `RESTORE`, nếu bạn đang dự trữ `Image copies` trong FRA:
```sql
ALTER DATABASE DATAFILE 4 OFFLINE;
SWITCH DATAFILE 4 TO COPY; -- Trỏ cái Datafile hỏng sang xài bản Image Copy luôn!
RECOVER DATAFILE 4;
ALTER DATABASE DATAFILE 4 ONLINE;
```
> Tốc độ siêu nhanh, đạt RTO tính bằng phút.

### 2. Database Point-in-Time Recovery (DBPITR)
Hành động quay ngược thời gian của cả bộ Database.
- **Quy tắc:** Bắt buộc DB phải offline ngắt kết nối (`MOUNT`), có chạy `ARCHIVELOG`.
- Ở cuối bước chạy lệnh, bắt buộc phải dùng `ALTER DATABASE OPEN RESETLOGS` (làm đứt lưới thời gian cũ - Incarnation).

```sql
RUN { 
  SET UNTIL TIME "TO_DATE('2026-10-01 09:00:00','YYYY-MM-DD HH24:MI:SS')";
  RESTORE DATABASE;
  RECOVER DATABASE; 
}
```

> 🛠️ **Thực hành Practice 12:** 
> Mô phỏng lỗi ngớ ngẩn (User lỡ tay DROP bảng `test`). DB sẽ được đưa về chế độ Mount. Học viên sẽ chạy `UNTIL TIME` lùi dần thời gian và thử mở Read Only (`ALTER DATABASE OPEN READ ONLY;`) để quét xem bảng `test` đã "đội mồ sống lại" chưa trước khi quyết định `RESETLOGS`.

---

# 🎯 Phần III: PITR Cấp Tablespace & Bảng (TSPITR & Table PITR)
*(Lý thuyết Bài 40 + Thực hành Practice 13)*

### 1. TSPITR (Tablespace PITR)
Làm thế nào để lùi thời gian cho 1 vùng nhớ mà không ảnh hưởng tới các Tablespace khác đang chạy ngon lành?
- Khái niệm **Auxiliary Database (DB Phụ):** RMAN sẽ âm thầm dựng lên một cái DB "nháp" tạm thời ở một thư mục rác. Nó tự khôi phục dữ liệu ở trong cỗ máy nháp này, bật Data Pump (`expdp`) bốc cái bảng ra, rồi nhét `impdp` lại vào Prod.
```sql
RECOVER TABLESPACE hr_data UNTIL TIME 'SYSDATE-1'
AUXILIARY DESTINATION '/disk1/auxdest'; -- Chỉ thư mục chứa DB nháp
```

### 2. RMAN Table Recovery
Từ 12c, không cần lôi cả Tablespace, có thể lôi TỪNG BẢNG trực tiếp từ cõi chết:
```sql
RECOVER TABLE HR.EMP, SH.DEPT UNTIL TIME 'SYSDATE-1'
AUXILIARY DESTINATION '/tmp/auxdest'
REMAP TABLE HR.EMP:TEST.RECOVERED_EMP; -- Rất hay ho: Trả bảng cũ vào Schema tạm để đối chiếu, không đè lên bảng xịn!
```

> 🛠️ **Thực hành Practice 13:** 
> Dùng chức năng check `DBMS_TTS.TRANSPORT_SET_CHECK` để xem Tablespace có dính rễ ràng buộc ra bảng ngoài không. Thực hành cứu riêng lẻ bảng biểu bị nhân viên lỡ tay DELETE WHERE nhầm điều kiện.

---

# 🎯 Phần IV: Khôi phục Control File, SPFILE và Lỗi NOLOGGING
*(Lý thuyết Bài 42 + Thực hành Practice 14)*

- **Mất SPFILE:** Nếu DB đang chạy ngầm, ngay lập tức tạo tạm 1 file PFILE từ memory (`CREATE SPFILE FROM MEMORY`). Nếu DB nghẻo rồi, khởi động bằng `STARTUP FORCE NOMOUNT` -> `RESTORE SPFILE FROM AUTOBACKUP`.
- **Mất 1/2 Control File (Bị xoá 1 file multiplexing):** Chỉ cần Shutdown Abort, dùng lệnh OS `cp` file control ngon đè lên file hỏng là xong.
- **Mất sạch Control File:** 
  ```sql
  SET DBID 12345;
  STARTUP NOMOUNT;
  RESTORE CONTROLFILE FROM AUTOBACKUP;
  ```
- **Lỗi nhói lòng cấu hình `NOLOGGING`:** Nếu có Job đổ Data chạy `INSERT /*+ APPEND */ NOLOGGING` để tiết kiệm dung lượng, đoạn Text đó sẽ KHÔNG vào Redo. Bản Restore sẽ bị hổng nguyên cái cục đó (`ORA-01578 Block Corrupted`). Cách khắc phục duy nhất: Chạy xong Nologging thì MỚI tiến hành Backup. Đã vỡ là mất hẳn, phải tính toán DROP và tái tạo Data.

---

# 🎯 Phần V: Thảm họa mất Redo Log Files
*(Lý thuyết Bài 44 + Thực hành Practice 15)*

Tháo tác với Redo log file sập tiệm là thử thách tâm lý nhất của DBA. Tuỳ thuộc File hỏng đang ở Status nào (`V$LOG`):

1. **Member hỏng (Còn member khác trong Group):** Dễ ợt! Copy file còn sống đè qua file hỏng khi đang Mount, hoặc chạy lệnh `ALTER DATABASE CLEAR LOGFILE GROUP n;` để Oracle tự rèn lại.
2. **Nguyên Group INACTIVE hỏng:** `CLEAR LOGFILE GROUP n`. (Clear để xoá hẳn quá khứ).
3. **Group ACTIVE hỏng (Hoảng hốt nhẹ):** Group này chứa Data đang chờ tạt xuống đĩa (DBWn chưa ghi xong). Chạy `ALTER DATABASE CLEAR UNARCHIVED LOGFILE GROUP n;`. DB sẽ báo đỏ và yêu cầu bạn chạy Backup FULL toàn DB lại từ đầu.
4. **Group CURRENT bị bốc hơi (Tuyệt vọng):** Mất Data thực sự vừa gõ xong. Nếu đang chạy, ráng lệnh `CLEAR UNARCHIVED LOGFILE;` có khi vớt được phần xác. Thường xuyên phải Incomplete Recovery (`RECOVER DATABASE UNTIL CANCEL`).

---

# 🎯 Phần VI: Các tình huống phụ trợ (Password, Temp, New Host)
*(Lý thuyết Bài 47 + Thực hành Practice 16)*

### 1. Rớt Password File / Tempfiles
- Nhẹ nhàng nhất mùa đông. Rớt Password file (`orapwSID`) khiến kết nối từ xa `sysdba` gặp lỗi `ORA-01017`. Chỉ cần thoát ra hệ điều hành chạy công cụ: 
  `orapwd file=$ORACLE_HOME/dbs/orapwORADB password=oracle entries=5 format=12`
- Tempfile rớt kệ nó. Drop đi tạo lại `ALTER TABLESPACE temp ADD TEMPFILE...`. Nó chỉ làm chậm truy vấn chứ không mất Data thật.

### 2. Dọn Nhà sang Máy Chủ Mới (Restoring database to a New Host)
Tuyệt kĩ sinh tồn nếu Server cũ cháy rụi và mua Server kim loại mới:
1. Ghi lại `DBID` của máy cũ lên Note.
2. Cài bản Oracle Software y hệt (Đồng phiên bản & Architecture).
3. Copy toàn bộ PFILE, Backupset, Wallet sang Server mới.
4. Mở RMAN ở NOMOUNT -> `SET DBID` -> `RESTORE SPFILE` -> `RESTORE CONTROLFILE`.
5. `CATALOG START WITH '/path_to_copied_backups/'` để báo RMAN biết đường mà lấy file phục hồi.
6. Dùng Script đổi tên thư mục (`SET NEWNAME FOR DATABASE`) do máy tính mới ổ đĩa cứng tên khác.
7. `RECOVER DATABASE` & Mở `RESETLOGS`.

---

# 🎯 Câu hỏi ôn tập Module 12

**1. DBA phàn nàn rằng DBPITR quá cồng kềnh vì làm sụp cả Database chỉ để cứu 1 bảng dữ liệu nhỏ xíu. Có cách nào tiện lợi hơn không?**
<details>
<summary>💡 Đáp án</summary>
Có 2 cách thông minh hơn DBPITR:
1. Nếu Timeframe quá ngắn: dùng công nghệ Flashback để Undo dữ liệu ngược lại.
2. Nếu Flashback không được: Dùng RECOVER TABLE (trong môi trường Oracle 12c). RMAN tự bật 1 DB nháp ẩn (Auxiliary DB), chích xuất bảng đó ra thư mục DUMP, rồi map về làm 1 Bảng riêng cho mình (Remap table). Prod DB đang chạy dịch vụ không bị gián đoạn 1 giây nào.
</details>

**2. Điểm khác biệt sống còn giữa `RESTORE` và `RECOVER`?**
<details>
<summary>💡 Đáp án</summary>
RESTORE là giải nén File Backup cũ ra ổ đĩa - Nó mang về cái xác vô hồn ở thời điểm của Quá khứ. 
RECOVER là chạy cuộn dây phim Redo log để replay hàng vạn thao tác INSERT/UPDATE đắp ngược lại lên cái File vừa Restore, mang hơi thở sống lại tới hiện tại hoặc 1 thời điểm mình muốn dừng.
</details>

**3. Làm thế nào để giải cứu Datafile nếu File vô tình bị rơi vào trạng thái cần Backup/Phục hồi nhưng bạn lại đang muốn khôi phục máy chỉ trong 10 giây?**
<details>
<summary>💡 Đáp án</summary>
Hãy dùng chức năng `SWITCH DATAFILE TO COPY`. Nó dẹp bỏ chữ RESTORE chậm rề. Biến File ảnh bản chụp sao lưu Image Copy thành Datafile chuẩn ngay lập tức trong Database (nếu File Copy này đang nằm trên ổ đĩa Flash xịn của Data center).
</details>

---

## ➡️ Bài tiếp theo
**Module 13: Handling Corrupted Blocks**
Bạn sẽ làm quen với việc dữ liệu bị thối rữa ở từng Block nhỏ lẻ bên trong ổ cứng vật lý. Làm thế nào dùng Data Recovery Advisor để sửa lỗ thủng đó cực kì mượt mà?
Dự kiến học qua Bài 49, 50, 51.

> Em đã hoàn thành bản tổng hợp vĩ đại cho trọn bộ khuyết điểm và phục hồi ở Module 12. Bài này thực sự khó nhằn và quan trọng nhất sự nghiệp DBA. Gõ lệnh trong môi trường **CrashSimulator** anh cẩn thận Snapshot đầy đủ nhé! Khi nào xong thì báo em để em khởi tạo Module 13 nha! 🚀


---

!!! info "Nguồn gốc"
    `dba_ai/oracle_rman/modules/module_12_guide.md`
