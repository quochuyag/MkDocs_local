---
title: '📘 Module 10: RMAN-Encrypted Backups'
course: 09-dba-ai
source: dba_ai/oracle_rman/modules/module_10_guide.md
---

# 📘 Module 10: RMAN-Encrypted Backups

> **Module**: 10/17
> **Phạm vi**: Bài 31 (Lý thuyết) & Bài 32 - Practice 10 (Thực hành)
> **Giảng viên**: Ahmed Baraka (Packt Publishing)
> **Thời gian học ước tính**: 1.5 giờ
> **Tiền điều kiện**: Đã hoàn thành Module 09 (Using RMAN Recovery Catalog)
> **Nguồn PDF**: `pdf_extracted/module_10/`

---

## 📑 Mục lục

- [Bài 31: Using RMAN-Encrypted Backups](#-bài-31-using-rman-encrypted-backups)
- [Bài 32: Practice 10 - Using RMAN-Encrypted Backups](#-bài-32-practice-10---using-rman-encrypted-backups)
- [Bảng tổng hợp Module 10](#-bảng-tổng-hợp-module-10)
- [Câu hỏi ôn tập tổng hợp](#-câu-hỏi-ôn-tập-tổng-hợp)

---

# 📖 Bài 31: Using RMAN-Encrypted Backups
> 📄 Nguồn: `Using RMAN-Encrypted Backups.pdf` — 17 slides

## 🎯 Mục tiêu bài học (Objectives)
Theo bài giảng gốc, sau bài này bạn sẽ học cách sử dụng 3 chế độ mã hóa (Encryption modes) trong RMAN Backups:
- ✅ **Transparent Encryption** (Mã hóa trong suốt bằng Keystore).
- ✅ **Password Encryption** (Mã hóa bằng mật khẩu).
- ✅ **Dual mode Encryption** (Mã hóa kép - kết hợp cả hai).

---

## 📋 Nội dung chính

### 1. Tổng quan về RMAN Encryption (Mã hóa RMAN) ⭐⭐

- Mục đích: Tạo ra các file backup được mã hóa (encrypted backup files) để bảo vệ chúng khỏi truy cập trái phép. (Đề phòng hacker hoặc ai đó copy trộm file backup và đem đi restore ở chỗ khác).
- **Yêu cầu hệ thống:**
  - Chỉ có mặt trên Oracle Database **Enterprise Edition**.
  - Parameter `COMPATIBLE` phải thiết lập là `10.2.0` trở lên.
  - Cần license tính năng **Oracle Advanced Security** (Tuy nhiên, được miễn phí license nếu backup lên Oracle Database Backup Cloud service).
- **Khác biệt:** Tính năng này độc lập và khác với Oracle Secure Backup (OSB) encryption.

---

### 2. Ba chế độ mã hóa của RMAN ⭐⭐⭐

#### A. Transparent Encryption (Mã hóa trong suốt)
- Sử dụng cấu hình TDE (Transparent Data Encryption). RMAN lấy **Key** (TDE key) trực tiếp từ một túi tiền (Keystore/Wallet).
- Vì sao gọi là "trong suốt"? Vì quá trình lấy Key từ Keystore diễn ra tự động ngầm.
- **Có 2 loại Keystore:**
  - *Autologin software keystore:* Luôn luôn "mở cửa". Không cần sự can thiệp của DBA (tuyệt vời cho việc chạy cronjob ban đêm tự động). ⚠️ Tuyệt đối không sao lưu file autologin cùng chỗ với file data backup.
  - *Password-based software keystore:* Cần DBA nhập lệnh mở thủ công trước khi có thể chạy việc backup mã hóa. (An toàn hơn, có thể sao lưu chung với file backup).
- Phù hợp nhất cho hệ thống **Day-to-day backups**.
- ⚠️ Cảnh báo: Tệp Backup sẽ VÔ DỤNG (không thể restore) nếu làm mất keystore.

#### B. Password Encryption (Mã hóa dùng Mật khẩu)
- Không dùng Keystore. Chỉ dựa vào Passsword.
- DBA cung cấp "mật mã" ngay lúc chạy lệnh Backup và cung cấp lại lúc chạy lệnh Restore.
- Phù hợp với: Các bản backup dùng 1 lần (One-off backups) đặc biệt là khi phải gửi sang location nằm ngoài Data Center (ví dụ: gửi dữ liệu cho đối tác hoặc trung tâm pháp y).
- ⚠️ Cảnh báo: Không thể restore nếu quên Password.

#### C. Dual Mode Encryption (Mã hóa Kép)
- Là sự kết hợp cực hay! Backup được tạo ra có thể giải mã bằng Keystore (tại On-site nội bộ) **HOẶC** giải mã bằng Password (khi gửi đi Offsite nơi không có Keystore).

---

### 3. Cấu hình Software Keystore (Chuẩn bị cho TDE)

**Bước 1:** Khai báo vị trí Keystore trong file `sqlnet.ora`.
```text
ENCRYPTION_WALLET_LOCATION =  
(SOURCE =
  (METHOD = FILE)  
  (METHOD_DATA =
    (DIRECTORY = /u01/app/oracle/orcl/kstore)
  )
)
```

**Bước 2:** Đăng nhập dưới quyền `SYSKM` (hoặc `SYSDBA`) và tạo Keystore.
```sql
-- Tạo Keystore loại Password-based:
SQL> ADMINISTER KEY MANAGEMENT CREATE KEYSTORE '/u01/app/oracle/orcl/kstore' IDENTIFIED BY oracle;

-- Tạo Keystore loại Auto-login từ Keystore ở trên (Tùy chọn):
SQL> ADMINISTER KEY MANAGEMENT CREATE AUTO_LOGIN FROM KEYSTORE '/u01/app/oracle/orcl/kstore' IDENTIFIED BY oracle;

-- Mở Keystore (với Password-based):
SQL> ADMINISTER KEY MANAGEMENT SET KEYSTORE OPEN IDENTIFIED BY oracle;

-- Tạo Master Encryption Key (Chìa khóa gốc):
SQL> ADMINISTER KEY MANAGEMENT SET KEY IDENTIFIED BY oracle WITH BACKUP USING 'bkp_key' ;
```

---

### 4. Bật Mã hóa trong RMAN ⭐⭐

#### A. Mức Persistent (Cấu hình cứng cho Transparent Encryption)
```sql
-- Mã hóa toàn bộ Database bằng Transparent
RMAN> CONFIGURE ENCRYPTION FOR DATABASE ON;

-- Chỉ mã hóa riêng Tablespace nhạy cảm
RMAN> CONFIGURE ENCRYPTION FOR TABLESPACE hr_data ON;

-- Thay đổi thuật toán mã hóa (Mặc định là AES128)
RMAN> CONFIGURE ENCRYPTION ALGORITHM 'AES256';
```

#### B. Mức Môi trường hiện tại / Session-level (Dùng Session hoặc Job)
Lệnh gõ ở dấu nhắc RMAN hoặc trong khối RUN {}:
```sql
-- Dành cho Transparent Encryption
RMAN> SET ENCRYPTION ON; 

-- Dành cho Password Encryption 
-- (Lưu ý chữ ONLY có nghĩa là CHỈ dùng Password, nếu không có ONLY thì thành Dual-mode)
RMAN> SET ENCRYPTION ON IDENTIFIED BY MyP@ssw0rd ONLY;

-- Dành cho Dual-Mode Encryption
RMAN> SET ENCRYPTION ON IDENTIFIED BY MyP@ssw0rd;
```

---

### 5. Những lưu ý Quan trọng (Considerations) ⭐
- ❌ RMAN Encryption **không hỗ trợ Image Copies**. Chỉ áp dụng cho định dạng **Backup Sets**.
- Sau mỗi lần tạo mới một file backup mã hóa, hệ thống sẽ sinh ra một Key mới.
- Quá trình mã hóa có tác động tiêu cực đến tốc độ ghi ổ cứng (tốn thêm CPU để mã hóa). Nếu hiệu năng là vấn đề, chỉ nên mã hóa riêng Tablespace chứa dữ liệu nhạy cảm hoặc tăng số lượng Channel lên chạy song song.

---
---

# 📖 Bài 32: Practice 10 - Using RMAN-Encrypted Backups
> 📄 Nguồn: `Practice 10 - Using RMAN-Encrypted Backups.pdf`

## 🎯 Mục tiêu thực hành
Làm quen ngay kỹ năng tạo mã hóa TDE và sau đó kích hoạt tạo Backup với đủ 3 phương pháp. Mọi cấu hình thực hiện trên DB `ORADB` tại appliance `srv1`.

> [!TIP]
> Hãy tạo Snapshot máy ảo trước khi bắt đầu bài tập này vì việc xử lý keystore có rủi ro tạo lỗi nếu làm sai các bước.

## 📋 Hướng dẫn từng bước

### Phần A: Cấu hình Transparent Data Encryption (TDE)

1. **Tạo thư mục chứa Keystore:** (Dưới quyền user oracle `os`)
```bash
$ mkdir /u01/app/oracle/oradata/ORADB/keystore
```

2. **Chỉ định vị trí vào file `sqlnet.ora`:**
```bash
$ vi $TNS_ADMIN/sqlnet.ora
```
Thêm dòng sau:
```text
ENCRYPTION_WALLET_LOCATION = 
 (SOURCE = 
 (METHOD = FILE) (METHOD_DATA = 
 (DIRECTORY = /u01/app/oracle/oradata/ORADB/keystore)))
```

3. **Truy cập Database và khởi tạo Keystore:**
```bash
$ sqlplus / as sysdba
```
```sql
-- Tạo Keystore file
SQL> ADMINISTER KEY MANAGEMENT CREATE KEYSTORE '/u01/app/oracle/oradata/ORADB/keystore' IDENTIFIED BY oracle;

-- Mở Keystore
SQL> ADMINISTER KEY MANAGEMENT SET KEYSTORE OPEN IDENTIFIED BY oracle;

-- Tạo Master Encryption Key
SQL> ADMINISTER KEY MANAGEMENT SET KEY IDENTIFIED BY oracle WITH BACKUP USING 'for_rman';
```
> 👉 *Lưu ý: Bạn có thể exit ra bash gõ lệnh `ls -al /u01/app/oracle/oradata/ORADB/keystore` để thấy file `ewallet.p12` vừa được sinh ra.*

---

### Phần B: Tạo bản Backup Mã hóa trong suốt (Transparent Mode)

1. Mở RMAN:
```bash
$ rman target /
```

2. Tạo backup đã được mã hóa:
```sql
RMAN> SET ENCRYPTION ON;
RMAN> BACKUP TABLESPACE users TAG 'ENCRYPTED_USERS';
```

3. Gõ `LIST BACKUPSET TAG 'ENCRYPTED_USERS';` bạn sẽ **không thấy** chỗ nào ghi là nó bị mã hóa. Phải query truy vấn V$VIEW để kiểm chứng:
```sql
SQL> SELECT S.RECID AS "BS_REC", P.RECID AS "BP_REC", P.ENCRYPTED 
     FROM V$BACKUP_PIECE P, V$BACKUP_SET S 
     WHERE P.SET_STAMP = S.SET_STAMP 
     AND P.SET_COUNT = S.SET_COUNT 
     AND P.TAG ='ENCRYPTED_USERS';
```
*(Cột `ENCRYPTED` sẽ trả về giá trị YES).*

4. **Trải nghiệm lỗi Wallet is not open:**
- Hãy Restart lại DB (Shutdown Immediate rồi Startup).
- Thử kết nối RMAN chạy lại lệnh Backup ở bước 2.
- 🔴 Lỗi nhận được: `ORA-28365: wallet is not open`.
- Lý do: Tùy chọn Keystore mặc định yêu cầu bạn mở thủ công mỗi khi Database khởi động lại.
- Xử lý mở lại: `RMAN> sql 'ADMINISTER KEY MANAGEMENT SET KEYSTORE OPEN IDENTIFIED BY oracle';`

5. **Giải quyết bằng Auto-Login Keystore:**
Trưởng hợp bạn chạy RMAN qua con bot (cron), sẽ không có ai ngồi trực để gõ lệnh Open Wallet, bạn cần tạo tính năng Auto-Login Keystore.
```sql
SQL> ADMINISTER KEY MANAGEMENT CREATE AUTO_LOGIN KEYSTORE FROM KEYSTORE '/u01/app/oracle/oradata/ORADB/keystore' IDENTIFIED BY oracle;
```
*(Bây giờ trong thư mục sẽ có thêm file `cwallet.sso`. Từ giờ bạn thoải mái restart DB xong vào RMAN backup luôn, không sợ ORA-28365 nữa).*

---

### Phần C: Tạo bản Backup Mã hóa Mật khẩu (Password Mode)

```sql
RMAN> SET ENCRYPTION ON IDENTIFIED BY Orapass123 ONLY; 
RMAN> BACKUP TABLESPACE users TAG 'PENCRYPTED_USERS';
```
*(Hãy để ý từ khóa `ONLY`. Nó mang ý nghĩa file bkp được sinh ra sẽ chỉ có thể dùng được nếu như người mở biết Password Orapass123. TDE Keystore bị phớt lờ, do đó mang file backup này vứt sang nhà bạn thân, bạn thân vẫn restore được như bình thường nếu có pass).*

---

### Phần D: Tạo bản Backup Mã hóa Kép (Dual-mode)

```sql
RMAN> SET ENCRYPTION ON IDENTIFIED BY Orapass123; 
RMAN> BACKUP TABLESPACE users TAG 'DENCRYPTED_USERS';
```
*(Tuyệt vời. Tháo chữ ONLY ra và bạn được quyền sử dụng cả 2 chế độ. Người nhà dùng `Keystore` để tự động khôi phục. Người ngoài nhà đem bản này đi nhưng có được mật khẩu thì cũng tự khôi phục được bằng password.)*

> **Dọn dẹp sau bài học:**
> `DELETE NOPROMPT BACKUPSET TAG 'ENCRYPTED_USERS';`
> `DELETE NOPROMPT BACKUPSET TAG 'PENCRYPTED_USERS';`
> `DELETE NOPROMPT BACKUPSET TAG 'DENCRYPTED_USERS';`


---

# 📊 Bảng tổng hợp Module 10

| Tính năng / Lệnh | Ý nghĩa kỹ thuật | Lấy Key từ đâu? | Nơi sử dụng |
|------------------|------------------|----------------|-------------|
| **Transparent Encryption** | Backup ngầm tự động mã hóa | TDE Keystore | Backup hàng ngày, On-site |
| **Password Encryption** (có chữ ONLY) | Mã hóa chỉ dựa vào mật khẩu | Password gõ bằng tay | Backup một lần gửi đi xa (Off-site) |
| **Dual Mode Encryption** | Mã hóa 2 ngã | TDE Keystore **Hoặc** Password | Nhu cầu lai (vừa back onsite vừa đi offsite) |
| `sqlnet.ora` (`ENCRYPTION_WALLET_LOCATION`)| Cấu hình báo cho DB biết đường dẫn thư mục lưu ví mã hóa | | Hệ thống mạng hạ tầng |
| `ADMINISTER KEY MANAGEMENT...` | Bộ Lệnh quản trị Keystore mới của Oracle (còn gọi là TDE) | | SQL*Plus sysdba |
| `SET ENCRYPTION ON;` | Lệnh RMAN kích hoạt Transparent | | RMAN Prompt |
| `SET ENCRYPTION ON IDENTIFIED BY pass [ONLY];`| Lệnh RMAN kích hoạt Dual Mode / [Password] | | RMAN Prompt |

---

# 🎯 Câu hỏi ôn tập tổng hợp

**1. Điều gì sẽ xảy ra nếu file Backup chứa thông tin quan trọng được cấu hình lấy chế độ Password Encryption bằng chữ `ONLY` và người quản trị quên mật khẩu?**
<details>
<summary>💡 Đáp án</summary>
DBA đó hoàn thành vé lấy xe đi về! 
Với Password Encryption, Keystore sẽ không được sử dụng. Hoàn toàn phụ thuộc vào đoạn Text. Mất Text => Mất bản Backup mãi mãi. Không có backdoor nào cho việc này.
</details>

**2. RMAN cho phép mã hóa tài nguyên nào và từ chối mã hóa định dạng backup nào?**
<details>
<summary>💡 Đáp án</summary>
RMAN chỉ chấp nhận mã hóa các file định dạng **Backup Sets**. Mọi định dạng nguyên gốc như **Image Copy** đều sẽ không được mã hóa.
</details>

**3. Vì sao Oracle cảnh báo KHÔNG copy chung file Auto-login (*.sso) sang hệ thống Tape Backup cùng lúc với dữ liệu?**
<details>
<summary>💡 Đáp án</summary>
Vì bản chất của việc mã hóa trên hệ thống Database là "Khóa tủ" để người sao chép trộm dữ liệu cũng chẳng xài được. Nếu gửi gắm file khóa `.sso` (Autologin - chìa khóa vạn năng tự động mở) đi chung với file Backup giống việc ghi Password chung với thẻ ATM. Hacker nẫng được cả cụm Data + `.sso` sẽ ung dung restore ra xài ở một DB mới bằng phương pháp Transparent.
</details>

---

## ➡️ Bài tiếp theo

**Module 11: Cross-Platform Transport**
- Bài 33 & 34: Giới thiệu cách di chuyển dữ liệu chéo nền tảng (Ví dụ: Chạy từ Solaris sang Linux, Windows sang Linux) & Cross-Platform Transportable Tablespace.
- Bài 35: Practice 11 — Thực hành dời nhà cho Tablespace.

> Bạn đã sẵn sàng để tiếp tục với **Module 11** về chiêu chuyển gốc hệ điều hành chéo chưa? 🚀 Hoặc nếu bạn muốn, mình có thể thảo luận sâu hơn về cách kết hợp TDE và RMAN trên hạ tầng thực tế.


---

!!! info "Nguồn gốc"
    `dba_ai/oracle_rman/modules/module_10_guide.md`
