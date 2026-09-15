---
title: Chapter 02 — Setting up your PowerShell environment for dbatools
course: 11-book-lab
source: book_lab/dbatools-lab/bookcode/chapter02.notes.md
---

# Chapter 02 — Setting up your PowerShell environment for dbatools

> Tham chiếu code gốc: [chapter02.ps1](chapter02.ps1)

## Mục tiêu
- Kiểm tra được PowerShell có thể load module `dbatools` trong môi trường lab.
- Hiểu vai trò của `$Env:PSModulePath` khi PowerShell tìm module.
- Biết cách trust PSGallery để cài `dbatools` không bị prompt.
- Biết import module vào session và kiểm tra cmdlet đã sẵn sàng.
- Làm quen với PowerShell remoting (`Invoke-Command`) — nền tảng cho các chapter sau.

## Tóm tắt 4 ý chính
1. **PowerShell remoting** (`Invoke-Command -ComputerName`) cho phép chạy script block trên máy khác và trả kết quả về local. Yêu cầu WinRM đã enable ở máy đích.
2. **`$Env:PSModulePath`** là chuỗi các thư mục cách nhau bằng `;` (Windows) hoặc `:` (Linux/Mac) — PowerShell sẽ scan các thư mục này để tự động tìm và load module.
3. **PSGallery (Trusted)** giúp `Install-Module dbatools` chạy thẳng không hỏi "Are you sure?". Chỉ làm trên máy lab/dev, production cân nhắc kỹ chính sách module signing.
4. **`Import-Module dbatools`** nạp module vào session hiện tại. PowerShell 5.1+ có thể auto-import lần đầu gọi cmdlet, nhưng gọi tường minh giúp dễ debug khi load fail.

## Giải thích từng đoạn code

### Đoạn 1: dòng 18
```powershell
Invoke-Command -ComputerName spsql01 -ScriptBlock { $Env:COMPUTERNAME }
```
- **Ý nghĩa:** Chạy block `{ $Env:COMPUTERNAME }` trên máy `spsql01` qua PowerShell remoting, trả về tên máy đích.
- **Đổi cho lab:** Thay `spsql01` bằng `dbatoolslab` (nếu chạy theo Đường B — Full Windows Lab) hoặc `localhost` (nếu đang trong devcontainer Linux). Lưu ý devcontainer Linux chạy SQL 2019 trên container — `Invoke-Command` qua WinRM sẽ không hoạt động giữa các container Linux mặc định.
- **Lưu ý:** Nếu chưa enable WinRM ở máy đích, lệnh sẽ báo lỗi "WinRM client cannot complete the operation" — đây là behaviour bình thường ở giai đoạn này. Chapter 04 sẽ chuyển sang dùng `Connect-DbaInstance` (qua TDS, không cần WinRM).

### Đoạn 2: dòng 22
```powershell
$Env:PSModulePath -Split ";"
```
- **Ý nghĩa:** Tách biến `$Env:PSModulePath` thành mảng các đường dẫn, mỗi dòng 1 thư mục cho dễ đọc.
- **Quan sát điển hình trên Windows:**
  - `C:\Users\<bạn>\Documents\PowerShell\Modules` (PS 7 user scope)
  - `C:\Program Files\PowerShell\Modules` (PS 7 all-users)
  - `C:\Program Files\WindowsPowerShell\Modules` (PS 5.1 all-users)
- **Lưu ý:** Trên Linux/Mac dùng separator `:` chứ không phải `;` — viết `-Split ":"` thay thế khi chạy trong devcontainer.

### Đoạn 3: dòng 26
```powershell
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
```
- **Ý nghĩa:** Đánh dấu repository PSGallery là Trusted để `Install-Module` không hỏi xác nhận từng lần.
- **Đổi cho lab:** Giữ nguyên, không phụ thuộc instance.
- **Lưu ý:** Đây là lệnh có side-effect lên profile máy hiện tại (thay đổi cấu hình PowerShellGet). Có thể chạy `-WhatIf` trước hoặc kiểm tra trạng thái hiện tại bằng `Get-PSRepository`.

### Đoạn 4: dòng 30
```powershell
Import-Module dbatools
```
- **Ý nghĩa:** Nạp `dbatools` vào session hiện tại. Sau lệnh này `Get-Command -Module dbatools` sẽ trả về ~600+ cmdlet.
- **Lưu ý prerequisites:**
  - Phải `Install-Module dbatools` trước (xem [scripts/00_Install_Prereqs.ps1](../scripts/00-install-prereqs.ps1)).
  - Lần đầu import có thể mất 5-15 giây vì module load nhiều assembly SMO.

## Lệnh thay vào lab của bạn

```powershell
# 1) (Tuỳ chọn) Test remoting tới máy đang chạy SQL — chỉ chạy nếu bạn đi Đường B
Invoke-Command -ComputerName dbatoolslab -ScriptBlock { $Env:COMPUTERNAME }

# 2) Xem các thư mục PowerShell sẽ tìm module
$Env:PSModulePath -Split [IO.Path]::PathSeparator   # dùng PathSeparator để cross-platform

# 3) Trust PSGallery để cài module không bị prompt (an toàn trong lab)
Get-PSRepository PSGallery
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted

# 4) Cài + import dbatools (nếu chưa làm qua scripts/00_Install_Prereqs.ps1)
if (-not (Get-Module -ListAvailable dbatools)) {
    Install-Module dbatools -Scope CurrentUser
}
Import-Module dbatools

# 5) Verify
Get-Module dbatools | Select-Object Name, Version
Get-Command -Module dbatools | Measure-Object   # ~600+ là OK
Test-DbaConnection -SqlInstance dbatoolslab\sql2017
```

## Self-check (3 câu)
1. **Định nghĩa:** Lệnh nào cho biết PSGallery hiện đang Trusted hay Untrusted? (Gợi ý: cmdlet bắt đầu bằng `Get-PSRepo...`).
2. **Thực hành:** Chạy `Get-Module dbatools` (không có `-ListAvailable`) trước và sau khi `Import-Module dbatools`. Output khác nhau thế nào? Lý giải tại sao?
3. **Liên hệ:** Tại sao chapter 02 đặt trước chapter 03 (Install-DbaInstance, Restore-DbaDatabase…)? `dbatools` đóng vai trò gì với việc setup lab ở chapter 03?

## Bài tập mở rộng
- **Bài 1 (~5 phút):** Viết function `Test-LabReady` trả về `$true` nếu cả `dbatools` đã import và `Test-DbaConnection -SqlInstance dbatoolslab\sql2017` thành công. Lưu vào `$PROFILE` để mỗi lần mở pwsh tự load.
- **Bài 2 (sâu hơn):** Thêm vào `$PROFILE` một block kiểm tra phiên bản `dbatools` đang dùng so với phiên bản mới nhất trên PSGallery (`Find-Module dbatools`) — in cảnh báo nếu lỗi thời. Cẩn thận không để block này chạy quá chậm khi mở pwsh (cache kết quả 1 ngày bằng file JSON là một cách).


---

!!! info "Nguồn gốc"
    `book_lab/dbatools-lab/bookcode/chapter02.notes.md`
