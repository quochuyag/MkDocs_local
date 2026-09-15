---
title: Chapter 15 — Migration database với Start-DbaMigration và Copy-DbaDatabase
course: 11-book-lab
source: book_lab/dbatools-lab/bookcode/chapter15.notes.md
---

# Chapter 15 — Migration database với Start-DbaMigration và Copy-DbaDatabase

## Mục tiêu
- Hiểu hai chiến lược chuyển database giữa hai instance: **Backup-Restore** và **Detach-Attach**, ưu/nhược của mỗi cái.
- Sử dụng `Start-DbaMigration` để migrate "tất cả mọi thứ" trong một lệnh.
- Dùng `Copy-DbaDatabase` để chuyển có chọn lọc một hoặc nhiều database.
- Biết cách giảm downtime bằng `-NoRecovery` + differential backup tail-log cutover.
- Biết bước chuẩn bị (test object tạo mới, `New-DbaDbTable`) và bước cutover bằng log shipping (`Invoke-DbaDbLogShipping` + `Invoke-DbaDbLogShipRecovery`).

## Tóm tắt 3-5 ý chính
1. **`Start-DbaMigration` = "do everything"** — chuyển database, logins, jobs, linked servers, audits, custom errors, sp_configure... từ source sang destination. Tham số tối thiểu: Source, Destination, BackupRestore + SharedPath.
2. **`Copy-DbaDatabase` chuyên chuyển database** — chọn mode Backup-Restore (qua share, không downtime source) hoặc Detach-Attach (nhanh hơn nhưng source phải offline).
3. **Backup-Restore an toàn hơn** — source vẫn online, chỉ cần share network. Detach-Attach bắt source offline → downtime ngay từ lúc bắt đầu.
4. **`-NoRecovery` + differential = cutover ngắn** — restore full với `NoRecovery`, sau đó set source offline rồi apply differential `Continue`. Downtime chỉ bằng thời gian diff backup + restore.
5. **Log shipping là cutover "lazy"** — đẩy log liên tục từ source, đến cửa sổ cutover thì `Invoke-DbaDbLogShipRecovery` đưa target online. Downtime cực ngắn.

## Giải thích từng đoạn code

### Đoạn 1: dòng 18 — Migration tất cả trong một lệnh
```powershell
Start-DbaMigration -Source sql01 -Destination sql02 -BackupRestore -SharedPath \\nas\sql\migration
```
- **Ý nghĩa:** Chuyển **toàn bộ** databases, logins, jobs, alerts, operators, custom errors, sp_configure, audits, linked servers, credentials, server roles... từ `sql01` sang `sql02`. `SharedPath` là share mà cả hai instance đọc/ghi được, dùng làm staging cho backup file.
- **Đổi cho lab:** `Source = "dbatoolslab\sql2017"` (đã có data), `Destination = "dbatoolslab"` (empty), `SharedPath = "C:\dbatoolslab\Backup"` (nếu cùng host thì path local cũng đủ).
- **Lưu ý:** **CẢNH BÁO RẤT NGHIÊM TRỌNG** — đây là lệnh "súng đại bác". Một lần chạy có thể tạo hàng chục object trên target. **Bắt buộc `-WhatIf` trước**, **backup target trước**, và chạy ngoài giờ. Trên môi trường production, chia thành nhiều `Copy-Dba*` riêng lẻ để kiểm soát.

### Đoạn 2: dòng 22-29 — Copy một database qua backup-restore
```powershell
$copySplat = @{
    Source        = "sql01"
    Destination   = "sql02"
    Database      = "WideWorldImporters"
    SharedPath    = "\\nas\sql\migration"
    BackupRestore = $true
}
Copy-DbaDatabase @copySplat
```
- **Ý nghĩa:** Backup `WideWorldImporters` ra share, restore vào target. Source vẫn online. Đây là pattern khuyến nghị cho hầu hết migration.
- **Đổi cho lab:** `Source = "dbatoolslab\sql2017"`, `Destination = "dbatoolslab"`, `SharedPath = "C:\dbatoolslab\Backup"`.
- **Lưu ý:** **CẢNH BÁO** — nếu target đã có DB cùng tên, lệnh sẽ lỗi (mặc định). Cần `-Force` để overwrite (cẩn thận!). Backup target DB trước nếu cần.

### Đoạn 3: dòng 33-40 — Copy tất cả database
```powershell
$copySplat = @{
    Source        = "sql01"
    Destination   = "sql02"
    AllDatabases  = $true
    SharedPath    = "\\nas\sql\migration"
    BackupRestore = $true
}
Copy-DbaDatabase @copySplat
```
- **Ý nghĩa:** `-AllDatabases` thay vì `-Database`. Chuyển toàn bộ user databases (không gồm system).
- **Đổi cho lab:** Tương tự đoạn 2 nhưng `-AllDatabases`.
- **Lưu ý:** **CẢNH BÁO** — có thể mất giờ tuỳ kích thước. Disk share phải đủ chỗ chứa tất cả backup tạm. Test trên một DB trước.

### Đoạn 4: dòng 44-52 — Backup-restore và đưa source offline
```powershell
$copySplat = @{
    Source           = "sql01"
    Destination      = "sql02"
    Database         = "WideWorldImporters"
    SharedPath       = "\\nas\sql\migration"
    BackupRestore    = $true
    SetSourceOffline = $true
}
Copy-DbaDatabase @copySplat
```
- **Ý nghĩa:** Sau khi copy xong, set source DB offline. Đảm bảo không ai ghi tiếp vào source nhầm — pattern cutover thẳng.
- **Đổi cho lab:** Thay tên instance như trên.
- **Lưu ý:** **CẢNH BÁO** — `-SetSourceOffline` là điểm "không quay lại" cho applications dùng source. Phải coordinate cutover window.

### Đoạn 5: dòng 56-62 — Detach-Attach mode
```powershell
$copySplat = @{
    Source       = "sql01"
    Destination  = "sql02"
    Database     = "WideWorldImporters"
    DetachAttach = $true
}
Copy-DbaDatabase @copySplat
```
- **Ý nghĩa:** Detach DB ở source, copy file `.mdf`/`.ldf` đến target qua admin share, attach vào target. Nhanh hơn backup-restore (không nén/giải nén) nhưng source phải offline.
- **Đổi cho lab:** Lab cùng host nên Detach-Attach có thể không khả thi qua container — Backup-Restore là chuẩn cho lab.
- **Lưu ý:** **CẢNH BÁO** — sau detach, nếu copy fail, source DB tạm thời "biến mất" khỏi SQL (file vẫn còn). dbatools cố attach lại nhưng vẫn có rủi ro.

### Đoạn 6: dòng 66-73 — Detach-Attach kèm Reattach source
```powershell
$copySplat = @{
    Source       = "sql01"
    Destination  = "sql02"
    Database     = "WideWorldImporters"
    DetachAttach = $true
    Reattach     = $true
}
Copy-DbaDatabase @copySplat
```
- **Ý nghĩa:** `-Reattach` tự attach lại DB ở source sau khi copy xong. Phù hợp khi muốn migration nhưng vẫn giữ source làm backup tạm.
- **Đổi cho lab:** Như đoạn 5.
- **Lưu ý:** Hai DB cùng tên ở hai instance — đảm bảo app trỏ đúng instance, tránh nhầm "split-brain" (đọc/ghi cả hai).

### Đoạn 7: dòng 77-86 — Backup-restore với NoRecovery (chuẩn bị cutover differential)
```powershell
$copySplat = @{
    Source        = "sql01"
    Destination   = "sql02"
    Database      = "WideWorldImporters"
    SharedPath    = "\\nas\sql\migration"
    BackupRestore = $true
    NoRecovery    = $true
    NoCopyOnly    = $true
}
Copy-DbaDatabase @copySplat
```
- **Ý nghĩa:** Restore với `NoRecovery` → DB target ở trạng thái `RESTORING`, sẵn sàng nhận differential/log. `NoCopyOnly = $true` nghĩa là backup này KHÔNG copy-only, sẽ reset diff base — quan trọng cho chain backup tiếp theo.
- **Đổi cho lab:** Tương tự, nhưng test cẩn thận vì DB target sẽ ở trạng thái RESTORING (không truy vấn được cho đến khi recover).
- **Lưu ý:** **CẢNH BÁO** — `NoCopyOnly` đụng vào diff base chain của production backup strategy. Cần coordinate với backup team.

### Đoạn 8: dòng 90-114 — Cutover bằng differential
```powershell
$diffSplat = @{
    SqlInstance = "sql01"
    Database    = "WideWorldImporters"
    Path        = "\\nas\sql\migration"
    Type        = "Differential"
}
$diff = Backup-DbaDatabase @diffSplat

# Set the source database offline
$offlineSplat = @{
    SqlInstance = "sql01"
    Database    = "WideWorldImporters"
    Offline     = $true
    Force       = $true
}
Set-DbaDbState @offlineSplat

# restore the differential and bring the destination online
$restoreSplat = @{
    SqlInstance = "sql02"
    Database    = "WideWorldImporters"
    Path        = $diff.Path
    Continue    = $true
}
Restore-DbaDatabase @restoreSplat
```
- **Ý nghĩa:** Workflow cutover 3 bước: (1) Backup diff từ source, (2) Đưa source offline để chốt, (3) Restore diff lên target với `-Continue` → DB online luôn.
- **Đổi cho lab:** `SqlInstance` source = `dbatoolslab\sql2017`, target = `dbatoolslab`. `Path = "C:\dbatoolslab\Backup"`.
- **Lưu ý:** **CẢNH BÁO MẠNH** — `-Force` ép kick user khỏi source. Đảm bảo cutover window đã được approve. Sau `Restore-DbaDatabase`, target sẽ online; nếu hỏng, source vẫn offline → cần plan rollback.

### Đoạn 9: dòng 118-129 — Tạo table test trên source
```powershell
$tableSplat = @{
    SqlInstance = "sql01"
    Database    = "WideWorldImporters"
    Name        = "MigrationTestTable"
    ColumnMap   = @{
        Name      = "test"
        Type      = "varchar"
        MaxLength = 20
        Nullable  = $true
    }
}
New-DbaDbTable @tableSplat
```
- **Ý nghĩa:** Tạo một table mới trên source để chứng minh chain restore đang hoạt động. Sau khi backup diff + restore, table này phải xuất hiện ở target.
- **Đổi cho lab:** `SqlInstance = "dbatoolslab\sql2017"`.
- **Lưu ý:** Đây là bước verify migration thành công. Trong production thay bằng "kiểm tra row count" hoặc "kiểm tra max(updated_at) của bảng cốt lõi".

### Đoạn 10: dòng 133-142 — Log shipping cutover
```powershell
$params = @{
    Source      = "mssql1"
    Destination = "mssql2"
    Database    = "Northwind"
    SharedPath  = "\\nas\sql\shipping"
}
Invoke-DbaDbLogShipping @params

# Then cutover
Invoke-DbaDbLogShipRecovery -SqlInstance mssql2 -Database Northwind
```
- **Ý nghĩa:** Thiết lập log shipping (full backup ban đầu + log backup định kỳ → ship → restore). Khi tới cutover, `Invoke-DbaDbLogShipRecovery` đưa target online.
- **Đổi cho lab:** `Source = "dbatoolslab\sql2017"`, `Destination = "dbatoolslab"`, `Database = "WideWorldImporters"`, `SharedPath = "C:\dbatoolslab\logship"`. Chapter 17 sẽ đi sâu vào log shipping.
- **Lưu ý:** Log shipping yêu cầu Agent chạy được trên cả hai instance, share path đọc/ghi từ cả hai service account.

## Lệnh thay vào lab của bạn

```powershell
# Migration trong lab: source = dbatoolslab\sql2017 (có data), target = dbatoolslab (empty)
$source = "dbatoolslab\sql2017"
$target = "dbatoolslab"
$share  = "C:\dbatoolslab\Backup"

# 1) BẮT BUỘC: chạy WhatIf trước cho Start-DbaMigration
$splat = @{
    Source        = $source
    Destination   = $target
    BackupRestore = $true
    SharedPath    = $share
    WhatIf        = $true
}
Start-DbaMigration @splat

# 2) Khi tự tin, chạy thật MỘT database trước
$copySplat = @{
    Source        = $source
    Destination   = $target
    Database      = "WideWorldImporters"
    SharedPath    = $share
    BackupRestore = $true
}
Copy-DbaDatabase @copySplat

# 3) Kiểm tra DB target đã online
Get-DbaDatabase -SqlInstance $target -Database "WideWorldImporters" |
    Select-Object Name, Status, RecoveryModel, SizeMB

# 4) Demo cutover differential (chỉ làm khi đã quen)
#    Bước 4a: copy với NoRecovery
$copySplat.NoRecovery = $true
$copySplat.NoCopyOnly = $true
$copySplat.Database = "AdventureWorks2017"
$copySplat.Force = $true   # vì target có thể đã có DB
Copy-DbaDatabase @copySplat

#    Bước 4b: backup diff source
$diff = Backup-DbaDatabase -SqlInstance $source -Database "AdventureWorks2017" `
    -Path $share -Type Differential

#    Bước 4c: set source offline
Set-DbaDbState -SqlInstance $source -Database "AdventureWorks2017" -Offline -Force

#    Bước 4d: restore diff với Continue
Restore-DbaDatabase -SqlInstance $target -Database "AdventureWorks2017" `
    -Path $diff.Path -Continue
```

## Self-check
1. **Định nghĩa:** Khác biệt giữa `BackupRestore` mode và `DetachAttach` mode của `Copy-DbaDatabase`? Khi nào ưu tiên cái nào?
2. **Thực hành:** Viết `Copy-DbaDatabase` chuyển `WideWorldImporters` từ `dbatoolslab\sql2017` sang `dbatoolslab` với `-WhatIf`. Đọc output và liệt kê các bước dbatools dự định thực hiện.
3. **Liên hệ:** Trong cutover differential, vì sao phải set source offline **trước khi** restore diff lên target? Điều gì xảy ra nếu bỏ qua bước đó?

## Bài tập mở rộng
- **Bài 1:** Thử migration `WideWorldImporters` bằng backup-restore. Sau khi xong, dùng `Get-DbaDatabase` xác nhận row count của bảng `Sales.Orders` ở hai instance bằng nhau (`Get-DbaDbRowCount` hoặc query trực tiếp).
- **Bài 2:** Tạo bảng mới `MigrationTestTable` ở source sau khi migrate (kiểu đoạn 9), sau đó backup log + restore log lên target để chứng minh chain log hoạt động. Quan sát table có xuất hiện ở target không.


---

!!! info "Nguồn gốc"
    `book_lab/dbatools-lab/bookcode/chapter15.notes.md`
