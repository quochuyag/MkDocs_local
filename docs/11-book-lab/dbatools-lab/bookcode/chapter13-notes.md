---
title: Chapter 13 — Install-DbaInstance và tự động hoá triển khai SQL Server
course: 11-book-lab
source: book_lab/dbatools-lab/bookcode/chapter13.notes.md
---

# Chapter 13 — Install-DbaInstance và tự động hoá triển khai SQL Server

## Mục tiêu
- Hiểu cách dùng `Install-DbaInstance` để cài SQL Server từ media ISO/setup mà không cần GUI.
- Biết cấu hình bộ tham số (config hashtable hoặc file `.ini`) để cài hàng loạt instance theo chuẩn doanh nghiệp.
- Cài đặt từ xa qua share Windows, hiểu yêu cầu Kerberos / "second-hop" và cách cấu hình resource-based constrained delegation.
- Biết cập nhật instance bằng `Update-DbaInstance` (Service Pack / Cumulative Update).
- Biết cập nhật service account của SQL Server / SQL Agent bằng `Update-DbaServiceAccount`.

## Tóm tắt 3-5 ý chính
1. **`Install-DbaInstance` là wrapper PowerShell cho setup.exe** — bạn chỉ cần `-Path` (folder chứa media SQL Server) và `-Version`, hàm sẽ tự tìm `setup.exe` và build dòng lệnh phù hợp.
2. **Cấu hình bằng hashtable hoặc file `.ini`** — mọi key trong `ConfigurationFile.ini` của SQL Server setup đều được hỗ trợ (`SQLSYSADMINACCOUNTS`, `SQLUSERDBDATADIR`, `TCPENABLED`, ...). Có thể truyền qua tham số `-Configuration` hoặc `-ConfigurationFile`.
3. **"Second-hop" Kerberos** — khi cài từ máy admin của bạn (hop 1) lên máy SQL (hop 2), SQL cần đọc media trên file server (hop 3). Phải bật resource-based constrained delegation: `Set-ADComputer -PrincipalsAllowedToDelegateToAccount`.
4. **`Update-DbaInstance` cập nhật SP/CU** — dò version hiện tại, áp đúng patch, hỗ trợ cluster (nhận `ComputerName = "sqlcluster"`).
5. **`Update-DbaServiceAccount` đổi tài khoản chạy dịch vụ** — kết hợp `Get-DbaService` + `Out-GridView -Passthru` để chọn dịch vụ rồi đổi credential mà không phải mở `services.msc`.

## Giải thích từng đoạn code

### Đoạn 1: dòng 18 — Cài SQL Server 2017 tại chỗ
```powershell
Install-DbaInstance -Path E:\ -Version 2017
```
- **Ý nghĩa:** Cài SQL 2017 trên máy local, dùng media nằm trong `E:\` (thường là ổ ISO đã mount). Tham số tối thiểu, lấy tất cả mặc định: instance `MSSQLSERVER`, feature `Engine`, tài khoản hiện tại làm sysadmin.
- **Đổi cho lab:** Lab của bạn đã có sẵn 2 instance `dbatoolslab` (SQL 2019) và `dbatoolslab\sql2017`. Không cần chạy `Install-DbaInstance` để có instance học, nhưng có thể thử với một VM phụ hoặc container.
- **Lưu ý:** **CẢNH BÁO NGHIÊM TRỌNG** — lệnh này cài hẳn một SQL Server engine mới, không phải sandbox. Trên môi trường thật phải có change ticket. Trong lab nên kèm `-WhatIf` trước, hoặc chạy trên VM disposable.

### Đoạn 2: dòng 22-26 — Cấu hình Kerberos delegation cho cài đặt từ xa
```powershell
$sqlserver = Get-ADComputer -Identity sql01
$shareserver = Get-ADComputer -Identity fs01
Set-ADComputer -Identity $shareserver -PrincipalsAllowedToDelegateToAccount $sqlserver
# Wait 15 minutes or execute the following, which clears system tickets
Invoke-Command -ComputerName sql01 -ScriptBlock { KLIST PURGE -LI 0x3e7 }
```
- **Ý nghĩa:** Cho phép computer account `sql01$` mượn danh tính khi đọc share trên `fs01`, vượt qua hạn chế "second hop". `KLIST PURGE -LI 0x3e7` xoá Kerberos ticket của tài khoản SYSTEM để cấu hình mới có hiệu lực ngay.
- **Đổi cho lab:** Lab dùng Docker container nội bộ, không có AD domain, **không cần đoạn này**. Chỉ ghi nhớ để áp dụng khi triển khai môi trường doanh nghiệp.
- **Lưu ý:** Sai cấu hình delegation có thể ảnh hưởng bảo mật. Chỉ delegation tới file server cụ thể, không delegation rộng.

### Đoạn 3: dòng 30 — Cài từ xa qua share
```powershell
Install-DbaInstance -SqlInstance sql01 -Path \\fs01\share\sqlinstall -Version 2017
```
- **Ý nghĩa:** Đứng từ workstation, ra lệnh cho `sql01` cài SQL 2017, đọc media từ `\\fs01\share\sqlinstall`. Yêu cầu PowerShell Remoting + Kerberos delegation đã thiết lập ở đoạn 2.
- **Đổi cho lab:** Trong lab không có second host. Có thể mô phỏng bằng cách chạy lệnh trực tiếp trên một container thứ hai nếu bạn muốn thực hành.
- **Lưu ý:** **CẢNH BÁO** — đây là lệnh thay đổi toàn instance trên máy đích. Chạy `-WhatIf` đầu tiên để xem hành động dự kiến.

### Đoạn 4: dòng 34-36 — Đổi service account
```powershell
$cred = Get-Credential ad\sql01engine
Get-DbaService -ComputerName sql01 | Out-GridView -Passthru |
    Update-DbaServiceAccount -ServiceCredential $cred
```
- **Ý nghĩa:** Lấy credential của tài khoản service, list các dịch vụ trên `sql01`, dùng `Out-GridView -Passthru` để chọn dịch vụ bằng GUI rồi đẩy vào `Update-DbaServiceAccount`.
- **Đổi cho lab:** Đổi `sql01` thành `localhost` (hoặc tên container) và dùng tài khoản local. Trong container Docker thường để mặc định — bài này chủ yếu để hiểu pattern.
- **Lưu ý:** Đổi service account sẽ **restart dịch vụ SQL** — không chạy trong giờ làm việc. `Out-GridView` cần PowerShell có GUI (Windows), không chạy trên container Linux.

### Đoạn 5: dòng 40-41 — Xem help chi tiết
```powershell
Get-Help -Name Install-DbaInstance -Detailed |
Select -ExpandProperty Parameters
```
- **Ý nghĩa:** Liệt kê toàn bộ tham số của `Install-DbaInstance` cùng mô tả. Cực kỳ hữu ích khi cần tra cứu key cấu hình.
- **Đổi cho lab:** Chạy nguyên không cần đổi, đây là lệnh đọc tài liệu.
- **Lưu ý:** Có thể thay `-Detailed` bằng `-Full` để xem ví dụ.

### Đoạn 6: dòng 45-65 — Cài instance production bằng hashtable cấu hình
```powershell
$config = @{
    SQLSYSADMINACCOUNTS = "AD\SQL Prod Admins"
    SQLUSERDBDATADIR    = "S:\Mounts\Data\MSSQL14.MSSQLSERVER\MSSQL\Data"
    SQLUSERDBLOGDIR     = "S:\Mounts\Log\MSSQL14.MSSQLSERVER\MSSQL\Data"
    SQLTEMPDBDIR        = "S:\Mounts\Tempdb\MSSQL14.MSSQLSERVER\MSSQL\Data"
    SQLBACKUPDIR        = "\\nas\sqlprod\backups"
    TCPENABLED          = "1"
    NPENABLED           = "0"
    SQLSVCACCOUNT       = "NT AUTHORITY\SYSTEM"
    AGTSVCACCOUNT       = "NT AUTHORITY\SYSTEM"
    UPDATEENABLED       = "True"
    UPDATESOURCE        = "\\nas\sql\2017\update"
}
$splatInstallInst = @{
    SqlInstance   = "sql01"
    Path          = "E:\"
    Version       = "2017"
    Feature       = "Engine"
    Configuration = $config
}
Install-DbaInstance @splatInstallInst
```
- **Ý nghĩa:** Tách tham số ra hashtable để dễ đọc và tái sử dụng. `$config` là các tuỳ chọn SQL Server setup, `$splatInstallInst` là tham số của `Install-DbaInstance`.
- **Đổi cho lab:** Thay đường dẫn `S:\Mounts\...` bằng đường dẫn trong container hoặc VM, ví dụ `C:\dbatoolslab\Data`, `C:\dbatoolslab\Log`, `C:\dbatoolslab\Backup`.
- **Lưu ý:** **CẢNH BÁO** — đây là lệnh tạo instance hoàn chỉnh, không thể "undo" nhanh. Backup state máy trước, hoặc dùng snapshot VM.

### Đoạn 7: dòng 69-85 — Cài instance dev/test với cấu hình khác
```powershell
$config = @{
    SQLSYSADMINACCOUNTS = "ADTEST\SQL Test Admins"
    SQLUSERDBDATADIR    = "T:\Mounts\Data\MSSQL14.MSSQLSERVER\MSSQL\Data"
    ...
}
$splatInstallInst = @{
    SqlInstance = "sqltest01"
    Path        = "E:\"
    Version     = "2017"
    Feature     = "Engine"
    Configuration = $config
}
Install-DbaInstance @splatInstallInst
```
- **Ý nghĩa:** Cùng pattern như đoạn 6 nhưng cho môi trường test, sysadmin và đường dẫn khác. Cho thấy tính tái sử dụng của approach này.
- **Đổi cho lab:** Tương tự đoạn 6, dùng tài khoản local lab.
- **Lưu ý:** Trong production thường tách hai script này thành hai PowerShell module riêng để CI/CD pipeline gọi.

### Đoạn 8: dòng 89-95 — Cài từ file `.ini` SharePoint
```powershell
$splatInstallInst = @{
    SqlInstance       = "sql01"
    Path              = "E:\"
    Version           = "2017"
    ConfigurationFile = "\\nas\sqlconfigs\sharepointprod.ini"
}
Install-DbaInstance @splatInstallInst
```
- **Ý nghĩa:** Thay vì hashtable, dùng `.ini` chuẩn của SQL Server setup. Hữu ích khi đội platform đã có file mẫu được kiểm duyệt.
- **Đổi cho lab:** Tạo file `.ini` local rồi trỏ vào `-ConfigurationFile`.
- **Lưu ý:** File `.ini` không chứa mật khẩu (security). Service account password truyền qua `-Credential`.

### Đoạn 9: dòng 99-114 — Cài bằng tham số trực tiếp của Install-DbaInstance
```powershell
$installparams = @{
    Version             = 2017
    Feature             = "Engine"
    InstancePath        = "T:\Mounts\Data"
    DataPath            = "T:\Mounts\Data\MSSQL14.MSSQLSERVER\MSSQL\Data"
    LogPath             = "T:\Mounts\Log\MSSQL14.MSSQLSERVER\MSSQL\Data"
    TempPath            = "T:\Mounts\Tempdb\MSSQL14.MSSQLSERVER\MSSQL\Data"
    BackupPath          = "\\nas\sqltest\backups"
    AdminAccount        = "ADTESTDEV\SQL Test Admins"
    PerformVolumeMaintenanceTasks = $true
    Verbose             = $true
    Confirm             = $false
}
Install-DbaInstance @installparams
```
- **Ý nghĩa:** Không dùng hashtable `Configuration`, thay vào đó dùng các tham số "first-class" của `Install-DbaInstance` (DataPath, LogPath, AdminAccount...). dbatools tự dịch sang setup options.
- **Đổi cho lab:** Đổi đường dẫn về thư mục lab.
- **Lưu ý:** `PerformVolumeMaintenanceTasks = $true` bật quyền Instant File Initialization — nên bật cho data drive nhưng không nên cho log drive (log file vẫn phải zero-out).

### Đoạn 10: dòng 119-124 — Cập nhật instance hàng loạt
```powershell
$servers = Get-Content -Path C:\temp\servers.txt
$splatUpdateInst = @{
    ComputerName = $servers
    Path         = "\\nas\share\sqlserver2017-kb4498951-x64_b143d28a48204eb6.exe"
}
Update-DbaInstance @splatUpdateInst
```
- **Ý nghĩa:** Đọc danh sách server từ file text, áp cùng một CU cho tất cả. `Update-DbaInstance` tự dò version, áp đúng patch, restart dịch vụ.
- **Đổi cho lab:** Trên lab chỉ có 1-2 instance, không cần file. Có thể truyền `ComputerName = "dbatoolslab"`.
- **Lưu ý:** **CẢNH BÁO RẤT NGHIÊM TRỌNG** — sẽ restart SQL Service, downtime. Phải có change window và backup. Test trên dev trước.

### Đoạn 11: dòng 128-135 — Cập nhật cluster
```powershell
$splatUpdateInst = @{
    ComputerName = "sqlcluster"
    Version      = "2017"
    Type         = "CumulativeUpdate"
    Path         = "C:\temp\sqlserver2017-kb4498951-x64_b143d28a48204eb6.exe"
    InstanceName = "sqlexpress"
}
Update-DbaInstance @splatUpdateInst
```
- **Ý nghĩa:** Update SQL Server Express named instance trên một WSFC cluster. dbatools tự rolling update qua các node.
- **Đổi cho lab:** Lab không có cluster — đây là kiến thức để biết.
- **Lưu ý:** Rolling update vẫn có downtime ngắn lúc failover. Phải test ứng dụng có giữ session qua failover không.

## Lệnh thay vào lab của bạn

```powershell
# Lab không thực sự cài instance mới — chỉ thực hành lệnh xem help và service
# (vì cài SQL trong container dbatoolslab là việc đã có sẵn)

# 1) Xem help chi tiết
Get-Help Install-DbaInstance -Detailed | Select-Object -ExpandProperty Parameters

# 2) Liệt kê các dịch vụ SQL trên container lab
Get-DbaService -ComputerName dbatoolslab

# 3) Mô phỏng WhatIf cho Install (KHÔNG thực sự cài, chỉ thử)
$config = @{
    SQLSYSADMINACCOUNTS = "$env:USERDOMAIN\$env:USERNAME"
    SQLUSERDBDATADIR    = "C:\dbatoolslab\Data"
    SQLUSERDBLOGDIR     = "C:\dbatoolslab\Log"
    SQLBACKUPDIR        = "C:\dbatoolslab\Backup"
    TCPENABLED          = "1"
    NPENABLED           = "0"
}
$splatInstallInst = @{
    SqlInstance   = "dbatoolslab"
    Path          = "E:\"               # thay bằng folder media thật của bạn
    Version       = "2019"
    Feature       = "Engine"
    Configuration = $config
    WhatIf        = $true               # CHỈ MÔ PHỎNG, không thực sự cài
}
Install-DbaInstance @splatInstallInst

# 4) Thử Update-DbaInstance với -WhatIf để xem nó dự định làm gì
Update-DbaInstance -ComputerName dbatoolslab -WhatIf
```

## Self-check
1. **Định nghĩa:** Phân biệt `-Configuration` (hashtable) và `-ConfigurationFile` (`.ini`). Khi nào nên dùng cái nào?
2. **Thực hành:** Viết hashtable `$config` để cài SQL 2019 với data path `C:\sqldata`, log path `C:\sqllog`, backup path `\\backups\sql`, sysadmin là nhóm `DOMAIN\DBA Team`, bật TCP, tắt Named Pipes.
3. **Liên hệ:** Tại sao "second-hop" Kerberos lại cần thiết khi cài từ xa và media nằm trên share thứ ba? Hãy mô tả chuỗi authentication.

## Bài tập mở rộng
- **Bài 1:** Tạo một file `installConfig.ini` đầy đủ cho lab của bạn, sau đó dùng `Install-DbaInstance -ConfigurationFile` với `-WhatIf` để kiểm tra setup line dbatools dự định chạy.
- **Bài 2:** Viết hàm `Get-LabService` bọc `Get-DbaService -ComputerName dbatoolslab` và format output dạng bảng `ServiceName | State | StartName | StartMode`, lưu vào file CSV để snapshot trạng thái trước khi update.


---

!!! info "Nguồn gốc"
    `book_lab/dbatools-lab/bookcode/chapter13.notes.md`
