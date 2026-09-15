---
title: Chapter 25 — Backup compression & Data compression (Compression & Storage)
course: 11-book-lab
source: book_lab/dbatools-lab/bookcode/chapter25.notes.md
---

# Chapter 25 — Backup compression & Data compression (Compression & Storage)

> **Cảnh báo MẠNH:**
> 1. **`Set-DbaSpConfigure -Name DefaultBackupCompression -Value 1`** thay đổi cấu hình **toàn instance** — mọi backup sau đó sẽ compressed mặc định. Trong lab thì OK; trên production cần thông báo team.
> 2. **`Set-DbaDbCompression`** chạy `ALTER ... REBUILD` trên index/heap — **chiếm CPU + I/O cao** và có thể **block** trong quá trình rebuild. Bảng lớn (vài chục triệu dòng) có thể chạy vài giờ. Luôn dùng `-MaxRunTime` và chạy ngoài giờ peak.
> 3. Trên Express Edition `Set-DbaDbCompression` sẽ fail — chỉ Standard/Enterprise hỗ trợ data compression (Standard từ SQL 2016 SP1).

## Mục tiêu
- Bật mặc định backup compression bằng `Get/Set-DbaSpConfigure`.
- Kiểm tra hiện trạng compression của tất cả index/heap (`Get-DbaDbCompression`).
- Gợi ý compression type tốt nhất qua `Test-DbaDbCompression`.
- Áp dụng `ROW`/`PAGE`/`NONE` compression bằng `Set-DbaDbCompression`.
- Hiểu `-MaxRunTime` và `-PercentCompression` để chạy có kiểm soát.

## Tóm tắt 3-5 ý chính
1. **Backup compression** ≠ **data compression**. Backup compression giảm kích thước file `.bak`; data compression nén row/page trong file `.mdf`.
2. **`Test-DbaDbCompression`** chạy `sp_estimate_data_compression_savings` và xếp loại đối tượng nên ROW, PAGE, hay NONE dựa trên scan/update pattern.
3. Workflow: `Test-DbaDbCompression` → review → pipe vào `Set-DbaDbCompression -InputObject` để áp đúng khuyến nghị.
4. `Set-DbaDbCompression -MaxRunTime 60` dừng sau 60 phút dù chưa xong — cứu chiến dịch maintenance window.
5. `-PercentCompression 25` chỉ apply nếu ước tính tiết kiệm ≥ 25% → tránh rebuild các bảng compression không có lợi.

## Giải thích từng đoạn code

### Đoạn 1: dòng 18-20 — bật default backup compression
```powershell
Get-DbaSpConfigure -SqlInstance mssql1 -Name DefaultBackupCompression

Set-DbaSpConfigure -SqlInstance mssql1 -Name DefaultBackupCompression -Value 1
```
- **Ý nghĩa:** Đọc rồi đặt option `backup compression default` = ON.
- **Đổi cho lab:** Đổi `mssql1` → `dbatoolslab\sql2017`.
- **Cảnh báo MẠNH:** Đây là **sp_configure cấp instance** — ảnh hưởng mọi backup sau đó, kể cả của tools khác. OK với lab, prod cần thông báo.

### Đoạn 2: dòng 24 — xem compression hiện tại
```powershell
Get-DbaDbCompression -SqlInstance mssql1 -Database AdventureWorks
```
- **Ý nghĩa:** Trả về từng index/heap kèm `DataCompression` (NONE/ROW/PAGE) + `SizeCurrent`.
- **Đổi cho lab:** `Get-DbaDbCompression -SqlInstance dbatoolslab\sql2017 -Database AdventureWorks2017`.

### Đoạn 3: dòng 28 — lặp lại đoạn 2 (chuẩn bị pipeline)
```powershell
Get-DbaDbCompression -SqlInstance mssql1 -Database AdventureWorks
```
- **Đổi cho lab:** Như đoạn 2.

### Đoạn 4: dòng 33-43 — group theo loại compression, tính dung lượng
```powershell
$splatProperties = @{
    Property =
        @{N="Data Compression Type"; E={$_.Name}},
        @{N="Number Of Objects"; E={$_.Count}},
        @{l='SizeMB'; e={'{0:n0}' -f (($_.Group.SizeCurrent |
        Measure-Object -Sum).Sum/1MB)}}
}

Get-DbaDbCompression -SqlInstance mssql1 -Database AdventureWorks |
    Group-Object DataCompression |
    Select-Object @splatProperties
```
- **Ý nghĩa:** Báo cáo: trong DB có bao nhiêu object NONE/ROW/PAGE, tổng MB từng loại.
- **Đổi cho lab:** Như đoạn 2.
- **Lưu ý:** Đây là pattern hữu ích cho mọi dataset — học cú pháp calculated property.

### Đoạn 5: dòng 47 — list tất cả DB trừ DB test
```powershell
Get-DbaDbCompression -SqlInstance mssql1 -ExcludeDatabase TestDatabase
```
- **Đổi cho lab:** `-SqlInstance dbatoolslab\sql2017 -ExcludeDatabase tempdb, msdb`.

### Đoạn 6: dòng 51 — đánh giá compression nên dùng
```powershell
Test-DbaDbCompression -SqlInstance mssql1 -Database AdventureWorks
```
- **Ý nghĩa:** Mỗi object có cột `CompressionTypeRecommendation` = NONE/ROW/PAGE.
- **Đổi cho lab:** Đổi instance + DB.
- **Lưu ý:** Có thể mất vài phút trên DB nhiều bảng — đang gọi `sp_estimate_data_compression_savings` cho từng partition.

### Đoạn 7: dòng 55 — apply auto theo recommendation
```powershell
Set-DbaDbCompression -SqlInstance mssql1 -Database AdventureWorks
```
- **Ý nghĩa:** Khi không có `-CompressionType`, lệnh tự chạy `Test-DbaDbCompression` rồi rebuild theo recommendation.
- **Cảnh báo MẠNH:** ALTER INDEX REBUILD trên toàn DB — CPU + I/O cao, blocking. Dùng `-MaxRunTime`.

### Đoạn 8: dòng 59-70 — tách Test và Set (chạy có kiểm soát)
```powershell
$splatTestCompression = @{
    SqlInstance = "mssql1"
    Database = "AdventureWorks"
}
$compressObjects = Test-DbaDbCompression @splatTestCompression

## Review the results in $compressObjects
$splatSetCompression = @{
    SqlInstance = "mssql1"
    InputObject = $compressObjects
}
Set-DbaDbCompression @splatSetCompression
```
- **Ý nghĩa:** Best practice: chạy Test trước, **review `$compressObjects`** (filter bảng nhỏ/nguội), rồi mới pipe vào Set.
- **Đổi cho lab:** Đổi instance + DB.

### Đoạn 9: dòng 74-87 — apply theo type cụ thể
```powershell
$splatSetCompressionPage = @{
    SqlInstance = "mssql1"
    Database = "AdventureWorks"
    CompressionType = "PAGE"
}
Set-DbaDbCompression @splatSetCompressionPage

$splatSetCompressionRow = @{
    SqlInstance = "mssql1"
    Database = "AdventureWorks"
    Table = "Employee"
    CompressionType = "ROW"
}
Set-DbaDbCompression @splatSetCompressionRow
```
- **Ý nghĩa:** Ép PAGE cho toàn DB, hoặc ROW chỉ cho 1 bảng.
- **Đổi cho lab:** Đổi instance + DB. Lab nên thử trước trên 1 bảng nhỏ.

### Đoạn 10: dòng 91-96 — tắt compression
```powershell
$splatSetCompressionPage = @{
    SqlInstance = "mssql1"
    Database = "AdventureWorks"
    CompressionType = "NONE"
}
Set-DbaDbCompression @splatSetCompressionPage
```
- **Ý nghĩa:** Gỡ compression trên toàn DB — index/heap về NONE.
- **Cảnh báo:** Rebuild lần nữa, tốn I/O ngược lại. Đồng thời file size có thể không giảm (cần `DBCC SHRINKFILE`).

### Đoạn 11: dòng 100 — chạy có giới hạn thời gian và ngưỡng
```powershell
Set-DbaDbCompression -SqlInstance mssql1 -Database AdventureWorks  -MaxRunTime 60 -PercentCompression 25
```
- **Ý nghĩa:** Chạy tối đa 60 phút; chỉ rebuild khi ước tính tiết kiệm ≥ 25%.
- **Đổi cho lab:** Đổi instance + DB. Lab thử `-MaxRunTime 5 -PercentCompression 10`.

## Lệnh thay vào lab của bạn

```powershell
$inst = 'dbatoolslab\sql2017'
$db   = 'AdventureWorks2017'

# 1) Bật default backup compression (sp_configure)
Get-DbaSpConfigure -SqlInstance $inst -Name DefaultBackupCompression
Set-DbaSpConfigure -SqlInstance $inst -Name DefaultBackupCompression -Value 1

# 2) Xem hiện trạng compression (group theo type)
Get-DbaDbCompression -SqlInstance $inst -Database $db |
    Group-Object DataCompression |
    Select-Object @{N='Type'; E={$_.Name}},
                  @{N='Objects'; E={$_.Count}},
                  @{N='SizeMB'; E={'{0:n0}' -f (($_.Group.SizeCurrent | Measure-Object -Sum).Sum/1MB)}}

# 3) Đánh giá nên dùng compression gì
$plan = Test-DbaDbCompression -SqlInstance $inst -Database $db
$plan | Where-Object CompressionTypeRecommendation -ne 'NO_GAIN' |
    Select-Object Schema, TableName, IndexName,
                  CompressionTypeRecommendation,
                  PercentCompression,
                  @{N='SizeMB'; E={[math]::Round($_.SizeCurrentKB/1024,1)}} |
    Sort-Object PercentCompression -Descending |
    Format-Table -AutoSize

# 4) Áp dụng có kiểm soát: chỉ object tiết kiệm ≥ 30%, tối đa 10 phút
Set-DbaDbCompression -SqlInstance $inst -Database $db `
    -MaxRunTime 10 -PercentCompression 30 -WhatIf

# 5) Khi đã chắc, bỏ -WhatIf
Set-DbaDbCompression -SqlInstance $inst -Database $db -MaxRunTime 10 -PercentCompression 30

# 6) Verify
Get-DbaDbCompression -SqlInstance $inst -Database $db |
    Group-Object DataCompression | Select Name, Count
```

## Self-check (3 câu)
1. **Định nghĩa:** Khác nhau giữa backup compression và data compression — chúng giảm dung lượng ở đâu?
2. **Thực hành:** Chạy `Test-DbaDbCompression` trên `AdventureWorks2017`, có bao nhiêu object recommendation = PAGE, bao nhiêu = ROW, bao nhiêu = NONE?
3. **Liên hệ:** Vì sao `Set-DbaDbCompression` không nên chạy giờ peak? Liên hệ với `ALTER INDEX REBUILD` đã học.

## Bài tập mở rộng
- **Bài 1:** Viết script `Get-CompressionReport` xuất bảng MD/CSV tổng MB tiết kiệm dự kiến nếu apply toàn bộ recommendation.
- **Bài 2:** Apply PAGE compression chỉ cho 1 bảng `Sales.SalesOrderDetail` (AdventureWorks2017), backup trước. So sánh `Get-DbaDbSpace` trước/sau.
- **Bài 3:** Đo thời gian backup `AdventureWorks2017` với/không backup compression mặc định bằng `Measure-Command { Backup-DbaDatabase ... }`. Ghi vào notes.


---

!!! info "Nguồn gốc"
    `book_lab/dbatools-lab/bookcode/chapter25.notes.md`
