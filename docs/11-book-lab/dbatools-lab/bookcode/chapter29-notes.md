---
title: Chapter 29 — Thực hành tổng hợp (Bonus lab chapter)
course: 11-book-lab
source: book_lab/dbatools-lab/bookcode/chapter29.notes.md
---

# Chapter 29 — Thực hành tổng hợp (Bonus lab chapter)

> Tham chiếu code gốc: [chapter29.ps1](chapter29.ps1)

> **Lưu ý:** Đây là **chapter bonus của repo `dbatools-lab`**, KHÔNG có trong sách *Learn dbatools in a Month of Lunches* (sách dừng ở chapter 28). Mục đích: cung cấp một bài thực hành tổng kết — chạy qua nhanh các kỹ năng chính từ chapter 02 đến chapter 28 trên một instance lab duy nhất (`dbatoolslab\sql2017`), kèm self-check câu hỏi.

## Mục tiêu
- Ôn tập có hệ thống 6 nhóm chức năng đã học: discovery, connectivity, database inventory, backup, agent jobs, và safe-mode practice.
- Xác nhận lab environment hoạt động end-to-end trước khi đi vào dự án thực tế.
- Củng cố thói quen dùng `-WhatIf` cho mọi write operation khi học.
- Tự kiểm tra hiểu biết qua 3 câu self-check tại cuối script.
- Có khung mẫu cho việc viết script "health check" ngắn ngày của riêng bạn.

## Tóm tắt 5 ý chính (gói lại 28 chapter)
1. **Discovery first** (chapter 02–04): mọi exploration đều bắt đầu từ `Get-Command -Module dbatools` và `Find-DbaCommand -Pattern <topic>`. Đừng cố nhớ ~600 cmdlet — học cách tìm.
2. **Connect once, reuse object** (chapter 04, 27): `$server = Connect-DbaInstance ...` rồi truyền `$server` cho cmdlet downstream — đỡ phải auth lại nhiều lần, đặc biệt quan trọng với Azure SQL.
3. **Inventory & state** (chapter 05–07, 12, 15, 18): `Get-DbaDatabase`, `Get-DbaAgentJob`, `Get-DbaLogin`, `Get-DbaBackupHistory`... là bộ "read-only mặc định an toàn" — chạy thoải mái.
4. **Write operations luôn có `-WhatIf`** (xuyên suốt sách): `Backup-DbaDatabase`, `Restore-DbaDatabase`, `Copy-DbaLogin`, `Set-DbaDbState`... đều hỗ trợ `-WhatIf`/`-Confirm`. Reflex tự nhiên khi học: viết `-WhatIf` trước, xoá sau khi review.
5. **Config & cloud** (chapter 27–28): cùng một bộ cmdlet làm việc với on-prem và Azure SQL nhờ abstraction qua `Connect-DbaInstance`. `dbatools` config system cho phép tinh chỉnh hành vi mặc định (timeout, log path, encrypt) ở cấp session hoặc persistent.

## Giải thích từng đoạn code

### Đoạn khởi tạo: dòng 8 — Tên instance lab
```powershell
$instance = 'dbatoolslab\sql2017'
```
- **Ý nghĩa:** Gán tên instance vào biến để tái sử dụng. Khớp với cấu hình lab trong `02_Configure_Lab.ps1` của repo.
- **Đổi cho lab:**
  - Đường A (devcontainer SQL 2019): đổi thành `'localhost'` hoặc `'localhost,1433'`.
  - Đường B (Full Windows Lab): giữ nguyên `'dbatoolslab\sql2017'`.
  - Production: đổi thành tên server thật của bạn.
- **Lưu ý:** Đặt 1 biến trên đầu file — pattern tốt; không hard-code rải rác.

### Đoạn 1: dòng 10–12 — Practice Discovery (chapter 02–04)
```powershell
Write-Host "=== Chapter 29 Practice: Discovery ===" -ForegroundColor Cyan
Get-Command -Module dbatools | Select-Object -First 10 Name
Find-DbaCommand -Pattern Backup | Select-Object -First 5
```
- **Ý nghĩa:** Hai cmdlet discovery cơ bản — `Get-Command` liệt kê cmdlet, `Find-DbaCommand` search có ngữ nghĩa (description, alias).
- **Liên hệ chapter trước:** Chapter 02 (PSModulePath), Chapter 04 (Find-DbaCommand intro).
- **Lưu ý:** `Find-DbaCommand` lần đầu chạy hơi chậm vì build index — sau đó cache.

### Đoạn 2: dòng 14–15 — Connectivity check (chapter 04)
```powershell
Write-Host "=== Chapter 29 Practice: Connectivity ===" -ForegroundColor Cyan
Test-DbaConnection -SqlInstance $instance
```
- **Ý nghĩa:** Kiểm tra TCP, ping, SQL auth, version, edition trong một cmdlet — pre-flight check trước mọi script.
- **Liên hệ chapter trước:** Chapter 04 (Connect-DbaInstance), Chapter 03 (Restore-DbaDatabase cần connectivity).
- **Lưu ý:** Output bao gồm cả `ConnectSuccess` (boolean) — nên check trước khi proceed:
  ```powershell
  if (-not (Test-DbaConnection -SqlInstance $instance).ConnectSuccess) { throw "Cannot connect to $instance" }
  ```

### Đoạn 3: dòng 17–19 — Database inventory (chapter 05–07)
```powershell
Write-Host "=== Chapter 29 Practice: Database Inventory ===" -ForegroundColor Cyan
Get-DbaDatabase -SqlInstance $instance -ExcludeSystem |
    Select-Object Name, Status, RecoveryModel, LastFullBackup
```
- **Ý nghĩa:** Liệt kê user database (loại trừ master/model/msdb/tempdb) + 4 thuộc tính trọng yếu.
- **Liên hệ chapter trước:** Chapter 05 (Get-DbaDatabase), Chapter 12 (LastFullBackup property là từ backup history).
- **Đổi cho lab:** Nên thấy `WideWorldImporters` và `AdventureWorks2017` nếu đã chạy `02_Configure_Lab.ps1`.
- **Lưu ý:** `Status` báo `Normal` là OK. `RecoveryModel` mặc định `Full` — chapter 12 sẽ học khi nào nên đổi `Simple`.

### Đoạn 4: dòng 21–23 — Backup WhatIf (chapter 12)
```powershell
Write-Host "=== Chapter 29 Practice: Backup WhatIf (safe) ===" -ForegroundColor Cyan
$backupPath = 'C:\dbatoolslab\Backup'
Backup-DbaDatabase -SqlInstance $instance -Database 'WideWorldImporters' -Path $backupPath -WhatIf
```
- **Ý nghĩa:** Demo cú pháp backup an toàn — `-WhatIf` chỉ in ra hành động dự kiến, không thực thi.
- **Liên hệ chapter trước:** Chapter 12 (Backup), Chapter 13 (Restore), Chapter 18 (Maintenance plan / Ola).
- **Đổi cho lab:**
  - Devcontainer Linux: đổi `$backupPath = '/var/opt/mssql/backup'` (path mà container SQL service write được).
  - Bỏ `-WhatIf` để backup thật, hoặc dùng `-CopyOnly` để không ảnh hưởng chuỗi LSN.
- **Lưu ý:** Folder `$backupPath` phải tồn tại + SQL Server service account có quyền write. `Backup-DbaDatabase` không tự tạo folder remote (chỉ tạo local).

### Đoạn 5: dòng 25–27 — Agent Jobs inventory (chapter 18)
```powershell
Write-Host "=== Chapter 29 Practice: Agent Jobs ===" -ForegroundColor Cyan
Get-DbaAgentJob -SqlInstance $instance |
    Select-Object Name, Enabled, LastRunOutcome
```
- **Ý nghĩa:** Liệt kê job SQL Agent + trạng thái enabled + outcome lần chạy cuối.
- **Liên hệ chapter trước:** Chapter 18 (Agent Jobs), Chapter 19 (Operators/Alerts).
- **Đổi cho lab:** Devcontainer/SQL Express không có Agent → cmdlet trả empty hoặc warning. Trên SQL Developer/Standard/Enterprise sẽ có dữ liệu.
- **Lưu ý:** Cột `LastRunOutcome` giá trị `Failed` cần điều tra — kết hợp `Get-DbaAgentJobHistory` để xem step nào fail.

### Đoạn 6: dòng 29–32 — Self-check questions
```powershell
Write-Host "=== Chapter 29 Practice: Self-check Questions ===" -ForegroundColor Yellow
Write-Host "1) Which dbatools command helps you discover commands by topic?"
Write-Host "2) Which instance in this lab holds the restored sample databases?"
Write-Host "3) Why do we use -WhatIf before a write operation in learning labs?"
```
- **Ý nghĩa:** Script kết thúc bằng 3 câu hỏi — không có code answer, để học viên tự trả lời.
- **Đổi cho lab:** Giữ nguyên. Đây là pattern hay copy sang script training nội bộ.
- **Đáp án gợi ý:**
  1. `Find-DbaCommand -Pattern <topic>` (đoạn 1 đã dùng).
  2. `dbatoolslab\sql2017` — gán ở dòng 8.
  3. Để xem trước hành động và tránh hỏng dữ liệu khi học; là reflex chuyên nghiệp cho mọi write operation chưa quen.

## Lệnh thay vào lab của bạn

Phiên bản "rộng hơn" của chapter 29 — ôn tập đa chiều, thêm cả chapter 27/28:

```powershell
$instance = 'dbatoolslab\sql2017'   # đổi cho môi trường bạn

# === Nhóm 1: Discovery & connectivity (chapter 02–04) ===
Get-Command -Module dbatools | Measure-Object       # ~600+ là OK
Find-DbaCommand -Pattern 'Login' | Select-Object Name -First 5
$server = Connect-DbaInstance -SqlInstance $instance
Test-DbaConnection -SqlInstance $server | Select-Object SqlInstance, ConnectSuccess, AuthType, Edition

# === Nhóm 2: Inventory (chapter 05–07, 15) ===
Get-DbaDatabase -SqlInstance $server -ExcludeSystem | Format-Table Name, Status, RecoveryModel, SizeMB, LastFullBackup
Get-DbaLogin -SqlInstance $server -ExcludeFilter '##*','sa' | Format-Table Name, LoginType, IsDisabled
Get-DbaProcess -SqlInstance $server -ExcludeSystemSpids | Format-Table Spid, Login, Host, Program -AutoSize

# === Nhóm 3: Backup & restore (chapter 12–13) ===
$backupPath = 'C:\dbatoolslab\Backup'   # Linux: '/var/opt/mssql/backup'
Backup-DbaDatabase -SqlInstance $server -Database WideWorldImporters -Path $backupPath -CopyOnly -WhatIf
Get-DbaBackupHistory -SqlInstance $server -Database WideWorldImporters -Last | Select-Object Database, Type, Start, Path

# === Nhóm 4: Maintenance & Agent (chapter 17–19) ===
Get-DbaAgentJob -SqlInstance $server | Select-Object Name, Enabled, LastRunOutcome, LastRunDate
Get-DbaDbIntegrityCheck -SqlInstance $server -Database WideWorldImporters | Select-Object Database, LastGoodCheckDb

# === Nhóm 5: Config & cloud awareness (chapter 27–28) ===
Get-DbatoolsConfigValue -FullName sql.connection.timeout
Get-DbatoolsConfig -Module sql.connection.encrypt | Select-Object FullName, Value
# (Azure SQL: bỏ qua nếu không có subscription — xem chapter27.notes.md)

# === Cleanup ===
$server.ConnectionContext.Disconnect()
Remove-Variable server
```

## Self-check (3 câu)
1. **Định nghĩa:** Trong 5 nhóm cmdlet đã ôn ở trên (Discovery, Connectivity, Inventory, Backup, Agent), nhóm nào là **read-only an toàn** chạy bất cứ lúc nào, và nhóm nào cần `-WhatIf` đầu tiên? Liệt kê.
2. **Thực hành:** Trên `dbatoolslab\sql2017`, chạy `Get-DbaDatabase -SqlInstance $instance -ExcludeSystem` và đếm số database. Nếu kết quả khác kỳ vọng (ví dụ `WideWorldImporters` không có), bạn sẽ kiểm tra script nào trong repo trước? (Gợi ý: `scripts/02_Configure_Lab.ps1`).
3. **Liên hệ:** Sau 28 chapter + chapter bonus này, bạn nghĩ workflow điển hình "buổi sáng DBA dùng dbatools" sẽ gồm những cmdlet nào theo thứ tự? Phác thảo 5–7 bước cho mình.

## Bài tập mở rộng
- **Bài 1 (~10 phút): Viết script `Invoke-MorningDbaCheck.ps1`** dựa trên chapter 29 nhưng cho TẤT CẢ instance trong file `config/instances.json` (giả định mỗi line là một `SqlInstance`). Output ra Excel/CSV (`Export-Excel` từ module `ImportExcel` hoặc `Export-Csv`).
- **Bài 2 (sâu hơn): Viết Pester test** trong `tests/` verify rằng sau khi `02_Configure_Lab.ps1` chạy xong, các điều kiện sau đều `$true`:
  - `Test-DbaConnection -SqlInstance 'dbatoolslab\sql2017'` thành công.
  - Có cả `WideWorldImporters` và `AdventureWorks2017` trong `Get-DbaDatabase`.
  - 3 login `WWI_ReadOnly`, `WWI_ReadWrite`, `WWI_Owner` tồn tại.
- **Bài 3 (ôn tổng kết — quan trọng nhất):** Mở lại 28 file `chapterXX.notes.md` (đã viết của bạn) — chọn ra **3 cmdlet bạn vẫn chưa thuần**. Viết 1 đoạn script ngắn (~5 dòng) demo từng cmdlet đó trên `dbatoolslab\sql2017`. Đây chính là "ôn cuối kỳ" trước khi dùng `dbatools` cho việc thật.
- **Bài 4 (chia sẻ):** Trong file `PROJECT_GUIDE_VI.md` hoặc một blog post cá nhân, ghi lại 3 bài học lớn nhất sau khi hoàn thành 29 chapter. Chia sẻ cộng đồng — đây cũng là cách củng cố tốt nhất.


---

!!! info "Nguồn gốc"
    `book_lab/dbatools-lab/bookcode/chapter29.notes.md`
