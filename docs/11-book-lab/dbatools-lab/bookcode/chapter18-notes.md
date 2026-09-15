---
title: Chapter 18 — Tự động hoá với `$PSDefaultParameterValues` và logging
course: 11-book-lab
source: book_lab/dbatools-lab/bookcode/chapter18.notes.md
---

# Chapter 18 — Tự động hoá với `$PSDefaultParameterValues` và logging

## Mục tiêu
- Hiểu cơ chế `$PSDefaultParameterValues` để giảm việc lặp lại tham số cho hàng loạt cmdlet `dbatools`.
- Biết cách bật `EnableException` mặc định cho toàn bộ lệnh `*-Dba*` để bắt được lỗi đúng theo chuẩn PowerShell.
- Sử dụng splatting (`@splat`) cho các lệnh dài như `Set-DbaAgentServer`.
- Ghi nhật ký phiên làm việc tự động bằng `Start-Transcript` / `Stop-Transcript` phục vụ audit.
- Phân biệt khi nào dùng default parameter, khi nào nên truyền tham số trực tiếp.

## Tóm tắt 3-5 ý chính
1. **`$PSDefaultParameterValues`** là hashtable hệ thống của PowerShell, key có dạng `'CmdletName:ParamName'`. Khi cmdlet được gọi, nếu user không truyền tham số đó thì PowerShell tự bơm giá trị mặc định vào — rất hữu ích khi bạn luôn làm việc trên cùng 1 instance.
2. **Wildcard cho cmdlet và tham số** — key `'*-Dba*:EnableException' = $true` áp dụng cho mọi lệnh `*-Dba*` của dbatools, biến warning silent thành exception thật để dùng được `try/catch`.
3. **Splatting** dùng hashtable đặt trước rồi truyền `@splat` thay vì viết một dòng dài — đặc biệt hợp với `Set-DbaAgentServer`, `New-DbaAgentJob` (nhiều tham số).
4. **Cẩn thận với scope** — `$PSDefaultParameterValues` có tác dụng cho cả session. Nếu set trong script mà không dọn, các script sau dùng chung tab cũng dính. Cách an toàn: dùng trong `$PROFILE` hoặc reset bằng `$PSDefaultParameterValues.Clear()` cuối script.
5. **`Start-Transcript`** ghi toàn bộ input/output của console ra file — dùng làm bằng chứng audit, nhất là khi chạy thao tác thay đổi cấu hình SQL.

## Giải thích từng đoạn code

### Đoạn 1: dòng 18
```powershell
$PSDefaultParameterValues["Get-DbaDatabase:SqlInstance"] = "sql01"
```
- **Ý nghĩa:** Mặc định, nếu gọi `Get-DbaDatabase` mà không truyền `-SqlInstance`, PowerShell sẽ tự thêm `-SqlInstance sql01`.
- **Đổi cho lab:** đổi sang `dbatoolslab\sql2017` (instance có Agent và sample DB).
- **Mẹo:** Sau khi set xong, thử chỉ gõ `Get-DbaDatabase` — sẽ thấy danh sách DB của lab xuất hiện mà không cần truyền instance.
- **Lưu ý:** Khi viết script chia sẻ cho người khác, đừng dựa vào default này — họ có thể chưa set, lệnh sẽ hỏi instance hoặc fail. Default chỉ dành cho lab/session cá nhân.

### Đoạn 2: dòng 22
```powershell
$PSDefaultParameterValues['*-Dba*:EnableException'] = $true
```
- **Ý nghĩa:** Áp dụng `-EnableException $true` cho **mọi** cmdlet có pattern tên `*-Dba*` (gần như toàn bộ dbatools).
- **Tại sao quan trọng:** Mặc định dbatools dùng `Write-Warning` thay vì throw — không bắt được bằng `try/catch`. Bật flag này biến warning thành terminating error → script tự động hoá an toàn hơn.
- **Đổi cho lab:** giữ nguyên — đây là best practice khi viết script tự động.
- **Lưu ý:** Khi bật rồi, gọi lệnh sai sẽ raise exception. Hãy bọc `try { ... } catch { ... }` cho các thao tác nhạy cảm.

### Đoạn 3: dòng 26-31
```powershell
$splatSetAgent = @{
  SqlInstance = "sql1"
  MaximumHistoryRows = 10000
  MaximumJobHistoryRows = 100
}
Set-DbaAgentServer @splatSetAgent
```
- **Ý nghĩa:** Cấu hình lại SQL Server Agent — giới hạn tổng số dòng lịch sử (`MaximumHistoryRows`) và số dòng mỗi job (`MaximumJobHistoryRows`).
- **Đổi cho lab:** đổi `SqlInstance = "sql1"` thành `SqlInstance = "dbatoolslab\sql2017"` (instance có Agent — `dbatoolslab` default trong devcontainer Linux không có Agent đầy đủ).
- **Cảnh báo:** `Set-DbaAgentServer` thay đổi cấu hình thật trên Agent → chạy `-WhatIf` lần đầu để xem sẽ đổi gì:
  ```powershell
  Set-DbaAgentServer @splatSetAgent -WhatIf
  ```
- **Mẹo:** Nếu thấy bảng `msdb..sysjobhistory` to bất thường, đây là 2 setting đầu tiên cần kiểm tra.

### Đoạn 4: dòng 35-38
```powershell
$date = Get-Date -Format FileDateTime
Start-Transcript -Path "\\loggingserver\sql01\filelist-$date.txt"
Get-ChildItem -Path C:\
Stop-Transcript
```
- **Ý nghĩa:** Bật transcript ghi mọi thứ console hiển thị vào file có timestamp, chạy 1 lệnh demo, rồi tắt transcript.
- **Format `FileDateTime`** trả về chuỗi an toàn cho tên file (vd `20260514T0930451234`).
- **Đổi cho lab:** đường dẫn `\\loggingserver\sql01\...` không tồn tại — đổi sang ổ local:
  ```powershell
  Start-Transcript -Path "C:\dbatoolslab\logs\filelist-$date.txt"
  ```
  (tạo thư mục `C:\dbatoolslab\logs` trước nếu chưa có).
- **Lưu ý:** Mỗi session chỉ chạy được 1 transcript tại 1 thời điểm. Nếu quên `Stop-Transcript` thì lần `Start-Transcript` sau sẽ báo lỗi (hoặc append, tuỳ flag).

## Lệnh thay vào lab của bạn

```powershell
# Lab đã có sẵn job 'dbatools lab job' và 'dbatools lab job - where am I' trên dbatoolslab\sql2017
# Cùng các Ola Hallengren jobs (DatabaseBackup, IndexOptimize...) do Install-DbaMaintenanceSolution tạo

# 1) Set default instance + bật EnableException cho cả session
$PSDefaultParameterValues['*-Dba*:SqlInstance']      = 'dbatoolslab\sql2017'
$PSDefaultParameterValues['*-Dba*:EnableException']  = $true

# Kiểm tra: gọi không cần -SqlInstance vẫn ra danh sách DB
Get-DbaDatabase | Select-Object Name, Status

# 2) Splat + WhatIf trước khi đổi cấu hình Agent
$splatSetAgent = @{
    SqlInstance           = 'dbatoolslab\sql2017'
    MaximumHistoryRows    = 10000
    MaximumJobHistoryRows = 100
}
Set-DbaAgentServer @splatSetAgent -WhatIf   # xem trước
# Khi đã chắc chắn:
Set-DbaAgentServer @splatSetAgent

# 3) Wrapper function dùng default values bên trong
function Get-LabDatabase {
    param([string]$Name = '*')
    Get-DbaDatabase -Database $Name | Select-Object Name, SizeMB, Status
}
Get-LabDatabase WideWorldImporters

# 4) Transcript ra ổ local
$logDir = 'C:\dbatoolslab\logs'
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }
$date = Get-Date -Format FileDateTime
Start-Transcript -Path (Join-Path $logDir "lab-session-$date.txt")
Get-DbaAgentJob | Select-Object Name, Category, Enabled
Stop-Transcript

# 5) Dọn default values trước khi đóng session (an toàn cho script khác)
$PSDefaultParameterValues.Remove('*-Dba*:SqlInstance')
$PSDefaultParameterValues.Remove('*-Dba*:EnableException')
```

## Self-check
1. **Định nghĩa:** Key trong `$PSDefaultParameterValues` có cấu trúc thế nào? Cho ví dụ áp dụng default `-Confirm:$false` cho mọi cmdlet `Remove-*`.
2. **Thực hành:** Set `$PSDefaultParameterValues['Get-DbaAgentJob:SqlInstance'] = 'dbatoolslab\sql2017'`, sau đó gõ `Get-DbaAgentJob` không kèm tham số. Quan sát kết quả. Tiếp theo gỡ default bằng `$PSDefaultParameterValues.Remove('Get-DbaAgentJob:SqlInstance')` và gõ lại — khác biệt là gì?
3. **Liên hệ:** So với việc viết hẳn 1 wrapper function (vd `function Get-LabJob { Get-DbaAgentJob -SqlInstance 'dbatoolslab\sql2017' @args }`), `$PSDefaultParameterValues` có ưu/nhược điểm gì khi cần override?

## Bài tập mở rộng
- **Bài 1:** Tạo file `$PROFILE` (hoặc thêm vào file profile sẵn có) để mỗi lần mở pwsh tự set `$PSDefaultParameterValues` cho `SqlInstance = 'dbatoolslab\sql2017'` và `EnableException = $true` đối với mọi `*-Dba*`. Verify bằng cách mở pwsh mới và gõ `$PSDefaultParameterValues`.
- **Bài 2:** Viết wrapper function `Start-LabAudit -Action <scriptblock>` tự động: (a) bật `Start-Transcript` ra `C:\dbatoolslab\logs\audit-<timestamp>.txt`, (b) chạy scriptblock, (c) gọi `Stop-Transcript` ngay cả khi scriptblock throw (dùng `try/finally`). Kiểm thử bằng cách truyền `{ Get-DbaDatabase }` và `{ throw 'oops' }` — cả hai trường hợp đều phải có file log.


---

!!! info "Nguồn gốc"
    `book_lab/dbatools-lab/bookcode/chapter18.notes.md`
