---
title: Chapter 22 — DACPAC & schema deployment (Export/Publish DAC Package)
course: 11-book-lab
source: book_lab/dbatools-lab/bookcode/chapter22.notes.md
---

# Chapter 22 — DACPAC & schema deployment (Export/Publish DAC Package)

## Mục tiêu
- Hiểu DACPAC là gì và khi nào dùng so với `.bak`/`.bacpac`.
- Export schema (không data) của 1 DB ra file `.dacpac` bằng `Export-DbaDacPackage`.
- Publish (deploy) `.dacpac` vào instance khác bằng `Publish-DbaDacPackage`, có loại trừ Users/Logins.
- Tạo publish profile chuẩn hoá bằng `New-DbaDacProfile`.
- Biết khi nào cần `New-DbaDacOption` để tinh chỉnh hành vi deploy.

## Tóm tắt 3-5 ý chính
1. **DACPAC** = gói schema-only (table, view, sp, role...). Khác `.bacpac` (schema + data) và `.bak` (full backup binary).
2. **`Export-DbaDacPackage`** đọc 1 DB sống và xuất ra `.dacpac`. Tham số path: book code dùng cả `FilePath` (mới) và `Path` (cũ) — dùng `Path` cho dbatools hiện tại.
3. **`Publish-DbaDacPackage`** đẩy `.dacpac` vào DB đích. Mặc định **so sánh schema và update** — KHÔNG drop DB.
4. **`New-DbaDacOption`** + property `DeployOptions.ExcludeObjectTypes` cho phép loại trừ `Users`, `RoleMembership`, `Logins` — tránh kéo theo security của môi trường nguồn sang đích.
5. **`New-DbaDacProfile`** sinh file `.publish.xml` để tái sử dụng — chuẩn hoá deploy giữa các môi trường (dev/staging/prod).

## Giải thích từng đoạn code

### Đoạn 1: dòng 18-23 — export với `FilePath` (cú pháp cũ trong sách)
```powershell
$splatExportDacPac = @{
  SqlInstance = $ProductionFactoryInstance
  Database = "Factory"
  FilePath = "C:\temp\ProdFactory_20201230.dacpac"
}
Export-DbaDacPackage @splatExportDacPac
```
- **Ý nghĩa:** Xuất DB `Factory` ra file dacpac đặt tại `C:\temp\...`.
- **Đổi cho lab:** `$ProductionFactoryInstance = 'dbatoolslab\sql2017'`, `Database = 'WideWorldImporters'`, `FilePath = 'C:\dbatoolslab\dacpac\WWI_$(Get-Date -f yyyyMMdd).dacpac'`.
- **Lưu ý:** Trong dbatools mới, parameter chuẩn là `-Path` (thư mục) — sẽ xem ở đoạn 2.

### Đoạn 2: dòng 27-32 — export với `Path` (cú pháp hiện hành)
```powershell
$splatExportDacPac = @{
  SqlInstance = $ProductionFactoryInstance
  Database    = "Factory"
  Path        = "C:\temp\ProdFactory_20201230.dacpac"
}
Export-DbaDacPackage @splatExportDacPac
```
- **Ý nghĩa:** Same as trên nhưng dùng `-Path`. Đây là cú pháp đúng cho version dbatools mới.
- **Đổi cho lab:** Như đoạn 1, đổi `Path = 'C:\dbatoolslab\dacpac'` (chỉ thư mục — dbatools tự đặt tên file).
- **Lưu ý:** Nếu chỉ trỏ thư mục, file kết quả là `<server>-<db>-<timestamp>.dacpac`.

### Đoạn 3: dòng 36-41 — publish vào dev container
```powershell
$splatPublishDacPac = @{
  SqlInstance = $developercontainer
  Database = "FactoryIssue"
  Path     = "C:\temp\ProdFactory_20201230.dacpac"
}
Publish-DbaDacPackage @splatPublishDacPac
```
- **Ý nghĩa:** Apply schema `ProdFactory...dacpac` lên DB `FactoryIssue` ở instance dev.
- **Đổi cho lab:** `$developercontainer = 'dbatoolslab'` (instance default SQL 2019). `Database = 'WWI_Dev_Schema'`.
- **Cảnh báo:** **Đây là deploy schema thật** — nếu DB đích đã có, các object khác schema sẽ bị ALTER/DROP. Chạy `-WhatIf` (nếu hỗ trợ) hoặc test trước trên DB sandbox.

### Đoạn 4: dòng 45-53 — publish loại trừ Users/RoleMembership/Logins
```powershell
$dacoptions  = New-DbaDacOption -Type DACPAC -Action Publish
$dacoptions.DeployOptions.ExcludeObjectTypes = "Users","RoleMembership" ,"Logins"
$splatPublishDacPacNoUsers = @{
  SqlInstance = $developercontainer
  Database = "FactoryIssue"
  FilePath = "C:\temp\ProdFactory_20201230.dacpac"
  DacOption = $dacoptions
}
Publish-DbaDacPackage @splatPublishDacPacNoUsers
```
- **Ý nghĩa:** Bỏ qua object security khi deploy — rất quan trọng khi đẩy schema prod xuống dev (không muốn tạo user của prod ở dev).
- **Đổi cho lab:** Như đoạn 3, đổi `FilePath` thành đường dẫn dacpac trong `C:\dbatoolslab\dacpac\`.
- **Lưu ý:** `ExcludeObjectTypes` còn nhận `Permissions`, `LoginMappings`, ... — xem `[Microsoft.SqlServer.Dac.ObjectType]` để có danh sách đầy đủ.

### Đoạn 5: dòng 57-70 — tạo publish profile XML
```powershell
$splatNewDacProfile = @{
  SqlInstance = "sql01"
  Database = "Factory"
  Path = "c:\temp"
  PublishOptions = @{
      IgnoreUserLoginMappings = $true
      IgnorePermissions = $true
      ExcludeObjectTypes = 'Users;RoleMembership;Logins'
      ExcludeLogins = $true
      ExcludeUsers = $true
      IgnoreUserSettingsObjects = $true
  }
}
New-DbaDacProfile @splatNewDacProfile
```
- **Ý nghĩa:** Sinh file `.publish.xml` chứa các tùy chọn publish, có thể commit vào git và dùng lại với `Publish-DbaDacPackage -PublishXml ...`.
- **Đổi cho lab:** `SqlInstance = 'dbatoolslab\sql2017'`, `Database = 'WideWorldImporters'`, `Path = 'C:\dbatoolslab\dacpac'`.
- **Lưu ý:** Trong cú pháp dacpac của DacFx, list dùng dấu `;` (string) — khác với array PowerShell ở đoạn 4.

## Lệnh thay vào lab của bạn

```powershell
$src = 'dbatoolslab\sql2017'
$dev = 'dbatoolslab'
$out = 'C:\dbatoolslab\dacpac'
New-Item -ItemType Directory -Force -Path $out | Out-Null

# 1) Export schema WideWorldImporters
Export-DbaDacPackage -SqlInstance $src -Database WideWorldImporters -Path $out
$dac = Get-ChildItem $out -Filter '*WideWorldImporters*.dacpac' |
       Sort-Object LastWriteTime -Descending | Select-Object -First 1

# 2) Tạo DB rỗng ở instance dev và publish vào
New-DbaDatabase -SqlInstance $dev -Name WWI_SchemaOnly
$opts = New-DbaDacOption -Type DACPAC -Action Publish
$opts.DeployOptions.ExcludeObjectTypes = 'Users','RoleMembership','Logins','Permissions'

Publish-DbaDacPackage -SqlInstance $dev -Database WWI_SchemaOnly `
    -Path $dac.FullName -DacOption $opts

# 3) Verify: cùng số table?
$srcTables = (Get-DbaDbTable -SqlInstance $src -Database WideWorldImporters).Count
$dstTables = (Get-DbaDbTable -SqlInstance $dev -Database WWI_SchemaOnly).Count
"$srcTables tables source / $dstTables tables target"

# 4) Sinh publish profile để tái sử dụng
New-DbaDacProfile -SqlInstance $src -Database WideWorldImporters -Path $out `
    -PublishOptions @{
        ExcludeLogins = $true
        ExcludeUsers = $true
        IgnorePermissions = $true
    }
```

## Self-check (3 câu)
1. **Định nghĩa:** Khác nhau giữa `.dacpac` và `.bacpac` là gì? Khi nào nên backup full `.bak` thay vì dacpac?
2. **Thực hành:** Sau khi `Publish-DbaDacPackage`, chạy `Get-DbaDbUser -SqlInstance $dev -Database WWI_SchemaOnly` — có thấy `WWI_ReadOnly` không? Tại sao?
3. **Liên hệ:** So với `Copy-DbaDatabase` (chapter migration), DACPAC khác ở điểm nào về data và downtime?

## Bài tập mở rộng
- **Bài 1:** Tạo pipeline tự động: mỗi sáng export dacpac của 3 DB sang `C:\dbatoolslab\dacpac\$(Get-Date -f yyyyMMdd)\` rồi zip lại.
- **Bài 2:** Sửa publish profile XML sinh ở đoạn 5, thêm `<BlockOnPossibleDataLoss>true</BlockOnPossibleDataLoss>` rồi publish — quan sát hành vi khi schema mới drop cột.
- **Bài 3:** So sánh `Export-DbaDacPackage -Type Bacpac` (kèm data) vs `Backup-DbaDatabase` về kích thước file + thời gian restore.


---

!!! info "Nguồn gốc"
    `book_lab/dbatools-lab/bookcode/chapter22.notes.md`
