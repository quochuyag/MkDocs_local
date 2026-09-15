---
title: 'Chapter 03 — Dựng lab dbatools: cài instance, restore DB, tạo login & job'
course: 11-book-lab
source: book_lab/dbatools-lab/bookcode/chapter03.notes.md
---

# Chapter 03 — Dựng lab dbatools: cài instance, restore DB, tạo login & job

> Tham chiếu code gốc: [chapter03.ps1](chapter03.ps1)

## Mục tiêu
- Hiểu workflow cài SQL Server bằng `Install-DbaInstance` (không phải bằng GUI Setup).
- Restore được sample database `WideWorldImporters` và `AdventureWorks2017`.
- Tạo login + database user + role member bằng dbatools.
- Tạo SQL Server Agent job đầu tiên bằng `New-DbaAgentJob` / `New-DbaAgentJobStep`.
- Hiểu cấu hình instance qua `Set-DbaSpConfigure` (RemoteDac, Cost Threshold for Parallelism).
- Nắm bài thay thế: dựng SQL bằng Docker (`dbatools/sqlinstance` image) khi không có Windows lab.

## Tóm tắt 5 ý chính
1. **`Install-DbaInstance`** tự động hoá hầu hết Setup.exe của SQL Server — chỉ cần media và 1-2 tham số quan trọng (Version, Feature, Path, AuthenticationMode).
2. **`Restore-DbaDatabase`** phát hiện cấu trúc backup chain rồi tự gọi đúng `RESTORE` T-SQL, không cần viết tay `RESTORE DATABASE … WITH MOVE …`.
3. **Quản lý security 3 bước:** tạo login (cấp instance) → tạo database user (cấp DB) → add vào role. dbatools có 3 cmdlet tương ứng `New-DbaLogin` / `New-DbaDbUser` / `Add-DbaDbRoleMember`.
4. **SQL Agent job** được build bằng pipeline 2 cmdlet: `New-DbaAgentJob` (vỏ job) → `New-DbaAgentJobStep` (bước cụ thể).
5. **`Set-DbaSpConfigure`** là wrapper của `sp_configure` — đổi cấu hình instance không cần SSMS, idempotent và có `-WhatIf`.
6. **Docker fallback:** nếu không có Windows lab, kéo image `dbatools/sqlinstance` để mô phỏng instance nhanh (script cuối file). `New-DbaClientAlias` giúp đặt alias đẹp cho container.

> Code gốc chapter này mang tính "dựng lab cho cả các chapter sau", nên có nhiều lệnh ghi dữ liệu. Hầu hết đã được script hoá lại sạch hơn trong `scripts/01_Install_Lab.ps1` và `scripts/02_Configure_Lab.ps1` — đọc song song để hiểu repo đã refactor như thế nào.

## Giải thích từng đoạn code

### Đoạn 1: dòng 18
```powershell
Install-DbaInstance -Version 2019 -SqlInstance dbatoolslab -Feature Engine -Path Z:\2019 -AuthenticationMode Mixed
```
- **Ý nghĩa:** Cài SQL Server 2019 default instance tên `dbatoolslab`, chỉ component Engine, media nằm ở `Z:\2019`, bật chế độ Mixed authentication (cho phép cả SQL login lẫn Windows).
- **Đổi cho lab:** Đường dẫn `-Path` phải khớp media bạn giải nén (xem [config/Config.psd1](../config/config.psd1)). Tên instance giữ nguyên — lab repo dùng đúng `dbatoolslab` làm default instance.
- **Side-effect:** Đây là lệnh **cài SQL Server thật** — chiếm vài GB ổ, mở port 1433, cần quyền admin local. **Chạy `-WhatIf` trước** để kiểm tra plan.
- **Lưu ý:** Chỉ chạy trên máy Windows. Devcontainer Linux đã có sẵn SQL 2019 nên skip lệnh này.

### Đoạn 2: dòng 22
```powershell
Install-DbaInstance -Version 2017
```
- **Ý nghĩa:** Cài SQL Server 2017 với cài đặt mặc định (named instance `SQL2017`, Path tự suy ra). Trong lab repo dự định cài thành named instance `dbatoolslab\sql2017`.
- **Đổi cho lab:** Bổ sung tham số để khớp lab:
  ```powershell
  Install-DbaInstance -Version 2017 -SqlInstance dbatoolslab\sql2017 -Feature Engine -Path Z:\2017 -AuthenticationMode Mixed
  ```
- **Side-effect:** Tương tự đoạn 1, đây là lệnh cài SQL Server thật — chạy `-WhatIf` trước.

### Đoạn 3: dòng 26
```powershell
Connect-DbaInstance -SqlInstance dbatoolslab
```
- **Ý nghĩa:** Smoke test sau khi cài. Output `Server[]` object cho biết version, edition, platform.
- **Đổi cho lab:** Có thể chạy thêm `Connect-DbaInstance -SqlInstance dbatoolslab\sql2017` để verify cả 2 instance.
- **Lưu ý:** Không có `-WhatIf` — lệnh read-only.

### Đoạn 4: dòng 30-32
```powershell
Find-DbaInstance -ComputerName localhost

ComputerName InstanceName Port  Availability Confidence ScanTypes
```
- **Ý nghĩa:** Quét tất cả instance SQL Server trên máy local (qua SQL Browser + WMI + registry…). Dòng dưới là **header output mẫu**, không phải code chạy.
- **Đổi cho lab:** Thay `localhost` bằng `dbatoolslab` nếu chạy từ máy khác trong cùng network. Chapter 06 sẽ đào sâu lệnh này.

### Đoạn 5: dòng 36-37
```powershell
Restore-DbaDatabase -SqlInstance dbatoolslab\sql2017 -Path C:\dbatoolslab\Backup\WideWorldImporters-Full.bak
Restore-DbaDatabase -SqlInstance dbatoolslab\sql2017 -Path C:\dbatoolslab\Backup\AdventureWorks2017-Full.bak
```
- **Ý nghĩa:** Restore 2 sample database. dbatools tự đọc header `.bak`, suy ra logical file name, MDF/LDF path, rồi gọi `RESTORE`.
- **Đổi cho lab:** Lab repo đã có 2 file `.bak` này tải về `C:\dbatoolslab\Backup\` qua `scripts/00_Install_Prereqs.ps1`. Đường dẫn match. Nếu khác thì sửa.
- **Side-effect:** **Ghi dữ liệu** (tạo DB mới hoặc overwrite). **Bắt buộc `-WhatIf` trước** để xem dbatools sẽ MOVE file vào đâu:
  ```powershell
  Restore-DbaDatabase -SqlInstance dbatoolslab\sql2017 -Path C:\dbatoolslab\Backup\WideWorldImporters-Full.bak -WhatIf
  ```

### Đoạn 6: dòng 41-62
```powershell
$pw = (Get-Credential wejustneedthepassword).Password
New-DbaLogin -SqlInstance dbatoolslab\sql2017 -Password $pw -Login WWI_ReadOnly
New-DbaLogin -SqlInstance dbatoolslab\sql2017 -Password $pw -Login WWI_ReadWrite
New-DbaLogin -SqlInstance dbatoolslab\sql2017 -Password $pw -Login WWI_Owner

# Create database users
New-DbaDbUser -SqlInstance dbatoolslab\sql2017 -Login WWI_ReadOnly -Database WideWorldImporters -Confirm:$false
New-DbaDbUser -SqlInstance dbatoolslab\sql2017 -Login WWI_ReadWrite -Database WideWorldImporters -Confirm:$false
New-DbaDbUser -SqlInstance dbatoolslab\sql2017 -Login WWI_Owner -Database WideWorldImporters -Confirm:$false

# Add database role members
Add-DbaDbRoleMember -SqlInstance dbatoolslab\sql2017 -Database WideWorldImporters -User WWI_Readonly -Role db_datareader
Add-DbaDbRoleMember -SqlInstance dbatoolslab\sql2017 -Database WideWorldImporters -User WWI_ReadWrite -Role db_datawriter
Add-DbaDbRoleMember -SqlInstance dbatoolslab\sql2017 -Database WideWorldImporters -User WWI_Owner -Role db_owner

# Create some SQL Server Agent jobs
$job = New-DbaAgentJob -SqlInstance dbatoolslab\sql2017 -Job 'dbatools lab job' -Description 'Creating a test job for our lab'
New-DbaAgentJobStep -SqlInstance dbatoolslab\sql2017 -Job $Job.Name -StepName 'Step 1: Select statement' -Subsystem TransactSQL -Command 'Select 1'

# add second job
$job = New-DbaAgentJob -SqlInstance dbatoolslab\sql2017 -Job 'dbatools lab - where am I' -Description 'Creating test2 job for our lab'
New-DbaAgentJobStep -SqlInstance dbatoolslab\sql2017 -Job $Job.Name -StepName 'Step 1: Select servername' -Subsystem TransactSQL -Command 'Select @@ServerName'
```
- **Ý nghĩa:** "Đầy đủ pipeline security": login (cấp instance) → user (cấp DB) → role. Sau đó tạo 2 Agent job demo.
- **Đổi cho lab:** Tên instance đã đúng `dbatoolslab\sql2017`. Mật khẩu: `Get-Credential` sẽ pop dialog — nhập password bất kỳ phù hợp policy SQL.
- **Side-effect:** Tất cả `New-Db*` và `Add-Db*` đều **ghi dữ liệu**. Cân nhắc `-WhatIf` từng dòng lần đầu chạy. Nếu lab đã được `02_Configure_Lab.ps1` setup, các đối tượng này có thể đã tồn tại → lệnh sẽ báo lỗi conflict (bình thường).
- **Lưu ý:** SQL Agent **không có trên SQL Linux container** (Đường A) — block này skip nếu đang trong devcontainer.

### Đoạn 7: dòng 66-67
```powershell
Set-DbaSpConfigure -SqlInstance dbatoolslab\sql2017 -Name RemoteDacConnectionsEnabled -Value 1
Set-DbaSpConfigure -SqlInstance dbatoolslab\sql2017 -Name CostThresholdForParallelism -Value 10
```
- **Ý nghĩa:** Bật Remote DAC (Dedicated Admin Connection) và đặt Cost Threshold for Parallelism = 10 (mặc định 5, best-practice 25-50 cho OLTP — sách dùng 10 để demo).
- **Đổi cho lab:** Giữ nguyên.
- **Side-effect:** **Ghi cấu hình instance**. Hai cấu hình này không cần restart SQL Service, nhưng `-WhatIf` trước vẫn tốt:
  ```powershell
  Set-DbaSpConfigure -SqlInstance dbatoolslab\sql2017 -Name CostThresholdForParallelism -Value 10 -WhatIf
  ```

### Đoạn 8: dòng 72-76
```powershell
# create a shared network
docker network create localnet

# Expose engines and setup shared path for migrations
docker run -p 1433:1433  --volume shared:/shared:z --name mssql1 --hostname mssql1 --network localnet -d dbatools/sqlinstance
docker run -p 14333:1433 --volume shared:/shared:z --name mssql2 --hostname mssql2 --network localnet -d dbatools/sqlinstance2
```
- **Ý nghĩa:** Bản Docker thay thế cho cài SQL on Windows: tạo network, 2 container chạy 2 image dbatools cung cấp sẵn, share volume `shared` để dùng cho migration chapter sau.
- **Đổi cho lab:** Nếu đang dùng devcontainer của repo, **bỏ qua block này** — devcontainer đã có sẵn 1 SQL instance. Block này chỉ hữu ích khi bạn muốn dựng 2 instance Linux song song bên ngoài VS Code Dev Containers.
- **Lưu ý:** Trên Windows, bỏ flag `:z` (đó là SELinux label chỉ áp dụng Linux). Username/password mặc định: `sqladmin / dbatools.IO`.

### Đoạn 9: dòng 80
```powershell
docker ps
```
- **Ý nghĩa:** Liệt kê các container đang chạy để verify 2 container `mssql1` và `mssql2` đã up.

### Đoạn 10: dòng 84-88
```powershell
Connect-DbaInstance -SqlInstance localhost -SqlCredential sqladmin

# Connect to SQL Server in a container listening on non standard port
$cred = Get-Credential sqladmin
Connect-DbaInstance -SqlInstance localhost:14333 -SqlCredential $cred
```
- **Ý nghĩa:** Kết nối vào 2 container — một qua port mặc định 1433, một qua port 14333.
- **Đổi cho lab:** Nếu chạy trong devcontainer, dùng tên service trong compose (`dbatoolslab`) hoặc `localhost`.

### Đoạn 11: dòng 92-93
```powershell
New-DbaClientAlias -ServerName localhost -Alias mssql1
Connect-DbaInstance -SqlInstance mssql1 -SqlCredential sqladmin
```
- **Ý nghĩa:** Đặt **alias client** (lưu trong registry trên Windows) để gõ `mssql1` thay vì `localhost`. Hữu ích khi code book hardcode tên `mssql1`/`mssql2` mà bạn không muốn sửa.
- **Side-effect:** Ghi registry. Có thể xoá bằng `Remove-DbaClientAlias`.
- **Lưu ý:** `New-DbaClientAlias` **chỉ chạy trên Windows** (cần SQL Server Native Client). Trên Linux thiết lập alias qua `/etc/hosts` hoặc DNS thay thế.

## Lệnh thay vào lab của bạn

```powershell
# Phiên bản đã đổi instance name cho lab dbatoolslab + dbatoolslab\sql2017
# CHÚ Ý: Hầu hết các bước này đã được tự động hoá trong scripts/01_Install_Lab.ps1 và
# scripts/02_Configure_Lab.ps1. Nếu đã chạy 2 script đó, bạn chỉ cần verify, không cần chạy lại.

# 1) Verify hai instance đã chạy
Connect-DbaInstance -SqlInstance dbatoolslab            | Select-Object Name, Product, Version
Connect-DbaInstance -SqlInstance dbatoolslab\sql2017    | Select-Object Name, Product, Version
Find-DbaInstance -ComputerName dbatoolslab

# 2) Verify sample DB đã restore
Get-DbaDatabase -SqlInstance dbatoolslab\sql2017 -Database WideWorldImporters, AdventureWorks2017 |
    Select-Object Name, Status, RecoveryModel, LastFullBackup

# 3) Verify login + role
Get-DbaLogin    -SqlInstance dbatoolslab\sql2017 -Login WWI_ReadOnly, WWI_ReadWrite, WWI_Owner |
    Select-Object Name, LoginType, IsDisabled
Get-DbaDbRoleMember -SqlInstance dbatoolslab\sql2017 -Database WideWorldImporters |
    Where-Object UserName -like 'WWI_*' |
    Select-Object UserName, Role

# 4) Verify Agent job
Get-DbaAgentJob -SqlInstance dbatoolslab\sql2017 -Job 'dbatools lab job', 'dbatools lab - where am I' |
    Select-Object Name, Enabled, LastRunOutcome

# 5) Nếu thật sự muốn chạy lại setup, hãy dùng -WhatIf trước
Restore-DbaDatabase -SqlInstance dbatoolslab\sql2017 -Path C:\dbatoolslab\Backup\WideWorldImporters-Full.bak -WhatIf
```

## Self-check (3 câu)
1. **Định nghĩa:** Khác biệt giữa `New-DbaLogin` và `New-DbaDbUser` là gì? Vì sao phải tạo cả hai cho `WWI_ReadOnly`?
2. **Thực hành:** Chạy `Get-DbaSpConfigure -SqlInstance dbatoolslab\sql2017 -Name CostThresholdForParallelism`. Giá trị `ConfiguredValue` và `RunningValue` khác nhau khi nào?
3. **Liên hệ:** Chapter này dùng `Restore-DbaDatabase`. Chapter 11 sẽ học `Backup-DbaDatabase`. Liệt kê ít nhất 2 tham số mà 2 cmdlet này có cùng tên, làm cùng nhiệm vụ?

## Bài tập mở rộng
- **Bài 1 (~5 phút):** Tạo 1 login thứ tư `WWI_Reporter` (chỉ đọc, nhưng chỉ vào schema `Sales`). Hint: `New-DbaLogin` → `New-DbaDbUser` → `Add-DbaDbRoleMember` với role custom (tạo role custom bằng `New-DbaDbRole`).
- **Bài 2 (sâu hơn):** Viết script `Test-LabConfigured.ps1` trả về danh sách object `{ Check, Expected, Actual, Pass }` cho 5 kiểm tra: cả 2 instance ping được, cả 2 DB restored, 3 login tồn tại, 2 Agent job tồn tại, `CostThresholdForParallelism` = 10. Đây là khởi đầu cho Pester test ở `tests/`.


---

!!! info "Nguồn gốc"
    `book_lab/dbatools-lab/bookcode/chapter03.notes.md`
