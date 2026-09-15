---
title: Chapter 05 — Xuất / nhập dữ liệu bảng & CSV với dbatools
course: 11-book-lab
source: book_lab/dbatools-lab/bookcode/chapter05.notes.md
---

# Chapter 05 — Xuất / nhập dữ liệu bảng & CSV với dbatools

> Tham chiếu code gốc: [chapter05.ps1](chapter05.ps1)

## Mục tiêu
- Xuất kết quả `Get-DbaDatabase` ra **clipboard** và **CSV** (`clip`, `Export-Csv`).
- Nhập CSV vào SQL bằng 2 cmdlet **`Import-DbaCsv`** (BCP nhanh, file-based) và **`Write-DbaDataTable`** (object pipeline, flexible hơn).
- Hiểu khi nào dùng `-AutoCreateTable` và rủi ro của nó.
- Truy vấn lại dữ liệu vừa import bằng `Invoke-DbaQuery` và `Get-DbaDbTable`.
- So sánh **type information** giữa CSV (`Get-Member` cho thấy toàn string) và object dbatools (kiểu mạnh — int, long, datetime).
- Copy bảng giữa 2 instance bằng `Copy-DbaDbTableData`.

## Tóm tắt 5 ý chính
1. **Pipeline xuất:** `Get-DbaDatabase | Select | Export-Csv` là pattern reporting căn bản. Output property của dbatools rất "PowerShell-friendly" — Format/Select/Sort hoạt động tự nhiên.
2. **`Import-DbaCsv` ≠ `Write-DbaDataTable`:** 
   - `Import-DbaCsv` đọc file CSV qua **SqlBulkCopy** — nhanh, ít memory, nhưng cứng (toàn string).
   - `Write-DbaDataTable` nhận **mọi object pipeline** — flexible (datetime, decimal, nested), nhưng load vào memory.
3. **`-AutoCreateTable`** tự sinh `CREATE TABLE` từ schema input. Tiện cho prototype nhưng **kiểu thường rộng quá** (`NVARCHAR(MAX)` mặc định) → đừng dùng cho production table.
4. **`Get-DbaDbTable` + `.Columns`** là cách kiểm tra schema thực tế sau khi import — luôn verify type trước khi build report.
5. **`Copy-DbaDbTableData`** = SqlBulkCopy giữa 2 instance, không qua file trung gian. Hỗ trợ schema mapping nguồn/đích khác nhau qua splat.

## Giải thích từng đoạn code

### Đoạn 1: dòng 18
```powershell
Get-DbaDatabase -SqlInstance SQLDEV01 -ExcludeSystem
```
- **Ý nghĩa:** Liệt kê user database (loại trừ `master`, `model`, `msdb`, `tempdb`).
- **Đổi cho lab:** `Get-DbaDatabase -SqlInstance dbatoolslab\sql2017 -ExcludeSystem`.

### Đoạn 2: dòng 23-24
```powershell
Get-DbaDatabase -SqlInstance SQLDEV01 -ExcludeSystem |
        Select Name, Size, LastFullBackup
```
- **Ý nghĩa:** Chỉ giữ 3 property thường dùng nhất khi báo cáo. Output sạch hơn, dễ đọc.
- **Đổi cho lab:** `Get-DbaDatabase -SqlInstance dbatoolslab\sql2017 -ExcludeSystem | Select Name, Size, LastFullBackup`.

### Đoạn 3: dòng 29-30
```powershell
Get-DbaDatabase -SqlInstance SQLDEV01 -ExcludeSystem |
Select Name, Size, LastFullBackup | clip
```
- **Ý nghĩa:** Đẩy kết quả **vào clipboard** (`clip` chỉ có trên Windows). Sau đó paste sang Excel/email.
- **Đổi cho lab:** Trên Linux/devcontainer thay `clip` bằng `Set-Clipboard` (nếu có), hoặc đơn giản pipe vào `Out-File`.

### Đoạn 4: dòng 34-38
```powershell
Get-DbaDatabase -SqlInstance SQLDEV01 -ExcludeSystem |
Select Name, Size, LastFullBackup |
Export-Csv -Path Databaseinfo.csv -NoTypeInformation

Get-Content DatabaseInfo.csv
```
- **Ý nghĩa:** Lưu kết quả ra CSV (không có dòng `#TYPE` header dư thừa), sau đó `Get-Content` để check file.
- **Đổi cho lab:** `Get-DbaDatabase -SqlInstance dbatoolslab\sql2017 -ExcludeSystem | Select Name, Size, LastFullBackup | Export-Csv .\Databaseinfo.csv -NoTypeInformation`.
- **Lưu ý:** PowerShell 7 có `-UseQuotes AsNeeded` để CSV ngắn hơn.

### Đoạn 5: dòng 42-43
```powershell
Get-ChildItem -Path E:\csvs\top.csv |
Import-DbaCsv -SqlInstance SQLDEV01 -Database tempdb -Table top
```
- **Ý nghĩa:** Pipe `FileInfo` (từ `Get-ChildItem`) vào `Import-DbaCsv`. dbatools đọc `.FullName` của FileInfo tự động.
- **Đổi cho lab:** `Get-ChildItem .\Databaseinfo.csv | Import-DbaCsv -SqlInstance dbatoolslab\sql2017 -Database tempdb -Table dbinfo`.
- **Side-effect:** **Ghi data vào tempdb.** Bảng `top` phải **tồn tại trước** (đoạn này không có `-AutoCreateTable`). Chạy `-WhatIf` trước.

### Đoạn 6: dòng 48-49
```powershell
Get-ChildItem E:\csv\top*.csv |
Import-DbaCsv -SqlInstance SQLDEV01 -Database tempdb -AutoCreateTable
```
- **Ý nghĩa:** Wildcard `top*.csv` → mỗi file thành 1 bảng. `-AutoCreateTable` tự tạo bảng từ header CSV (cột = string nvarchar(max)).
- **Side-effect:** **Tạo bảng + ghi data.** Tên bảng = tên file (không có `.csv`). `-WhatIf` để xem mapping trước.

### Đoạn 7: dòng 54-55
```powershell
Import-Csv -Path E:\csv\top-tracks.csv |
Select Rank, Plays, Artist, Title
```
- **Ý nghĩa:** Demo đọc CSV thuần PowerShell (không vào SQL) — show property kiểu object. Mọi cột đều là `[string]`.

### Đoạn 8: dòng 60-61
```powershell
Import-Csv -Path .\Databaseinfo.csv |
Write-DbaDataTable -SqlInstance SQLDEV01 -Database tempdb -Table Databases -AutoCreateTable
```
- **Ý nghĩa:** Đọc CSV → object PowerShell → ghi vào SQL qua `Write-DbaDataTable`. Khác `Import-DbaCsv` ở chỗ chấp nhận **mọi object**, không chỉ file.
- **Đổi cho lab:** `Import-Csv .\Databaseinfo.csv | Write-DbaDataTable -SqlInstance dbatoolslab\sql2017 -Database tempdb -Table Databases -AutoCreateTable`.
- **Side-effect:** **Tạo bảng + ghi data**. `-WhatIf` trước. Bảng sẽ toàn cột `nvarchar` vì input đến từ `Import-Csv` (string).

### Đoạn 9: dòng 65-66
```powershell
$csv = Import-Csv \\server\bigdataset.csv
Write-DbaDataTable -SqlInstance sql2014 -InputObject $csv -Database mydb
```
- **Ý nghĩa:** Truyền dữ liệu qua **`-InputObject`** (không qua pipeline). Hữu ích khi cần tái sử dụng `$csv` nhiều lần.
- **Đổi cho lab:** `Write-DbaDataTable -SqlInstance dbatoolslab\sql2017 -InputObject $csv -Database tempdb -Table Databases`.

### Đoạn 10: dòng 70-71
```powershell
$query = "Select * from Databases"
Invoke-DbaQuery -SqlInstance SQLDEV01 -Database tempdb -Query $query
```
- **Ý nghĩa:** Verify dữ liệu vừa import bằng `SELECT *`. Output là PSCustomObject — column = property.
- **Đổi cho lab:** `Invoke-DbaQuery -SqlInstance dbatoolslab\sql2017 -Database tempdb -Query "select * from Databases"`.

### Đoạn 11: dòng 75
```powershell
Remove-DbaDbTable SqlInstance SQL01 -Database tempdb -Table databases
```
- **Ý nghĩa:** **Xoá bảng** — cleanup giữa các lần demo.
- **Bug code gốc:** Thiếu dấu `-` trước `SqlInstance`. Cú pháp đúng:
  ```powershell
  Remove-DbaDbTable -SqlInstance SQL01 -Database tempdb -Table databases
  ```
- **Đổi cho lab:** `Remove-DbaDbTable -SqlInstance dbatoolslab\sql2017 -Database tempdb -Table Databases -Confirm:$false`.
- **Side-effect:** **DESTRUCTIVE.** **Bắt buộc `-WhatIf` lần đầu**:
  ```powershell
  Remove-DbaDbTable -SqlInstance dbatoolslab\sql2017 -Database tempdb -Table Databases -WhatIf
  ```

### Đoạn 12: dòng 79-81
```powershell
Get-DbaDatabase -SqlInstance SQLDEV01 -ExcludeSystem |
Select Name, Size, LastFullBackUp |
Write-DbaDataTable -SqlInstance SQLDEV01 -Database tempdb -Table Databases -AutoCreateTable
```
- **Ý nghĩa:** **Bypass CSV hoàn toàn** — pipe trực tiếp object dbatools vào `Write-DbaDataTable`. Lúc này column **giữ đúng kiểu** (datetime cho `LastFullBackup`, decimal cho `Size`).
- **Đổi cho lab:** `Get-DbaDatabase -SqlInstance dbatoolslab\sql2017 -ExcludeSystem | Select Name, Size, LastFullBackup | Write-DbaDataTable -SqlInstance dbatoolslab\sql2017 -Database tempdb -Table Databases -AutoCreateTable`.
- **Side-effect:** Ghi data vào tempdb. `-WhatIf` trước.

### Đoạn 13: dòng 85-86
```powershell
$query = "Select * from Databases"
Invoke-DbaQuery -SqlInstance SQLDEV01 -Query $query -Database tempdb
```
- **Ý nghĩa:** Verify lần 2. So sánh với đoạn 10 — nội dung số liệu giống, nhưng schema bảng giờ có kiểu chính xác hơn (xem đoạn 14).

### Đoạn 14: dòng 90-91
```powershell
(Get-DbaDbTable -SqlInstance SQLDEV01 -Database tempdb -Table Databases).Columns |
Select-Object Parent, Name, Datatype
```
- **Ý nghĩa:** **Xem schema bảng** sau import. Đây là cách kiểm chứng `-AutoCreateTable` đã sinh kiểu gì.
- **Đổi cho lab:** `(Get-DbaDbTable -SqlInstance dbatoolslab\sql2017 -Database tempdb -Table Databases).Columns | Select Parent, Name, Datatype`.

### Đoạn 15: dòng 96-98
```powershell
Import-Csv -Path .\Databaseinfo.csv | Get-Member
Get-DbaDatabase -SqlInstance SQLDEV01 -ExcludeSystem |
Select Name, Size, LastFullBackup | Get-Member
```
- **Ý nghĩa:** So sánh **TypeName** của 2 nguồn:
  - `Import-Csv` → `PSCustomObject` với mọi property là `[string]`.
  - `Get-DbaDatabase | Select` → `PSCustomObject` với property kiểu mạnh (datetime, decimal).
- **Bài học:** Type ở nguồn quyết định type ở bảng SQL đích.

### Đoạn 16: dòng 102-103
```powershell
Import-Csv -Path .\Databaseinfo.csv |
Write-DbaDataTable -SqlInstance SQLDEV01 -Database tempdb -Table Databases
```
- **Ý nghĩa:** Lần này **không có `-AutoCreateTable`** — yêu cầu bảng `Databases` đã tồn tại với schema khớp.
- **Side-effect:** Ghi data. Sẽ lỗi nếu bảng chưa có hoặc schema lệch.

### Đoạn 17: dòng 107-109
```powershell
Import-Csv -Path .\Databaseinfo.csv |
Write-DbaDataTable -SqlInstance SQLDEV01 -Database tempdb -Table Databases
Invoke-DbaQuery -SqlInstance SQLDEV01 -Query "select * from Databases" -Database tempdb
```
- **Ý nghĩa:** Import rồi verify ngay. Pattern "load + read" chuẩn.

### Đoạn 18: dòng 114-115
```powershell
Get-Process | Select -Last 10 |
Write-DbaDataTable -SqlInstance SQLDEV01 -Database tempdb -Table processes -AutoCreateTable
```
- **Ý nghĩa:** Demo thú vị — bất kỳ output PowerShell nào cũng đổ vào SQL được. Ở đây là 10 process gần nhất.
- **Đổi cho lab:** `Get-Process | Select -Last 10 | Write-DbaDataTable -SqlInstance dbatoolslab\sql2017 -Database tempdb -Table processes -AutoCreateTable`.
- **Bài học:** Mọi monitoring / inventory script có thể đẩy thẳng kết quả vào DB để build report sau.

### Đoạn 19: dòng 119
```powershell
(Get-DbaDbTable -SqlInstance SQLDEV01 -Database tempdb -Table processes).Columns | Select-Object Parent, Name, Datatype
```
- **Ý nghĩa:** Kiểm tra schema bảng `processes` vừa auto-create.

### Đoạn 20: dòng 124
```powershell
Connect-AzAccount
```
- **Ý nghĩa:** Đăng nhập Azure (mở popup browser hoặc device code).
- **Lưu ý lab:** Không bắt buộc cho lab cơ bản. Skip nếu không có Azure subscription.

### Đoạn 21: dòng 129
```powershell
Get-AzVM -Status | Write-DbaDataTable -SqlInstance SQLDEV01 -Database tempdb -Table AzureVMs -AutoCreateTable
```
- **Ý nghĩa:** Đổ inventory Azure VM sang SQL — minh hoạ "PowerShell pipeline = ETL nhẹ".
- **Đổi cho lab:** Skip nếu không có Azure.

### Đoạn 22: dòng 133-138
```powershell
$query = "SELECT [Name]
        ,[Location]
        ,[PowerState]
        ,[StatusCode]
        FROM [AzureVMs]"
Invoke-DbaQuery -SqlInstance SQLDEV01 -Query $query -Database tempdb
```
- **Ý nghĩa:** Query lại bảng `AzureVMs` vừa tạo từ đoạn 21.

### Đoạn 23: dòng 143-163
```powershell
$copyDbaDbTableDataSplat = @{
    SqlInstance = "SQLDEV01"
    Database = "WideWorldImporters"
    Table = '[Purchasing].[PurchaseOrders]'
    Destination = "SQLDEV02,15591"
    DestinationDatabase = 'WIP'
    DestinationTable = 'dbo.PurchaseOrders'
    AutoCreateTable = $true
}
Copy-DbaDbTableData @copyDbaDbTableDataSplat
```
- **Ý nghĩa:** **Copy bảng** giữa 2 instance khác nhau (kể cả khác schema/tên bảng/port). Dùng SqlBulkCopy bên dưới — nhanh.
- **Đổi cho lab:** Lab chỉ có 1 instance chính `dbatoolslab\sql2017`. Có thể demo copy cùng instance, khác database:
  ```powershell
  $copyArgs = @{
      SqlInstance         = "dbatoolslab\sql2017"
      Database            = "WideWorldImporters"
      Table               = "[Purchasing].[PurchaseOrders]"
      Destination         = "dbatoolslab\sql2017"
      DestinationDatabase = "tempdb"
      DestinationTable    = "dbo.PurchaseOrders_copy"
      AutoCreateTable     = $true
  }
  Copy-DbaDbTableData @copyArgs -WhatIf   # luôn -WhatIf trước
  ```
- **Side-effect:** **Ghi data + tạo bảng đích.** `-WhatIf` bắt buộc.

## Lệnh thay vào lab của bạn

```powershell
# Phiên bản đã đổi instance name cho lab dbatoolslab\sql2017

$srv = "dbatoolslab\sql2017"

# 1) Xuất danh sách DB ra CSV
Get-DbaDatabase -SqlInstance $srv -ExcludeSystem |
    Select-Object Name, Size, LastFullBackup |
    Export-Csv -Path .\Databaseinfo.csv -NoTypeInformation

# 2) Import CSV → bảng SQL (Import-DbaCsv — nhanh, file-based)
Get-ChildItem .\Databaseinfo.csv |
    Import-DbaCsv -SqlInstance $srv -Database tempdb -Table dbinfo -AutoCreateTable -WhatIf

# 3) Pipe object → bảng SQL (Write-DbaDataTable — type-preserving)
Get-DbaDatabase -SqlInstance $srv -ExcludeSystem |
    Select-Object Name, Size, LastFullBackup |
    Write-DbaDataTable -SqlInstance $srv -Database tempdb -Table Databases -AutoCreateTable -WhatIf

# 4) Kiểm tra schema bảng vừa tạo
(Get-DbaDbTable -SqlInstance $srv -Database tempdb -Table Databases).Columns |
    Select-Object Parent, Name, DataType

# 5) Đọc lại
Invoke-DbaQuery -SqlInstance $srv -Database tempdb -Query "SELECT TOP 5 * FROM Databases"

# 6) Cleanup (DESTRUCTIVE — luôn -WhatIf trước)
Remove-DbaDbTable -SqlInstance $srv -Database tempdb -Table Databases, dbinfo -WhatIf
# Khi đã chắc chắn:
# Remove-DbaDbTable -SqlInstance $srv -Database tempdb -Table Databases, dbinfo -Confirm:$false

# 7) Copy bảng (cùng instance, khác DB) — demo Copy-DbaDbTableData
$copyArgs = @{
    SqlInstance         = $srv
    Database            = "WideWorldImporters"
    Table               = "[Purchasing].[PurchaseOrders]"
    Destination         = $srv
    DestinationDatabase = "tempdb"
    DestinationTable    = "dbo.PurchaseOrders_copy"
    AutoCreateTable     = $true
}
Copy-DbaDbTableData @copyArgs -WhatIf
```

## Self-check (3 câu)
1. **Định nghĩa:** `Import-DbaCsv` và `Write-DbaDataTable` đều ghi vào bảng SQL — khác nhau ở **input type** và **performance** thế nào?
2. **Thực hành:** Chạy `Import-Csv .\Databaseinfo.csv | Get-Member` rồi chạy `Get-DbaDatabase -SqlInstance dbatoolslab\sql2017 | Select Name, Size, LastFullBackup | Get-Member`. So sánh **TypeName** của property `LastFullBackup` ở 2 lần — vì sao khác?
3. **Liên hệ:** Chapter 04 dạy `Invoke-DbaQuery -SqlInstance $server` (truyền SMO object). Chapter này dùng `Invoke-DbaQuery -SqlInstance "..."` (truyền string). Cả 2 cách đều chạy được — lợi/hại từng cách là gì?

## Bài tập mở rộng
- **Bài 1 (~5 phút):** Tạo bảng `tempdb.dbo.HostInfo` chứa kết quả `Get-DbaComputerSystem -ComputerName dbatoolslab` qua pipeline + `Write-DbaDataTable -AutoCreateTable`. Sau đó verify schema bằng `Get-DbaDbTable`.
- **Bài 2 (sâu hơn):** Viết script `Export-DbInventory.ps1` nhận `-SqlInstance` và `-DestinationCsvFolder`, xuất 4 CSV: `databases.csv`, `tables.csv`, `users.csv`, `agentjobs.csv`. Mỗi file là output của 1 cmdlet (`Get-DbaDatabase`, `Get-DbaDbTable`, `Get-DbaDbUser`, `Get-DbaAgentJob`). Bonus: thêm tham số `-AlsoToSql` đẩy luôn vào bảng `Inventory.dbo.*`.


---

!!! info "Nguồn gốc"
    `book_lab/dbatools-lab/bookcode/chapter05.notes.md`
