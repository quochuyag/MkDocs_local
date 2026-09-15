---
title: Chapter 07 — Lập inventory host & instance (features, builds, OS, databases)
course: 11-book-lab
source: book_lab/dbatools-lab/bookcode/chapter07.notes.md
---

# Chapter 07 — Lập inventory host & instance (features, builds, OS, databases)

> Tham chiếu code gốc: [chapter07.ps1](chapter07.ps1)

## Mục tiêu
- Lấy được **feature list** của SQL setup bằng `Get-DbaFeature` (thay cho `setup.exe /Action=RunDiscovery`).
- Tra **build/patch level** + so sánh với danh mục build mới nhất bằng `Get-DbaBuildReference`/`Test-DbaBuild`.
- Thu thập **thông tin OS + hardware** bằng `Get-DbaComputerSystem` / `Get-DbaOperatingSystem`.
- Khai thác `Get-DbaDatabase` ở mức inventory: lọc `-NoFullBackup`, `-NoFullBackupSince`, `-Database`, `-User`.
- Hiểu pattern **DBAEstate database** — gom tất cả output vào 1 DB tổng để truy vấn về sau.

## Tóm tắt 5 ý chính
1. **`Get-DbaFeature` thay setup.exe** — không cần SSH vào máy chạy `setup.exe /Action=RunDiscovery`. Lệnh remote về danh sách feature đã cài (Engine, RS, IS, Tools…).
2. **`Get-DbaBuildReference` + cache JSON local** — dbatools giữ file map "build number → tên CU/SP/version". `-Update` để pull mới nhất từ GitHub.
3. **`Test-DbaBuild -Latest`** trả lời câu hỏi nhức nhối: "instance này đã ở patch mới nhất chưa?". Output có cột `Compliant` true/false.
4. **`-NoFullBackup` / `-NoFullBackupSince`** giúp scan nhanh DB không backup — đầu vào trực tiếp cho daily compliance report.
5. **`Find-DbaUserObject`** liệt kê **đối tượng owned bởi user** (jobs, schemas, DB) — đắc lực khi nhân viên nghỉ việc, cần re-assign owner.

## Giải thích từng đoạn code

### Đoạn 1: dòng 18-19
```powershell
cd "C:\Program Files\Microsoft SQL Server\140\Setup Bootstrap\SQL2017"
.\setup.exe /Action=RunDiscovery
```
- **Ý nghĩa:** Cách **thủ công** (không dbatools) để lấy danh sách feature đã cài cho SQL 2017 (`140` = version internal). Mở ra để học sinh thấy sự khác biệt với cmdlet.
- **Đổi cho lab:** Có thể test trên máy host Windows. Lưu ý: SQL 2017 ở `140`, SQL 2019 ở `150`, SQL 2022 ở `160`.
- **Lưu ý:** Không hoạt động trong devcontainer Linux (không có setup.exe).

### Đoạn 2: dòng 23
```powershell
Get-DbaFeature -ComputerName $sqlinstances
```
- **Ý nghĩa:** Cmdlet wrapper cho `setup.exe /Action=RunDiscovery`, chạy **remote** không cần đăng nhập máy đích.
- **Đổi cho lab:** `Get-DbaFeature -ComputerName dbatoolslab`.
- **Lưu ý:** Cần **Local Admin trên máy đích** (vì gọi `setup.exe` qua remoting). Chỉ chạy được trên Windows.

### Đoạn 3: dòng 27
```powershell
Get-DbaBuildReference -SqlInstance SQLDEV01
```
- **Ý nghĩa:** Lấy build number của instance + tra cứu xem build đó tương ứng version/CU/SP nào.
- **Đổi cho lab:** `Get-DbaBuildReference -SqlInstance dbatoolslab\sql2017`.
- **Output mong đợi:** Properties như `SqlInstance, Build, NameLevel, SPLevel, CULevel, SupportedUntil`.

### Đoạn 4: dòng 32
```powershell
Get-DbaBuildReference -Update
```
- **Ý nghĩa:** **Update local cache** từ GitHub repo của dbatools — tải file `dbatools-buildref-index.json` mới nhất.
- **Lưu ý:** Cần internet. Đáng chạy 1 lần/tuần để có data CU mới nhất từ Microsoft.

### Đoạn 5: dòng 36
```powershell
Test-DbaBuild -SqlInstance SQLDEV01 -Latest
```
- **Ý nghĩa:** Cmdlet thông minh nhất chapter này — trả về `Compliant: True/False` so với build mới nhất Microsoft ra.
- **Đổi cho lab:** `Test-DbaBuild -SqlInstance dbatoolslab, dbatoolslab\sql2017 -Latest`.
- **Tham số phụ:**
  - `-MaxBehind '1CU'` — chấp nhận tụt 1 CU
  - `-MaxBehind '6 months'` — chấp nhận build trong 6 tháng gần đây.

### Đoạn 6: dòng 40
```powershell
Get-DbaComputerSystem -ComputerName SQLDEV01
```
- **Ý nghĩa:** Lấy thông tin **hardware/OS layer**: số CPU, RAM tổng, domain, manufacturer…
- **Đổi cho lab:** `Get-DbaComputerSystem -ComputerName dbatoolslab`.
- **Lưu ý:** Qua CIM/WMI → cần Local Admin. Không chạy trên Linux.

### Đoạn 7: dòng 45
```powershell
Get-DbaOperatingSystem -ComputerName SQL2016N1.ad.local
```
- **Ý nghĩa:** Lấy thông tin OS: tên version, build OS, install date, last boot, language…
- **Đổi cho lab:** `Get-DbaOperatingSystem -ComputerName dbatoolslab`.

### Đoạn 8: dòng 50
```powershell
Get-DbaDatabase -SqlInstance SQLDEV01
```
- **Ý nghĩa:** Liệt kê **tất cả DB** (kể cả system). Trở lại cmdlet quen từ chapter 04-05.
- **Đổi cho lab:** `Get-DbaDatabase -SqlInstance dbatoolslab\sql2017`.

### Đoạn 9: dòng 54-58
```powershell
$splatDatabase = @{
    SqlInstance = "SQLDEV01"
    Database = "WideWorldImporters", "AdventureWorks"
}
Get-DbaDatabase @splatDatabase
```
- **Ý nghĩa:** **Splatting** — kỹ thuật PowerShell đóng gói tham số vào hashtable, gọi cmdlet với `@var`. Đọc dễ hơn cho command nhiều param.
- **Đổi cho lab:**
  ```powershell
  $args = @{
      SqlInstance = "dbatoolslab\sql2017"
      Database    = "WideWorldImporters", "AdventureWorks2017"
  }
  Get-DbaDatabase @args
  ```

### Đoạn 10: dòng 62
```powershell
Get-DbaDatabase -SqlInstance SQLDEV01 -NoFullBackup
```
- **Ý nghĩa:** **Filter rất hữu ích cho daily report:** chỉ trả DB **chưa bao giờ có full backup**. Output trống là tin tốt.
- **Đổi cho lab:** `Get-DbaDatabase -SqlInstance dbatoolslab\sql2017 -NoFullBackup`.

### Đoạn 11: dòng 66-67
```powershell
$date = (Get-Date).AddDays(-30)
Get-DbaDatabase -SqlInstance SQLDEV01 -NoFullBackupSince $date
```
- **Ý nghĩa:** DB **chưa có full backup trong 30 ngày qua**. Đầu vào trực tiếp cho alert system.
- **Đổi cho lab:**
  ```powershell
  $date = (Get-Date).AddDays(-30)
  Get-DbaDatabase -SqlInstance dbatoolslab\sql2017 -NoFullBackupSince $date
  ```

### Đoạn 12: dòng 71-78
```powershell
$splatInvokeQuery = @{
    SqlInstance = "ConfigInstance"
    Database = "Instances"
    Query = "SELECT InstanceName FROM Config"
}
$SqlInstances = (Invoke-DbaQuery @splatInvokeQuery).InstanceName
# Find databases owned by the user
Get-DbaDatabase -SqlInstance $instances -User ad\g.sartori
```
- **Ý nghĩa:** Pattern enterprise — đọc danh sách instance từ DB inventory, rồi tìm DB sở hữu bởi 1 user cụ thể.
- **Bug code gốc:** Đặt giá trị vào `$SqlInstances` nhưng dòng sau dùng `$instances` (khác tên). Sửa:
  ```powershell
  $SqlInstances = (Invoke-DbaQuery @splatInvokeQuery).InstanceName
  Get-DbaDatabase -SqlInstance $SqlInstances -User ad\g.sartori
  ```
- **Đổi cho lab:** Lab không có CMDB → thay bằng:
  ```powershell
  Get-DbaDatabase -SqlInstance dbatoolslab\sql2017 -Owner sa
  # hoặc -Owner WWI_Owner sau khi đã set với Set-DbaDbOwner
  ```

### Đoạn 13: dòng 82
```powershell
Find-DbaUserObject -SqlInstance sql2017, sql2005
```
- **Ý nghĩa:** Tìm **mọi object SQL Server** thuộc sở hữu của user nào đó (default: user hiện tại). Bao gồm jobs, schemas, DB, endpoint, linked server…
- **Đổi cho lab:** `Find-DbaUserObject -SqlInstance dbatoolslab\sql2017`.
- **Use case classic:** Nhân viên nghỉ việc → chạy lệnh này để biết phải re-assign owner cho object nào trước khi disable login.

### Đoạn 14: dòng 88-121
```powershell
$sqlconfiginstance = "ConfigInstance"

# A comma delimited list of Host names
$sqlhosts = "SQLDEV01", "sql1"

# A comma-delimted list of SQL Server instances
$sqlinstances = "SQLDEV01","sql1","SQLDEV01\SHAREPOINT", "sql1\DW"

# Create DBAEstate database if not existing
New-DbaDatabase -SqlInstance $sqlconfiginstance -Name DBAEstate

# Put information about the SQL hosts into the DBAEstate database
$splatWriteDataTable = @{
    SqlInstance = $sqlconfiginstance
    Database = "DBAEstate"
    AutoCreateTable = $true
}
Get-DbaFeature -ComputerName $sqlhosts |
Write-DbaDataTable @splatWriteDataTable -Table Features

Get-DbaBuildReference -SqlInstance $sqlinstances |
Write-DbaDataTable @splatWriteDataTable -Table SQLBuilds

Get-DbaComputerSystem -ComputerName $sqlhosts |
Write-DbaDataTable @splatWriteDataTable -Table ComputerSystem

Get-DbaOperatingSystem -ComputerName $sqlhosts |
Write-DbaDataTable @splatWriteDataTable -Table OperatingSystem

Get-DbaDatabase -SqlInstance $sqlinstances |
Write-DbaDataTable @splatWriteDataTable -Table Database

Find-DbaUserObject -SqlInstance $sqlinstances |
Write-DbaDataTable @splatWriteDataTable -Table UserObject
```
- **Ý nghĩa:** **Pattern "DBAEstate"** — build 1 database duy nhất chứa toàn bộ inventory. 6 bảng:
  1. `Features` — feature đã cài (từ `Get-DbaFeature`)
  2. `SQLBuilds` — build/patch (từ `Get-DbaBuildReference`)
  3. `ComputerSystem` — hardware (từ `Get-DbaComputerSystem`)
  4. `OperatingSystem` — OS info (từ `Get-DbaOperatingSystem`)
  5. `Database` — danh sách DB (từ `Get-DbaDatabase`)
  6. `UserObject` — objects theo owner (từ `Find-DbaUserObject`)
- **Đổi cho lab:**
  ```powershell
  $cfg   = "dbatoolslab\sql2017"
  $hosts = "dbatoolslab"
  $inst  = "dbatoolslab", "dbatoolslab\sql2017"

  New-DbaDatabase -SqlInstance $cfg -Name DBAEstate -WhatIf   # luôn -WhatIf trước
  $wargs = @{ SqlInstance = $cfg; Database = "DBAEstate"; AutoCreateTable = $true }

  Get-DbaFeature        -ComputerName $hosts | Write-DbaDataTable @wargs -Table Features
  Get-DbaBuildReference -SqlInstance  $inst  | Write-DbaDataTable @wargs -Table SQLBuilds
  Get-DbaComputerSystem -ComputerName $hosts | Write-DbaDataTable @wargs -Table ComputerSystem
  Get-DbaOperatingSystem -ComputerName $hosts| Write-DbaDataTable @wargs -Table OperatingSystem
  Get-DbaDatabase       -SqlInstance  $inst  | Write-DbaDataTable @wargs -Table Database
  Find-DbaUserObject    -SqlInstance  $inst  | Write-DbaDataTable @wargs -Table UserObject
  ```
- **Side-effect:** **Tạo DB + 6 bảng + ghi data.** `New-DbaDatabase` và mọi `Write-DbaDataTable` đều ghi — dùng `-WhatIf` lần đầu.

## Lệnh thay vào lab của bạn

```powershell
# Phiên bản đã đổi instance name cho lab dbatoolslab + dbatoolslab\sql2017

$inst  = "dbatoolslab\sql2017"
$hosts = "dbatoolslab"

# 1) Feature đã cài (cần Local Admin; không chạy trên Linux container)
Get-DbaFeature -ComputerName $hosts

# 2) Build / patch level
Get-DbaBuildReference -SqlInstance $inst |
    Select-Object SqlInstance, Build, NameLevel, SPLevel, CULevel, SupportedUntil

# 3) Kiểm tra "đã ở build mới nhất chưa"
Test-DbaBuild -SqlInstance dbatoolslab, $inst -Latest |
    Select-Object SqlInstance, Build, BuildTarget, Compliant

# 4) Hardware + OS
Get-DbaComputerSystem -ComputerName $hosts | Select-Object *
Get-DbaOperatingSystem -ComputerName $hosts | Select-Object ComputerName, OSVersion, OSInstallDate, LastBootTime

# 5) Database không có full backup gần đây
$date = (Get-Date).AddDays(-7)
Get-DbaDatabase -SqlInstance $inst -NoFullBackupSince $date |
    Select-Object Name, RecoveryModel, LastFullBackup

# 6) Object thuộc sở hữu user — đổi -InputObject cho user cụ thể của lab
Find-DbaUserObject -SqlInstance $inst |
    Select-Object Type, Owner, Name, Parent

# 7) Build DBAEstate (luôn -WhatIf trước khi chạy thật)
New-DbaDatabase -SqlInstance $inst -Name DBAEstate -WhatIf
```

## Self-check (3 câu)
1. **Định nghĩa:** Sự khác biệt giữa `Get-DbaBuildReference` và `Test-DbaBuild`? Khi nào dùng cái nào?
2. **Thực hành:** Chạy `Test-DbaBuild -SqlInstance dbatoolslab\sql2017 -Latest`. Cột `Compliant` là `True` hay `False`? Nếu `False`, dbatools đề xuất build nào ở cột `BuildTarget`?
3. **Liên hệ:** Chapter 06 dạy `Find-DbaInstance` (tìm host). Chapter này dạy `Get-DbaFeature/Build/ComputerSystem` (lấy thông tin chi tiết). Hai bước này tương ứng giai đoạn nào trong **lifecycle audit DBA**?

## Bài tập mở rộng
- **Bài 1 (~5 phút):** Build mini-DBAEstate trên lab: chạy 6 lệnh `Write-DbaDataTable` theo template đoạn 14 (đổi instance). Sau khi xong, query `SELECT t.name, p.rows FROM DBAEstate.sys.tables t JOIN sys.partitions p ON t.object_id=p.object_id WHERE p.index_id IN (0,1)` để xem mỗi bảng có bao nhiêu dòng.
- **Bài 2 (sâu hơn):** Viết script `Update-DBAEstate.ps1` schedulable — chạy 6 lệnh trên với param `-ScanDate (Get-Date)`. Thêm cột `ScanDate` vào mỗi bảng (gợi ý: `Add-Member -InputObject $_ -NotePropertyName ScanDate -NotePropertyValue ...` trước khi pipe vào `Write-DbaDataTable`). Sau 7 ngày, viết query phát hiện DB mới xuất hiện / mất đi giữa 2 lần scan.


---

!!! info "Nguồn gốc"
    `book_lab/dbatools-lab/bookcode/chapter07.notes.md`
