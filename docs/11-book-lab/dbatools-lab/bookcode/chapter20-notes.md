---
title: Chapter 20 — Tạo và quản lý SQL Agent Jobs nâng cao (categories, schedules, steps,
  proxies, history)
course: 11-book-lab
source: book_lab/dbatools-lab/bookcode/chapter20.notes.md
---

# Chapter 20 — Tạo và quản lý SQL Agent Jobs nâng cao (categories, schedules, steps, proxies, history)

## Mục tiêu
- Khám phá toàn bộ "họ" lệnh Agent (`Get-Command -Module dbatools -Verb New,Set,Remove -Noun *Agent*`).
- Tạo job category, schedule (daily/monthly/weekly), credential + proxy, operator.
- Tạo job đa step (`New-DbaAgentJob` + nhiều `New-DbaAgentJobStep`) có liên kết `OnSuccessAction` / `OnFailAction`.
- Khởi động job (`Start-DbaAgentJob`), theo dõi job đang chạy (`Get-DbaRunningJob`), đọc lịch sử (`Get-DbaAgentJobHistory`).
- Hiểu khái niệm Subsystem: `TransactSql`, `CmdExec`, `PowerShell` và khi nào cần Proxy.

## Tóm tắt 3-5 ý chính
1. **Job = container, Step = đơn vị thực thi.** Mỗi step có Subsystem (loại lệnh), Database, Command, hành động khi thành công/thất bại. Nhiều step kết nối thành workflow.
2. **Category trước, job sau.** `New-DbaAgentJobCategory` phải có trước khi `New-DbaAgentJob -Category ...`. Lab đã tạo sẵn category `dbatoolslab`.
3. **Schedule có thể độc lập với job.** Tạo schedule bằng `New-DbaAgentSchedule`, sau đó gán bằng tham số `-Schedule` khi tạo job. Một schedule dùng cho nhiều job được.
4. **Proxy + Credential** cần thiết khi step Subsystem `CmdExec` hoặc `PowerShell` cần chạy dưới quyền user không phải Agent service account. Quy trình: `New-DbaCredential` → `New-DbaAgentProxy` → step `-ProxyName`.
5. **Theo dõi runtime:** `Get-DbaRunningJob` cho ảnh chụp job đang chạy ngay lúc này; `Get-DbaAgentJobHistory` cho lịch sử quá khứ. Dùng `Get-DbaRegisteredServer | Get-DbaRunningJob` để quét nhiều instance đã đăng ký.

## Giải thích từng đoạn code

### Đoạn 1: dòng 18
```powershell
Get-Command -Module dbatools -Verb New, Set, Remove -Noun *Agent*
```
- **Ý nghĩa:** Liệt kê tất cả cmdlet thao tác (tạo/sửa/xoá) liên quan Agent — cách "khám phá" họ lệnh.
- **Đổi cho lab:** giữ nguyên, chạy được ngay.
- **Mẹo:** Thêm `| Group-Object Verb` để thấy đếm theo verb.

### Đoạn 2: dòng 23
```powershell
New-DbaAgentJobCategory -SqlInstance SQL01 -Category PastaFactory
```
- **Ý nghĩa:** Tạo category "PastaFactory" — dùng để gom job theo nghiệp vụ.
- **Đổi cho lab:** đổi sang `dbatoolslab\sql2017` (instance có Agent — `dbatoolslab` default trong devcontainer Linux không có Agent đầy đủ). Có thể dùng category `Lab-Tutorial` (lab đã có sẵn `dbatoolslab` từ `02_Configure_Lab.ps1`).
- **Lưu ý:** Nếu category đã tồn tại sẽ lỗi → kiểm tra trước bằng `Get-DbaAgentJobCategory`.

### Đoạn 3: dòng 28-36
```powershell
$schedulesplat = @{
    FrequencyType = 'Daily'
    SqlInstance = 'SQL01'
    Schedule = 'Daily-Midnight'
    Force = $true
    StartTime = '000327'
    FrequencyInterval = 'Everyday'
}
New-DbaAgentSchedule @schedulesplat
```
- **Ý nghĩa:** Tạo schedule chạy hàng ngày lúc 00:03:27.
- **`StartTime = '000327'`** là format `HHmmss` (chuỗi 6 ký tự) — đây là điểm dễ nhầm.
- **Đổi cho lab:** đổi sang `dbatoolslab\sql2017`. Đổi `StartTime` thành thời điểm sát hiện tại để test (vd hiện tại 14:25 → đặt `'142700'`).
- **`Force = $true`:** ghi đè nếu schedule cùng tên đã tồn tại — cẩn thận trong production.

### Đoạn 4: dòng 40-48
```powershell
$schedulesplat = @{
    FrequencyType = 'Monthly'
    SqlInstance = 'SQL01'
    Schedule = 'Monthly-1st-Midnight'
    Force = $true
    StartTime = '000248'
    FrequencyInterval = 1
}
New-DbaAgentSchedule @schedulesplat
```
- **Ý nghĩa:** Schedule hàng tháng vào ngày 1, lúc 00:02:48.
- **`FrequencyInterval = 1`** = ngày 1 trong tháng.
- **Đổi cho lab:** đổi instance sang `dbatoolslab\sql2017`.

### Đoạn 5: dòng 52-63
```powershell
$schedulesplat = @{
    FrequencyType = 'Weekly'
    FrequencyInterval = 'Weekdays'
    SqlInstance = 'SQL01'
    Schedule = 'WorkingWeek-Every-15-Minute'
    Force = $true
    StartTime = '070036'
    EndTime = '180000'
    FrequencySubdayInterval = 15
    FrequencySubdayType = 'Minutes'
}
New-DbaAgentSchedule @schedulesplat
```
- **Ý nghĩa:** Chạy 15 phút/lần, từ 07:00:36 đến 18:00:00, các ngày trong tuần (Mon-Fri).
- **Đổi cho lab:** đổi instance. Đây là pattern hay dùng cho job log shipping / monitoring giờ làm việc.

### Đoạn 6: dòng 67-88 — Credential + Proxy
```powershell
$credential = Get-Credential -Message "Enter the Username and Password for the credential"
$credsplat = @{
    SqlInstance = 'SQL01'
    SecurePassword = $credential.Password
    Name = 'FactoryProcess'
    Identity = $credential.UserName
}
New-DbaCredential @credsplat

$proxysplat = @{
    SqlInstance = 'SQL01'
    ProxyCredential = 'FactoryProcess'
    Name = 'FactoryProcess'
    Description = 'Proxy account to run the Factory processing using the ad\FactoryProcesss account'
    SubSystem = 'CmdExec'
}
New-DbaAgentProxy @proxysplat
```
- **Ý nghĩa:** Tạo SQL Credential (lưu Windows username/password trong SQL), rồi tạo Proxy ràng buộc credential đó cho subsystem `CmdExec`.
- **Đổi cho lab:** Lab devcontainer/Linux thường không có domain user → có thể **bỏ qua** đoạn này, hoặc trên Windows lab thì tạo proxy với local user. Đây là code mang tính minh hoạ, không cần chạy thật để hiểu khái niệm.
- **Cảnh báo:** `Get-Credential` mở prompt UI — chạy block này riêng, đừng chạy cả script luôn.

### Đoạn 7: dòng 92-97
```powershell
$operatorSplat = @{
    SqlInstance = 'SQL01'
    Operator = 'DBA Team'
    EmailAddress = 'operator@dbateam.com'
}
New-DbaAgentOperator @operatorsplat
```
- **Ý nghĩa:** Tạo operator "DBA Team" với email — dùng làm đích nhận thông báo job (`EmailOperator` khi tạo job).
- **Đổi cho lab:** đổi sang `dbatoolslab\sql2017`, đổi email thành email test của bạn. Operator này chưa chạy thật mail nếu chưa cấu hình Database Mail.
- **Lưu ý chính tả:** code gốc có `New-DbaAgentOperator @operatorsplat` (chữ `s` thường) — khớp với biến `$operatorSplat` nhờ PowerShell không phân biệt hoa thường tên biến.

### Đoạn 8: dòng 102-115
```powershell
$jobsplat = @{
    SqlInstance = 'SQL01'
    Description = '...'
    Category = 'PastaFactory'
    EmailOperator = 'DBA Team'
    Job = 'Factory Data Processing'
    Schedule = 'WorkingWeek-Every-3-Hours'
    EventLogLevel = 'OnFailure'
    EmailLevel = 'OnFailure'
    OwnerLogin = 'ad\FactoryProcesss'
}
New-DbaAgentJob @jobsplat
```
- **Ý nghĩa:** Tạo job "Factory Data Processing" thuộc category PastaFactory, schedule đã tạo trước đó, gửi email khi fail, owner là `ad\FactoryProcesss`.
- **Đổi cho lab:** `SqlInstance = 'dbatoolslab\sql2017'`, `OwnerLogin = 'sa'` (vì lab không có domain account), `Schedule` đổi sang schedule đã tạo (vd `WorkingWeek-Every-15-Minute`).
- **Cảnh báo:** chạy `-WhatIf` lần đầu:
  ```powershell
  New-DbaAgentJob @jobsplat -WhatIf
  ```
- **Lưu ý:** `Schedule = 'WorkingWeek-Every-3-Hours'` trong code gốc — schedule này **chưa tạo** ở các block trước (chỉ có 15-Minute) → khi chạy thật sẽ lỗi. Tạo schedule trùng tên trước hoặc đổi tên cho khớp.

### Đoạn 9: dòng 120-174 — 4 step nối tiếp
```powershell
$stepcommand = 'EXEC Process_Factory_Sales @Factory="Pasta"'
$stepsplat = @{
    StepId = 1
    Subsystem = 'TransactSql'
    SqlInstance = 'SQL01'
    StepName = ' Process Pasta Factory Data'
    OnSuccessAction = 'GoToNextStep'
    Job = 'Factory Data Processing'
    Command = $stepcommand
    OnFailAction = 'QuitWithFailure'
    Database = 'FactorySales'
}
New-DbaAgentJobStep @stepsplat
# ... tương tự cho Pizza, Sausage, Sauce
```
- **Ý nghĩa:** Tạo 4 step T-SQL chạy nối tiếp. Step cuối (`Sauce`) có `OnSuccessAction = 'QuitWithSuccess'` thay vì `'GoToNextStep'` — đây là điểm kết thúc workflow.
- **Đổi cho lab:** đổi `SqlInstance` → `dbatoolslab\sql2017`, đổi `Database` → `WideWorldImporters` (đã restore trong lab), `Command` → `SELECT COUNT(*) FROM Sales.Orders` (lệnh an toàn, không thay đổi dữ liệu).
- **Cảnh báo:** Trước khi tạo, kiểm tra job đích tồn tại; nếu lỡ tạo nhầm tên thì `Remove-DbaAgentJobStep` để dọn.

### Đoạn 10: dòng 178-182
```powershell
$splatGetJobStep = @{
    SqlInstance = "SQL01"
    Job = 'Factory Data Processing'
}
Get-DbaAgentJobStep @splatGetJobStep | Format-Table
```
- **Ý nghĩa:** Liệt kê step của job để verify thứ tự, on-success/on-fail.
- **Đổi cho lab:** đổi instance + job name.

### Đoạn 11: dòng 187-212 — Job CmdExec qua Proxy
```powershell
$jobname = 'Copy logins from model'
$jobsplat = @{
    SqlInstance = 'SQL02'
    Category = 'DBA-Model'
    ...
    Schedule = 'Daily-Midnight'
    Force = $true
}
New-DbaAgentJob @jobsplat

$command = 'powershell.exe -File C:\AgentScripts\CopyFromModel.ps1'
$stepsplat = @{
    SqlInstance = 'SQL02'
    Subsystem = 'CmdExec'
    Command = $command
    StepName = 'Copy Logins'
    Job = $jobname
    ProxyName = 'PowerShell Proxy'
    Flag = 'AppendAllCmdExecOutputToJobHistory'
}
New-DbaAgentJobStep @stepsplat
```
- **Ý nghĩa:** Tạo job chạy script PowerShell qua `CmdExec` + proxy `'PowerShell Proxy'`. Flag `AppendAllCmdExecOutputToJobHistory` ghi output vào job history (hữu ích để debug).
- **Đổi cho lab:** Lab chỉ có 1 instance → đổi `SqlInstance = 'dbatoolslab\sql2017'`. Cần có proxy tên `'PowerShell Proxy'` (chưa có trong lab → tạo trước hoặc bỏ tham số `-ProxyName` nếu Agent service account đủ quyền).
- **Cảnh báo:** `Force = $true` sẽ ghi đè nếu job trùng tên → đảm bảo không mất job production.

### Đoạn 12: dòng 216-220
```powershell
$splatGetJob = @{
    SqlInstance = "SQL02", "SQL2017N20"
    Job = 'Factory Data Processing'
}
Get-DbaAgentJob @splatGetJob | Start-DbaAgentJob
```
- **Ý nghĩa:** Lấy job ở 2 instance, pipe sang `Start-DbaAgentJob` để khởi động đồng loạt.
- **Đổi cho lab:** đổi mảng thành `'dbatoolslab\sql2017'`, đổi job thành `'dbatools lab job'`.
- **CẢNH BÁO:** `Start-DbaAgentJob` chạy job thật. Lần đầu **bắt buộc** dùng `-WhatIf`:
  ```powershell
  Get-DbaAgentJob -SqlInstance dbatoolslab\sql2017 -Job 'dbatools lab job' | Start-DbaAgentJob -WhatIf
  ```

### Đoạn 13: dòng 225
```powershell
Get-DbaRegisteredServer | Get-DbaRunningJob
```
- **Ý nghĩa:** Lấy tất cả server đã đăng ký trong Registered Servers (SSMS) rồi xem mỗi server có job nào đang chạy không.
- **Đổi cho lab:** Lab có thể chưa register server → trước hết `Add-DbaRegServer -SqlInstance dbatoolslab\sql2017 -ServerName 'lab2017'` (tuỳ chọn). Hoặc thay bằng đoạn 14 (truyền instance trực tiếp).

### Đoạn 14: dòng 230
```powershell
Get-DbaRunningJob -SqlInstance SQL02, SQL2017N20
```
- **Ý nghĩa:** Cách đơn giản hơn — truyền thẳng danh sách instance.
- **Đổi cho lab:** `Get-DbaRunningJob -SqlInstance dbatoolslab\sql2017`.
- **Mẹo:** Để demo, mở pwsh thứ hai chạy job dài, pwsh chính gọi `Get-DbaRunningJob` xem có thấy không.

### Đoạn 15: dòng 234-238
```powershell
$splatGetJobHist = @{
    SqlInstance = "SQL02"
    Job = 'Copy logins from model'
}
Get-DbaAgentJobHistory @splatGetJobHist
```
- **Ý nghĩa:** Lấy lịch sử của 1 job cụ thể.
- **Đổi cho lab:** đổi instance + đổi job thành `'dbatools lab job'`.

## Lệnh thay vào lab của bạn

```powershell
# Lab đã có sẵn:
#  - Category 'dbatoolslab'
#  - Jobs: 'dbatools lab job', 'dbatools lab job - where am I'
#  - Ola Hallengren jobs (DatabaseBackup, IndexOptimize, CommandLog Cleanup, ...)
#  - Instance: dbatoolslab\sql2017

$instance = 'dbatoolslab\sql2017'

# 1) Khám phá họ lệnh Agent
Get-Command -Module dbatools -Verb New, Set, Remove -Noun *Agent* |
    Group-Object Verb | Format-Table Name, Count

# 2) Xem category đã có (sẽ thấy 'dbatoolslab' do lab tạo)
Get-DbaAgentJobCategory -SqlInstance $instance |
    Select-Object Name, CategoryType | Format-Table

# 3) Tạo schedule Daily lúc gần hiện tại (để test) — WhatIf trước
$soon = (Get-Date).AddMinutes(3).ToString('HHmmss')
$schedSplat = @{
    SqlInstance       = $instance
    Schedule          = 'Lab-Demo-Daily'
    FrequencyType     = 'Daily'
    FrequencyInterval = 'Everyday'
    StartTime         = $soon
    Force             = $true
}
New-DbaAgentSchedule @schedSplat -WhatIf
# Khi đã chắc:
New-DbaAgentSchedule @schedSplat

# 4) Gán schedule vào job lab có sẵn (Set-DbaAgentJob — CẢNH BÁO: thay đổi job thật)
Set-DbaAgentJob -SqlInstance $instance -Job 'dbatools lab job' -Schedule 'Lab-Demo-Daily' -WhatIf
# Khi đã chắc:
Set-DbaAgentJob -SqlInstance $instance -Job 'dbatools lab job' -Schedule 'Lab-Demo-Daily'

# 5) Tạo operator (Database Mail chưa setup nên chỉ để test cấu trúc)
$opSplat = @{
    SqlInstance  = $instance
    Operator     = 'Lab DBA'
    EmailAddress = 'lab-dba@example.com'
}
New-DbaAgentOperator @opSplat -WhatIf
New-DbaAgentOperator @opSplat

# 6) Tạo job mới có 2 step nối tiếp — an toàn vì câu lệnh chỉ SELECT
$newJob = 'Lab Multi-Step Demo'
$jobSplat = @{
    SqlInstance   = $instance
    Job           = $newJob
    Category      = 'dbatoolslab'
    Description   = 'Demo 2-step job — selects only, safe to run'
    EmailOperator = 'Lab DBA'
    EmailLevel    = 'OnFailure'
    EventLogLevel = 'OnFailure'
    OwnerLogin    = 'sa'
    Force         = $true
}
New-DbaAgentJob @jobSplat -WhatIf
New-DbaAgentJob @jobSplat

$step1 = @{
    SqlInstance     = $instance
    Job             = $newJob
    StepId          = 1
    StepName        = 'Count Sales Orders'
    Subsystem       = 'TransactSql'
    Database        = 'WideWorldImporters'
    Command         = 'SELECT COUNT(*) AS OrderCount FROM Sales.Orders'
    OnSuccessAction = 'GoToNextStep'
    OnFailAction    = 'QuitWithFailure'
}
New-DbaAgentJobStep @step1

$step2 = @{
    SqlInstance     = $instance
    Job             = $newJob
    StepId          = 2
    StepName        = 'Show server name'
    Subsystem       = 'TransactSql'
    Database        = 'master'
    Command         = 'SELECT @@SERVERNAME AS ServerName'
    OnSuccessAction = 'QuitWithSuccess'
    OnFailAction    = 'QuitWithFailure'
}
New-DbaAgentJobStep @step2

# 7) Verify step
Get-DbaAgentJobStep -SqlInstance $instance -Job $newJob |
    Select-Object Parent, ID, Name, SubSystem, OnSuccessAction, OnFailAction |
    Format-Table -AutoSize

# 8) Chạy job — CẢNH BÁO: WhatIf trước
Start-DbaAgentJob -SqlInstance $instance -Job $newJob -WhatIf
# Khi đã chắc:
Start-DbaAgentJob -SqlInstance $instance -Job $newJob

# 9) Theo dõi job đang chạy (chạy ngay sau Start trong pwsh khác hoặc job dài)
Get-DbaRunningJob -SqlInstance $instance

# 10) Lịch sử job
Get-DbaAgentJobHistory -SqlInstance $instance -Job $newJob |
    Select-Object StartDate, RunDuration, Status, Message | Format-Table

# 11) Dọn dẹp khi học xong — CẢNH BÁO: Remove-DbaAgentJob xoá thật, dùng WhatIf trước
Remove-DbaAgentJob      -SqlInstance $instance -Job $newJob -WhatIf
Remove-DbaAgentSchedule -SqlInstance $instance -Schedule 'Lab-Demo-Daily' -WhatIf
Remove-DbaAgentOperator -SqlInstance $instance -Operator 'Lab DBA' -WhatIf
# Khi đã chắc, bỏ -WhatIf để xoá thật
```

## Self-check
1. **Định nghĩa:** Phân biệt `Subsystem = 'TransactSql'` vs `'CmdExec'` vs `'PowerShell'`. Khi nào bắt buộc dùng Proxy?
2. **Thực hành:** Tạo 1 schedule chạy mỗi 5 phút trong giờ làm việc, gán vào job `'dbatools lab job - where am I'`, đợi 1 chu kỳ rồi đọc `Get-DbaAgentJobHistory` để xác nhận. Sau đó gỡ schedule (`Set-DbaAgentJob -Schedule $null` hoặc xoá schedule).
3. **Liên hệ:** So với việc tạo job qua SSMS (UI), tạo bằng dbatools có lợi gì cho deployment nhiều server? (gợi ý: idempotent, version control, splatting).

## Bài tập mở rộng
- **Bài 1:** Viết function `New-LabSelectJob -SqlInstance <name> -JobName <name> -Query <string>` tạo job 1 step T-SQL chạy `$Query`, gán category `dbatoolslab`, owner `sa`, không schedule. Idempotent: nếu job đã tồn tại thì update step thay vì lỗi (dùng `Get-DbaAgentJob` để kiểm tra trước).
- **Bài 2:** Viết script `Export-LabAgentInventory.ps1` xuất ra CSV danh sách: tất cả job (Name, Category, Enabled, LastRunOutcome), tất cả schedule (Name, FrequencyType, StartTime), tất cả operator (Name, Email). Mỗi loại vào 1 sheet (gợi ý: dùng `Export-Excel` nếu đã cài module ImportExcel, hoặc 3 file CSV riêng).
- **Bài 3 (nâng cao):** Thử dùng `ConvertTo-DbaTimeline` từ chapter 19 trên job mới tạo, mở HTML xem trực quan workflow 2 step có thành công nối tiếp đúng không.


---

!!! info "Nguồn gốc"
    `book_lab/dbatools-lab/bookcode/chapter20.notes.md`
