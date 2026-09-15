---
title: Chapter 21 — Data masking, PII scan & dữ liệu giả lập (Data tooling)
course: 11-book-lab
source: book_lab/dbatools-lab/bookcode/chapter21.notes.md
---

# Chapter 21 — Data masking, PII scan & dữ liệu giả lập (Data tooling)

> **Cảnh báo MẠNH:** Chapter này có nhóm lệnh **ghi/thay đổi dữ liệu trong bảng** (`Invoke-DbaDbDataMasking`, và gián tiếp khi import bằng `Write-DbaDataTable`/`Import-DbaCsv` ở các bước thực hành). **Tuyệt đối không chạy trên DB production.** Luôn `Backup-DbaDatabase` trước, và chạy trên bản clone của `WideWorldImporters` / `AdventureWorks2017`. `Invoke-DbaDbDataMasking` có thể chạy rất lâu và sinh khối lượng I/O lớn nếu table có hàng triệu dòng.

## Mục tiêu
- Sinh được dữ liệu ngẫu nhiên có kiểu dữ liệu hợp lệ (`Get-DbaRandomizedValue`).
- Quét cột chứa PII tự động bằng `Invoke-DbaDbPiiScan`.
- Tạo file cấu hình masking với `New-DbaDbMaskingConfig` rồi áp dụng bằng `Invoke-DbaDbDataMasking`.
- Hiểu khác biệt giữa "fake data" (sinh mới) và "masking" (ghi đè dữ liệu thật).
- Biết khi nào nên kết hợp với `Write-DbaDataTable` / `Import-DbaCsv` để nạp dữ liệu mẫu trở lại bảng.

## Tóm tắt 3-5 ý chính
1. **`Get-DbaRandomizedValue`** — sinh 1 giá trị ngẫu nhiên hợp kiểu (datetime, IP, name, address...). Dùng làm building block cho test data.
2. **`Invoke-DbaDbPiiScan`** — quét metadata + sample row để đoán cột có chứa PII (email, SSN, phone, address...). Output là kế hoạch masking.
3. **`New-DbaDbMaskingConfig`** — sinh file `.json` mô tả cách thay từng cột; bạn nên review và chỉnh tay file này trước khi apply.
4. **`Invoke-DbaDbDataMasking`** — đọc file JSON và **ghi đè dữ liệu thật** trong bảng. Đây là điểm cần backup trước.
5. **Quy trình chuẩn:** scan PII → sinh config → review/sửa JSON → backup DB → invoke masking → verify.

## Giải thích từng đoạn code

### Đoạn 1: dòng 19-24 — sinh datetime ngẫu nhiên
```powershell
$splatGetRandValueDT = @{
  Datatype = "datetime"
  Min = "2021-01-01"
  Max = "2021-12-31 23:59:59"
}
Get-DbaRandomizedValue @splatGetRandValueDT
```
- **Ý nghĩa:** Trả về 1 `DateTime` ngẫu nhiên trong khoảng 2021.
- **Đổi cho lab:** Giữ nguyên — không phụ thuộc instance. Có thể đổi `Max` thành ngày hôm nay để gần thực tế.
- **Lưu ý:** Mỗi lần chạy ra 1 giá trị khác; muốn 100 giá trị thì wrap trong `1..100 | ForEach-Object { Get-DbaRandomizedValue ... }`.

### Đoạn 2: dòng 27-31 — sinh IP address giả
```powershell
$splatGetRandValueIP = @{
  RandomizerType = "Internet"
  RandomizerSubType = "IP"
}
Get-DbaRandomizedValue @splatGetRandValueIP
```
- **Ý nghĩa:** `RandomizerType`/`RandomizerSubType` là cách dùng thư viện Bogus phía dưới. Xem danh sách đầy đủ qua `Get-DbaRandomizedType` và `Get-DbaRandomizedValue -List`.
- **Đổi cho lab:** Giữ nguyên.

### Đoạn 3: dòng 35 — scan PII lần đầu
```powershell
Invoke-DbaDbPiiScan -SqlInstance mssql1 -Database AdventureWorks
```
- **Ý nghĩa:** Quét toàn DB, trả về danh sách cột có tên/giá trị nghi là PII (Email, FirstName, Phone, SSN...).
- **Đổi cho lab:** `Invoke-DbaDbPiiScan -SqlInstance dbatoolslab\sql2017 -Database AdventureWorks2017`.
- **Lưu ý:** Mặc định scan limited rows. Nếu bảng rất lớn, scan có thể vẫn nhanh nhưng độ chính xác phụ thuộc sample.

### Đoạn 4: dòng 40 — chạy lại scan
```powershell
Invoke-DbaDbPiiScan -SqlInstance mssql1 -Database AdventureWorks
```
- **Ý nghĩa:** Lặp lại để dùng kết quả trong pipeline (`| Out-GridView` hoặc gán biến).
- **Đổi cho lab:** Như đoạn 3. Gợi ý: `$pii = Invoke-DbaDbPiiScan ...` để giữ kết quả.

### Đoạn 5: dòng 45 — scan với sample lớn hơn
```powershell
Invoke-DbaDbPiiScan -SqlInstance mssql1 -Database AdventureWorks -SampleCount 200
```
- **Ý nghĩa:** Tăng số dòng quét mỗi bảng lên 200 → giảm false negative.
- **Đổi cho lab:** Đổi `mssql1` → `dbatoolslab\sql2017`, `AdventureWorks` → `AdventureWorks2017`.
- **Lưu ý:** `SampleCount` cao = scan lâu hơn nhưng chính xác hơn.

### Đoạn 6: dòng 49 — sinh masking config cho bảng Address
```powershell
New-DbaDbMaskingConfig -SqlInstance mssql1 -Database AdventureWorks -Table Address -Column City, PostalCode -Path D:\temp
```
- **Ý nghĩa:** Tạo file `mssql1.AdventureWorks.DataMaskingConfig.json` trong `D:\temp`, chứa kế hoạch mask cột `City`, `PostalCode` của bảng `Address`.
- **Đổi cho lab:** Path Windows → `C:\dbatoolslab\masking` hoặc `C:\temp`. Bảng `Address` ở AdventureWorks là `Person.Address`. Có thể cần đầy đủ schema: `-Table Person.Address`.
- **Lưu ý:** Mở file JSON, REVIEW, chỉnh `RandomizerSubType` cho hợp ngữ nghĩa (ví dụ PostalCode → ZipCode).

### Đoạn 7: dòng 53 — apply masking
```powershell
Invoke-DbaDbDataMasking -SqlInstance mssql1 -Database dbatools -FilePath "D:\temp\mssql1.AdventureWorks.DataMaskingConfig.json"
```
- **Ý nghĩa:** Đọc JSON ở trên rồi **UPDATE thật** vào DB đích.
- **Đổi cho lab:** `-SqlInstance dbatoolslab\sql2017 -Database AdventureWorks2017_Clone -FilePath C:\dbatoolslab\masking\dbatoolslab.AdventureWorks2017.DataMaskingConfig.json`.
- **Cảnh báo:** **Ghi đè dữ liệu thật**. Phải backup trước. Có hỗ trợ `-WhatIf` — luôn dùng lần đầu.

## Lệnh thay vào lab của bạn

```powershell
# 0) Chuẩn bị: clone DB AdventureWorks2017 sang bản test
$src = 'dbatoolslab\sql2017'
Backup-DbaDatabase -SqlInstance $src -Database AdventureWorks2017 -Path C:\dbatoolslab\Backup -CompressBackup
Restore-DbaDatabase -SqlInstance $src -Path C:\dbatoolslab\Backup `
    -DatabaseName AdventureWorks2017_Mask -ReplaceDbNameInFile

# 1) Sinh value mẫu
Get-DbaRandomizedValue -Datatype datetime -Min '2024-01-01' -Max (Get-Date).ToString('yyyy-MM-dd')
Get-DbaRandomizedValue -RandomizerType Internet -RandomizerSubType Email

# 2) Scan PII
$pii = Invoke-DbaDbPiiScan -SqlInstance $src -Database AdventureWorks2017_Mask -SampleCount 200
$pii | Select Schema, Table, Column, PII_Category, PII_Name | Format-Table -AutoSize

# 3) Sinh config (ví dụ bảng Person.Address)
New-Item -ItemType Directory -Force -Path C:\dbatoolslab\masking | Out-Null
New-DbaDbMaskingConfig -SqlInstance $src -Database AdventureWorks2017_Mask `
    -Table 'Person.Address' -Column City, PostalCode -Path C:\dbatoolslab\masking

# 4) Review & apply (DRY RUN trước!)
$cfg = 'C:\dbatoolslab\masking\dbatoolslab.AdventureWorks2017_Mask.DataMaskingConfig.json'
Invoke-DbaDbDataMasking -SqlInstance $src -Database AdventureWorks2017_Mask `
    -FilePath $cfg -WhatIf

# 5) Khi đã chắc, bỏ -WhatIf
Invoke-DbaDbDataMasking -SqlInstance $src -Database AdventureWorks2017_Mask -FilePath $cfg
```

## Self-check (3 câu)
1. **Định nghĩa:** Sự khác nhau giữa `Get-DbaRandomizedValue` và `Invoke-DbaDbDataMasking` là gì? (Gợi ý: 1 cái sinh giá trị, 1 cái ghi vào DB.)
2. **Thực hành:** Chạy `Invoke-DbaDbPiiScan` 2 lần với `-SampleCount` 50 và 500 — kết quả khác nhau cột nào?
3. **Liên hệ:** Trước khi gọi `Invoke-DbaDbDataMasking` trên DB lớn, bạn phải làm 2 bước an toàn nào (so với chapter backup đã học)?

## Bài tập mở rộng
- **Bài 1:** Viết hàm `Invoke-LabMaskingPipeline -Database <name>` thực hiện cả 3 bước: scan PII → tạo config → mask, kèm `-WhatIf`.
- **Bài 2:** Sinh CSV 10.000 dòng customer giả bằng `Get-DbaRandomizedValue` (FirstName, LastName, Email, IP) rồi dùng `Import-DbaCsv` đẩy vào bảng `dbo.FakeCustomers` mới trong `AdventureWorks2017_Mask`. **Cảnh báo:** `Import-DbaCsv` chèn dữ liệu thật, kiểm tra `-WhatIf` và `-Truncate` trước.
- **Bài 3:** So sánh `Export-DbaDbTableData` (T-SQL `INSERT`) vs `Write-DbaDataTable` (bulk copy) khi export 100k dòng — đo thời gian.


---

!!! info "Nguồn gốc"
    `book_lab/dbatools-lab/bookcode/chapter21.notes.md`
