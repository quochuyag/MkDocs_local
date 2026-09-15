---
title: Chapter 09 — Error log, logins và quản trị quyền
course: 11-book-lab
source: book_lab/dbatools-lab/bookcode/chapter09.notes.md
---

# Chapter 09 — Error log, logins và quản trị quyền

> Lưu ý quan trọng: Tên user gọi chapter 09 là "SQL Server error log analysis", nhưng đọc file `chapter09.ps1` thực tế thấy nội dung gồm 3 cụm chính:
> 1. Đọc SQL Server error log (`Get-DbaErrorLog`)
> 2. Tạo / copy / export login (`New-DbaLogin`, `Copy-DbaLogin`, `Export-DbaLogin`)
> 3. Audit quyền user và xuất Excel có conditional formatting (`Get-DbaUserPermission`, `Find-DbaLoginInGroup`)
>
> Notes file này theo đúng nội dung thực tế của file `.ps1`.

## Mục tiêu

- Biết cách đọc error log SQL Server bằng `Get-DbaErrorLog` thay vì mở SSMS.
- Tạo SQL login và Windows login bằng `New-DbaLogin`, hiểu cách splat tham số.
- Đồng bộ login giữa các replica AG bằng `Copy-DbaLogin` (mẫu code Agent job production).
- Export login schema (T-SQL) ra file để version control bằng Git.
- Audit quyền user trong database và tô màu cảnh báo bằng `Export-Excel` + `Add-ConditionalFormatting`.

## Tóm tắt 5 ý chính

1. **`Get-DbaErrorLog -After`** — lọc log theo timestamp gần đây, tránh xả toàn bộ log mấy MB. Đây là cách thay thế SSMS Log File Viewer cho mọi instance bạn quản lý.
2. **`New-DbaLogin`** — tạo login với 3 dạng đầu vào: tên (mặc định Windows login), object `PSCredential` (SQL login), hoặc qua splat. Có thể đẩy vào `-SqlInstance` là **mảng instance** từ `Get-DbaRegisteredServer` để tạo cùng lúc trên nhiều server.
3. **`Copy-DbaLogin` trong AG** — mẫu code production: lấy danh sách replica, lặp qua, copy login chéo. Có error handling với `EnableException = $true` để Agent job báo fail đúng.
4. **`Export-DbaLogin` + Git** — sinh script `CREATE LOGIN` ra file `.sql`, commit vào repo. Đây là pattern "infrastructure as code" cho security.
5. **Audit Excel** — kết hợp `Get-DbaUserPermission` với module `ImportExcel`. Hàng có `sysadmin` hoặc `db_owner` được tô vàng cảnh báo — ý tưởng: gửi báo cáo Excel tự động cho team security.

## Giải thích từng đoạn code

### Đoạn 1: dòng 18-22 — Đọc error log 5 phút gần nhất

```powershell
$splatGetErrorLog = @{
    SqlInstance = "SQL01"
    After = (Get-Date).AddMinutes(-5)
}
Get-DbaErrorLog @splatGetErrorLog | Select LogDate, Source, Text
```

- **Ý nghĩa:** Đọc SQL Server error log của instance `SQL01`, chỉ lấy các entry sau thời điểm "5 phút trước". Chiếu 3 cột chính: thời điểm, nguồn (Logon, Backup, Server, …), nội dung.
- **Đổi cho lab:** Thay `"SQL01"` → `"dbatoolslab\sql2017"`. `Get-DbaErrorLog` dùng SMO nên không cần SQL Agent — chạy được cả trên SQL Express.
- **Lưu ý:** Nếu instance vừa khởi động, error log có thể có rất nhiều entry "Login succeeded" trong vòng vài phút. Có thể thêm `| Where-Object Source -ne 'Logon'` để giảm nhiễu.

### Đoạn 2: dòng 26 — Tạo Windows login đơn giản

```powershell
New-DbaLogin -SqlInstance SQL01 -Login Factory
```

- **Ý nghĩa:** Tạo Windows login tên `Factory` (mặc định khi không có `-SecurePassword`, dbatools giả định đây là Windows login).
- **Đổi cho lab:** Thay `SQL01` → `dbatoolslab\sql2017`. Tên `Factory` trong lab nên đổi thành tài khoản thật tồn tại trên máy bạn — ví dụ `BUILTIN\Users` hoặc 1 local user bạn đã tạo (`$env:COMPUTERNAME\TestUser`).
- **Lưu ý:** Lệnh sẽ FAIL nếu Windows principal không tồn tại. Dùng `-WhatIf` lần đầu để xem nó định làm gì:
  ```powershell
  New-DbaLogin -SqlInstance dbatoolslab\sql2017 -Login "$env:COMPUTERNAME\TestUser" -WhatIf
  ```

### Đoạn 3: dòng 30-31 — Tạo login trên TẤT CẢ registered servers

```powershell
$servers = Get-DbaRegisteredServer
New-DbaLogin -SqlInstance $servers -Login ad\factoryauditors
```

- **Ý nghĩa:** Lấy danh sách instance đã đăng ký trong Central Management Server (CMS) hoặc Local Server Groups của SSMS, rồi tạo login `ad\factoryauditors` (AD group) trên mọi instance.
- **Đổi cho lab:** Lab chưa có CMS — bạn có thể tự đăng ký bằng `Add-DbaRegServer` trước, hoặc thay `$servers` bằng mảng cứng:
  ```powershell
  $servers = "dbatoolslab", "dbatoolslab\sql2017"
  ```
- **Lưu ý:** Đây là mô hình "broadcast" — rất tiện nhưng rất nguy hiểm. Một lỗi sẽ áp lên N server cùng lúc. Luôn `-WhatIf` trước.

### Đoạn 4: dòng 35-42 — Tạo SQL login (có mật khẩu) trên nhiều server

```powershell
$servers = Get-DbaRegisteredServer
$cred = Get-Credential factoryuser1
$splatNewLogin = @{
    SqlInstance = $servers
    Login = $cred.UserName
    SecurePassword = $cred.Password
}
New-DbaLogin @splatNewLogin
```

- **Ý nghĩa:** Hỏi mật khẩu tương tác (`Get-Credential`), rồi tạo SQL login `factoryuser1` trên tất cả registered server. Khi có `-SecurePassword`, dbatools tạo SQL login (không phải Windows login).
- **Đổi cho lab:**
  ```powershell
  $servers = "dbatoolslab\sql2017"
  $cred = Get-Credential -UserName factoryuser1 -Message "Mat khau login moi"
  ```
- **Lưu ý:** Mật khẩu phải vượt qua password policy của Windows nếu instance enable `CHECK_POLICY = ON`. Thêm `-PasswordPolicyEnforced:$false -PasswordExpirationEnabled:$false` nếu muốn test nhanh.

### Đoạn 5: dòng 46 — Liệt kê user của 1 database

```powershell
Get-DbaDbUser -SqlInstance SQL01 -Database WideWorldImporters | Select Name
```

- **Ý nghĩa:** Đếm và liệt kê tên user trong DB `WideWorldImporters`. Khác với `Get-DbaLogin` (cấp instance), `Get-DbaDbUser` ở cấp database.
- **Đổi cho lab:** `dbatoolslab\sql2017`. DB `WideWorldImporters` đã có sẵn sau khi chạy `scripts/02_Configure_Lab.ps1`.
- **Lưu ý:** Đoạn 6 (dòng 50) giống hệt đoạn 5 — có vẻ là chỗ sách đối chiếu trước/sau khi sửa orphan user.

### Đoạn 6: dòng 54 — Sửa orphan user (CHÚ Ý CÓ TYPO)

```powershell
Repair-DbaDbOrphanUser -SqlInstance SQL01"
```

- **Ý nghĩa:** Một orphan user là DB user mà SID không khớp với login nào trên instance (thường xảy ra khi restore DB từ server khác). `Repair-DbaDbOrphanUser` tự động map lại SID nếu tìm được login cùng tên.
- **CẢNH BÁO:** Dòng này có dấu `"` thừa cuối — code book bị lỗi cú pháp, sẽ throw parse error. Khi paste vào lab, BỎ dấu `"`:
  ```powershell
  Repair-DbaDbOrphanUser -SqlInstance dbatoolslab\sql2017
  ```
- **Lưu ý:** Mặc định lệnh chạy cho tất cả DB. Thêm `-Database WideWorldImporters` để giới hạn.

### Đoạn 7: dòng 58-100 — Mẫu code đồng bộ login cho AG (Agent job)

```powershell
try {
    $splatGetAgReplica = @{
        SqlInstance = $ENV:ComputerName
        EnableException = $true
    }
    $replicas = (Get-DbaAgReplica $splatGetAgReplica).Name
}
catch {
    Write-Error -Message $_ -ErrorAction Stop
}

foreach ($replica in $replicas) {
    Write-Output "For this replica $replica"
    $replicastocopy = $replicas | Where-Object { $_ -ne $replica }
    foreach ($replicatocopy in $replicastocopy) {
      Write-Output "We will copy logins from $replica to $replicatocopy"

      $splatCopyLogin = @{
          Source = $replica
          Destination = $replicatocopy
          ExcludeSystemLogins = $true
          EnableException = $true
      }

      try {
        $output =  Copy-DbaLogin @splatCopyLogin
      } catch {
        $error[0..5] | Format-List -Force | Out-String
        Write-Error -Message $_ -ErrorAction Stop
      }
        if ($output.Status -contains 'Failed') {
            $error[0..5] | Format-List -Force | Out-String
            Write-Error -Message "At least one login failed.
            [CA]See log for details." -ErrorAction Stop
        }
    }
}
```

- **Ý nghĩa:** Đây là pattern Agent job production. Chạy trên 1 node AG, tự khám phá các replica khác, rồi copy login chéo giữa các node. Lý do quan trọng: AG không sync metadata cấp instance — login phải đồng bộ thủ công.
- **Tại sao `EnableException = $true`?** Mặc định dbatools chỉ in lỗi (warning), không throw — Agent job sẽ thấy "Succeeded" dù lệnh fail. Bật `EnableException` để biến warning thành exception, kết hợp `-ErrorAction Stop` để Agent job báo Failed đúng.
- **Đổi cho lab:** Lab chỉ có 1 instance đơn lẻ — KHÔNG có AG. Đoạn này coi như đọc hiểu, không chạy. Nếu muốn thử `Copy-DbaLogin` giữa 2 instance lab:
  ```powershell
  Copy-DbaLogin -Source "dbatoolslab\sql2017" -Destination "dbatoolslab" `
      -ExcludeSystemLogins -Login WWI_ReadOnly, WWI_ReadWrite -WhatIf
  ```
- **Lưu ý:** Đoạn `[CA]` ở dòng 97 có vẻ là ký tự lạ do encode — bỏ đi khi copy.

### Đoạn 8: dòng 104 — Export login schema (CŨNG CÓ TYPO)

```powershell
Export-DbaLogin -SqlInstance SQL01"
```

- **CẢNH BÁO:** Lại dấu `"` thừa. Bỏ khi paste.
- **Ý nghĩa:** Sinh ra script T-SQL `CREATE LOGIN ... WITH PASSWORD = HASHED ...` cho tất cả login, lưu vào `$home\<instance>-<timestamp>-login.sql`.
- **Đổi cho lab:**
  ```powershell
  Export-DbaLogin -SqlInstance dbatoolslab\sql2017 -Path C:\dbatoolslab\exports
  ```

### Đoạn 9: dòng 108 — Khởi tạo git repo cho schema

```powershell
git init
```

- **Ý nghĩa:** Khởi tạo Git repo ngay tại thư mục hiện hành, chuẩn bị version control cho file `.sql` export.
- **Lưu ý:** Chạy đúng trong thư mục bạn muốn track — vd `cd C:\dbatoolslab\exports; git init`.

### Đoạn 10: dòng 114-117 — Export với tên file định trước

```powershell
$date = Get-Date
$path = "$home\sourcerepo\SqlPermission"
$file = "Factory.sql"
Export-DbaLogin -SqlInstance SQL01"
```

- **CẢNH BÁO:** Cùng typo `SQL01"`. Hơn nữa, lệnh chưa truyền `-FilePath` hay `-Path`, nên các biến `$path`, `$file` không có tác dụng.
- **Đổi cho lab (có ý nghĩa):**
  ```powershell
  $date = Get-Date -Format 'yyyyMMdd'
  $path = "$home\sourcerepo\SqlPermission"
  New-Item -ItemType Directory -Path $path -Force | Out-Null
  $file = "Factory-$date.sql"
  Export-DbaLogin -SqlInstance dbatoolslab\sql2017 -FilePath (Join-Path $path $file)
  ```

### Đoạn 11: dòng 121-123 — Commit file vào git

```powershell
Set-Location $path
git add $file
git commit -m "The Factory users update for $date"
```

- **Ý nghĩa:** Cd vào thư mục export, stage file, commit.
- **Lưu ý:** Chạy `git config user.email` và `user.name` trước nếu chưa có. Đoạn này yêu cầu Git đã cài (`scripts/00_Install_Prereqs.ps1` cài qua chocolatey).

### Đoạn 12: dòng 127-128 — Audit user permission

```powershell
Get-DbaUserPermission -SqlInstance SQL01 -Database WideWorldImporters |
Select SqlInstance, Object, Type, Member, RoleSecurableClass | Format-Table"
```

- **CẢNH BÁO:** Lại dấu `"` thừa cuối. Bỏ.
- **Ý nghĩa:** `Get-DbaUserPermission` trả về 1 dataset rất chi tiết — server roles, database roles, object permissions. Project ra 5 cột để dễ đọc.
- **Đổi cho lab:**
  ```powershell
  Get-DbaUserPermission -SqlInstance dbatoolslab\sql2017 -Database WideWorldImporters |
      Select-Object SqlInstance, Object, Type, Member, RoleSecurableClass |
      Format-Table -AutoSize
  ```
- **Lưu ý:** Lệnh này CHẬM trên DB lớn — nó tạo và xoá vài stored proc tạm để query system catalog. Lần đầu chạy có thể mất 30-60s.

### Đoạn 13: dòng 132-161 — Xuất Excel có conditional formatting

```powershell
$splatExportExcel = @{
 Path = "C:\temp\FactoryPermissions.xlsx"
 WorksheetName = "User Permissions"
 AutoSize = $true
 FreezeTopRow = $true
 AutoFilter = $true
 PassThru = $true
}

$excel = Get-DbaUserPermission -SqlInstance SQL01 -Database WideWorldImporters | Export-Excel @splatExportExcel

$rulesparam = @{
 Address = $excel.Workbook.Worksheets["User Permissions"].Dimension.Address
 WorkSheet = $excel.Workbook.Worksheets["User Permissions"]
 RuleType = "Expression"
}

Add-ConditionalFormatting @rulesparam -ConditionValue 'NOT(ISERROR(FIND("sysadmin",$G1)))' -BackgroundColor Yellow -StopIfTrue
Add-ConditionalFormatting @rulesparam -ConditionValue 'NOT(ISERROR(FIND("db_owner",$G1)))' -BackgroundColor Yellow -StopIfTrue
Add-ConditionalFormatting @rulesparam -ConditionValue 'NOT(ISERROR(FIND("SERVER LOGINS",$E1)))' -BackgroundColor PaleGreen
Add-ConditionalFormatting @rulesparam -ConditionValue 'NOT(ISERROR(FIND("SERVER SECURABLES",$E1)))' -BackgroundColor PowderBlue
Add-ConditionalFormatting @rulesparam -ConditionValue 'NOT(ISERROR(FIND("DB ROLE MEMBERS",$E1)))' -BackgroundColor GoldenRod
Add-ConditionalFormatting @rulesparam -ConditionValue 'NOT(ISERROR(FIND("DB SECURABLES",$E1)))' -BackgroundColor BurlyWood

Close-ExcelPackage $excel
```

- **Ý nghĩa:** Xuất kết quả audit ra file `.xlsx`, freeze hàng tiêu đề, bật autofilter, sau đó áp 6 conditional formatting rule:
  - Cột G chứa "sysadmin" → tô **vàng** (cảnh báo cao).
  - Cột G chứa "db_owner" → tô **vàng**.
  - Cột E (RoleSecurableClass) chứa "SERVER LOGINS" / "SERVER SECURABLES" / "DB ROLE MEMBERS" / "DB SECURABLES" → tô màu phân loại.
- **Đổi cho lab:**
  ```powershell
  $splatExportExcel.Path = "C:\dbatoolslab\reports\WWI-Permissions.xlsx"
  New-Item -ItemType Directory -Path "C:\dbatoolslab\reports" -Force | Out-Null
  $excel = Get-DbaUserPermission -SqlInstance dbatoolslab\sql2017 -Database WideWorldImporters |
      Export-Excel @splatExportExcel
  # ... (giữ nguyên các Add-ConditionalFormatting)
  Close-ExcelPackage $excel
  ```
- **Lưu ý:** Cần cài module `ImportExcel`:
  ```powershell
  Install-Module ImportExcel -Scope CurrentUser
  ```
  Chú ý `$G1`, `$E1` là **địa chỉ tương đối** kiểu Excel — sách giả định layout cột G = Member, E = RoleSecurableClass. Nếu bạn `Select` cột khác, phải đổi địa chỉ.

### Đoạn 14: dòng 165 — Tìm login nằm trong AD group

```powershell
Find-DbaLoginInGroup -SqlInstance SQL01 -Login "ad\bmiller"
```

- **Ý nghĩa:** Bạn có 1 user AD `ad\bmiller`. Họ không có login trực tiếp trên SQL — nhưng thuộc 1 AD group đã được cấp quyền. Lệnh này resolve gián tiếp, trả về group nào đang chứa user.
- **Đổi cho lab:** Lab không trong AD, lệnh sẽ fail. Coi như đọc hiểu, hoặc thử với local group:
  ```powershell
  Find-DbaLoginInGroup -SqlInstance dbatoolslab\sql2017 -Login "$env:COMPUTERNAME\<user>"
  ```

## Lệnh thay vào lab của bạn

```powershell
# 1) Đọc error log 30 phút qua, bỏ qua Logon noise
$splat = @{
    SqlInstance = "dbatoolslab\sql2017"
    After       = (Get-Date).AddMinutes(-30)
}
Get-DbaErrorLog @splat |
    Where-Object Source -ne 'Logon' |
    Select-Object LogDate, Source, Text |
    Format-Table -AutoSize

# 2) Tạo SQL login mới trong lab — luôn -WhatIf trước
$cred = Get-Credential -UserName "lab_factory1" -Message "Mat khau cho login moi"
$splatNew = @{
    SqlInstance              = "dbatoolslab\sql2017"
    Login                    = $cred.UserName
    SecurePassword           = $cred.Password
    PasswordPolicyEnforced   = $false
    PasswordExpirationEnabled = $false
}
New-DbaLogin @splatNew -WhatIf
# Sau khi -WhatIf in đúng dự định, bỏ -WhatIf chạy thật

# 3) Liệt kê user trong WideWorldImporters
Get-DbaDbUser -SqlInstance dbatoolslab\sql2017 -Database WideWorldImporters |
    Select-Object Name, LoginType, CreateDate

# 4) Export login schema ra thư mục backup
$exportDir = "C:\dbatoolslab\Backup\logins"
New-Item -ItemType Directory -Path $exportDir -Force | Out-Null
Export-DbaLogin -SqlInstance dbatoolslab\sql2017 -Path $exportDir

# 5) Audit quyền user WWI ra Excel
Install-Module ImportExcel -Scope CurrentUser -Force -ErrorAction SilentlyContinue
$reportDir = "C:\dbatoolslab\reports"
New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
$splatExcel = @{
    Path          = Join-Path $reportDir "WWI-Permissions.xlsx"
    WorksheetName = "User Permissions"
    AutoSize      = $true
    FreezeTopRow  = $true
    AutoFilter    = $true
    PassThru      = $true
}
$excel = Get-DbaUserPermission -SqlInstance dbatoolslab\sql2017 -Database WideWorldImporters |
    Export-Excel @splatExcel
$rules = @{
    Address   = $excel.Workbook.Worksheets["User Permissions"].Dimension.Address
    WorkSheet = $excel.Workbook.Worksheets["User Permissions"]
    RuleType  = "Expression"
}
Add-ConditionalFormatting @rules -ConditionValue 'NOT(ISERROR(FIND("sysadmin",$G1)))' -BackgroundColor Yellow -StopIfTrue
Add-ConditionalFormatting @rules -ConditionValue 'NOT(ISERROR(FIND("db_owner",$G1)))'  -BackgroundColor Yellow -StopIfTrue
Close-ExcelPackage $excel
Invoke-Item $splatExcel.Path  # mở file để xem
```

## Self-check (3 câu)

1. **Định nghĩa:** `Get-DbaErrorLog` có thể đọc log của bao nhiêu file `errorlog.N` mặc định? Tham số nào giới hạn số file đọc?
2. **Thực hành:** Tạo 1 login SQL `lab_test1`, chạy `Get-DbaUserPermission` ngay sau đó. Vì sao login mới không xuất hiện trong kết quả?
3. **Liên hệ:** `Copy-DbaLogin` khác `Export-DbaLogin` + `Invoke-DbaQuery` ở 2 điểm — kể tên (gợi ý: idempotency và secret handling).

## Bài tập mở rộng

- **Bài 1:** Viết script kiểm tra error log 24h qua, lọc các entry có Text khớp regex `failed|error|severity`, gửi email cho admin nếu có >5 entry. Dùng `Send-MailMessage` hoặc `Send-MgUserMail`.
- **Bài 2:** Mở rộng đoạn audit Excel — thêm sheet thứ 2 chứa `Get-DbaServerRoleMember` (sysadmin của instance), highlight đỏ nếu thấy login lạ (không thuộc allow-list của bạn).
- **Bài 3:** Đoạn AG sync login coi như template — viết phiên bản đơn server: xuất login từ `dbatoolslab\sql2017` ra T-SQL, lưu vào git, commit hằng tuần bằng Scheduled Task.


---

!!! info "Nguồn gốc"
    `book_lab/dbatools-lab/bookcode/chapter09.notes.md`
