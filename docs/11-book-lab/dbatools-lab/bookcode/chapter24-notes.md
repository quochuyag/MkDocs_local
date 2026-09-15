---
title: Chapter 24 — Certificates, Network Encryption & Database Encryption
course: 11-book-lab
source: book_lab/dbatools-lab/bookcode/chapter24.notes.md
---

# Chapter 24 — Certificates, Network Encryption & Database Encryption

> **Cảnh báo MẠNH:** Chapter này thao tác lên **certificate store của OS** và **bật mã hoá DB (TDE)**. Hậu quả nếu sai:
> - `Enable-DbaForceNetworkEncryption` cấu hình bắt buộc TLS — client cũ có thể **không kết nối được**.
> - `Start-DbaDbEncryption` (TDE) ghi **master key + certificate + DEK** — **mất certificate = mất DB**. Phải `Backup-DbaDbMasterKey` và `Backup-DbaDbCertificate` ngay sau khi tạo.
> - Đổi SPN sai có thể phá Kerberos toàn instance.
> Lab chỉ làm trên `dbatoolslab\sql2017` (đơn lẻ), KHÔNG chạy trên prod.

## Mục tiêu
- Sinh self-signed cert cho SQL Server (`New-DbaComputerCertificate`) hoặc CSR (`New-DbaComputerCertificateSigningRequest`).
- Gán cert vào instance bằng `Set-DbaNetworkCertificate`, bật force encryption.
- Cấu hình Extended Protection, SPN, hide instance.
- Bật/tắt TDE toàn bộ user DB bằng `Start-DbaDbEncryption`/`Stop-DbaDbEncryption`/`Disable-DbaDbEncryption`.
- Tạo + backup database master key & certificate cho **encrypted backup**.
- Test 1 file `.bak` có phải backup mã hoá không (`Test-DbaBackupEncrypted`).

## Tóm tắt 3-5 ý chính
1. **3 lớp mã hoá khác nhau:**
   - **Connection encryption** (TLS): cert ở Windows cert store, gán qua `Set-DbaNetworkCertificate`.
   - **TDE** (data at rest): cert ở `master` DB, áp lên user DB.
   - **Encrypted backup**: cert riêng dùng tham số `EncryptionCertificate` của `Backup-DbaDatabase`.
2. **Self-signed cert OK cho dev/lab**, prod thường lấy cert từ CA → dùng `New-DbaComputerCertificateSigningRequest`.
3. **Phải backup master key + certificate NGAY** sau khi tạo, lưu chỗ an toàn — mất là mất DB.
4. **`Test-DbaSpn` + `Set-DbaSpn`** giúp khắc phục lỗi Kerberos (đăng nhập domain bị ép NTLM).
5. **`Enable-DbaHideInstance`** + custom port (`Connect-DbaInstance -SqlInstance host:port`) là 2 chiêu giảm bề mặt tấn công.

## Giải thích từng đoạn code

### Đoạn 1: dòng 18-22 — sinh self-signed cert cho máy
```powershell
$splatCert = @{
    ComputerName = "sql1"
    Dns = "sql1.ad.local", "sql1"
}
New-DbaComputerCertificate $splatCert
```
- **Ý nghĩa:** Tạo cert trong Windows cert store của máy `sql1`, SAN gồm `sql1.ad.local` và `sql1`.
- **Đổi cho lab:** `ComputerName = 'dbatoolslab'`, `Dns = 'dbatoolslab', 'dbatoolslab.lab.local'` (đổi domain hợp môi trường).
- **Lưu ý:** Cần chạy as Admin để ghi vào LocalMachine store.

### Đoạn 2: dòng 27-31 — sinh CSR để gửi CA
```powershell
$splatCSR = @{
    ComputerName = "sql1"
    Dns = "sql1.ad.local", "sql1"
}
New-DbaComputerCertificateSigningRequest $splatCSR
```
- **Ý nghĩa:** Sinh CSR (Certificate Signing Request) `.req` để gửi lên Active Directory CA / public CA.
- **Đổi cho lab:** Như đoạn 1.

### Đoạn 3: dòng 36 — list cert đang có
```powershell
Get-DbaComputerCertificate -ComputerName sql1
```
- **Đổi cho lab:** `Get-DbaComputerCertificate -ComputerName dbatoolslab`.

### Đoạn 4: dòng 41-45 — gán cert vào SQL bằng thumbprint
```powershell
$splatSetCertificate = @{
    SqlInstance = "sql1"
    Thumbprint = "1245FB1ACBCA44D3EE9640F81B6BA14A92F3D6E2"
}
Set-DbaNetworkCertificate @splatSetCertificate
```
- **Ý nghĩa:** Ghi registry để SQL Service dùng cert này khi setup TLS.
- **Đổi cho lab:** `SqlInstance = 'dbatoolslab\sql2017'`, `Thumbprint` lấy từ đoạn 3.
- **Lưu ý:** **Phải restart SQL Service** mới có hiệu lực.

### Đoạn 5: dòng 49-50 — pick cert từ GridView rồi gán
```powershell
Get-DbaComputerCertificate | Out-GridView -PassThru |
    Set-DbaNetworkCertificate -SqlInstance sql1
```
- **Đổi cho lab:** Đổi `sql1` → `dbatoolslab\sql2017`. GridView không có trong devcontainer.

### Đoạn 6: dòng 54 — bật bắt buộc mã hoá
```powershell
Enable-DbaForceNetworkEncryption -SqlInstance sql1
```
- **Cảnh báo MẠNH:** Client cũ (TLS 1.0/1.1, driver outdate) sẽ không connect được.
- **Đổi cho lab:** `Enable-DbaForceNetworkEncryption -SqlInstance dbatoolslab\sql2017`. Restart service.

### Đoạn 7: dòng 58 — Extended Protection
```powershell
Set-DbaExtendedProtection -SqlInstance sql1 -Value Required
```
- **Ý nghĩa:** Chống relay attack trên kết nối Windows auth.
- **Đổi cho lab:** Đổi instance, value: `Off | Allowed | Required`. Lab nên dùng `Allowed` để tránh khoá client.

### Đoạn 8: dòng 62 — kiểm SPN
```powershell
Test-DbaSpn -ComputerName sql1
```
- **Ý nghĩa:** Liệt kê SPN cần có vs đã đăng ký trong AD.

### Đoạn 9: dòng 67-69 — auto-register SPN còn thiếu
```powershell
Test-DbaSpn -ComputerName sql1 |
    Where-Object isSet -eq $false  |
    Set-DbaSpn
```
- **Cảnh báo:** Cần quyền `Write servicePrincipalName` trên AD account — thường là Domain Admin.

### Đoạn 10: dòng 73 — ẩn instance khỏi browser
```powershell
Enable-DbaHideInstance -SqlInstance sql1
```
- **Ý nghĩa:** Stop SQL Browser broadcast — client phải biết tên/port chính xác.

### Đoạn 11: dòng 77-81 — connect bằng port custom
```powershell
Connect-DbaInstance -SqlInstance sql01:12345
Connect-DbaInstance -SqlInstance "sql01,12345"
Connect-DbaInstance -SqlInstance sql01:12345
```
- **Ý nghĩa:** Cả `host:port` và `host,port` đều OK — dbatools chuẩn hoá.

### Đoạn 12: dòng 85-94 — start TDE toàn instance
```powershell
$masterkeypass = (Get-Credential nobody).Password
$certbackuppass = (Get-Credential nobody).Password
$splatEncrypt = @{
        SqlInstance             = "sql1"
        MasterKeySecurePassword = $masterkeypass
        BackupSecurePassword    = $certbackuppass
        BackupPath              = "/tmp"
        AllUserDatabases        = $true
    }
Start-DbaDbEncryption @splatEncrypt
```
- **Ý nghĩa:** Tạo master key + cert + DEK + bật encryption cho **tất cả user DB**, backup cert ra `/tmp`.
- **Đổi cho lab:** `SqlInstance = 'dbatoolslab\sql2017'`, `BackupPath = 'C:\dbatoolslab\Encryption'`.
- **Cảnh báo MẠNH:** Mất `BackupPath` = mất DB. Sao lưu `BackupPath` ra ngoài máy.

### Đoạn 13: dòng 98-106 — TDE chọn DB cụ thể
```powershell
$masterkeypass = (Get-Credential nobody).Password
$certbackuppass = (Get-Credential nobdody).Password   # NOTE: typo trong sách
$splatdbEncrypt = @{
        MasterKeySecurePassword = $masterkeypass
        BackupSecurePassword    = $certbackuppass
        BackupPath              = "/tmp"
    }
Get-DbaDatabase -SqlInstance sql1 -Database db1, db2, db3 |
    Start-DbaDbEncryption @splatdbEncrypt
```
- **Lưu ý:** Có typo `nobdody` ở sách — không sai logic vì chỉ là tên dummy cho prompt credential.
- **Đổi cho lab:** `Get-DbaDatabase -SqlInstance dbatoolslab\sql2017 -Database AdventureWorks2017 | Start-DbaDbEncryption ...` (chỉ làm trên DB test).

### Đoạn 14: dòng 110 — stop encryption (giữ cấu hình)
```powershell
Stop-DbaDbEncryption -SqlInstance sql1
```
- **Ý nghĩa:** Tạm dừng quá trình encrypt nếu đang chạy dở.

### Đoạn 15: dòng 114 — disable TDE
```powershell
Disable-DbaDbEncryption -SqlInstance sql1 -Database db1, db2, db3
```
- **Ý nghĩa:** Tắt TDE → giải mã ngược lại. Mất I/O.
- **Đổi cho lab:** Đổi instance + tên DB lab.

### Đoạn 16: dòng 118-125 — tạo + backup master key cho `master`
```powershell
$securepass = (Get-Credential doesntmatter).Password
$params = @{
    SqlInstance = "sql1"
    Database = "master"
    SecurePassword = $securepass
}
New-DbaDbMasterKey @params
Backup-DbaDbMasterKey @params
```
- **Ý nghĩa:** Master key của `master` DB là gốc bảo vệ cert dùng cho TDE & encrypted backup.

### Đoạn 17: dòng 129-137 — tạo + backup cert cho backup
```powershell
$splatCert = @{
    SqlInstance = "sql1"
    Database = "master"
}
New-DbaDbCertificate @splatCert -Name BackupCert

$splatCert.EncryptionPassword = $securepass
Backup-DbaDbCertificate @splatCert -Certificate BackupCert
```
- **Ý nghĩa:** Cert dùng cho `Backup-DbaDatabase -EncryptionCertificate`. Phải backup cert ra file.

### Đoạn 18: dòng 141-149 — backup mã hoá AES192
```powershell
$backupparam = @{
    SqlInstance = "sql1"
    Database = "master"
    FilePath = "c:\backups"
    EncryptionAlgorithm = "AES192"
    EncryptionCertificate = "BackupCert"
}

Backup-DbaDatabase @backupparam
```
- **Đổi cho lab:** `SqlInstance = 'dbatoolslab\sql2017'`, `Database = 'AdventureWorks2017'`, `FilePath = 'C:\dbatoolslab\Backup'`.
- **Lưu ý:** `Database = "master"` chỉ ví dụ — trong lab nên test trên DB user.

### Đoạn 19: dòng 153-157 — test backup có mã hoá không
```powershell
$splatReadBackup = @{
    SqlInstance = "sql1"
    FilePath = "C:\backups\myEncryptedDatabaseBackup.bak"
}
Test-DbaBackupEncypted @splatReadBackup
```
- **Lưu ý:** Tên lệnh ở sách thiếu `r`: `Test-DbaBackupEncypted` (typo trong dbatools cũ). Phiên bản mới có thể là `Test-DbaBackupEncrypted`. Check `Get-Command Test-DbaBackup*`.

### Đoạn 20: dòng 162-166 — test 1 backup không mã hoá
```powershell
$splatReadBackup = @{
    SqlInstance = "sql1"
    FilePath = "S:\backups\myDatabaseBackup.bak"
}
Test-DbaBackupEncypted @splatReadBackup
```

## Lệnh thay vào lab của bạn

```powershell
$inst = 'dbatoolslab\sql2017'
$backupDir = 'C:\dbatoolslab\Backup'
$encDir = 'C:\dbatoolslab\Encryption'
New-Item -ItemType Directory -Force -Path $encDir | Out-Null

# 1) Tạo master key + cert phục vụ encrypted backup (an toàn cho lab)
$pw = ConvertTo-SecureString 'LabPass!2024' -AsPlainText -Force
New-DbaDbMasterKey -SqlInstance $inst -Database master -SecurePassword $pw -Confirm:$false
Backup-DbaDbMasterKey -SqlInstance $inst -Database master -SecurePassword $pw -Path $encDir

New-DbaDbCertificate -SqlInstance $inst -Database master -Name LabBackupCert
Backup-DbaDbCertificate -SqlInstance $inst -Database master -Certificate LabBackupCert `
    -EncryptionPassword $pw -Path $encDir

# 2) Backup mã hoá AdventureWorks2017
Backup-DbaDatabase -SqlInstance $inst -Database AdventureWorks2017 `
    -Path $backupDir -EncryptionAlgorithm AES256 -EncryptionCertificate LabBackupCert `
    -CompressBackup

# 3) Test xem file mới có thật là encrypted không
$lastBak = Get-ChildItem $backupDir -Filter '*AdventureWorks2017*.bak' |
    Sort LastWriteTime -Desc | Select -First 1
Test-DbaBackupEncrypted -SqlInstance $inst -FilePath $lastBak.FullName
# (nếu version dbatools cũ: Test-DbaBackupEncypted)

# 4) (Tuỳ chọn) liệt kê cert SQL nội bộ
Get-DbaDbCertificate -SqlInstance $inst -Database master
```

## Self-check (3 câu)
1. **Định nghĩa:** Phân biệt 3 lớp mã hoá: connection (TLS), TDE, encrypted backup — chúng dùng cert nào ở đâu?
2. **Thực hành:** Sau `New-DbaDbCertificate`, nếu bạn QUÊN `Backup-DbaDbCertificate` rồi DB bị hỏng — restore được không? Tại sao?
3. **Liên hệ:** Khác biệt giữa `Enable-DbaForceNetworkEncryption` và `Start-DbaDbEncryption` là gì? Cái nào có thể làm rớt connection ngay?

## Bài tập mở rộng
- **Bài 1:** Viết script `Backup-LabEncryptionAssets` zip toàn bộ `$encDir` (master key + cert) thành file `.zip` mã hoá và copy ra ổ ngoài. (Mục đích: kỷ luật backup cert.)
- **Bài 2:** Bật TDE cho 1 bản clone của `WideWorldImporters`, đo I/O `Get-DbaIoLatency` trước/sau khi encrypt.
- **Bài 3:** Tạo CSR bằng `New-DbaComputerCertificateSigningRequest`, mở file `.req` xem nội dung Base64 — giải thích các field Subject/SAN.


---

!!! info "Nguồn gốc"
    `book_lab/dbatools-lab/bookcode/chapter24.notes.md`
