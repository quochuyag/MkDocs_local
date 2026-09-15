---
title: '📘 Module 09: Chinh phục Bộ Đĩa Trung Tâm (RMAN Recovery Catalog)'
course: 09-dba-ai
source: dba_ai/oracle_rman/modules/module_09_guide.md
---

# 📘 Module 09: Chinh phục Bộ Đĩa Trung Tâm (RMAN Recovery Catalog)

> **Phạm vi**: Bài 28 - 30 (Using RMAN Recovery Catalog & Practice 9)
> **Thời gian học ước tính**: 3 giờ
> **Tiền điều kiện**: Hiểu giới hạn trí nhớ Controlfile, cách Backup Archival (Module 08) cần tủ lưu Metadata dài dòng.

---

## 📑 Mục lục
- [Bài 28-29: Giới thiệu & Định cấu trúc RMAN Recovery Catalog](#-bài-28-29-giới-thiệu--định-cấu-trúc-rman-recovery-catalog)
- [Bài 30: Thực hành (Practice 9) Quản trị Catalog](#-bài-30-thực-hành-practice-9-quản-trị-catalog)
- [Bảng tổng hợp & Cú pháp](#-bảng-tổng-hợp--cú-pháp)
- [Câu hỏi ôn tập tổng hợp](#-câu-hỏi-ôn-tập-tổng-hợp)

---

# 📖 Bài 28-29: Giới thiệu & Định cấu trúc RMAN Recovery Catalog

## 🎯 Mục tiêu bài học
Sau khi hoàn thành bài này, bạn sẽ:
- ✅ Đặc tả rõ điểm khác biệt và nhược điểm "Brain-Dead" (Trí nhớ 365 ngày tối đa) của Control File so với sức mạnh Recovery Catalog.
- ✅ Tự tay Design 1 DataBase trung tâm (Catalog DB) - gán quyền RC_OWNER.
- ✅ Đăng kí (Register) các Target Database con vào Mạng lưới mẹ Catalog Repository.
- ✅ Đồng bộ thủ công (Resync) qua 2 cơ chế Partial/Full và Nạp lại File mất mát (Catalog command).
- ✅ Thiết lập các hệ mã kịch bản tự động ngầm tĩnh Stored Scripts (Local, Global) chạy cho muôn đời con cháu.

## 💡 Ý tưởng cốt lõi (Memory Hack)
- RMAN xưa nay có "Bầu não" lưu siêu dữ liệu gọi là **Target Control File**. (Tức DataBase của bạn lưu thông tin Backup CỦA CHÍNH NÓ). Nghĩa là: Database bạn (Target) tự sát chết cháy, Control File khét lẹt -> RMAN mất não. Bạn rất cực khổ để kéo Controlfile lại từ tay trắng.
- **Recovery Catalog** là "Gửi não đi DataCenter": Bạn lấy một cái Database ORAWIN (Server tách biệt vật lý) làm Trụ sở chính (Catalog). Database ORADB (Con) hằng ngày khai báo thành tích vào đó. 
- ORADB chết? Không sao, ORAWIN vẫn sống 100% cầm bản đồ cứu nó nhẹ như tên bay! Tương lai: ORAWIN sẽ quản trị hàng loạt 50 con DB ORADB1, ORADB2... ở khắp nơi!

---

## 📋 Nội dung chính

### 1. Cuộc chiến lưu trữ Metadata: Control File vs Recovery Catalog

| Đặc tính sinh tồn | **Database Control File (Local Mode)** | **Recovery Catalog (DB Độc Lập)** |
|----------|-----------------------|------------|
| Điểm mạnh lớn nhất | Miễn phí, sẵn có mặc định, dễ quản trị (không cần DB rời). | Quản lý **Hàng Trăm Target Databases** trên 1 chỗ thống nhất. |
| Thời gian nhớ (Memory Time) | Bị giới hạn vĩnh viễn bởi tham số `CONTROL_FILE_RECORD_KEEP_TIME` (Tối đa < 365 ngày). Quá chừng đó nó quên! | Sổ sách ghi chép **Vô cực** (Nếu đĩa còn chứa nổi). Thoải mái lưu Keep Forever 10 năm. |
| Tính năng Script Ngầm | ❌ Không hỗ trợ Code Stored Scripts. | ✅ Có hỗ trợ Local và Global Stored Scripts. |
| Lưu lịch sử cấu trúc tĩnh | ❌ Không lưu Schema (Lịch sử Add Datafiles). | ✅ Biết Database năm xưa có bao nhiêu Datafiles qua lệnh `REPORT SCHEMA AT TIME`. |

> [!CAUTION]
> Best Practice Doanh nghiệp lớn: **Không bao giờ đè bẹp hệ thống bằng việc đặt Recovery Catalog trên chính con Database Production!** Target và Catalog phải xa nhau về mặt vật lý (Khác Zone, Server, SAN). Nếu máy nổ, 2 con nổ chung thì xài Catalog làm chi?

### 2. Hành trình kiến thiết Hệ thống Catalog (3 Bước Bắt Buộc)

Bạn đang ở Server 2 (Một máy tính Oracle trinh trắng để làm Trụ sở):
```sql
-- B1. Tạo riêng 1 Tablespace lưu hồ sơ và Account đại Boss:
SQL> CREATE TABLESPACE rcat_tbs DATAFILE '/oradata/rcat.dbf' SIZE 15M;
SQL> CREATE USER rcowner IDENTIFIED BY cat_pwd DEFAULT TABLESPACE rcat_tbs;

-- B2. Ban lệnh Bài tối thượng từ Oracle để Account này cầm ấn giám:
SQL> GRANT RECOVERY_CATALOG_OWNER TO rcowner;

-- B3. Gọi RMAN tạo Data Dictionary tĩnh mảng bám lên Account này:
[oracle@srv2]$ rman target /       -- (Khoan log target if not local)
RMAN> CONNECT CATALOG rcowner/cat_pwd@catdb
RMAN> CREATE CATALOG;
```
Ngôi vương Catalog đã thành hình vĩnh viễn! 👑

### 3. Đăng ký & Giải thủ công (Register và Resync) ⭐⭐⭐

Bây giờ về con Database Production nhỏ bé của bạn (OracleDB), gọi RMAN kết nối song song cả mình (`TARGET`) và Sếp (`CATALOG`).

**Lệnh Đăng ký:**
```sql
[oracle@srv1]$ rman TARGET / CATALOG rcowner/cat_pwd@catdb
RMAN> REGISTER DATABASE;
-- Kể từ giờ phút này phút này, Control File của ORADB đã đồng bộ với Sếp.
```

Nhưng khoan, Database mẹ đâu phải thần thánh mà biết mọi thay đổi Real-time (Thời gian thực)? Nếu bạn đổi đường truyền mạng và thêm 1 File, Control File ghi nhớ nhanh, mẹ chưa biết! Phải báo cáo thủ công ngay:
**Lệnh RMAN cấu hình bù lại:**
```sql
RMAN> RESYNC CATALOG;
```
*(Nếu bạn thỉnh thoảng mới backup (1 tháng/ 1 lần) hay vừa cấy thêm Tablespace, làm ơn Gõ lệnh này ngay!)*.

### 4. Thuật triệu hồi lệnh CATALOG: Cứu Datafile hoang ngoài Đĩa Vật Lý

Admin công ty lén giấu 1 mớ file Backup OS Copy từ máy A qua máy B mà RMAN không hề hay biết (Do xài Terminal OS Command `cp` / `mv`). 
RMAN chỉ quản lý những gì ở trong RMAN. Muốn nó nhận diện Data hoang này, phải khai sáng (Thêm vào Metadata bằng tay). 

**Lệnh CATALOG triệu hồn:**
```sql
-- Dẫn đường cho RMAN vô thư mục ăn trộm đó bóc file vô lại hệ thống 
RMAN> CATALOG START WITH '/fs1/datafiles_nhap_lau/';  -- Đọc hết đống file này đi!

-- Nhồi riêng 1 file nhỏ lạc bầy 
RMAN> CATALOG BACKUPPIECE '/disk2/mat_lien_lac_01.bkp';

-- Hay kể cả chỉ điểm đống Archive Log lượm đc:
RMAN> CATALOG ARCHIVELOG '/disk1/arch_logs/archive1_731.log';
```

### 5. Stored Scripts: Tự động hóa "Có Lưu Bộ Nhớ" thay vì File `.sh`

Nếu bạn phải dùng hàng loạt dòng lệnh phức tạp dài ngoằn, RMAN cho bạn lưu code vô Database Catalog. Không lo Admin xóa nhầm script file Bash `.sh` hay `.bat` trong thư mục OS gốc nữa!
Bao gồm Local Script (Cho con Node Register) và Global Script (Tất cả anh em Register đều truy xuất được).

**Tạo Script Mèo Méo:**
```sql
RMAN> CREATE GLOBAL SCRIPT global_full_backup 
   COMMENT 'Chuan Full DB va Delete Obsolete Toàn tập' 
   { 
     BACKUP DATABASE PLUS ARCHIVELOG;
     DELETE OBSOLETE;
   }
-- (Mật mã lưu trữ đã chui tọt vào Server Catalog. Trộm xóa Bash.sh bên OS bằng niềm tin).

-- Kêu RMAN nôn script ra chạy:
RMAN> RUN { EXECUTE GLOBAL SCRIPT global_full_backup; }
```

---

# 💻 Bài 30: Thực hành (Practice 9) Quản trị Catalog

> **Mục tiêu**: Xây bộ RMAN Catalog với 2 Virtual Machine độc lập (SRV1 làm Target, WINSRV2 làm Catalog). Thử thách tạo đống file giấu vào Share Folder, rồi Catalog triệu hồn chúng nó lại rực rỡ! Xài Stored Script có chứa Biến.

## Tình huống 1: Mở khóa Kênh RMAN 2 Ống Pointers
RMAN có khả năng vừa target vào con Local, vừa nhòm qua Mạng WAN kết nối Catalog Database tít tận xa. Cú pháp móc ống:
```bash
# Ở máy SRV1, lệnh RMAN thần tốc:
rman target "'/ as SYSBACKUP'" catalog rc_owner/oracle@orawin
# Lúc này RMAN đã có Target (Local) và Catalog (orawin network).

RMAN> REGISTER DATABASE;
# Kết nối máu mủ hình thành!
```

## Tình huống 2: Sức mạnh CATALOG Nhận Diện Của Rơi vãi 
Giả sử ta ra ngoài Hệ điều hành OS, chớp nhoáng tạo 1 folder rồi copy BackupSet lén lút qua. Sau đó xóa gốc đi.
```bash
HOST 'mkdir /media/sf_extdisk/backup_cua_roi';
HOST 'cp /u01/app/.../*.bkp /media/sf_extdisk/backup_cua_roi/';
```
RMAN bị đứt kết nối dây cương, hỏi nó ko ra. Ta cứu bằng tay 1 nháy duy nhất!
```sql
RMAN> CATALOG START WITH '/media/sf_extdisk/backup_cua_roi/'; 
# Hệ thống dò quét và hỏi Yes/No -> Quả bom rớt trúng mặt, nhận về Inventory RMAN! Quá ghê!
```

## Tình huống 3: Lập trình Biến `&1, &2` trong Stored Script
Scripting không tĩnh, có tham số. RMAN không thua gì Terminal Shell!
```sql
RMAN> CREATE SCRIPT tbs_full_script 
{ BACKUP TABLESPACE &1 TAG &2 ; } 
--- Đang nhập input parameters ngầm ảo!

# Bơm dữ liệu vào mồm Script khi Execution:
RMAN> RUN { EXECUTE SCRIPT tbs_full_script USING USERS 'USERS_BKP_OCTOBER'; }

# Hoặc bơm từ ngoài môi trường đen OS không thèm văng vào prompt báo danh!
[oracle@srv1]$ rman target / catalog rc_owner@orawin script=tbs_full_script USING USERS 'CMD_BKP'
```

---

# 📊 Bảng tổng hợp & Cú pháp

| Mã lệnh Hủy Diệt | Chức năng cốt lõi (Cứu thế hệ) | Điểm mù |
|----------|-------------------|--------------------------------------|
| Khởi tạo `CREATE CATALOG` | Đóng cái móng cho Nhà Trụ sở | Bắt buộc login bằng user được GRANT Role Recovery_Catalog_owner. Bị từ chối nếu user thường. |
| Kết nối `REGISTER DATABASE` | Buộc dây thừng Target vào Trụ sở | Gọi sai Target (Lộn qua con Catalog) sẽ dẫn đến lỗi cực lớn. |
| Đồng bộ `RESYNC CATALOG` | Đồng bộ dữ liệu tĩnh (Add DB files/ Logs) | Cần chạy bằng tay ngay nếu thay đổi cấu trúc Tablespace/Network file mà Database chưa kịp Auto-Resync. |
| Triệu hồi `CATALOG START WITH` | Phát hiện tệp rác rải rác ngoài thư mục OS đưa vô Quỹ đọa Control File | Khi gõ đuôi thư mục `/` nó hốt hết cả đống file vô tội vạ. Hãy tạo riêng rẽ folder sạch sẽ Backup Archive chứa tụi nó. |
| Bơm tham số Variable `EXECUTE SCRIPT xyz USING ...` | Truyền biến động mượt như Bash Script | Lùi vị trí param không đúng biến `&1`, `&2` có nguy cơ hỏng lệnh động nghiêm trọng. |

---

# 🎯 Câu hỏi ôn tập tổng hợp

1. Nếu hệ thống mạng Internet đột ngột bứt gãy, RMAN (nằm trên Target DB) không thể nói chuyện với máy chủ Oracle Catalog mệ mỏi. Job Backup Nightly lúc đó dùng RMAN có bị lỗi chập khựng và dừng mẹ ngang hông không? Tại sao? (Tricks: Nguyên lý Fallback Memory).
2. Hãy giải thích ý nghĩa tham số thời gian cực kỳ chết chóc mang tên `CONTROL_FILE_RECORD_KEEP_TIME`? Nếu doanh nghiệp yêu cầu lưu giữ Backups tận 12 tháng, nhưng tham số này trên hệ thống chỉ là 30 ngày, và công ty KHÔNG xài Recovery Catalog. Thảm họa ORA gì sẽ xảy ra vào khoảnh khắc cần restore lúc tháng thứ 10?
3. Lênh `CATALOG START WITH '+disk'` áp dụng trên Database cấu hình ASM (Automatic Storage Management). RMAN sẽ làm gì với cấu trúc này, quét toàn cục bộ ASM để chọc vào file ảo phải không?
4. Đâu là định dạng cấu trúc đúng nếu tui muốn tạo 1 biến Stored Script chạy dạo quanh vương quốc 500 con Database khác nhau thay vì chỉ gắn chặt với Database ID môt chỗ? 
(Gợi ý: Tìm chữ G!).

---
## ➡️ Bài tiếp theo
Xin chúc mừng sự nỗ lực kiên cường cắm trại liên tục! Catalog quyền uy là chìa khóa vô hạn để thao túng thời gian thực 10 năm của Oracle Data.
Nhưng... Nếu Băng Từ Backup của bạn rớt trên đường vận chuyển, Kẻ thủ ác đem cắm vào máy tính khác đọc xuyên data khách hàng của bạn thì sao? Khóa đuôi an ninh cho Hệ thống Backups là tuyệt đối bắt buộc với: **Module 10: Using RMAN-Encrypted Backups** (Giáp chống tin tặc!). 🚀 

Bạn muốn ôn lại cái lệnh biến ảo `&1`, `&2` hay bạn muốn đi cài Tường lửa mã hóa Encrypted Backups ngay nào?


---

!!! info "Nguồn gốc"
    `dba_ai/oracle_rman/modules/module_09_guide.md`
