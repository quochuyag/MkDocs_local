---
title: Chapter 16 — Copy logins, jobs và các đối tượng instance-level
course: 11-book-lab
source: book_lab/dbatools-lab/bookcode/chapter16.notes.md
---

# Chapter 16 — Copy logins, jobs và các đối tượng instance-level

## Mục tiêu
- Dùng `Copy-DbaLogin` để chuyển login (Windows và SQL Auth) giữa hai instance, giữ nguyên SID và hash mật khẩu.
- Loại trừ system login hoặc một số login cụ thể khi copy.
- Dùng `Copy-DbaAgentJob`, `Copy-DbaAgentOperator`, `Copy-DbaAgentAlert` để chuyển hệ sinh thái Agent.
- Dùng `Copy-DbaCustomError` và `Copy-DbaLinkedServer` cho các object instance-level khác.
- Khám phá toàn bộ họ `Copy-Dba*` để hiểu phạm vi automation cross-instance.

## Tóm tắt 3-5 ý chính
1. **Copy-DbaLogin giữ SID** — đây là điểm quan trọng cho contained-database-style mapping: SID khớp giữa server login và database user, không bị "orphaned user".
2. **ExcludeSystemLogins / ExcludeLogin / Login** — ba cách filter: lấy hết trừ system, lấy hết trừ một số cụ thể, hoặc chỉ lấy danh sách định trước.
3. **Họ Copy-DbaAgent\*** — `Copy-DbaAgentJob`, `Copy-DbaAgentSchedule`, `Copy-DbaAgentOperator`, `Copy-DbaAgentAlert`, `Copy-DbaAgentJobCategory`... Mỗi cái copy một loại object Agent.
4. **`DisableOnSource` cho cutover** — sau khi copy job sang target, tắt job ở source để tránh chạy trùng (cả hai cùng backup, cùng xoá log, ...).
5. **`Out-GridView -Passthru` + `Copy-DbaAgentJob`** — pattern interactive: chọn job bằng GUI rồi đẩy thẳng qua pipeline để copy.

## Giải thích từng đoạn code

### Đoạn 1: dòng 18-24 — Copy login cụ thể (lưu ý syntax có lỗi gõ trong sách)
```powershell
$copyLoginSplat = @{
    Source      = "sql01"
    Destination = "sql02"
    Login       = "WWI_Owner","WWI_ReadWrite","WWI_ReadOnly",
    [CA]"ad\JaneReeves"
}
Copy-DbaLogin @copyLoginSplat
```
- **Ý nghĩa:** Copy 4 login cụ thể: 3 SQL login của WideWorldImporters và 1 Windows login. Phần `[CA]` trong sách là lỗi gõ — phải là chuỗi string `"ad\JaneReeves"`.
- **Đổi cho lab:** `Source = "dbatoolslab\sql2017"`, `Destination = "dbatoolslab"`, `Login = "WWI_Owner","WWI_ReadWrite","WWI_ReadOnly"`. Bỏ Windows login vì lab không có AD.
- **Lưu ý:** **CẢNH BÁO** — `Copy-DbaLogin` tạo login trên target. Nếu target đã có login cùng tên, lệnh sẽ skip (mặc định). Cần `-Force` để overwrite (rủi ro: thay đổi password hiện hành ở target).

### Đoạn 2: dòng 29-36 — Liệt kê database (không phải copy)
```powershell
$dbSplat = @{
    SqlInstance   = "sql02"
    ExcludeSystem = $true
    OutVariable   = "databases"
}
Get-DbaDatabase @dbSplat

$databases
```
- **Ý nghĩa:** `Get-DbaDatabase` với `-OutVariable databases` lưu kết quả vào biến `$databases` đồng thời output. `-ExcludeSystem` bỏ master/model/msdb/tempdb.
- **Đổi cho lab:** `SqlInstance = "dbatoolslab"`.
- **Lưu ý:** `-OutVariable` (alias `-ov`) là feature chung của PowerShell — pipe vào biến mà vẫn không cản trở output. Rất tiện cho scripting.

### Đoạn 3: dòng 40-45 — Copy tất cả login trừ system
```powershell
$copyLoginSplat = @{
    Source              = "sql01"
    Destination         = "sql02"
    ExcludeSystemLogins = $true
}
Copy-DbaLogin @copyLoginSplat
```
- **Ý nghĩa:** Copy toàn bộ login trừ system (sa, ##MS_*, NT SERVICE\..., NT AUTHORITY\...).
- **Đổi cho lab:** `Source = "dbatoolslab\sql2017"`, `Destination = "dbatoolslab"`.
- **Lưu ý:** **CẢNH BÁO** — vẫn có thể đè login user-defined ở target nếu trùng tên. Dùng `-WhatIf` trước để xem danh sách dự kiến.

### Đoạn 4: dòng 50-55 — Copy tất cả trừ một login cụ thể
```powershell
$copyLoginSplat = @{
    Source       = "sql01"
    Destination  = "sql02"
    ExcludeLogin = "ad\JaneReeves"
}
Copy-DbaLogin @copyLoginSplat
```
- **Ý nghĩa:** Copy tất cả login trừ `ad\JaneReeves`. Hữu ích khi muốn bỏ qua tài khoản đã nghỉ việc hoặc tài khoản dùng cho mục đích khác ở target.
- **Đổi cho lab:** `ExcludeLogin = "WWI_ReadOnly"` (chẳng hạn không muốn role này ở target).
- **Lưu ý:** Có thể combine `-ExcludeSystemLogins` và `-ExcludeLogin`.

### Đoạn 5: dòng 59 — Liệt kê Agent job
```powershell
Get-DbaAgentJob -SqlInstance sql01 | select-Object SqlInstance, Name, Category
```
- **Ý nghĩa:** List tên + category các Agent job để biết cái nào nên copy.
- **Đổi cho lab:** `SqlInstance = "dbatoolslab\sql2017"`.
- **Lưu ý:** Category là nhóm logic ("Database Maintenance", "DBA"...). dbatools cũng có `Copy-DbaAgentJobCategory` để chuyển category trước.

### Đoạn 6: dòng 64-70 — Copy Agent job và tắt ở source
```powershell
$copyJobSplat = @{
    Source          = "sql01"
    Destination     = "sql02"
    Job             = 'dbatools lab job','dbatools lab job - where am I'
    DisableOnSource = $true
}
Copy-DbaAgentJob @copyJobSplat
```
- **Ý nghĩa:** Copy hai job cụ thể, sau đó tắt chúng ở source. Đây là pattern "migrate job và đảm bảo không chạy trùng".
- **Đổi cho lab:** Thay tên instance, dùng job thật có trong `dbatoolslab\sql2017` (chạy đoạn 5 để liệt kê).
- **Lưu ý:** **CẢNH BÁO** — `DisableOnSource` thay đổi state job ở source. Nếu cutover thất bại và phải rollback, nhớ enable lại job ở source.

### Đoạn 7: dòng 75-80 — Copy operator (người nhận thông báo)
```powershell
$copyJobOperatorSplat = @{
    Source      = "sql01"
    Destination = "sql02"
    Operator    = 'dba'
}
Copy-DbaAgentOperator @copyJobOperatorSplat
```
- **Ý nghĩa:** Copy operator có tên `dba` (định nghĩa email/page/netsend cho cảnh báo). Job ở target sẽ tham chiếu operator này.
- **Đổi cho lab:** Trong lab có thể chưa có operator. Tạo trước hoặc xem `Get-DbaAgentOperator -SqlInstance dbatoolslab\sql2017`.
- **Lưu ý:** Thứ tự copy quan trọng: copy operator trước, sau đó copy job nào tham chiếu operator đó.

### Đoạn 8: dòng 85-91 — Lặp lại copy job (giống đoạn 6)
```powershell
$copyJobSplat = @{
    Source          = "sql01"
    Destination     = "sql02"
    Job             = 'dbatools lab job','dbatools lab job - where am I'
    DisableOnSource = $true
}
Copy-DbaAgentJob @copyJobSplat
```
- **Ý nghĩa:** Y hệt đoạn 6 — sách lặp để minh hoạ workflow tuần tự (đã copy operator ở đoạn 7, giờ copy job mới hoạt động đầy đủ).
- **Đổi cho lab:** Như đoạn 6.
- **Lưu ý:** Trong production thường gộp 3 bước (`Copy-DbaAgentOperator` → `Copy-DbaAgentJobCategory` → `Copy-DbaAgentJob`) trong một script.

### Đoạn 9: dòng 96-101 — Copy custom error message
```powershell
$copyMessageSplat = @{
    Source      = "sql01"
    Destination = "sql02"
    CustomError = 50005
}
Copy-DbaCustomError @copyMessageSplat
```
- **Ý nghĩa:** Copy message ID 50005 từ `sys.messages` của source sang target. Application code dùng `RAISERROR(50005, ...)` cần message tồn tại ở instance đích.
- **Đổi cho lab:** Thay tên instance. Có thể không có message id 50005 — `Get-DbaCustomError -SqlInstance dbatoolslab\sql2017` để xem.
- **Lưu ý:** Custom error IDs ≥ 50001. Trùng ID nhưng khác text giữa các instance là nguồn bug khó tìm.

### Đoạn 10: dòng 106-111 — Copy Agent alert
```powershell
$copyAlertSplat = @{
    Source      = "sql01"
    Destination = "sql02"
    Alert       = 'FactoryApp - Custom Alert'
}
Copy-DbaAgentAlert @copyAlertSplat
```
- **Ý nghĩa:** Copy một alert (rule kích hoạt khi gặp event/error/performance condition). Alert thường tham chiếu operator (đã copy ở đoạn 7) và message id (đã copy ở đoạn 9).
- **Đổi cho lab:** Thay tên instance và alert name. `Get-DbaAgentAlert -SqlInstance dbatoolslab\sql2017` để xem.
- **Lưu ý:** Alert phụ thuộc vào: (1) custom error / severity, (2) operator. Đảm bảo dependency có trước.

### Đoạn 11: dòng 116-118 — Pattern interactive: chọn job bằng GUI
```powershell
Get-DbaAgentJob -SqlInstance sql01 |
    Out-GridView -Passthru |
    Copy-DbaAgentJob -Destination dbatoolslab
```
- **Ý nghĩa:** Mở GUI grid để chọn job (ctrl-click chọn nhiều), nhấn OK, các job được chọn pipe thẳng qua `Copy-DbaAgentJob`. Cực kỳ tiện cho ad-hoc.
- **Đổi cho lab:** `Get-DbaAgentJob -SqlInstance dbatoolslab\sql2017 | Out-GridView -Passthru | Copy-DbaAgentJob -Destination dbatoolslab`.
- **Lưu ý:** `Out-GridView` chỉ chạy trên Windows PowerShell với UI. Trên server không UI hoặc PowerShell Core Linux thì không khả dụng.

### Đoạn 12: dòng 122-126 — Copy linked server
```powershell
$copyLinkedServerSplat = @{
    Source      = "sql01"
    Destination = "sql02"
}
Copy-DbaLinkedServer @copyLinkedServerSplat
```
- **Ý nghĩa:** Copy tất cả linked server (kèm credential nếu có) từ source sang target. dbatools dùng kỹ thuật DPAPI để giải mã password linked server.
- **Đổi cho lab:** Thay instance. Lab thường không có linked server, có thể chỉ là dry-run.
- **Lưu ý:** **CẢNH BÁO BẢO MẬT** — copy linked server gồm cả password đã lưu. Cần SQL service account đặc quyền local admin trên source. Tham khảo `Get-Help Copy-DbaLinkedServer -Examples`.

### Đoạn 13: dòng 131 — Khám phá tất cả Copy-Dba*
```powershell
Get-Command -Module dbatools -Verb Copy
```
- **Ý nghĩa:** Liệt kê toàn bộ cmdlet bắt đầu bằng `Copy-` trong module dbatools. Giúp khám phá phạm vi automation: Copy-DbaCredential, Copy-DbaDataCollector, Copy-DbaPolicyManagement, Copy-DbaResourceGovernor...
- **Đổi cho lab:** Chạy nguyên.
- **Lưu ý:** Cách tốt nhất để biết "tôi có thể copy gì giữa hai instance". `Get-Command -Module dbatools -Verb Get` cũng đáng xem.

## Lệnh thay vào lab của bạn

```powershell
$source = "dbatoolslab\sql2017"
$target = "dbatoolslab"

# 1) WhatIf trước cho mọi Copy-Dba* — đặc biệt khi target không trống
Copy-DbaLogin -Source $source -Destination $target `
    -Login "WWI_Owner","WWI_ReadWrite","WWI_ReadOnly" -WhatIf

# 2) Copy 3 login mẫu của WideWorldImporters
Copy-DbaLogin -Source $source -Destination $target `
    -Login "WWI_Owner","WWI_ReadWrite","WWI_ReadOnly"

# 3) Kiểm tra login đã sang
Get-DbaLogin -SqlInstance $target -Login "WWI_Owner","WWI_ReadWrite","WWI_ReadOnly" |
    Select-Object Name, LoginType, IsDisabled, Sid

# 4) Liệt kê Agent job ở source
Get-DbaAgentJob -SqlInstance $source |
    Select-Object Name, Category, Enabled, LastRunDate

# 5) Copy một job cụ thể (đổi tên job theo lab của bạn)
$copyJobSplat = @{
    Source          = $source
    Destination     = $target
    Job             = 'dbatools lab job'
    DisableOnSource = $false   # đặt $false để vẫn chạy ở source khi học
    WhatIf          = $true
}
Copy-DbaAgentJob @copyJobSplat

# 6) Pattern interactive (Windows-only)
Get-DbaAgentJob -SqlInstance $source |
    Out-GridView -Passthru |
    Copy-DbaAgentJob -Destination $target -WhatIf

# 7) Khám phá toàn bộ Copy-Dba*
Get-Command -Module dbatools -Verb Copy | Sort-Object Name
```

## Self-check
1. **Định nghĩa:** Vì sao `Copy-DbaLogin` giữ nguyên SID lại quan trọng với database vừa được restore sang target? (Gợi ý: orphaned user)
2. **Thực hành:** Sau khi copy 3 login `WWI_*` sang `dbatoolslab`, restore `WideWorldImporters` lên target. Dùng `Get-DbaDbOrphanUser -SqlInstance dbatoolslab` để kiểm tra: nếu SID đã khớp, không có orphan; nếu không, fix bằng `Repair-DbaDbOrphanUser`.
3. **Liên hệ:** Khi nào nên dùng `-ExcludeSystemLogins` và khi nào dùng `-ExcludeLogin "tên cụ thể"`? Cho ví dụ tình huống thực tế.

## Bài tập mở rộng
- **Bài 1:** Xây dựng script "migration checklist" cho lab: tuần tự `Copy-DbaCustomError` → `Copy-DbaAgentOperator` → `Copy-DbaAgentAlert` → `Copy-DbaAgentJobCategory` → `Copy-DbaAgentJob` từ `dbatoolslab\sql2017` sang `dbatoolslab`, mỗi bước có `-WhatIf` đầu rồi chạy thật.
- **Bài 2:** Dùng `Out-GridView -Passthru` để chọn ngẫu nhiên một số job và copy. Sau đó so sánh `Get-DbaAgentJob` trên cả hai instance bằng `Compare-Object -Property Name` để xác nhận đúng những job được chọn đã sang.


---

!!! info "Nguồn gốc"
    `book_lab/dbatools-lab/bookcode/chapter16.notes.md`
