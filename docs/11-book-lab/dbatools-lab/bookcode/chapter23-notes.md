---
title: Chapter 23 — SQL Trace & Extended Events (XEvents)
course: 11-book-lab
source: book_lab/dbatools-lab/bookcode/chapter23.notes.md
---

# Chapter 23 — SQL Trace & Extended Events (XEvents)

> **Cảnh báo MẠNH:** Các session Extended Events ghi log vào file `.xel` có thể **phình to rất nhanh** (vài GB/giờ với session bắt query nhiều). Luôn:
> 1. Thiết lập `max_file_size` + `max_rollover_files` hợp lý khi tạo session.
> 2. Lưu file `.xel` vào ổ KHÔNG phải ổ system / ổ data của user DB.
> 3. `Stop-DbaXESession` ngay khi không còn cần.
> 4. Dọn `.xel`/`.xem` cũ định kỳ.
> Trace cũ (`sp_trace_*`) ít rủi ro tràn nhưng cũng cần stop sau khi xong.

## Mục tiêu
- Lấy danh sách SQL Trace cũ đang chạy bằng `Get-DbaTrace`.
- Convert default trace sang XEvent session bằng `ConvertTo-DbaXESession`.
- Liệt kê, import template, start/stop XEvent session.
- Đọc file `.xel` đã ghi và watch session real-time.
- Copy session sang nhiều instance.

## Tóm tắt 3-5 ý chính
1. **SQL Trace là legacy**, Microsoft khuyến nghị dùng **Extended Events (XE)**. dbatools có lệnh chuyển đổi.
2. **`Get-DbaXESession`** trả về session đã tạo trên instance; **`Get-DbaXESessionTemplate`** trả về template có sẵn (Microsoft + community).
3. Workflow: `Get-DbaXESessionTemplate -Template <name>` → `Import-DbaXESessionTemplate -SqlInstance <s>` → `Start-DbaXESession` → ... → `Stop-DbaXESession`.
4. **`Watch-DbaXESession`** stream event theo thời gian thực; **`Read-DbaXEFile`** đọc lại từ file `.xel` đã ghi.
5. **`Copy-DbaXESession`** đẩy 1 session sang nhiều server — chuẩn hoá monitoring trên cả nhóm.

## Giải thích từng đoạn code

### Đoạn 1: dòng 18 — list trace cũ trên nhiều server
```powershell
Get-DbaTrace -SqlInstance sql01, sql02, sql03
```
- **Ý nghĩa:** Liệt kê các SQL Trace (`sp_trace_*`) đang định nghĩa trên 3 instance. Default trace có `Id = 1`.
- **Đổi cho lab:** `Get-DbaTrace -SqlInstance dbatoolslab\sql2017, dbatoolslab`.

### Đoạn 2: dòng 22 — lấy trace từ Registered Server
```powershell
Get-DbaRegisteredServer | Get-DbaTrace
```
- **Ý nghĩa:** Pipeline từ CMS/Local Registered Servers vào `Get-DbaTrace`.
- **Đổi cho lab:** Nếu chưa đăng ký server: `Add-DbaRegServer -SqlInstance dbatoolslab\sql2017 -ServerName 'dbatoolslab\sql2017'` trước.

### Đoạn 3: dòng 27-28 — pick rồi start trace
```powershell
Get-DbaRegisteredServer | Get-DbaTrace |
    Out-GridView -PassThru | Start-DbaTrace
```
- **Ý nghĩa:** Hiện GridView để chọn trace nào → `Start-DbaTrace` bật lên.
- **Đổi cho lab:** Như đoạn 2.
- **Lưu ý:** `Out-GridView -PassThru` cần Windows PowerShell host có GUI; không chạy được trong devcontainer Linux.

### Đoạn 4: dòng 32-34 — convert default trace sang XE
```powershell
Get-DbaTrace -SqlInstance sql2014 | Where-Object Id -eq 1 |
    ConvertTo-DbaXESession -Name 'Converted Default Trace' |
    Start-DbaXESession
```
- **Ý nghĩa:** Lấy default trace, đẻ ra 1 XE session tương đương rồi start luôn.
- **Đổi cho lab:** `Get-DbaTrace -SqlInstance dbatoolslab\sql2017 | Where-Object Id -eq 1 | ConvertTo-DbaXESession -Name 'Lab Converted Default Trace' | Start-DbaXESession`.
- **Cảnh báo:** Session mới ghi file `.xel` — kiểm tra path đích.

### Đoạn 5: dòng 39 — tìm command liên quan XE
```powershell
Find-DbaCommand -Tag ExtendedEvent
```
- **Ý nghĩa:** Liệt kê toàn bộ cmdlet dbatools có tag `ExtendedEvent`.
- **Đổi cho lab:** Giữ nguyên.

### Đoạn 6: dòng 43 — list XE session qua Registered Server
```powershell
Get-DbaRegServer | Get-DbaXESession
```
- **Đổi cho lab:** Như đoạn 2.

### Đoạn 7: dòng 47 — xem 1 session cụ thể
```powershell
Get-DbaXESession -SqlInstance mssql1 -Session telemetry_xevents
```
- **Ý nghĩa:** `telemetry_xevents` là session mặc định SQL Server 2016+ chạy sẵn.
- **Đổi cho lab:** `Get-DbaXESession -SqlInstance dbatoolslab\sql2017 -Session telemetry_xevents`.

### Đoạn 8: dòng 52 — list template
```powershell
Get-DbaXESessionTemplate
```
- **Ý nghĩa:** Trả về template có trong dbatools (deadlocks, query timeouts, login tracker...).

### Đoạn 9: dòng 57-59 — import template & start
```powershell
Get-DbaXESessionTemplate -Template 'Deprecated Feature Usage' |
    Import-DbaXESessionTemplate -SqlInstance mssql1 |
    Start-DbaXESession
```
- **Đổi cho lab:** Đổi `mssql1` → `dbatoolslab\sql2017`.
- **Lưu ý:** Session "Deprecated Feature Usage" ít noise — tốt để thử.

### Đoạn 10: dòng 64-65 — import từ file XML custom
```powershell
Get-ChildItem 'C:\temp\Login Tracker.xml' |
    Import-DbaXESessionTemplate -SqlInstance mssql1
```
- **Đổi cho lab:** Lưu file XML template vào `C:\dbatoolslab\xe-templates\Login Tracker.xml`, đổi instance thành `dbatoolslab\sql2017`.

### Đoạn 11: dòng 70 — start session
```powershell
Start-DbaXESession -SqlInstance mssql1 -Session "Query Timeouts"
```
- **Đổi cho lab:** Đổi `mssql1` → `dbatoolslab\sql2017`.

### Đoạn 12: dòng 75 — stop session
```powershell
Stop-DbaXESession -SqlInstance mssql1 -Session "Query Timeouts"
```
- **Đổi cho lab:** Như đoạn 11.

### Đoạn 13: dòng 80 — auto-stop sau N phút
```powershell
Start-DbaXESession -SqlInstance mssql1 -Session 'Query Timeouts'  -StopAt (Get-Date).AddMinutes(30)
```
- **Ý nghĩa:** Hữu ích khi muốn thu thập trong giờ peak rồi tự tắt.
- **Đổi cho lab:** Đổi `mssql1` → `dbatoolslab\sql2017`. Có thể đổi `30` → `5` cho lab.

### Đoạn 14: dòng 84-85 — watch real-time
```powershell
Watch-DbaXESession -SqlInstance mssql1 -Session QuickSessionStandard |
    Where-Object client_app_name -match dbatools
```
- **Ý nghĩa:** Stream event ra console, lọc theo app name.
- **Đổi cho lab:** Đổi `mssql1` → `dbatoolslab\sql2017`. Cần session `QuickSessionStandard` đã tồn tại — import từ template trước.

### Đoạn 15: dòng 90 — đọc file .xel
```powershell
Read-DbaXEFile -Path C:\temp\deadocks.xel
```
- **Ý nghĩa:** Parse file `.xel` (có thể từ server khác) thành object PowerShell.
- **Đổi cho lab:** Đổi path. Lưu ý chính tả `deadocks` → `deadlocks` trong file thực.

### Đoạn 16: dòng 94-99 — copy session sang nhiều server
```powershell
$splatCopyXESession = @{
    Source = "mssql1"
    Destination = "mssql2", "mssql3"
    XeSession = "Login Tracker"
}
Copy-DbaXESession @splatCopyXESession
```
- **Đổi cho lab:** `Source = 'dbatoolslab\sql2017'`, `Destination = 'dbatoolslab'`. Nếu chỉ có 1 instance đích, vẫn OK.

## Lệnh thay vào lab của bạn

```powershell
$inst = 'dbatoolslab\sql2017'

# 1) Khám phá
Get-DbaTrace -SqlInstance $inst
Get-DbaXESession -SqlInstance $inst | Format-Table Name, Status, StartTime

# 2) Import template "Deprecated Feature Usage" và start
$session = Get-DbaXESessionTemplate -Template 'Deprecated Feature Usage' |
    Import-DbaXESessionTemplate -SqlInstance $inst
Start-DbaXESession -SqlInstance $inst -Session $session.Name -StopAt (Get-Date).AddMinutes(5)

# 3) Sinh 1 cảnh báo deprecated (chạy 1 deprecated syntax cũ)
Invoke-DbaQuery -SqlInstance $inst -Database master `
    -Query "SET ROWCOUNT 10; SELECT TOP 1 * FROM sys.databases;"

# 4) Đợi rồi đọc file .xel mà session ghi ra
Start-Sleep -Seconds 10
$xeFile = (Get-DbaXESession -SqlInstance $inst -Session $session.Name).TargetFile
Read-DbaXEFile -Path $xeFile | Select-Object timestamp, name | Format-Table

# 5) Stop & cleanup
Stop-DbaXESession -SqlInstance $inst -Session $session.Name
Remove-DbaXESession -SqlInstance $inst -Session $session.Name -Confirm:$false
```

## Self-check (3 câu)
1. **Định nghĩa:** Khác nhau giữa `Watch-DbaXESession` và `Read-DbaXEFile` là gì? (Gợi ý: stream live vs đọc file đã ghi.)
2. **Thực hành:** Sau khi `Start-DbaXESession`, gọi `Get-DbaXESession -SqlInstance $inst -Session <name>` — property `TargetFile` trỏ tới đâu? File có tồn tại trên đĩa không?
3. **Liên hệ:** Vì sao Microsoft khuyến nghị XEvents thay cho SQL Trace? Nêu 2 lý do (hiệu năng, độ linh hoạt).

## Bài tập mở rộng
- **Bài 1:** Tạo XE session bắt mọi `error_reported` với severity ≥ 16, chạy 10 phút rồi tự stop, đọc kết quả ra console.
- **Bài 2:** Viết script daily: list session đang chạy, cảnh báo nếu có session nào ghi file > 500 MB.
- **Bài 3:** Convert default trace (`Id = 1`) của `dbatoolslab\sql2017` sang XE, lưu file template `.xml` ra `C:\dbatoolslab\xe-templates\` để reuse.


---

!!! info "Nguồn gốc"
    `book_lab/dbatools-lab/bookcode/chapter23.notes.md`
