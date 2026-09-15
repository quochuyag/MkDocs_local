---
title: Chapter 14 — Export-DbaInstance và snapshot cấu hình instance
course: 11-book-lab
source: book_lab/dbatools-lab/bookcode/chapter14.notes.md
---

# Chapter 14 — Export-DbaInstance và snapshot cấu hình instance

## Mục tiêu
- Dùng `Export-DbaInstance` để xuất "toàn bộ" cấu hình một SQL instance ra script T-SQL có thể replay.
- Hiểu cấu trúc folder/file mà `Export-DbaInstance` tạo ra và biết loại trừ các thành phần không cần.
- Sử dụng `New-DbaScriptingOption` để kiểm soát cách dbatools script object (ví dụ thêm `IF NOT EXISTS`).
- Xuất từng phần (Agent job, stored proc, audit, audit spec) bằng `Export-DbaScript`.
- Xuất/import cấu hình `sp_configure` để đảm bảo instance đích có cùng setting với instance nguồn.

## Tóm tắt 3-5 ý chính
1. **`Export-DbaInstance` là "Documentation as Code"** — sinh ra một thư mục có timestamp, mỗi loại object (logins, jobs, audits, sp_configure...) một file `.sql`. Dùng làm baseline disaster recovery hoặc đầu vào cho Git.
2. **`Export-DbaScript` tổng quát hơn** — nhận bất kỳ object dbatools nào qua pipeline (job, sproc, view, audit...) và xuất ra T-SQL.
3. **`New-DbaScriptingOption` điều khiển SMO ScriptingOptions** — bật `IncludeIfNotExists`, `ScriptDrops`, `WithDependencies`... y hệt SSMS "Generate Scripts".
4. **`Export-DbaSpConfigure` và `Import-DbaSpConfigure`** — cặp lệnh đặc biệt để snapshot và áp lại cấu hình `sp_configure` (max memory, parallelism, ...).
5. **Get-Member là người bạn** — khi không biết object có scriptable hay không, `| Get-Member` cho thấy method `.Script()` hoặc property hữu ích.

## Giải thích từng đoạn code

### Đoạn 1: dòng 18 — Export toàn bộ instance
```powershell
Export-DbaInstance -SqlInstance sql01 -Path \\nas\backups\sql01
```
- **Ý nghĩa:** Xuất tất cả: logins, server roles, linked servers, audits, endpoints, Agent jobs, operators, alerts, sp_configure, custom errors, resource governor... Mỗi loại một file `.sql` trong folder con có timestamp.
- **Đổi cho lab:** Thay `sql01` bằng `dbatoolslab\sql2017` và `\\nas\backups\sql01` bằng `C:\dbatoolslab\Export`.
- **Lưu ý:** **CẢNH BÁO** — output có thể chứa **thông tin nhạy cảm** (login hash, linked server config). Không commit thẳng lên Git public. Đối với production, lưu vào share có ACL.

### Đoạn 2: dòng 22 — Xem folder kết quả
```powershell
Get-ChildItem .\sql01-11112019080741\
```
- **Ý nghĩa:** List nội dung folder export. Tên folder = `<instance>-<yyyyMMddHHmmss>`. Mỗi file là một object type.
- **Đổi cho lab:** `Get-ChildItem C:\dbatoolslab\Export\dbatoolslab$sql2017-*`.
- **Lưu ý:** Folder timestamp dùng để giữ lịch sử nhiều lần export liên tiếp.

### Đoạn 3: dòng 28-29 — Xem các tuỳ chọn scripting mặc định
```powershell
$options = New-DbaScriptingOption
$options | Select *
```
- **Ý nghĩa:** Tạo object `Microsoft.SqlServer.Management.Smo.ScriptingOptions` với mặc định dbatools, rồi xem toàn bộ thuộc tính (Indexes, Triggers, ScriptDrops, IncludeIfNotExists, ...).
- **Đổi cho lab:** Không cần đổi, chạy bất cứ máy nào có dbatools.
- **Lưu ý:** Mặc định đã chỉnh khá hợp lý so với SSMS, nhưng vẫn nên xem trước khi production-export.

### Đoạn 4: dòng 33-34 — Bật IncludeIfNotExists
```powershell
$options = New-DbaScriptingOption
$options.IncludeIfNotExists = $true
```
- **Ý nghĩa:** Sửa scripting option để script ra dạng `IF NOT EXISTS (...) BEGIN ... END` — idempotent, chạy nhiều lần không lỗi "object đã tồn tại".
- **Đổi cho lab:** Dùng nguyên.
- **Lưu ý:** Tuỳ chọn này thiết yếu khi script dùng cho deploy có thể replay.

### Đoạn 5: dòng 38-43 — Export instance loại trừ một phần
```powershell
$splatExportInstance = @{
    SqlInstance = "sql01"
    Path        = "C:\git\ExportInstance"
    Exclude     = "ResourceGovernor"
}
Export-DbaInstance @splatExportInstance
```
- **Ý nghĩa:** Export tất cả trừ Resource Governor. `-Exclude` nhận mảng, có thể loại bỏ nhiều mục: `Exclude = "ResourceGovernor","Logins","LinkedServers"`.
- **Đổi cho lab:** `SqlInstance = "dbatoolslab\sql2017"`, `Path = "C:\dbatoolslab\Export"`.
- **Lưu ý:** Loại trừ `Logins` nếu repo của bạn public — login script chứa hash SID.

### Đoạn 6: dòng 47-48 — Export một Agent job duy nhất
```powershell
Get-DbaAgentJob -SqlInstance sql01 | Select-Object -First 1 |
Export-DbaScript
```
- **Ý nghĩa:** Lấy job đầu tiên, đẩy qua pipeline cho `Export-DbaScript`. Mặc định lưu vào `Documents\<instance>-<timestamp>.sql`.
- **Đổi cho lab:** `Get-DbaAgentJob -SqlInstance dbatoolslab\sql2017`.
- **Lưu ý:** `Select-Object -First 1` chỉ để demo. Production thường `Where-Object Name -like 'Backup*'` chẳng hạn.

### Đoạn 7: dòng 53-55 — Xem nội dung script ngay tại console
```powershell
Get-DbaDbStoredProcedure -SqlInstance sql01 -Database master |
Where-Object Name -eq sp_MScleanupmergepublisher |
Export-DbaScript -Passthru
```
- **Ý nghĩa:** `-Passthru` in script thẳng ra console thay vì ghi file. Hữu ích khi muốn copy-paste nhanh hoặc nối thêm processing.
- **Đổi cho lab:** Thay sproc target. Ví dụ trên `WideWorldImporters` chọn một sproc thật.
- **Lưu ý:** `-Passthru` cũng có thể pipe đến `clip` (Windows) hoặc `Set-Clipboard`.

### Đoạn 8: dòng 59-60 — Copy script vào clipboard
```powershell
Get-DbaAgentJob -SqlInstance sql01 | Select-Object -First 1 |
Export-DbaScript | clip
```
- **Ý nghĩa:** Dùng `clip` của Windows để đưa script vào clipboard, paste vào SSMS/VS Code nhanh.
- **Đổi cho lab:** `Get-DbaAgentJob -SqlInstance dbatoolslab\sql2017 | Where-Object Name -like '*backup*' | Export-DbaScript | clip`.
- **Lưu ý:** `clip` không tồn tại trên Linux. Dùng `Set-Clipboard` của PowerShell 5+ cho cross-platform.

### Đoạn 9: dòng 64-71 — Export audit kèm scripting option
```powershell
$options = New-DbaScriptingOption
$options.includeifnotexists = $true
$splatExportScript = @{
    FilePath               = "C:\git\export\sql01\audit.sql"
    ScriptingOptionsObject = $options
}
Get-DbaInstanceAudit -SqlInstance sql01 |
Export-DbaScript @splatExportScript
```
- **Ý nghĩa:** Pattern chuẩn: tạo option, build splat, pipe object qua `Export-DbaScript`. Output là file `.sql` chứa toàn bộ Server Audit kèm `IF NOT EXISTS`.
- **Đổi cho lab:** `SqlInstance = "dbatoolslab\sql2017"`, `FilePath = "C:\dbatoolslab\Export\audit.sql"`.
- **Lưu ý:** Audit gắn với file path trên disk SQL. Script này phải replay trên máy có cùng cấu trúc thư mục, hoặc edit file path sau khi export.

### Đoạn 10: dòng 76-81 — Export Server Audit Specification
```powershell
$splatExportScript = @{
    FilePath               = "C:\git\export\sql01\auditspec.sql"
    ScriptingOptionsObject = $options
}
Get-DbaInstanceAuditSpecification -SqlInstance sql01 |
Export-DbaScript @splatExportScript
```
- **Ý nghĩa:** Tương tự đoạn 9 nhưng cho Server Audit Specification (định nghĩa event nào được audit).
- **Đổi cho lab:** Thay instance về `dbatoolslab\sql2017`.
- **Lưu ý:** Audit Spec phụ thuộc vào Audit object — replay phải theo thứ tự: Audit trước, AuditSpec sau, rồi `ALTER SERVER AUDIT ... WITH (STATE = ON)`.

### Đoạn 11: dòng 86 — Inspect member của Agent job
```powershell
Get-DbaAgentJob -SqlInstance sql01 | Get-Member
```
- **Ý nghĩa:** Liệt kê toàn bộ property/method của object SMO Agent Job. Dùng để biết object hỗ trợ `.Script()`, `.EnumHistory()`...
- **Đổi cho lab:** `Get-DbaAgentJob -SqlInstance dbatoolslab\sql2017 | Get-Member`.
- **Lưu ý:** `Get-Member` là một trong những cmdlet quan trọng nhất PowerShell — luôn dùng khi không rõ object có gì.

### Đoạn 12: dòng 91 — Inspect member của sp_configure object
```powershell
Get-DbaSpConfigure -SqlInstance sql01 | Get-Member
```
- **Ý nghĩa:** Xem object trả về của `Get-DbaSpConfigure` có property nào (`Name`, `ConfiguredValue`, `RunningValue`, `MinValue`, `MaxValue`...).
- **Đổi cho lab:** Thay instance.
- **Lưu ý:** Cách tốt nhất để học cấu trúc output trước khi viết script automation.

### Đoạn 13: dòng 96-100 — Export sp_configure
```powershell
$splatExportSpConf = @{
    SqlInstance = "sql01"
    FilePath    = "C:\git\ExportInstance\spconfigure.sql"
}
Export-DbaSpConfigure @splatExportSpConf
```
- **Ý nghĩa:** Xuất toàn bộ `sp_configure` của instance ra file T-SQL, dạng `EXEC sp_configure 'max server memory (MB)', 8192; RECONFIGURE;`.
- **Đổi cho lab:** `SqlInstance = "dbatoolslab\sql2017"`, `FilePath = "C:\dbatoolslab\Export\spconfigure.sql"`.
- **Lưu ý:** Cẩn thận: file này chứa cả setting nâng cao. Khi import lên instance khác, phải bật `show advanced options` trước.

### Đoạn 14: dòng 104-109 — Import sp_configure
```powershell
$splatExportSpConf = @{
    SqlInstance   = "sql01,15591"
    SqlCredential = "sqladmin"
    Path          = "C:\git\ExportInstance\spconfigure.sql"
}
Import-DbaSpConfigure @splatExportSpConf
```
- **Ý nghĩa:** Áp lại file `spconfigure.sql` lên instance đích. `sql01,15591` là syntax `host,port`. `-SqlCredential` đăng nhập SQL Auth.
- **Đổi cho lab:** `SqlInstance = "dbatoolslab"` (target — empty instance để đồng bộ setting từ sql2017), `Path = "C:\dbatoolslab\Export\spconfigure.sql"`.
- **Lưu ý:** **CẢNH BÁO** — sẽ thay đổi cấu hình instance đích. Có config yêu cầu restart (max worker threads, locks, ...). Phải `-WhatIf` trước.

## Lệnh thay vào lab của bạn

```powershell
# Source = dbatoolslab\sql2017 (instance đã có data trong lab)
$source = "dbatoolslab\sql2017"
$exportRoot = "C:\dbatoolslab\Export"

# 1) Export toàn bộ instance — loại trừ ResourceGovernor cho gọn
$splatExportInstance = @{
    SqlInstance = $source
    Path        = $exportRoot
    Exclude     = "ResourceGovernor"
}
Export-DbaInstance @splatExportInstance

# 2) Xem folder kết quả
Get-ChildItem $exportRoot

# 3) Export một Agent job ra clipboard
Get-DbaAgentJob -SqlInstance $source |
    Select-Object -First 1 |
    Export-DbaScript -Passthru

# 4) Export sp_configure
Export-DbaSpConfigure -SqlInstance $source -FilePath "$exportRoot\spconfigure.sql"

# 5) Import sp_configure sang target — DÙNG -WhatIf TRƯỚC
Import-DbaSpConfigure -SqlInstance "dbatoolslab" -Path "$exportRoot\spconfigure.sql" -WhatIf

# 6) Script audit với IncludeIfNotExists
$opt = New-DbaScriptingOption
$opt.IncludeIfNotExists = $true
Get-DbaInstanceAudit -SqlInstance $source |
    Export-DbaScript -FilePath "$exportRoot\audit.sql" -ScriptingOptionsObject $opt
```

## Self-check
1. **Định nghĩa:** `Export-DbaInstance` và `Export-DbaScript` khác nhau ở điểm nào? Khi nào dùng cái nào?
2. **Thực hành:** Tạo `$options = New-DbaScriptingOption` rồi bật cả `IncludeIfNotExists` và `ScriptDrops`. Pipe `Get-DbaDbStoredProcedure` qua `Export-DbaScript` với options đó, mở file kết quả và xác nhận thấy cả `DROP PROCEDURE IF EXISTS` lẫn `CREATE PROCEDURE`.
3. **Liên hệ:** Một instance production của bạn đột nhiên crash phải build lại. Bạn có folder export từ tuần trước. Liệt kê thứ tự apply các file `.sql` để hồi phục cấu hình (không gồm database, chỉ instance-level).

## Bài tập mở rộng
- **Bài 1:** Viết script PowerShell chạy `Export-DbaInstance` hàng tuần cho `dbatoolslab\sql2017`, sau đó commit folder kết quả vào git repo. Đặt scheduled task hoặc SQL Agent job kích hoạt nó.
- **Bài 2:** So sánh `sp_configure` giữa hai instance: export từ `dbatoolslab\sql2017` và từ `dbatoolslab`, dùng `Compare-Object` (hoặc diff thường) để xem cấu hình lệch nhau ở đâu.


---

!!! info "Nguồn gốc"
    `book_lab/dbatools-lab/bookcode/chapter14.notes.md`
