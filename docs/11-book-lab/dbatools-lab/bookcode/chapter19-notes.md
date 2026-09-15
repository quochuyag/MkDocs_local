---
title: Chapter 19 — Khám phá SQL Agent Jobs, Alerts và Operators
course: 11-book-lab
source: book_lab/dbatools-lab/bookcode/chapter19.notes.md
---

# Chapter 19 — Khám phá SQL Agent Jobs, Alerts và Operators

## Mục tiêu
- Liệt kê và lọc SQL Agent jobs trên một hoặc nhiều instance bằng `Get-DbaAgentJob` / `Find-DbaAgentJob`.
- Đọc thông tin alert và operator của Agent (`Get-DbaAgentAlert`, `Get-DbaAgentOperator`).
- Lọc job chưa được lập lịch (`-IsNotScheduled`) — một dạng "smell" cần điều tra.
- Lấy lịch sử chạy job (`Get-DbaAgentJobHistory`) và xuất ra timeline HTML (`ConvertTo-DbaTimeline`).
- Quen với mẫu pipeline: tìm job → lấy history → biến đổi → xuất file.

## Tóm tắt 3-5 ý chính
1. **`Get-DbaAgentJob` vs `Find-DbaAgentJob`** — `Get-` lấy tất cả/lọc cứng theo tham số có sẵn; `Find-` thiên về wildcard search nhiều instance và có thêm các bộ lọc nghiệp vụ như `-IsNotScheduled`, `-IsFailed`, `-IsDisabled`.
2. **Alert chưa từng raise** có `LastRaised` = `0001-01-01` (giá trị mặc định của `DateTime`). Lọc khác giá trị này = alert đã từng raise thật.
3. **Pipeline `Find-DbaAgentJob | Get-DbaAgentJobHistory`** là chuỗi rất tự nhiên trong dbatools — output object của lệnh trước trở thành input cho lệnh sau qua binding property.
4. **`ConvertTo-DbaTimeline`** sinh trang HTML timeline tương tác (dùng vis.js) — cực kỳ trực quan khi báo cáo trạng thái job cho team.
5. **Audit nhiều instance một lần** bằng cách gán mảng `$instances = "SQL01","SQL02",...` rồi truyền cùng `-SqlInstance`. dbatools chạy song song và gộp kết quả.

## Giải thích từng đoạn code

### Đoạn 1: dòng 18
```powershell
Get-DbaAgentJob -SqlInstance sql01
```
- **Ý nghĩa:** Liệt kê toàn bộ Agent jobs trên instance.
- **Đổi cho lab:** đổi sang `dbatoolslab\sql2017` (instance có Agent — `dbatoolslab` default trong devcontainer Linux không có Agent đầy đủ).
- **Quan sát mong đợi:** thấy `dbatools lab job`, `dbatools lab job - where am I` (đã tạo trong `scripts\02_Configure_Lab.ps1`) cùng các job của Ola Hallengren (`DatabaseBackup - USER_DATABASES - FULL`, `IndexOptimize - USER_DATABASES`, `CommandLog Cleanup`, v.v.) do `Install-DbaMaintenanceSolution` cài.

### Đoạn 2: dòng 23
```powershell
Get-DbaAgentJob -SqlInstance SQL01 -Database dbachecks
```
- **Ý nghĩa:** Chỉ lấy job nào có ít nhất 1 step trỏ vào database `dbachecks`.
- **Đổi cho lab:** thử `Get-DbaAgentJob -SqlInstance dbatoolslab\sql2017 -Database WideWorldImporters` (chưa có job nào của lab dùng DB này, nhưng đây là cách để bạn thấy filter hoạt động).

### Đoạn 3: dòng 29
```powershell
Get-DbaAgentAlert -SqlInstance SQL01
```
- **Ý nghĩa:** Liệt kê alert của Agent (theo severity, error number, performance condition...).
- **Đổi cho lab:** `Get-DbaAgentAlert -SqlInstance dbatoolslab\sql2017`.
- **Lưu ý:** Lab mặc định chưa tạo alert nào (script `02_Configure_Lab.ps1` còn dòng `# add alerts` chưa hoàn thiện) → output có thể rỗng. Đây là cơ hội bài tập để tạo alert.

### Đoạn 4: dòng 34-36
```powershell
$NotRaised = Get-Date -Date '01-01-0001 00:00:00'
Get-DbaAgentAlert -SqlInstance SQL01 |
Where-Object LastRaised -ne $NotRaised
```
- **Ý nghĩa:** Lọc các alert đã từng raise (loại bỏ alert chưa bao giờ kích hoạt).
- **Tại sao dùng `0001-01-01`:** đó là giá trị `[datetime]::MinValue` — dbatools dùng làm sentinel cho "chưa từng".
- **Đổi cho lab:** đổi sang `dbatoolslab\sql2017`.

### Đoạn 5: dòng 41
```powershell
Get-DbaAgentOperator -SqlInstance SQL01
```
- **Ý nghĩa:** Liệt kê operator (người nhận thông báo) cấu hình trên Agent.
- **Đổi cho lab:** `dbatoolslab\sql2017`. Lab mặc định chưa tạo operator → output rỗng — tự tạo bằng `New-DbaAgentOperator` (chapter 20).

### Đoạn 6: dòng 46-47
```powershell
$instances = "SQL01","SQL02","SQL03","SQL04","SQL05"
Find-DbaAgentJob -SqlInstance $instances -JobName *FTP*
```
- **Ý nghĩa:** Quét 5 instance, tìm mọi job có tên chứa "FTP".
- **Đổi cho lab:** chỉ có 1 instance Agent → đổi mảng thành `$instances = 'dbatoolslab\sql2017'` (vẫn dùng pattern mảng để khi mở rộng dễ thêm), và đổi pattern thành `*dbatools*` hoặc `*Ola*` để khớp với job lab thật.

### Đoạn 7: dòng 52-57
```powershell
$splatFindAgentJob = @{
    SqlInstance = 'SQL01','SQL02','SQL03','SQL04','SQL05'
    JobName = "*Integrity*"
    IsNotScheduled = $true
}
Find-DbaAgentJob @splatFindAgentJob
```
- **Ý nghĩa:** Tìm job khớp pattern *và* hiện chưa được lập lịch — đây là một "smell" thường xuất hiện sau khi DBA tắt schedule tạm thời rồi quên bật lại.
- **Đổi cho lab:** đổi instance, thử pattern `*dbatools*` — 2 job lab tạo qua `02_Configure_Lab.ps1` không có schedule → sẽ thấy ngay.

### Đoạn 8: dòng 62-63
```powershell
Find-DbaAgentJob -SqlInstance $instances -JobName *ftp* |
Select SqlInstance, JobName, LastRunDate, LastRunOutcome
```
- **Ý nghĩa:** Lọc job và hiển thị 4 cột quan trọng nhất khi audit — đặc biệt `LastRunOutcome`.
- **Đổi cho lab:** `Find-DbaAgentJob -SqlInstance dbatoolslab\sql2017 -JobName *dbatools* | Select SqlInstance, JobName, LastRunDate, LastRunOutcome`.

### Đoạn 9: dòng 68-70
```powershell
$midnight = [datetime]::Today
Find-DbaAgentJob -SqlInstance $instances -JobName *ftp* |
Get-DbaAgentJobHistory -StartDate $midnight
```
- **Ý nghĩa:** Lấy lịch sử chạy của các job đó **từ 00:00 hôm nay** đến hiện tại — pattern phổ biến cho "báo cáo hôm nay".
- **`[datetime]::Today`** trả về DateTime hôm nay lúc 00:00:00.
- **Đổi cho lab:** đổi instance + pattern; nếu job lab chưa chạy thì output rỗng — chạy `Start-DbaAgentJob` (cảnh báo bên dưới) trước rồi thử lại.

### Đoạn 10: dòng 75-79
```powershell
$threeDaysAgo = [datetime]::Today.AddDays(-3)
Find-DbaAgentJob -SqlInstance sql01 |
Get-DbaAgentJobHistory -StartDate $threeDaysAgo |
ConvertTo-DbaTimeline |
Out-File -FilePath c:\temp\jobs.html -Encoding ASCII
```
- **Ý nghĩa:** Lấy lịch sử 3 ngày qua → biến thành timeline HTML → ghi ra file. Mở `c:\temp\jobs.html` trong trình duyệt để xem trực quan.
- **Đổi cho lab:**
  - `SqlInstance` → `dbatoolslab\sql2017`.
  - Đường dẫn `c:\temp\jobs.html` → `C:\dbatoolslab\reports\jobs.html` (tạo thư mục trước).
- **Lưu ý:** Cần các job đã từng chạy mới có history. Các job lab mới tạo có thể rỗng → chạy thử `dbatools lab job` 1-2 lần để có dữ liệu (xem cảnh báo `Start-DbaAgentJob` ở phần "Lệnh thay vào lab").

## Lệnh thay vào lab của bạn

```powershell
# Lab đã có sẵn job 'dbatools lab job' và 'dbatools lab job - where am I' trên dbatoolslab\sql2017
# Cùng các Ola Hallengren jobs do Install-DbaMaintenanceSolution cài đặt

$instance = 'dbatoolslab\sql2017'

# 1) Liệt kê toàn bộ job + xem cột nghiệp vụ
Get-DbaAgentJob -SqlInstance $instance |
    Select-Object Name, Category, Enabled, LastRunDate, LastRunOutcome |
    Sort-Object Category, Name | Format-Table -AutoSize

# 2) Tìm job theo category 'dbatoolslab' (do lab tạo)
Get-DbaAgentJob -SqlInstance $instance -Category 'dbatoolslab'

# 3) Tìm các job CHƯA có schedule — sẽ thấy 2 job dbatools lab
$splat = @{
    SqlInstance    = $instance
    IsNotScheduled = $true
}
Find-DbaAgentJob @splat | Select-Object SqlInstance, Name, Category

# 4) Chạy thử 1 job để có dữ liệu lịch sử
#    CẢNH BÁO: Start-DbaAgentJob chạy job thật — dùng -WhatIf lần đầu để chắc.
Start-DbaAgentJob -SqlInstance $instance -Job 'dbatools lab job' -WhatIf
# Khi đã chắc chắn:
Start-DbaAgentJob -SqlInstance $instance -Job 'dbatools lab job'

# 5) Lấy lịch sử của job trong 3 ngày gần nhất
$threeDaysAgo = [datetime]::Today.AddDays(-3)
Get-DbaAgentJobHistory -SqlInstance $instance -Job 'dbatools lab job' -StartDate $threeDaysAgo |
    Select-Object StartDate, RunDuration, Status, Message

# 6) Xuất timeline HTML
$reportDir = 'C:\dbatoolslab\reports'
if (-not (Test-Path $reportDir)) { New-Item -ItemType Directory -Path $reportDir | Out-Null }
Find-DbaAgentJob -SqlInstance $instance |
    Get-DbaAgentJobHistory -StartDate $threeDaysAgo |
    ConvertTo-DbaTimeline |
    Out-File -FilePath (Join-Path $reportDir 'jobs.html') -Encoding ASCII
Invoke-Item (Join-Path $reportDir 'jobs.html')   # mở trong trình duyệt mặc định

# 7) Alert + Operator (lab có thể rỗng — đó là kết quả mong đợi)
Get-DbaAgentAlert    -SqlInstance $instance
Get-DbaAgentOperator -SqlInstance $instance
```

## Self-check
1. **Định nghĩa:** Khác biệt chính giữa `Get-DbaAgentJob` và `Find-DbaAgentJob` là gì? Khi nào nên ưu tiên `Find-`?
2. **Thực hành:** Chạy `Find-DbaAgentJob -SqlInstance dbatoolslab\sql2017 -IsFailed`. Nếu output rỗng, hãy giải thích vì sao (gợi ý: liên hệ tới việc job có từng chạy chưa).
3. **Liên hệ:** Pipeline `Find-DbaAgentJob | Get-DbaAgentJobHistory` hoạt động được nhờ cơ chế nào của PowerShell? (gợi ý: property binding theo tên).

## Bài tập mở rộng
- **Bài 1:** Viết script `Get-LabAgentHealth.ps1` in ra: (a) số job có category `dbatoolslab`, (b) số job Ola đang `Enabled`, (c) job nào đã `LastRunOutcome = Failed` trong 7 ngày qua. Bọc trong function `Get-LabAgentHealth -SqlInstance dbatoolslab\sql2017` để tái sử dụng.
- **Bài 2:** Tạo timeline HTML chỉ cho category `dbatoolslab` trong 24h gần nhất, mở file bằng `Invoke-Item`. Sau đó chỉnh schedule `-StartDate` lùi về 7 ngày để thấy khác biệt khi job chưa chạy bao giờ.


---

!!! info "Nguồn gốc"
    `book_lab/dbatools-lab/bookcode/chapter19.notes.md`
