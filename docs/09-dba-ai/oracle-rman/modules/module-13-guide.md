---
title: '📘 Module 13: Handling Corrupted Blocks & Data Recovery Advisor'
course: 09-dba-ai
source: dba_ai/oracle_rman/modules/module_13_guide.md
---

# 📘 Module 13: Handling Corrupted Blocks & Data Recovery Advisor 

> **Module**: 13/17
> **Phạm vi**: Bài 49, 51 (Lý thuyết) & Bài 50, 52 (Practice 17 & 18)
> **Giảng viên**: Ahmed Baraka
> **Thời gian học ước tính**: 2 giờ
> **Tiền điều kiện**: Đã hoàn thành Module 12
> **Nguồn PDF**: `pdf_extracted/module_13/`

---

## 📑 Mục lục

- [Kịch bản Lý thuyết 1: Handling Corrupted Blocks](#-kịch-bản-lý-thuyết-1-handling-corrupted-blocks)
- [Kịch bản Lý thuyết 2: Khai thác Data Recovery Advisor](#-kịch-bản-lý-thuyết-2-khai-thác-data-recovery-advisor)
- [Thực hành Practice 17 & 18: Thử nghiệm phá hủy và sửa chữa](#-thực-hành-practice-17--18-thử-nghiệm-phá-hủy-và-sửa-chữa)
- [Câu hỏi ôn tập tổng hợp](#-câu-hỏi-ôn-tập-tổng-hợp)

---

# 📖 Kịch bản Lý thuyết 1: Handling Corrupted Blocks

Khác với Module 12 (Bạn làm mất nguyên cái Datafile hoặc bị xóa trọn cái Bảng), Module 13 xử lý tình huống "Block Corruption" - khi Datafile gốc vẫn còn đó, file OS vẫn bình thường, nhưng **vài Byte bên trong ruột** của File bị thối rữa/biến dạng do lỗi từ trường ổ cứng (Disk Drive) hoặc lỗi HĐH (OS).

### 1. Hai loại thối rữa dữ liệu (Corruption Types) ⭐⭐

- **Phân rã Vật lý (Media/Physical Corruption):** Định dạng block bị sai số. Database không nhận diện được block đó nữa (Checksum invalid, bit biến thành số 0, hoặc vỡ Header). Oracle mặc định BẬT tính năng check lỗi này.
- **Phân rã Logic (Logical Corruption):** Block đọc được, chuẩn format nhưng dữ liệu bên trong thì phi lý và không nhất quán ('Lost write'). Oracle mặc định TẮT tính năng check lỗi này để đỡ tốn hao CPU. Bật bằng tham số `DB_BLOCK_CHECKING`.

### 2. Công cụ Quét và Bắt bệnh (Detection Tools) ⭐⭐⭐

> Dấu hiệu: Khi hệ thống báo lỗi **`ORA-01578: ORACLE data block corrupted (file# n, block# s)`**

Các cách để cố tình đi quét tìm ổ dịch (Corrupted blocks) trước khi nó lây lan:
1. Gõ thẳng ở RMAN: `VALIDATE DATABASE;` (Sẽ cho ra lỗi vật lý). Nếu nghi ngờ Logic thì thêm tham số: `VALIDATE CHECK LOGICAL DATABASE;`
2. Quét bằng công cụ riêng lẻ của OS tên là **DBVERIFY**: 
   `dbv FILE=/u01/../mydatafile1.dbf FEEDBACK=100` (Không cần bật DB lên).
3. Đang trong SQL*Plus rảnh rỗi kiểm tra bảng: 
   `ANALYZE TABLE emp VALIDATE STRUCTURE;`

### 3. RMAN Block Media Recovery (BMR) - Liều thuốc tiên ⭐⭐⭐
Thay vì phải Restore nguyên cái Datafile nặng nghìn GB chỉ vì một cái block xíu xiu bị hư, RMAN cung cấp kĩ thuật **BMR**.
Nó tìm Block tốt nhất ở [Flashback logs] hoặc [Bản Incremental / Bản Zero LevelBackup], sau đó bóc đúng cái block đó dán đè lên Block thối.

```sql
-- Dán đè tất cả các Block đang bị bệnh đỏ (có danh sách lưu trong view V$DATABASE_BLOCK_CORRUPTION)
RMAN> RECOVER CORRUPTION LIST;

-- Sửa đích danh từng Block hỏng 
RMAN> RECOVER DATAFILE 6 BLOCK 14 DATAFILE 2 BLOCK 11;
```

> **Tuyệt kỹ Active Data Guard:** Nếu công ty dùng Data Guard (Có 1 con DB khác đồng bộ liên tục lúc nào cũng read-only). Con DB chính mà bị hư Block, nó sẽ NÓI CHUYỆN ngầm với con Standby và mượn cái Block lành lặn đắp vào luôn theo **Thời gian thực** (Không cần RMAN luôn!).

---

# 📖 Kịch bản Lý thuyết 2: Khai thác Data Recovery Advisor (DRA)

DRA là anh Bác sĩ tự động của Oracle. Khi DB bị nghễnh ngãng, thay vì hì hục dò Alert Log và tự gõ lệnh Fix, hãy gọi anh Bác Sĩ. Lợi ích: Tự quét (Diagnose), đưa ra hướng giải quyết (Advise), và tự tay viết Script gõ dùm luôn (Repair).

### Vòng đời sử dụng (Lifecycle) của Advisor: ⭐⭐⭐

| Bước của DBA | Lệnh (Command) | Ý nghĩa |
|--------------|----------------|---------|
| 1. Báo cáo tình hình | `LIST FAILURE;` | Lấy danh sách bệnh viện mà Health Monitor đã báo cáo. |
| 2. Đòi hỏi Lời khuyên | `ADVISE FAILURE;` | Advisor báo rằng: Bệnh này có 2 đường trị. Một là thủ công (DBA tự đánh lệnh), hai là để tao (Automated repair options). Nó sẽ vạch rõ đường hướng. |
| 3. Chốt phương án | `REPAIR FAILURE;` | Advisor lấy phương án tốt nhất, in cả cái script khôi phục ra màn hình hỏi "Ông có chốt YES không?", chốt YES là nó gõ lệnh làm rẹt rẹt. |
| 4. Xóa báo cáo bệnh | `CHANGE FAILURE 104 CLOSED;`| Khép lại hồ sơ bệnh án số 104. |

---

# 🎯 Thực hành Practice 17 & 18: Thử nghiệm phá hủy và sửa chữa

### Practice 17: Mất Datafile và để Advisor tự lấy lại
- **Kịch bản:** DBA chạy tool CrashSimulator xóa sạch tệp non-system. DB báo lỗi `ORA-01157`. Ai cũng hoảng loạn.
- **Tiến hành RMAN:** DBA rất ung dung, chui vào RMAN đánh lệnh `LIST FAILURE`. RMAN nhận ra một File bị mất hỏng, vội gợi ý `ADVISE FAILURE` (tao sẽ dán Datafile 28 offline, sau đó restore cái 28, rồi recover, rồi mở lại). Bạn ngồi cười và đánh `REPAIR FAILURE`. RMAN làm hộ bạn A-Z. Cứu rỗi cuộc đời!

### Practice 18: Dùng lệnh DD độc ác của Linux để tàn phá Block ruột 😈
Đây là Lab hay nhất về Data Corruption.
1. Chui vào DB xem Bảng `SOE.ORDERS` nó nằm vắt trên đoạn Block từ số mấy đến số mấy (VD: số 100).
2. Lấy con số 100 đó, cộng lên tí xíu (VD: 105) để nhắm mục tiêu vào giữa tim Bảng.
3. Thoát ra OS Linux, dùng mũi dùi thiết giáp hạm đâm thủng Datafile:
   ```bash
   dd of=/u01/.../soetbs01.dbf bs=8192 conv=notrunc seek=105 << EOF
     hello world toang nhe
     EOF
   ```
4. Quay lại DB, `SELECT * FROM ORDERS;` >> Lỗi ầm ập `ORA-01578: ORACLE data block corrupted`.
5. Vào RMAN gọi đội cấp cứu: `LIST FAILURE;` >> `ADVISE FAILURE;` >> `REPAIR FAILURE;`
6. Và Data Recovery Advisor lại tung một phép màu, chữa lành đúng cái cục u ác tính. Bảng sống lại!

---

# 🎯 Câu hỏi ôn tập tổng hợp

**1. Data Recovery Advisor (DRA) rất thần thánh, vậy trong trường hợp cơ sở hạ tầng nào thì tiện ích RMAN này bị cấm sử dụng?**
<details>
<summary>💡 Đáp án</summary>
ORA Advisor RẤT TIẾC không được hỗ trợ trong môi trường máy chủ cụm **RAC (Real Application Clusters)**. Ngoài ra ở mô hình đa người thuê 12c, tính năng này được cắm ở CDB root chứ không xài cho Pluggable Databases (PDBs). DBA hệ phi tập trung vẫn sẽ phải tự thân vận động!
</details>

**2. Nếu hệ thống DB quá lớn, mỗi đêm bạn muốn gõ lệnh tự động RMAN Check xem có cái Block nào bị đục thủng ngầm trên Datafile không thì làm cách nào?**
<details>
<summary>💡 Đáp án</summary>
Gài vào script một câu RMAN `VALIDATE DATABASE;`. Lệnh quét này sẽ kiểm tra header/footer của toàn bộ từng block một (Physical). Trâu bò hơn nữa thì gõ `VALIDATE CHECK LOGICAL DATABASE` luôn, nó vào từng đoạn memory nội dung để móc nghoe coi có bị lệch chuẩn không (Tất nhiên check logical thì chạy sẽ chậm hơn xíu).
</details>

**3. DBA có File Backup xịn vừa copy sang Data Center, nhưng đang nghi ngờ RMAN báo láo là File đã ngon lắn trong khi Internet quá giật. Làm sao để xùy RMAN tự check xem bộ Backup này dùng được không (không cần đụng tới data Prod)?**
<details>
<summary>💡 Đáp án</summary>
Giờ không gọi VALIDATE DATABASE nữa, mà gọi `VALIDATE BACKUPSET 3890;` để ngấu nghiến Check lại cái cục Nén xem nó có rỗng ruột hay vỡ do copy file hỏng không nha. Hoặc `RESTORE DATABASE VALIDATE;`
</details>

---

## ➡️ Bài tiếp theo
**Module 14: Vận Tải Xuyên Nền Tảng (Cross-Platform Data Transportation)**
Bạn sẽ học chiêu chuyển nhà, di dời nguyên cái Database đang cắm rễ ở Windows sang một cái máy chủ Linux mới cong, cách Convert kiến trúc cấu hình tệp tin sao cho tương thích Little-endian với Big-endian!

> Lab 18 là Lab rất đỉnh và vui vì được phép dùng lệnh đập sập Data `dd` của Linux. Anh luyện tay thật sướng vào nhé. Check qua file Module 13 em vừa báo cáo, xong rồi mình qua **Module 14** luôn ạ! 🚀


---

!!! info "Nguồn gốc"
    `dba_ai/oracle_rman/modules/module_13_guide.md`
