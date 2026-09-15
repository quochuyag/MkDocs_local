---
title: Chapter 26 — dbachecks & Pester validation
course: 11-book-lab
source: book_lab/dbatools-lab/bookcode/chapter26.notes.md
---

# Chapter 26 — dbachecks & Pester validation

## Mục tiêu
- Cài `dbachecks` + Pester 4.10.1 (yêu cầu phiên bản cụ thể).
- Chạy check đơn lẻ bằng `Invoke-DbcCheck` (LastFullBackup, LastGoodCheckDb, MaxMemory...).
- List tất cả check có sẵn và tag bằng `Get-DbcCheck`.
- Tinh chỉnh ngưỡng đánh giá qua `Get-DbcConfig` / `Set-DbcConfig`.
- Ghi kết quả check vào DB và visualize qua Power BI (`Start-DbcPowerBi`).

## Tóm tắt 3-5 ý chính
1. **dbachecks** = framework Pester-based, đóng gói hàng trăm best-practice check cho SQL Server bởi cộng đồng dbatools.
2. **Pester 4.x bắt buộc** (không phải 5.x) — vì syntax `Describe`/`It` của dbachecks viết theo v4. Cài đúng version là điều kiện sống còn.
3. **Mỗi check có config riêng** (vd `policy.backup.fullmaxdays`) — chỉnh bằng `Set-DbcConfig` cho phù hợp môi trường.
4. **Workflow chuẩn:** `Set-DbcConfig` → `Invoke-DbcCheck -Check <tag>` → kết quả Pass/Fail → action.
5. **Pipeline lưu trữ:** `Invoke-DbcCheck -Passthru | Convert-DbcResult | Write-DbcTable` → ghi vào DB `DatabaseAdmin`, rồi `Start-DbcPowerBi -FromDatabase` để xem dashboard.

## Giải thích từng đoạn code

### Đoạn 1: dòng 18 — cài dbachecks
```powershell
Install-Module dbachecks -Scope CurrentUser
```
- **Ý nghĩa:** Cài module từ PSGallery cho user hiện tại.
- **Đổi cho lab:** Lab này đã được cài qua `scripts/00_Install_Prereqs.ps1` — chỉ chạy nếu chưa có.
- **Lưu ý:** Có thể đã cài rồi → bỏ qua hoặc dùng `-Force` để update.

### Đoạn 2: dòng 22 — cài Pester đúng version
```powershell
Install-Module Pester -RequiredVersion 4.10.1 -Scope CurrentUser
```
- **Ý nghĩa:** **PHẢI** dùng Pester 4.x. Pester 5 đổi syntax `Describe`/`Context`/`It` không tương thích.
- **Đổi cho lab:** Giữ nguyên. Kiểm tra `Get-Module Pester -ListAvailable` trước.
- **Lưu ý:** Windows PowerShell 5.1 thường có Pester 3.4 cài sẵn → cần `-SkipPublisherCheck` đôi khi.

### Đoạn 3: dòng 26 — chạy 1 check
```powershell
Invoke-DbcCheck -SqlInstance dbatoolslab -Check LastFullBackup
```
- **Ý nghĩa:** Chạy check "Last Full Backup" trên instance `dbatoolslab` — DB nào không có full backup gần đây sẽ FAIL.
- **Đổi cho lab:** Đã đúng `dbatoolslab`. Nếu muốn sql2017: `Invoke-DbcCheck -SqlInstance dbatoolslab\sql2017 -Check LastFullBackup`.

### Đoạn 4: dòng 30 — lặp lại đoạn 3
```powershell
Invoke-DbcCheck -SqlInstance dbatoolslab -Check LastFullBackup
```
- **Đổi cho lab:** Như đoạn 3.

### Đoạn 5: dòng 34 — chạy nhiều check 1 lần
```powershell
Invoke-DbcCheck -SqlInstance dbatoolslab -Check LastGoodCheckDb, MaxMemory
```
- **Ý nghĩa:** Chạy đồng thời check "Last DBCC CHECKDB" + "Max Server Memory cấu hình đúng".
- **Đổi cho lab:** Same as above.

### Đoạn 6: dòng 38 — list mọi check
```powershell
Get-DbcCheck | Select-Object Group, UniqueTag
```
- **Ý nghĩa:** Trả về toàn bộ check kèm tag để filter (Backup, Database, Instance, Agent...).
- **Đổi cho lab:** Giữ nguyên.

### Đoạn 7: dòng 43 — chi tiết 1 tag
```powershell
Get-DbcCheck -Tag LastFullBackup | Format-List
```
- **Ý nghĩa:** Xem mô tả + config keys liên quan đến check này.

### Đoạn 8: dòng 48 — list config keys 1 check cần
```powershell
(Get-DbcCheck -Tag LastFullBackup).config.Split(' ')
```
- **Ý nghĩa:** Mỗi check phụ thuộc 1+ config (vd `policy.backup.fullmaxdays`). Lấy danh sách để biết cần `Set-DbcConfig` cái nào.

### Đoạn 9: dòng 52 — xem giá trị config
```powershell
Get-DbcConfig -Name policy.backup.fullmaxdays
```
- **Ý nghĩa:** Mặc định thường là 1 ngày → DB chưa full backup hôm nay = FAIL.

### Đoạn 10: dòng 57 — đặt ngưỡng mới
```powershell
Set-DbcConfig -Name policy.backup.fullmaxdays -Value 7
```
- **Ý nghĩa:** Cho phép tối đa 7 ngày giữa các full backup.
- **Đổi cho lab:** Giữ nguyên — phù hợp môi trường học.

### Đoạn 11: dòng 62-66 — set nhiều config + run
```powershell
Set-DbcConfig -Name policy.backup.fullmaxdays -Value 7 
Set-DbcConfig -Name policy.backup.diffmaxhours -Value 24 
Set-DbcConfig -Name policy.backup.logmaxminutes -Value 240 

Invoke-DbcCheck -SqlInstance dbatoolslab -Check LastBackup -Show Fails
```
- **Ý nghĩa:** Đặt SLA backup: Full 7 ngày, Diff 24 giờ, Log 240 phút. `-Show Fails` chỉ in test fail.

### Đoạn 12: dòng 70-71 — set + run
```powershell
Set-DbcConfig -Name policy.backup.fullmaxdays -Value 7
Invoke-DbcCheck -SqlInstance dbatoolslab -Check LastFullBackup
```
- **Ý nghĩa:** Lặp lại pattern set + run đơn giản hơn.

### Đoạn 13: dòng 75-82 — pipe result vào DB
```powershell
$splatInvokeCheck = @{
  SqlInstance = "dbatoolslab"
  Check = "LastBackup"
  Passthru = $true
}
Invoke-DbcCheck @splatInvokeCheck |
Convert-DbcResult -Label dbatoolsMol |
Write-DbcTable -SqlInstance dbatoolslab -Database DatabaseAdmin
```
- **Ý nghĩa:** `-Passthru` xuất Pester result, `Convert-DbcResult` chuẩn hoá, `Write-DbcTable` ghi vào DB `DatabaseAdmin` (sẽ tự tạo table nếu chưa có).
- **Cảnh báo:** `Write-DbcTable` INSERT vào DB thật — đảm bảo có DB `DatabaseAdmin` hoặc lệnh sẽ tự tạo. Lab có thể `New-DbaDatabase -SqlInstance dbatoolslab -Name DatabaseAdmin` trước.

### Đoạn 14: dòng 86-93 — lặp lại đoạn 13
```powershell
$splatInvokeCheck = @{
  SqlInstance = "dbatoolslab"
  Check = "LastBackup"
  Passthru = $true
}
Invoke-DbcCheck @splatInvokeCheck |
Convert-DbcResult -Label dbatoolsMol |
Write-DbcTable -SqlInstance dbatoolslab -Database DatabaseAdmin
```
- **Đổi cho lab:** Giữ nguyên hoặc đổi `Label` thành tên môi trường.

### Đoạn 15: dòng 97 — mở Power BI dashboard từ DB
```powershell
Start-DbcPowerBi -FromDatabase
```
- **Ý nghĩa:** Mở file `.pbix` có sẵn trong module, đã kết nối table do `Write-DbcTable` tạo.
- **Lưu ý:** Cần Power BI Desktop cài trên máy. Nếu chạy headless/devcontainer → bỏ qua bước này.

## Lệnh thay vào lab của bạn

```powershell
# 0) Verify Pester + dbachecks
Get-Module Pester -ListAvailable | Where-Object Version -like '4.*'
Get-Module dbachecks -ListAvailable

# 1) Cài nếu chưa có (đã có trong 00_Install_Prereqs.ps1)
# Install-Module Pester -RequiredVersion 4.10.1 -Scope CurrentUser -SkipPublisherCheck -Force
# Install-Module dbachecks -Scope CurrentUser -Force

# 2) Khám phá check
Get-DbcCheck | Group-Object Group |
    Select-Object Name, Count | Sort Count -Descending
Get-DbcCheck -Tag Backup | Select-Object UniqueTag, Description

# 3) Cấu hình ngưỡng cho lab
Set-DbcConfig -Name policy.backup.fullmaxdays   -Value 7
Set-DbcConfig -Name policy.backup.diffmaxhours  -Value 24
Set-DbcConfig -Name policy.backup.logmaxminutes -Value 240
Set-DbcConfig -Name policy.connection.authscheme -Value KERBEROS,NTLM

# 4) Chạy nhóm check cho cả 2 instance lab
$instances = 'dbatoolslab\sql2017','dbatoolslab'
Invoke-DbcCheck -SqlInstance $instances -Check LastBackup -Show Fails

# 5) Lưu lịch sử check vào DB
New-DbaDatabase -SqlInstance dbatoolslab -Name DatabaseAdmin -ErrorAction SilentlyContinue
Invoke-DbcCheck -SqlInstance $instances -Check LastBackup -Passthru |
    Convert-DbcResult -Label LabRun |
    Write-DbcTable -SqlInstance dbatoolslab -Database DatabaseAdmin

# 6) (Optional) mở Power BI dashboard
# Start-DbcPowerBi -FromDatabase
```

## Self-check (3 câu)
1. **Định nghĩa:** Tại sao dbachecks **bắt buộc** Pester 4.x mà không phải 5.x?
2. **Thực hành:** Chạy `Invoke-DbcCheck -Check LastFullBackup` trước và sau khi `Set-DbcConfig -Name policy.backup.fullmaxdays -Value 7` — số FAIL khác nhau thế nào? Giải thích.
3. **Liên hệ:** So với `Test-DbaLastBackup` (chapter backup đã học), dbachecks `LastBackup` khác ở điểm nào về phạm vi và output?

## Bài tập mở rộng
- **Bài 1:** Tạo script `Run-DailyChecks.ps1` chạy 5 check ưu tiên (`LastBackup`, `LastGoodCheckDb`, `MaxMemory`, `ErrorLog`, `DatabaseStatus`) lúc 6:00 mỗi sáng qua scheduled task, lưu kết quả vào DB `DatabaseAdmin`.
- **Bài 2:** Viết `Send-DbcFailureReport` đọc bảng kết quả 24h gần nhất, gửi mail nếu có FAIL. (Dùng `Send-MailMessage` hoặc Microsoft Graph.)
- **Bài 3:** Tạo custom Pester test cho 1 quy ước nội bộ (vd: mọi DB phải có Owner = `sa`), đặt vào folder `checks\` của dbachecks rồi tag riêng — chạy bằng `Invoke-DbcCheck -Tag CompanyConvention`.


---

!!! info "Nguồn gốc"
    `book_lab/dbatools-lab/bookcode/chapter26.notes.md`
