---
title: Chapter 08 — Central Management Server (CMS) & Registered Servers
course: 11-book-lab
source: book_lab/dbatools-lab/bookcode/chapter08.notes.md
---

# Chapter 08 — Central Management Server (CMS) & Registered Servers

> Tham chiếu code gốc: [chapter08.ps1](chapter08.ps1)

## Mục tiêu
- Hiểu khái niệm **Registered Servers** (lưu local trên SSMS) vs **Central Management Server / CMS** (lưu tập trung trên 1 SQL instance).
- Dùng `Get-DbaRegServer` để **thay danh sách instance hardcode** bằng query đến CMS — chạy 1 lệnh, áp lên N server.
- Tạo / sửa / chuyển nhóm / xoá registered server bằng các cmdlet `*-DbaRegServer`.
- Import/Export CMS giữa các instance bằng CSV hoặc XML.
- Hiểu pattern: **CMS = source of truth duy nhất** cho danh sách SQL instance trong tổ chức.

## Tóm tắt 5 ý chính
1. **CMS = 1 instance SQL bất kỳ + tính năng MSDB lưu danh sách "các server tôi quản lý"**. Bật bằng cách click chuột phải trong SSMS hoặc gọi dbatools — không cần feature đặc biệt.
2. **`Get-DbaRegServer` thay vì hardcode mảng `$instances`** — cmdlet này trả về object có property `SqlInstance`, **pipe được vào hầu hết cmdlet dbatools**.
3. **Hệ thống nhóm phân cấp** dùng dấu `\`: `OnPrem\Accounting`, `Cloud\Azure\Dev`. Filter bằng `-Group` hoặc `-ExcludeGroup`.
4. **Local Registered Servers** (file `RegSrvr.xml` của SSMS) khác **CMS** — dùng `-IncludeLocal` để gộp cả hai.
5. **Migration pattern:** `Export-DbaRegServer` (XML) → file backup → `Import-DbaRegServer` vào instance mới. Hoặc copy thẳng `Copy-DbaRegServer -Source ... -Destination ...`.

## Giải thích từng đoạn code

### Đoạn 1: dòng 18
```powershell
Get-DbaRegServer | Invoke-DbaQuery -Query "SELECT @@VERSION"
```
- **Ý nghĩa:** "Mẫu mơ ước" — lấy mọi server đã đăng ký, chạy `SELECT @@VERSION` lên từng cái. Không cần biết tên server, không cần loop, không cần file CSV.
- **Đổi cho lab:** Trước khi chạy lệnh này, phải `Add-DbaRegServer` cho ít nhất 2 instance lab (xem đoạn 11-12 bên dưới).

### Đoạn 2: dòng 22
```powershell
Get-DbaRegServer
```
- **Ý nghĩa:** Liệt kê các registered server **của user hiện tại** trên SSMS local (Local Server Groups). Output trống nếu chưa đăng ký gì.
- **Đổi cho lab:** Giữ nguyên. Nếu output trống → chuyển sang đoạn 11-12 để add trước.

### Đoạn 3: dòng 27-28
```powershell
Get-DbaRegServer -Name sql01 | Get-DbaDatabase |
Backup-DbaDatabase
```
- **Ý nghĩa:** Pattern 3 cmdlet pipe: lấy server tên `sql01` từ registry → lấy mọi DB của nó → backup mọi DB.
- **Đổi cho lab:**
  ```powershell
  Get-DbaRegServer -Name LabSql2017 | Get-DbaDatabase -ExcludeSystem | Backup-DbaDatabase -WhatIf
  ```
- **Side-effect:** `Backup-DbaDatabase` ghi file `.bak`. **Bắt buộc `-WhatIf` trước** để xem path đích.
- **Prerequisites:** Phải có server tên `sql01` (hoặc `LabSql2017`) trong registry.

### Đoạn 4: dòng 33-35
```powershell
$cred = Get-Credential sqladmin
Get-DbaRegserver -SqlInstance dbainstance |
Backup-DbaDatabase -SqlCredential $cred
```
- **Ý nghĩa:** Lấy registered servers **từ CMS trên `dbainstance`** (không phải local SSMS), backup mọi DB với SQL credential `sqladmin`.
- **Đổi cho lab:** `$cred = Get-Credential WWI_Owner; Get-DbaRegServer -SqlInstance dbatoolslab\sql2017 | Backup-DbaDatabase -SqlCredential $cred -WhatIf`.
- **Lưu ý:** Đây là chỗ phân biệt rõ **local registered server vs CMS** — `-SqlInstance` trỏ tới CMS.

### Đoạn 5: dòng 39
```powershell
Get-DbaRegServer -SqlInstance dbainstance
```
- **Ý nghĩa:** Liệt kê server từ CMS trên `dbainstance`.
- **Đổi cho lab:** `Get-DbaRegServer -SqlInstance dbatoolslab\sql2017`. Sẽ trống cho đến khi `Add-DbaRegServer` (xem đoạn 11+).

### Đoạn 6: dòng 44-46
```powershell
Import-Csv -Path C:\temp\regservers.csv

ServerName Name               Description    Group
```
- **Ý nghĩa:** Đọc file CSV chuẩn bị cho import. Dòng dưới là **header mẫu** — file CSV cần ít nhất 2 cột `ServerName` và `Name`, optional `Description` và `Group`.
- **Đổi cho lab:** Tạo file CSV mẫu:
  ```powershell
  @"
  ServerName,Name,Description,Group
  dbatoolslab,LabDefault,Default 2019 instance,Lab
  dbatoolslab\sql2017,LabSql2017,Named SQL 2017,Lab
  "@ | Out-File .\regservers.csv -Encoding UTF8
  Import-Csv .\regservers.csv
  ```

### Đoạn 7: dòng 50-51
```powershell
Import-Csv -Path C:\temp\regservers.csv |
Import-DbaRegServer -SqlInstance sql2016
```
- **Ý nghĩa:** Pipe CSV → import vào CMS trên `sql2016`. Output các record vừa tạo.
- **Đổi cho lab:** `Import-Csv .\regservers.csv | Import-DbaRegServer -SqlInstance dbatoolslab\sql2017 -WhatIf`.
- **Side-effect:** **Ghi vào MSDB của CMS.** `-WhatIf` trước.

### Đoạn 8: dòng 56
```powershell
Get-DbaRegServer -SqlInstance sql2016 -Group Test\Dev
```
- **Ý nghĩa:** Filter chỉ server trong group `Test\Dev` (nested 2 cấp, dấu `\` phân cách).
- **Đổi cho lab:** `Get-DbaRegServer -SqlInstance dbatoolslab\sql2017 -Group Lab` (sau khi đã import).

### Đoạn 9: dòng 61
```powershell
Get-DbaRegServer -SqlInstance sql2016 -ExcludeGroup Test\Dev
```
- **Ý nghĩa:** Ngược lại — bỏ qua server trong group cho trước. Hữu ích khi muốn áp lệnh lên prod mà không động đến dev.
- **Đổi cho lab:** `Get-DbaRegServer -SqlInstance dbatoolslab\sql2017 -ExcludeGroup Lab` (sẽ trống nếu chỉ có group `Lab`).

### Đoạn 10: dòng 66
```powershell
Get-DbaRegServer -SqlInstance dbainstance -IncludeLocal
```
- **Ý nghĩa:** **Gộp** cả Local Server Groups (file SSMS) lẫn CMS — pattern khi DBA dùng cả 2 hệ thống.
- **Đổi cho lab:** `Get-DbaRegServer -SqlInstance dbatoolslab\sql2017 -IncludeLocal`.

### Đoạn 11: dòng 70
```powershell
Add-DbaRegServer -ServerName sql2017
```
- **Ý nghĩa:** Thêm `sql2017` vào **Local Registered Servers** (vì không truyền `-SqlInstance`).
- **Đổi cho lab:** `Add-DbaRegServer -ServerName dbatoolslab\sql2017 -Name LabSql2017`.
- **Side-effect:** Ghi vào file SSMS `RegSrvr.xml`.

### Đoạn 12: dòng 74-79
```powershell
$splatRegServer = @{
    SqlInstance = "sqldb01"
    Group = "OnPrem"
    ServerName = "sql01"
}
Add-DbaRegServer @splatRegServer
```
- **Ý nghĩa:** Add vào **CMS trên `sqldb01`** với group `OnPrem`. Splat để rõ ràng nhiều tham số.
- **Đổi cho lab:**
  ```powershell
  $args = @{
      SqlInstance = "dbatoolslab\sql2017"
      Group       = "Lab"
      ServerName  = "dbatoolslab"
      Name        = "LabDefault"
  }
  Add-DbaRegServer @args -WhatIf
  ```
- **Side-effect:** Ghi MSDB của CMS. `-WhatIf` trước.

### Đoạn 13: dòng 83-88
```powershell
$splatRegServer = @{
    SqlInstance = "sqldb01"
    Group = "OnPrem\Accounting"
    ServerName = "sql01"
}
Add-DbaRegServer @splatRegServer
```
- **Ý nghĩa:** Add vào **subgroup** `OnPrem\Accounting`. dbatools tự tạo nhóm nested nếu chưa có.
- **Đổi cho lab:**
  ```powershell
  $args = @{
      SqlInstance = "dbatoolslab\sql2017"
      Group       = "Lab\Demo"
      ServerName  = "dbatoolslab"
  }
  Add-DbaRegServer @args -WhatIf
  ```

### Đoạn 14: dòng 92-96
```powershell
$splatConnect = @{
    SqlInstance = "dockersql1,14333"
    SqlCredential = "sqladmin"
}
Connect-DbaInstance @splatConnect | Add-DbaRegServer -Description = "Container for AG tests"
```
- **Ý nghĩa:** Kết nối container, **pipe SMO server object** vào `Add-DbaRegServer` thay vì truyền `-ServerName`. dbatools tự suy ra tên.
- **Bug code gốc:** `-Description = "..."` có dấu `=` thừa — PowerShell parser sẽ báo lỗi. Sửa thành:
  ```powershell
  Connect-DbaInstance @splatConnect | Add-DbaRegServer -Description "Container for AG tests"
  ```
- **Đổi cho lab:** `Connect-DbaInstance -SqlInstance dbatoolslab\sql2017 | Add-DbaRegServer -Description "Lab named instance" -WhatIf`.

### Đoạn 15: dòng 100-111
```powershell
Copy-DbaRegServer -Source sql2008 -Destination sql01

# Export CMS list to an XML file
$splatExportRegServer = @{
    SqlInstance = "sql2008"
    Path = "C:\temp"
    OutVariable = file
}
Export-DbaRegServer @splatExportRegServer

# Import CMS list from an XML file
Import-DbaRegServer -SqlInstance sql01 -Path $file
```
- **Ý nghĩa:** 2 pattern migration CMS:
  - **Direct copy:** `Copy-DbaRegServer` từ Source sang Destination.
  - **Via XML file:** Export ra file → backup/version control → Import vào instance mới.
- **Bug code gốc:** `OutVariable = file` → đúng phải `OutVariable = "file"` (string). Khi dùng phải dùng `$file` (PowerShell tự thêm `$`).
- **Đổi cho lab:**
  ```powershell
  # Export
  Export-DbaRegServer -SqlInstance dbatoolslab\sql2017 -Path C:\dbatoolslab\Backup\
  # Import lại vào chính instance đó (demo round-trip)
  Import-DbaRegServer -SqlInstance dbatoolslab -Path C:\dbatoolslab\Backup\dbatoolslab$sql2017-regservers.xml -WhatIf
  ```
- **Side-effect:** `Export` chỉ ghi file. `Import`/`Copy` ghi MSDB → `-WhatIf` trước.

### Đoạn 16: dòng 115
```powershell
Move-DbaRegServer -Name 'Web SQL Cluster' -Group HR\Prod
```
- **Ý nghĩa:** Chuyển 1 registered server sang group khác. Dùng `-Name` (tên hiển thị, không phải ServerName).
- **Đổi cho lab:** `Move-DbaRegServer -SqlInstance dbatoolslab\sql2017 -Name LabSql2017 -Group "Lab\Production" -WhatIf`.

### Đoạn 17: dòng 119-120
```powershell
Get-DbaRegServer | Where Name -match HR |
Move-DbaRegServer -Group HR\Prod
```
- **Ý nghĩa:** Bulk move: lấy hết server có tên chứa "HR", move toàn bộ vào `HR\Prod`. Regex match qua `Where-Object`.
- **Đổi cho lab:** `Get-DbaRegServer -SqlInstance dbatoolslab\sql2017 | Where Name -match "^Lab" | Move-DbaRegServer -Group "Lab\Production" -WhatIf`.

### Đoạn 18: dòng 124
```powershell
Remove-DbaRegServer -ServerName sql01
```
- **Ý nghĩa:** Xoá registered server. Lưu ý: **chỉ xoá registration**, **không xoá SQL instance thật**.
- **Đổi cho lab:** `Remove-DbaRegServer -SqlInstance dbatoolslab\sql2017 -ServerName dbatoolslab -WhatIf`.
- **Side-effect:** Ghi MSDB. `-WhatIf` trước.

### Đoạn 19: dòng 128-129
```powershell
Get-DbaRegServer -ServerName sql2016, sql01 |
Remove-DbaRegServer -Confirm:$false
```
- **Ý nghĩa:** Bulk remove + bypass prompt confirm. **Nguy hiểm** — chỉ chạy khi chắc chắn.
- **Đổi cho lab:** Tốt hơn vẫn `-WhatIf` trước:
  ```powershell
  Get-DbaRegServer -SqlInstance dbatoolslab\sql2017 -ServerName dbatoolslab, dbatoolslab\sql2017 |
      Remove-DbaRegServer -WhatIf
  ```

## Lệnh thay vào lab của bạn

```powershell
# Phiên bản đã đổi instance name cho lab dbatoolslab + dbatoolslab\sql2017
$cms = "dbatoolslab\sql2017"   # dùng named instance làm CMS host

# 1) Setup: add 2 server lab vào CMS (luôn -WhatIf trước)
$args = @{ SqlInstance = $cms; Group = "Lab"; ServerName = "dbatoolslab";        Name = "LabDefault"  }
Add-DbaRegServer @args -WhatIf
$args = @{ SqlInstance = $cms; Group = "Lab"; ServerName = "dbatoolslab\sql2017"; Name = "LabSql2017" }
Add-DbaRegServer @args -WhatIf

# 2) Đọc lại
Get-DbaRegServer -SqlInstance $cms
Get-DbaRegServer -SqlInstance $cms -Group Lab

# 3) Pattern thực dụng: chạy 1 query lên mọi server đã đăng ký
Get-DbaRegServer -SqlInstance $cms -Group Lab |
    Invoke-DbaQuery -Query "SELECT @@SERVERNAME AS srv, @@VERSION AS ver"

# 4) Pattern report: inventory mọi DB không backup gần đây trên cả estate
$d = (Get-Date).AddDays(-7)
Get-DbaRegServer -SqlInstance $cms | Get-DbaDatabase -NoFullBackupSince $d |
    Select-Object SqlInstance, Name, LastFullBackup

# 5) Import từ CSV
@"
ServerName,Name,Description,Group
dbatoolslab,LabDefault,Default 2019 instance,Lab\Imported
dbatoolslab\sql2017,LabSql2017,Named SQL 2017,Lab\Imported
"@ | Out-File .\regservers.csv -Encoding UTF8
Import-Csv .\regservers.csv | Import-DbaRegServer -SqlInstance $cms -WhatIf

# 6) Export ra XML (backup CMS)
Export-DbaRegServer -SqlInstance $cms -Path C:\dbatoolslab\Backup\

# 7) Move + cleanup (DESTRUCTIVE — luôn -WhatIf trước)
Get-DbaRegServer -SqlInstance $cms -Group Lab\Imported |
    Remove-DbaRegServer -WhatIf
```

## Self-check (3 câu)
1. **Định nghĩa:** Phân biệt **Local Registered Servers** vs **CMS**. Tham số nào của `Get-DbaRegServer` quyết định query cái nào?
2. **Thực hành:** Sau khi `Add-DbaRegServer` 2 instance lab, chạy `Get-DbaRegServer -SqlInstance dbatoolslab\sql2017 | Get-DbaDatabase | Group-Object SqlInstance | Select Name, Count`. Output cho biết điều gì?
3. **Liên hệ:** Chapter 04 dạy truyền `$instances` array từ CSV hoặc query. Chapter 08 dạy lấy từ CMS qua `Get-DbaRegServer`. Lợi thế của CMS so với CSV trong môi trường 50+ instance?

## Bài tập mở rộng
- **Bài 1 (~5 phút):** Add 2 instance lab vào CMS trên `dbatoolslab\sql2017` với group `Lab\OnPrem`. Sau đó chạy 1 lệnh `Invoke-DbaQuery -Query "SELECT GETDATE() AS now"` cho toàn group, format output dạng bảng.
- **Bài 2 (sâu hơn):** Viết function `Sync-LabCms` mỗi sáng: (1) `Export-DbaRegServer -Path .\cms-backups\YYYY-MM-DD\` để có history; (2) chạy `Test-DbaConnection` cho mọi `Get-DbaRegServer` và ghi `ConnectSuccess` vào bảng `DBAEstate.dbo.CmsHealth`; (3) gửi email/Teams alert nếu có server fail. Hint: dùng `Send-MailMessage` hoặc webhook qua `Invoke-RestMethod`.


---

!!! info "Nguồn gốc"
    `book_lab/dbatools-lab/bookcode/chapter08.notes.md`
