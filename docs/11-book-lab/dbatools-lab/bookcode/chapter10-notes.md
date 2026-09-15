---
title: Chapter 10 — Backup database với dbatools
course: 11-book-lab
source: book_lab/dbatools-lab/bookcode/chapter10.notes.md
---

# Chapter 10 — Backup database với dbatools

> Lưu ý: User mapping gọi chapter 10 là "Database properties & configuration", nhưng nội dung thực tế của `chapter10.ps1` là **backup** (`Backup-DbaDatabase`, `Read-DbaBackupHeader`, `Find-DbaBackup`, `Test-DbaLastBackup`). Notes này theo nội dung file thực tế.

## Mục tiêu

- Hiểu `Backup-DbaDatabase` mặc định làm gì khi không chỉ định path/database.
- Backup ra UNC share, ra Azure Blob (URL backup), ra Linux container.
- Đọc backup header và backup history để biết DB đã backup khi nào.
- Áp dụng retention policy bằng `Find-DbaBackup`.
- Validate backup chất lượng cao bằng `Test-DbaLastBackup` (restore thật + DBCC).

## Tóm tắt 5 ý chính

1. **`Backup-DbaDatabase` mặc định backup TẤT CẢ database** (kể cả system DB) ra default backup directory của instance, dạng `.bak`. Đây là pattern "lazy DBA" — nhưng đủ tốt cho ad-hoc.
2. **`-OutputScriptOnly`** sinh ra T-SQL `BACKUP DATABASE ...` mà không chạy — dùng để review trước, hoặc đẩy vào Agent job lưu ý phép gán biến.
3. **Backup ra Azure Blob** cần `New-DbaCredential` trước. Có 2 chế độ: (a) SAS token thông qua identity `SHARED ACCESS SIGNATURE`, (b) Access Key. `Backup-DbaDatabase -AzureBaseUrl` chỉ ra URL container.
4. **`Get-DbaDbBackupHistory -Last`** trả về chuỗi backup "đủ để restore mới nhất" (Full + Diff gần nhất + Log từ Diff đến hiện tại) — đây là input chính cho `Restore-DbaDatabase`.
5. **`Test-DbaLastBackup`** = restore vào server test + DBCC CHECKDB + ghi kết quả. Đây là cách duy nhất chứng minh backup "thực sự usable", thay vì chỉ `BACKUP ... VERIFYONLY`.

## CẢNH BÁO trước khi chạy

Mọi lệnh `Backup-DbaDatabase` trong notes này **PHẢI** chạy với `-WhatIf` lần đầu để biết:
- Backup vào path nào (tránh ghi vào ổ system).
- Bao nhiêu DB sẽ được backup (nếu không truyền `-Database`, lệnh backup **toàn bộ**).
- Đặc biệt cảnh giác `-Type Log` — backup log liên tục có thể đầy disk nhanh.

## Giải thích từng đoạn code

### Đoạn 1: dòng 18 — Backup mặc định (TẤT CẢ database)

```powershell
Backup-DbaDatabase -SqlInstance sql01
```

- **Ý nghĩa:** Backup tất cả user DB + system DB ra default backup directory của instance, file `.bak` riêng cho mỗi DB.
- **Đổi cho lab:**
  ```powershell
  Backup-DbaDatabase -SqlInstance dbatoolslab\sql2017 -WhatIf
  ```
- **Lưu ý:** Lab default backup directory của `dbatoolslab\sql2017` thường là `C:\Program Files\Microsoft SQL Server\MSSQL14.SQL2017\MSSQL\Backup`. Kiểm tra bằng `Get-DbaDefaultPath`. Backup path khuyến nghị cho lab: `C:\dbatoolslab\Backup` (xem `config\Config.psd1`).

### Đoạn 2: dòng 22 — Backup ra UNC share

```powershell
Backup-DbaDatabase -SqlInstance sql01 -Path \\nas\sqlbackups
```

- **Ý nghĩa:** Backup tất cả DB ra share `\\nas\sqlbackups`. SQL Engine service account phải có quyền `Modify` trên share.
- **Đổi cho lab:**
  ```powershell
  Backup-DbaDatabase -SqlInstance dbatoolslab\sql2017 -Path C:\dbatoolslab\Backup -WhatIf
  ```
- **Lưu ý:** Lab dùng local path `C:\dbatoolslab\Backup` (đã được set quyền cho SQL service trong `scripts\02_Configure_Lab.ps1`). Nếu thay bằng UNC, đảm bảo service account (`NT Service\MSSQL$SQL2017`) có quyền — đây là 1 trong những lý do backup hay fail nhất.

### Đoạn 3: dòng 27 — Backup vào NUL (test compression/size)

```powershell
Backup-DbaDatabase -SqlInstance sql01 -Database pubs -BackupFileName NUL
```

- **Ý nghĩa:** Backup DB `pubs` vào device `NUL` (tương đương `/dev/null`). Lệnh chạy hết, nhưng không ghi ra disk. Dùng để đo backup time / kích thước thực tế / xem compression ratio mà không tốn ổ đĩa.
- **Đổi cho lab:**
  ```powershell
  Backup-DbaDatabase -SqlInstance dbatoolslab\sql2017 `
      -Database WideWorldImporters -BackupFileName NUL -CompressBackup
  ```
- **Lưu ý:** Đây là 1 trong rất ít lệnh `Backup-*` an toàn 100% với production — không ảnh hưởng disk, không ảnh hưởng log chain (`-Type Log NUL` thì khác, dùng riêng cho test perf).

### Đoạn 4: dòng 31-32 — Filter DB rồi backup, in script

```powershell
$bigdbs = Get-DbaDatabase -SqlInstance sql01 | Where Name -match factory
$bigdbs | Backup-DbaDatabase -Path \\nas\sqlbackups -OutputScriptOnly
```

- **Ý nghĩa:** Lấy các DB có tên chứa "factory" → pipe vào backup nhưng chỉ in script T-SQL (`-OutputScriptOnly`), không thực thi. Pattern này dùng khi cần đẩy lệnh backup vào Agent job hoặc audit trail.
- **Đổi cho lab:**
  ```powershell
  $dbs = Get-DbaDatabase -SqlInstance dbatoolslab\sql2017 |
      Where-Object Name -match 'WideWorld|Adventure'
  $dbs | Backup-DbaDatabase -Path C:\dbatoolslab\Backup -OutputScriptOnly
  ```
- **Lưu ý:** `-OutputScriptOnly` an toàn — không backup thật. KHÔNG cần `-WhatIf` cho biến thể này.

### Đoạn 5: dòng 36-51 — Backup ra Azure Blob (SAS token)

```powershell
$splatCredential = @{
    SqlInstance = "sql01"
    Name = "https://acmecorp.blob.core.windows.net/backups"
    Identity = "SHARED ACCESS SIGNATURE"
    SecurePassword = (Get-Credential).Password
}
New-DbaCredential @splatCredential

$splatBackup = @{
    SqlInstance = "sql01"
    AzureBaseUrl = "https://acmecorp.blob.core.windows.net/backups/"
    Database = "mydb"
    BackupFileName = "mydb.bak"
    WithFormat = $true
}
Backup-DbaDatabase @splatBackup
```

- **Ý nghĩa:** Tạo SQL credential mà NAME chính là URL container Azure, IDENTITY là `SHARED ACCESS SIGNATURE`, PASSWORD chính là SAS token. Sau đó backup trực tiếp lên blob.
- **Đổi cho lab:** Lab không có Azure subscription — coi như đọc hiểu. Nếu có Azure, sinh SAS token trong portal hoặc:
  ```powershell
  $ctx = New-AzStorageContext -StorageAccountName acmecorp -StorageAccountKey ...
  New-AzStorageContainerSASToken -Name backups -Permission rwdl -Context $ctx
  ```
- **Lưu ý:** SAS phải có quyền `Read, Write, Delete, List` cho VSS-style streaming backup. Mật khẩu nhập qua `Get-Credential` — không hardcode token trong script.

### Đoạn 6: dòng 55-69 — Backup ra Azure Blob (Access Key, legacy)

```powershell
$splatCredential = @{
    SqlInstance = "sql01"
    Name = "AzureAccessKey"
    Identity = "acmecorp"
    SecurePassword = (Get-Credential).Password
}
New-DbaCredential @splatCredential

$splatBackup = @{
    SqlInstance = "sql01"
    AzureCredential = "AzureAccessKey"
    AzureBaseUrl = "https://acmecorp.blob.core.windows.net/backups/"
    Database = "mydb"
}
Backup-DbaDatabase @splatBackup
```

- **Ý nghĩa:** Phương pháp cũ (SQL 2012 SP1+). Identity = tên storage account, password = primary/secondary access key. SQL hỗ trợ cả 2, nhưng Microsoft khuyến nghị SAS.
- **Lưu ý:** Access key đầy đủ quyền lên toàn storage account → rủi ro bảo mật cao. Chỉ dùng cho legacy SQL 2012/2014.

### Đoạn 7: dòng 73-79 — Backup từ SQL Linux (port 14433)

```powershell
Backup-DbaDatabase -SqlInstance localhost:14433 -SqlCredential sqladmin
  -BackupDirectory /tmp

Backup-DbaDatabase -SqlInstance localhost:14433 -SqlCredential sqladmin
  -BackupDirectory /shared/backups
```

- **Ý nghĩa:** SQL Linux container thường expose port khác 1433 (vd 14433). `-SqlCredential` để dùng SQL login thay vì Windows auth (Linux không có Windows auth).
- **Đổi cho lab Linux container (Đường A trong `LEARNING_PATH_VI.md`):**
  ```powershell
  $cred = New-Object PSCredential('sa', (ConvertTo-SecureString 'dbatools.IO' -AsPlainText -Force))
  Backup-DbaDatabase -SqlInstance localhost -SqlCredential $cred `
      -Database master -BackupDirectory /var/opt/mssql/data -WhatIf
  ```
- **Lưu ý:** Path Linux dùng forward slash. `/tmp` không tồn tại sau khi container restart — dùng `/var/opt/mssql/data` hoặc mount volume.

### Đoạn 8: dòng 83-84 — Đọc header backup file

```powershell
Read-DbaBackupHeader -SqlInstance sql01 -Path
 \\nas\sql\backups\mydb.bak
```

- **Ý nghĩa:** Đọc metadata của file `.bak` — version SQL nguồn, ngày backup, kích thước, recovery model, LSN. Hữu ích khi nhận 1 file `.bak` không biết nguồn gốc.
- **Đổi cho lab:**
  ```powershell
  Read-DbaBackupHeader -SqlInstance dbatoolslab\sql2017 `
      -Path C:\dbatoolslab\Backup\WideWorldImporters-Full.bak
  ```
- **Lưu ý:** Đọc header bằng cách gọi `RESTORE HEADERONLY` qua SMO. SQL instance phải có quyền đọc file. Không hỏng backup, không hỏng DB.

### Đoạn 9: dòng 88-89 — Lấy thông tin chi tiết backup set

```powershell
Get-DbaBackupInformation -SqlInstance sql01 -Path
 \\nas\sql\backups\sql01
```

- **Ý nghĩa:** Quét toàn bộ thư mục, đọc header từng file, tổng hợp thành object `BackupInformation` (giúp `Restore-DbaDatabase` xác định trình tự).
- **Đổi cho lab:**
  ```powershell
  Get-DbaBackupInformation -SqlInstance dbatoolslab\sql2017 `
      -Path C:\dbatoolslab\Backup | Select Database, BackupType, BackupStartDate
  ```
- **Lưu ý:** Chạy chậm nếu thư mục có hàng nghìn file. Có thể giới hạn bằng `-MaintenanceSolution` (nếu backup theo cấu trúc Ola).

### Đoạn 10: dòng 93 — Lịch sử backup của 1 DB

```powershell
Get-DbaDbBackupHistory -SqlInstance sql01 -Database pubs
```

- **Ý nghĩa:** Đọc `msdb.dbo.backupset` để trả về toàn bộ history của DB `pubs`.
- **Đổi cho lab:**
  ```powershell
  Get-DbaDbBackupHistory -SqlInstance dbatoolslab\sql2017 -Database WideWorldImporters
  ```

### Đoạn 11: dòng 97 — Backup chain mới nhất

```powershell
Get-DbaDbBackupHistory -SqlInstance sql01 -Last
```

- **Ý nghĩa:** `-Last` trả về tổ hợp: Full mới nhất + Diff mới nhất sau Full + tất cả Log sau Diff. Đây là chính xác chuỗi cần để restore ra trạng thái hiện tại.
- **Đổi cho lab:**
  ```powershell
  Get-DbaDbBackupHistory -SqlInstance dbatoolslab\sql2017 -Last
  ```
- **Lưu ý:** Pipe được trực tiếp vào `Restore-DbaDatabase` (xem chapter11).

### Đoạn 12: dòng 101-102 — Cleanup `.bak` cũ hơn 90 ngày

```powershell
Find-DbaBackup -Path \\nas\sql\backups -BackupFileExtension bak
 -RetentionPeriod 90d | Remove-Item -Verbose
```

- **Ý nghĩa:** `Find-DbaBackup` quét thư mục, đọc `LastWriteTime` file, trả về file cũ hơn retention. Pipe vào `Remove-Item` để XÓA THẬT.
- **Đổi cho lab:**
  ```powershell
  Find-DbaBackup -Path C:\dbatoolslab\Backup -BackupFileExtension bak `
      -RetentionPeriod 30d | Remove-Item -WhatIf
  ```
- **CẢNH BÁO:** `Remove-Item` không có `-WhatIf` trong code sách = XÓA NGAY. Lab nên thêm `-WhatIf` lần đầu để xem file nào sẽ bị xóa.

### Đoạn 13: dòng 106-107 — Cleanup `.trn` cũ hơn 90 ngày

```powershell
Find-DbaBackup -Path \\nas\sql\backups -BackupFileExtension trn
 -RetentionPeriod 90d | Remove-Item -Verbose
```

- **Ý nghĩa:** Tương tự nhưng cho log backup. Log file thường nhiều và nhỏ — retention ngắn hơn (vd 14-30 ngày) trong thực tế.
- **CẢNH BÁO:** Xóa `.trn` mà chưa restore = mất khả năng point-in-time recovery cho khoảng thời gian đó. Phối hợp với chính sách archive (đẩy lên tape/cold storage) trước khi xóa.

### Đoạn 14: dòng 111-136 — Test backup thật bằng restore + DBCC

```powershell
$query = "CREATE TABLE dbo.lastbackuptests (
    SourceServer nvarchar(255),
    TestServer nvarchar(255),
    [Database] nvarchar(128),
    FileExists bit,
    Size bigint,
    RestoreResult nvarchar(4000),
    DbccResult nvarchar(4000),
    RestoreStart datetime,
    RestoreEnd datetime,
    RestoreElapsed nvarchar(128),
    DbccStart datetime,
    DbccEnd datetime,
    DbccElapsed nvarchar(128),
    BackupDates nvarchar(4000),
    BackupFiles nvarchar(4000))"
Invoke-DbaQuery -SqlInstance sqltest -Database dbatools -Query $query

$splatTestBackups = @{
    SqlInstance = "sql01", "sql02"
    Destination = "sqltest"
    DataDirectory = "R:\"
    LogDirectory = "L:\"
}
Test-DbaLastBackup @splatTestBackups | Write-DbaDataTable -SqlInstance
sqltest -Table dbatools.dbo.lastbackuptests
```

- **Ý nghĩa:** Pattern enterprise:
  1. Tạo bảng tracking trong DB `dbatools` trên `sqltest`.
  2. Với mỗi DB trên `sql01` và `sql02`: lấy backup mới nhất, restore lên `sqltest` (tên DB có prefix `dbatools-`), chạy `DBCC CHECKDB`, ghi kết quả vào bảng tracking.
  3. Sau đó xoá DB tạm.
- **Đổi cho lab (chạy được):**
  ```powershell
  # Tạo bảng tracking trong WideWorldImporters (hoặc DB riêng)
  $createTable = @"
  IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name='lastbackuptests')
  CREATE TABLE dbo.lastbackuptests (
      SourceServer nvarchar(255), TestServer nvarchar(255), [Database] nvarchar(128),
      FileExists bit, Size bigint, RestoreResult nvarchar(4000), DbccResult nvarchar(4000),
      RestoreStart datetime, RestoreEnd datetime, RestoreElapsed nvarchar(128),
      DbccStart datetime, DbccEnd datetime, DbccElapsed nvarchar(128),
      BackupDates nvarchar(4000), BackupFiles nvarchar(4000))
  "@
  Invoke-DbaQuery -SqlInstance dbatoolslab\sql2017 -Database WideWorldImporters -Query $createTable

  $splatTest = @{
      SqlInstance   = "dbatoolslab\sql2017"
      Destination   = "dbatoolslab"
      DataDirectory = "C:\dbatoolslab\TestRestore\Data"
      LogDirectory  = "C:\dbatoolslab\TestRestore\Log"
  }
  New-Item -ItemType Directory -Path $splatTest.DataDirectory -Force | Out-Null
  New-Item -ItemType Directory -Path $splatTest.LogDirectory -Force | Out-Null
  Test-DbaLastBackup @splatTest |
      Write-DbaDataTable -SqlInstance dbatoolslab\sql2017 `
          -Database WideWorldImporters -Table dbo.lastbackuptests
  ```
- **CẢNH BÁO:**
  - `Test-DbaLastBackup` sẽ tạo DB tạm tên `dbatools-<dbname>` trên server destination, restore thật, chạy CHECKDB rồi DROP. Cần đủ disk.
  - DBCC CHECKDB tốn CPU/IO nhiều — đừng chạy trên server đang busy.

## Lệnh thay vào lab của bạn

```powershell
# ============================================================
# 1) BACKUP AN TOÀN — luôn -WhatIf lần đầu
# ============================================================
$backupRoot = "C:\dbatoolslab\Backup"
New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null

# Full backup WideWorldImporters — chạy thử -WhatIf
Backup-DbaDatabase -SqlInstance dbatoolslab\sql2017 `
    -Database WideWorldImporters `
    -Path $backupRoot `
    -Type Full -CompressBackup -WhatIf

# Sau khi xác nhận, bỏ -WhatIf:
Backup-DbaDatabase -SqlInstance dbatoolslab\sql2017 `
    -Database WideWorldImporters `
    -Path $backupRoot `
    -Type Full -CompressBackup

# ============================================================
# 2) Chuỗi Full + Diff + Log (cần recovery FULL)
# ============================================================
Set-DbaDbRecoveryModel -SqlInstance dbatoolslab\sql2017 `
    -Database WideWorldImporters -RecoveryModel Full -Confirm:$false

Backup-DbaDatabase -SqlInstance dbatoolslab\sql2017 `
    -Database WideWorldImporters -Path $backupRoot -Type Full
Backup-DbaDatabase -SqlInstance dbatoolslab\sql2017 `
    -Database WideWorldImporters -Path $backupRoot -Type Diff
Backup-DbaDatabase -SqlInstance dbatoolslab\sql2017 `
    -Database WideWorldImporters -Path $backupRoot -Type Log

# ============================================================
# 3) Đọc backup header & history
# ============================================================
$lastBak = Get-ChildItem $backupRoot -Filter "WideWorldImporters*.bak" |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
Read-DbaBackupHeader -SqlInstance dbatoolslab\sql2017 -Path $lastBak.FullName

Get-DbaDbBackupHistory -SqlInstance dbatoolslab\sql2017 `
    -Database WideWorldImporters -Last |
    Select-Object Database, Type, Start, End, TotalSize, Path

# ============================================================
# 4) Cleanup backup cũ — LUÔN -WhatIf trước
# ============================================================
Find-DbaBackup -Path $backupRoot -BackupFileExtension bak -RetentionPeriod 30d |
    Remove-Item -WhatIf
# Khi đã yên tâm: bỏ -WhatIf

# ============================================================
# 5) Test backup chất lượng cao (restore + DBCC)
# ============================================================
$testDataDir = "C:\dbatoolslab\TestRestore\Data"
$testLogDir  = "C:\dbatoolslab\TestRestore\Log"
New-Item -ItemType Directory -Path $testDataDir, $testLogDir -Force | Out-Null

Test-DbaLastBackup -SqlInstance dbatoolslab\sql2017 `
    -Destination dbatoolslab `
    -Database WideWorldImporters `
    -DataDirectory $testDataDir `
    -LogDirectory  $testLogDir `
    -WhatIf
# Bỏ -WhatIf để chạy thật. Lệnh sẽ tạo DB tạm "dbatools-WideWorldImporters"
# trên instance `dbatoolslab`, chạy DBCC, rồi drop.
```

## Self-check (3 câu)

1. **Định nghĩa:** Khác biệt giữa `Backup-DbaDatabase -OutputScriptOnly` và `BACKUP DATABASE ... WITH VERIFYONLY` là gì? (Gợi ý: cái nào sinh T-SQL, cái nào chạy thật và check checksum?)
2. **Thực hành:** Backup `WideWorldImporters` 3 lần liên tiếp (Full → Diff → Log). Mở `Get-DbaDbBackupHistory -Last` — có thấy đủ 3 record không? Nếu thiếu Log, kiểm tra `Get-DbaDbRecoveryModel`.
3. **Liên hệ:** `Test-DbaLastBackup` đắt đỏ về CPU/IO. Khi nào nên chạy hàng đêm vs hàng tuần? Liệt kê 2 yếu tố quyết định.

## Bài tập mở rộng

- **Bài 1:** Viết script `Invoke-LabBackup.ps1` — backup TẤT CẢ user DB trên `dbatoolslab\sql2017` ra `C:\dbatoolslab\Backup\<date>\`, compress, retention 14 ngày. Lên schedule bằng Task Scheduler chạy 2h sáng.
- **Bài 2:** Sửa đoạn 14 (`Test-DbaLastBackup`) để chạy chỉ với 1 DB chỉ định, log kết quả ra file CSV thay vì bảng SQL — tiện cho lab không có server tracking riêng.
- **Bài 3:** Đo compression ratio của 5 DB lab bằng kỹ thuật backup ra `NUL` (đoạn 3), so sánh `BackupSize` vs `CompressedBackupSize` từ output của `Backup-DbaDatabase`. Tạo bảng so sánh có/không nén.


---

!!! info "Nguồn gốc"
    `book_lab/dbatools-lab/bookcode/chapter10.notes.md`
