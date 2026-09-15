---
title: Chapter 11 — Restore database với dbatools
course: 11-book-lab
source: book_lab/dbatools-lab/bookcode/chapter11.notes.md
---

# Chapter 11 — Restore database với dbatools

> Lưu ý: User mapping gọi chapter 11 là "Backup operations", nhưng nội dung thực tế của `chapter11.ps1` là **restore** (`Restore-DbaDatabase` đầy đủ các kịch bản: cơ bản, NoRecovery chain, rename, point-in-time, point-in-time bằng MARK, page restore, Azure). Notes này theo nội dung file thực tế.

## Mục tiêu

- Restore 1 file `.bak` đơn lẻ bằng `Restore-DbaDatabase`.
- Restore một chuỗi Full + Diff + nhiều Log từ cùng thư mục (dbatools tự sắp xếp thứ tự).
- Restore rename DB và đổi đường dẫn file.
- Restore với `NoRecovery` + `Continue` để build standby manual / disaster recovery.
- Restore point-in-time bằng `RestoreTime` hoặc `StopMark` (named transaction).
- Restore page-level (sửa data page corruption).
- Restore từ Azure Blob (stripe và non-stripe).

## Tóm tắt 5 ý chính

1. **`Restore-DbaDatabase -Path <folder>`** đủ thông minh để quét thư mục, đọc header, tự sắp xếp Full → Diff → Log đúng LSN. DBA không cần tự ghép từng file.
2. **`-OutputScriptOnly`** sinh ra script `RESTORE DATABASE ...` để review / audit / chạy bằng tay. Đây là cách an toàn nhất khi học.
3. **Restore chain bằng `-NoRecovery` + `-Continue`** là pattern để xây log shipping standby thủ công: Full + Diff với NoRecovery, từng Log với Continue, cuối cùng restore với `WITH RECOVERY`.
4. **Point-in-time** có 2 cơ chế: `-RestoreTime <datetime>` (cần Log có cover thời điểm đó), hoặc `-StopMark <markname> -StopBefore` (transaction phải được mark trước khi commit).
5. **Page restore** chỉ áp dụng khi `Get-DbaSuspectPage` trả về corruption — dbatools tự lo restore từng page + apply log tail, DB vẫn ONLINE trong lúc xử lý.

## CẢNH BÁO trước khi chạy

`Restore-DbaDatabase` mặc định sẽ **GHI ĐÈ** DB cùng tên nếu có `-WithReplace`. Mọi lệnh dưới đây:
- **Luôn `-WhatIf` lần đầu** để xem dbatools dự định làm gì (file đích, kích thước, tên DB).
- KHÔNG chạy trên DB production. Lab dùng `WideWorldImporters` / `AdventureWorks2017` (restore lại được).
- Sau khi restore, kiểm tra DB ONLINE bằng `Get-DbaDatabase -SqlInstance dbatoolslab\sql2017 -Database <name>` và xem `Status`.

## Giải thích từng đoạn code

### Đoạn 1: dòng 18 — Restore cơ bản từ 1 file

```powershell
Restore-DbaDatabase -SqlInstance sql01 -Path S:\backups\pubs.bak
```

- **Ý nghĩa:** Restore DB từ `pubs.bak`. Tên DB lấy từ header (`pubs`). File `.mdf` / `.ldf` đi vào default data/log path của instance.
- **Đổi cho lab:**
  ```powershell
  Restore-DbaDatabase -SqlInstance dbatoolslab\sql2017 `
      -Path C:\dbatoolslab\Backup\WideWorldImporters-Full.bak -WhatIf
  ```
- **Lưu ý:** Nếu DB cùng tên đã tồn tại → lệnh FAIL. Thêm `-WithReplace` để ghi đè (mất data hiện tại). Trên lab nên rename:
  ```powershell
  Restore-DbaDatabase -SqlInstance dbatoolslab\sql2017 `
      -Path C:\dbatoolslab\Backup\WideWorldImporters-Full.bak `
      -DatabaseName WideWorldImporters_Restored -WhatIf
  ```

### Đoạn 2: dòng 23-24 — Pipe file vào restore

```powershell
Get-ChildItem \\nas\backups\mydb.bak |
Restore-DbaDatabase -SqlInstance sql01
```

- **Ý nghĩa:** Lấy `FileInfo` từ `Get-ChildItem`, pipe vào `Restore-DbaDatabase`. dbatools đọc `.FullName`.
- **Đổi cho lab:**
  ```powershell
  Get-ChildItem C:\dbatoolslab\Backup\WideWorldImporters-Full.bak |
      Restore-DbaDatabase -SqlInstance dbatoolslab\sql2017 -WhatIf
  ```

### Đoạn 3: dòng 28-42 — Backup chain rồi restore tất cả

```powershell
New-Item -Path 'C:\temp\sql' -Type Directory -Force
$splatGetDatabase = @{
    SqlInstance = "sql01"
    ExcludeDatabase = "tempdb", "master", "msdb"
}
$dbs = Get-DbaDatabase @splatGetDatabase
$dbs | Backup-DbaDatabase -Path C:\temp\sql -Type Full
$dbs | Backup-DbaDatabase -Path C:\temp\sql -Type Diff
$dbs | Backup-DbaDatabase -Path C:\temp\sql -Type Log
$dbs | Backup-DbaDatabase -Path C:\temp\sql -Type Log
$dbs | Backup-DbaDatabase -Path C:\temp\sql -Type Log

# See files, set the variable to $files, restore all files
Get-ChildItem -Path C:\temp\sql -OutVariable files
$files | Restore-DbaDatabase -SqlInstance sql01 -WithReplace
```

- **Ý nghĩa:** Chuẩn bị 1 chuỗi backup (1 Full, 1 Diff, 3 Log) cho TẤT CẢ user DB. Sau đó pipe tất cả `.bak/.trn` cho `Restore-DbaDatabase`. dbatools tự đọc header, sắp thứ tự, restore đúng chain.
- **CẢNH BÁO:**
  - `-WithReplace` **GHI ĐÈ** mọi DB cùng tên trên instance. Cực kỳ nguy hiểm nếu chạy nhầm instance.
  - Lệnh chạy chỉ với "user DB" (loại trừ `tempdb`, `master`, `msdb`) — đây là mặc định an toàn.
- **Đổi cho lab (an toàn):**
  ```powershell
  $backupDir = "C:\dbatoolslab\Backup\chain-demo"
  New-Item -ItemType Directory -Path $backupDir -Force | Out-Null

  # CHỈ chọn 1 DB cụ thể, không backup hàng loạt
  $db = Get-DbaDatabase -SqlInstance dbatoolslab\sql2017 -Database WideWorldImporters
  $db | Backup-DbaDatabase -Path $backupDir -Type Full -WhatIf
  $db | Backup-DbaDatabase -Path $backupDir -Type Diff -WhatIf
  $db | Backup-DbaDatabase -Path $backupDir -Type Log  -WhatIf
  # Bỏ -WhatIf sau khi xác nhận

  # Restore vào tên khác để không ghi đè bản gốc
  Get-ChildItem $backupDir | Restore-DbaDatabase -SqlInstance dbatoolslab\sql2017 `
      -DatabaseName WideWorldImporters_chain -ReplaceDbNameInFile -WhatIf
  ```

### Đoạn 4: dòng 46-52 — Sinh script restore (không chạy)

```powershell
$splatRestoreDatabase = @{
    SqlInstance = "sql01"
    Path = "C:\temp\sql\full.bak"
    WithReplace = $true
    OutputScriptOnly = $true
}
Restore-DbaDatabase @splatRestoreDatabase
```

- **Ý nghĩa:** In ra T-SQL `RESTORE DATABASE ...` cho ai muốn review trước khi chạy, hoặc đẩy vào Agent job.
- **Đổi cho lab:**
  ```powershell
  $splat = @{
      SqlInstance      = "dbatoolslab\sql2017"
      Path             = "C:\dbatoolslab\Backup\WideWorldImporters-Full.bak"
      DatabaseName     = "WWI_dryrun"
      OutputScriptOnly = $true
  }
  Restore-DbaDatabase @splat
  ```
- **Lưu ý:** An toàn 100% — không thực thi. KHÔNG cần `-WhatIf` cho biến thể này.

### Đoạn 5: dòng 56-62 — Restore đổi vị trí file vật lý

```powershell
$splatRestoreDb = @{
    SqlInstance = "sql01"
    Path = "\\nas\sql01\mydb01.bak"
    DestinationDataDirectory = "D:\data"
    DestinationLogDirectory = "L:\log"
}
Restore-DbaDatabase @splatRestoreDb
```

- **Ý nghĩa:** Backup gốc lưu `.mdf` ở `S:\data`, `.ldf` ở `T:\log`. Khi restore sang server mới mà chỉ có `D:\` và `L:\`, dùng `DestinationDataDirectory` / `DestinationLogDirectory` để override.
- **Đổi cho lab:**
  ```powershell
  $dataDir = "C:\dbatoolslab\TestRestore\Data"
  $logDir  = "C:\dbatoolslab\TestRestore\Log"
  New-Item -ItemType Directory -Path $dataDir, $logDir -Force | Out-Null

  $splat = @{
      SqlInstance              = "dbatoolslab\sql2017"
      Path                     = "C:\dbatoolslab\Backup\WideWorldImporters-Full.bak"
      DatabaseName             = "WWI_relocated"
      DestinationDataDirectory = $dataDir
      DestinationLogDirectory  = $logDir
  }
  Restore-DbaDatabase @splat -WhatIf
  ```
- **Lưu ý:** Service account của SQL phải có quyền `Modify` trên 2 directory này. Lab default đã có quyền cho `C:\dbatoolslab\*`.

### Đoạn 6: dòng 66-71 — Restore chain phần 1: Full + Diff với NoRecovery

```powershell
$splatRestoreDb = @{
    SqlInstance = "sql01"
    NoRecovery = $true
}
Restore-DbaDatabase @splatRestoreDb -Path C:\temp\sql\full.bak
Restore-DbaDatabase @splatRestoreDb -Path C:\temp\sql\diff.bak
```

- **Ý nghĩa:** Restore Full giữ DB ở trạng thái `RESTORING`, sau đó apply Diff cũng giữ `RESTORING`. Đây là bước 1 của log shipping manual.
- **Đổi cho lab:**
  ```powershell
  $splat = @{
      SqlInstance  = "dbatoolslab\sql2017"
      DatabaseName = "WWI_standby"
      NoRecovery   = $true
      WithReplace  = $true
  }
  Restore-DbaDatabase @splat -Path C:\dbatoolslab\Backup\chain-demo\WideWorldImporters-Full.bak -WhatIf
  Restore-DbaDatabase @splat -Path C:\dbatoolslab\Backup\chain-demo\WideWorldImporters-Diff.bak -WhatIf
  ```
- **Lưu ý:** Khi `-NoRecovery`, DB không query được — chỉ chờ apply tiếp Diff/Log. Nếu muốn read-only standby, dùng `-Standby <undofile>` thay vì `-NoRecovery`.

### Đoạn 7: dòng 75-80 — Restore chain phần 2: Log cuối + recover

```powershell
$splatRestoreDbFinal = @{
    SqlInstance = "sql01"
    Path = "C:\temp\sql\trans.trn"
    Continue = $true
}
Restore-DbaDatabase @splatRestoreDbFinal
```

- **Ý nghĩa:** `-Continue` báo dbatools rằng đây là phần tiếp của chain đang dang dở. Mặc định lệnh sẽ recover (đưa DB ONLINE) khi không có `-NoRecovery`.
- **Đổi cho lab:**
  ```powershell
  $splat = @{
      SqlInstance = "dbatoolslab\sql2017"
      Database    = "WWI_standby"
      Path        = "C:\dbatoolslab\Backup\chain-demo\WideWorldImporters-Log.trn"
      Continue    = $true
  }
  Restore-DbaDatabase @splat -WhatIf
  ```
- **Lưu ý:** Nếu muốn tiếp tục apply log nữa, phải lại thêm `-NoRecovery`. Khi đã recover, không thể apply log nữa.

### Đoạn 8: dòng 84-90 — Restore đổi tên DB

```powershell
$splatRestoreDbRename = @{
    SqlInstance = "sql01"
    Path = "C:\temp\sql\pubs.bak"
    DatabaseName = "Pestering"
    ReplaceDbNameInFile = $true
}
Restore-DbaDatabase @splatRestoreDbRename
```

- **Ý nghĩa:** Backup gốc là `pubs`, restore thành `Pestering`. `-ReplaceDbNameInFile` rename luôn file `.mdf/.ldf` cho khớp — tránh nhầm lẫn khi quản lý.
- **Đổi cho lab:**
  ```powershell
  $splat = @{
      SqlInstance         = "dbatoolslab\sql2017"
      Path                = "C:\dbatoolslab\Backup\WideWorldImporters-Full.bak"
      DatabaseName        = "WWI_test_$(Get-Date -Format yyyyMMdd)"
      ReplaceDbNameInFile = $true
  }
  Restore-DbaDatabase @splat -WhatIf
  ```
- **Lưu ý:** Nếu không có `-ReplaceDbNameInFile`, file vật lý vẫn tên gốc — bạn sẽ có DB `Pestering` nhưng file `pubs.mdf`. Khó đọc trên ổ đĩa.

### Đoạn 9: dòng 94-99 — Point-in-time restore bằng timestamp

```powershell
$splatRestoreDbContinue = @{
    SqlInstance = "sql01"
    Path = "\\nas\sql\sql01\mydb"
    RestoreTime = (Get-Date "2019-05-02 21:12:27")
}
Restore-DbaDatabase @splatRestoreDbContinue
```

- **Ý nghĩa:** Quét thư mục, xác định Full mới nhất trước thời điểm `RestoreTime`, áp Diff/Log đến đúng giây yêu cầu. Lệnh tự dừng giữa chuỗi Log nếu cần (STOPAT).
- **Đổi cho lab:** Cần có sẵn 1 Full + Log với khoảng thời gian hợp lý:
  ```powershell
  $stopAt = Get-Date # lấy thời điểm hiện tại
  Backup-DbaDatabase -SqlInstance dbatoolslab\sql2017 -Database WideWorldImporters `
      -Path C:\dbatoolslab\Backup\pit -Type Log -WhatIf

  $splat = @{
      SqlInstance  = "dbatoolslab\sql2017"
      Path         = "C:\dbatoolslab\Backup\pit"
      RestoreTime  = $stopAt
      DatabaseName = "WWI_pit"
      WithReplace  = $true
  }
  Restore-DbaDatabase @splat -WhatIf
  ```
- **Lưu ý:** PIT chỉ áp dụng cho DB recovery model FULL hoặc BULK_LOGGED. SIMPLE không có Log backup.

### Đoạn 10: dòng 103-118 — Restore tới named MARK (rollback trước DELETE)

```powershell
$splatRestoreDb = @{
    SqlInstance = "sql01"
    Database = "pubs"
    FilePath = "C:\temp\full.bak"
}
Backup-DbaDatabase @splatRestoreDb

# Restore to the point right before the delete was executed
$splatRestoreDbMark = @{
    SqlInstance = "sql01"
    Path = "C:\temp\full.bak"
    StopMark = "DeleteCandidates"
    StopBefore = $true
    WithReplace = $true
}
Restore-DbaDatabase @splatRestoreDbMark
```

- **Ý nghĩa:** Trước khi chạy lệnh DELETE nguy hiểm, app dùng `BEGIN TRAN DeleteCandidates WITH MARK 'before purge'; ... ; COMMIT`. Khi cần rollback, restore với `-StopMark "DeleteCandidates" -StopBefore` đưa DB về NGAY TRƯỚC MARK đó.
- **Đổi cho lab (demo):**
  ```sql
  -- Tạo mark thử trong WideWorldImporters
  USE WideWorldImporters;
  BEGIN TRAN MarkSample WITH MARK 'before test'
  -- INSERT/UPDATE gì đó để có thay đổi
  COMMIT
  ```
  ```powershell
  # Backup log để có Log chứa mark
  Backup-DbaDatabase -SqlInstance dbatoolslab\sql2017 -Database WideWorldImporters `
      -Path C:\dbatoolslab\Backup\mark-demo -Type Log

  # Restore lùi về trước mark
  $splat = @{
      SqlInstance  = "dbatoolslab\sql2017"
      Path         = "C:\dbatoolslab\Backup\mark-demo"
      StopMark     = "MarkSample"
      StopBefore   = $true
      DatabaseName = "WWI_rolledback"
      WithReplace  = $true
  }
  Restore-DbaDatabase @splat -WhatIf
  ```
- **Lưu ý:** Mark chỉ áp dụng cho transaction `WITH MARK 'name'`. Không phải mọi transaction đều có mark — đây là pattern lập trình defensive cho ETL.

### Đoạn 11: dòng 122-129 — Page restore (sửa corruption)

```powershell
$corruption = Get-DbaSuspectPage -SqlInstance sql01 -Database pubs
$splatRestoreDbPage = @{
    SqlInstance = "sql01"
    Path = "\\nas\backups\sql\pubs.bak"
    PageRestore = $corruption
    PageRestoreTailFolder = "c:\temp"
}
Restore-DbaDatabase @splatRestoreDbPage
```

- **Ý nghĩa:** `Get-DbaSuspectPage` đọc `msdb.dbo.suspect_pages`. Nếu có row → có page corruption. `Restore-DbaDatabase` sẽ:
  1. Backup tail-log vào `PageRestoreTailFolder`.
  2. Restore từng page bị hỏng từ Full backup.
  3. Apply lại Log để bring forward.
  DB vẫn ONLINE trong suốt quá trình (Enterprise Edition).
- **Đổi cho lab:** Lab thường KHÔNG có corruption — `Get-DbaSuspectPage` trả empty. Đoạn này coi như đọc hiểu. Nếu cố tình test, dùng `DBCC WRITEPAGE` trên DB throwaway (cần trace flag).
- **CẢNH BÁO:** Page restore chỉ hoạt động trên Enterprise/Developer edition cho DB online. Standard edition phải offline → khôi phục từ full.

### Đoạn 12: dòng 133-137 — Restore từ Azure Blob (URL backup)

```powershell
$splatRestoreDbFromAzure = @{
    SqlInstance = "sql01"
    Path = "https://acmecorp.blob.core.windows.net/backups/mydb.bak"
}
Restore-DbaDatabase @splatRestoreDbFromAzure
```

- **Ý nghĩa:** SQL có thể restore trực tiếp từ blob URL. Cần SQL credential (đã setup ở chapter 10).
- **Đổi cho lab:** Lab không có Azure → coi như đọc hiểu. Nếu có:
  ```powershell
  # Đảm bảo đã có credential trùng URL container (chapter 10)
  Restore-DbaDatabase -SqlInstance dbatoolslab\sql2017 `
      -Path "https://yourstorage.blob.core.windows.net/backups/WWI.bak" -WhatIf
  ```

### Đoạn 13: dòng 141-144 — Restore từ stripe (3 file trên Azure)

```powershell
$stripe = "https://acmecorp.blob.core.windows.net/backups/mydb-1.bak",
"https://acmecorp.blob.core.windows.net/backups/mydb-2.bak",
"https://acmecorp.blob.core.windows.net/backups/mydb-3.bak"
$stripe | Restore-DbaDatabase -SqlInstance sql01
```

- **Ý nghĩa:** Backup striped (chia 3 file song song) tăng throughput. Restore cần tất cả các file — pipe mảng URL vào lệnh.
- **Đổi cho lab (local stripe):**
  ```powershell
  $stripeFiles = "C:\dbatoolslab\Backup\WWI-1.bak",
                 "C:\dbatoolslab\Backup\WWI-2.bak",
                 "C:\dbatoolslab\Backup\WWI-3.bak"
  $stripeFiles | Restore-DbaDatabase -SqlInstance dbatoolslab\sql2017 `
      -DatabaseName WWI_stripe -WithReplace -WhatIf
  ```

### Đoạn 14: dòng 148-153 — Restore từ Azure với Access Key

```powershell
$splatRestoreDbFromAzureAK = @{
    SqlInstance = "sql01"
    Path = "https://acmecorp.blob.core.windows.net/backups/mydb.bak"
    AzureCredential = "AzureAccessKey"
}
Restore-DbaDatabase @splatRestoreDbFromAzureAK
```

- **Ý nghĩa:** Tương tự nhưng dùng credential kiểu Access Key (legacy, đã giải thích ở chapter 10 đoạn 6).
- **Lưu ý:** Nếu mới deploy, dùng SAS thay vì Access Key.

## Lệnh thay vào lab của bạn

```powershell
# ============================================================
# Pre-req: đã có backup trong C:\dbatoolslab\Backup (chapter 10)
# ============================================================
$backupRoot = "C:\dbatoolslab\Backup"
$instance   = "dbatoolslab\sql2017"
$restoreData = "C:\dbatoolslab\TestRestore\Data"
$restoreLog  = "C:\dbatoolslab\TestRestore\Log"
New-Item -ItemType Directory -Path $restoreData, $restoreLog -Force | Out-Null

# ============================================================
# 1) Restore 1 file an toàn — đổi tên DB để không đè
# ============================================================
$fullBak = Get-ChildItem $backupRoot -Filter "WideWorldImporters*Full*.bak" |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1

$splat1 = @{
    SqlInstance              = $instance
    Path                     = $fullBak.FullName
    DatabaseName             = "WWI_restored_$(Get-Date -Format yyyyMMdd)"
    DestinationDataDirectory = $restoreData
    DestinationLogDirectory  = $restoreLog
    ReplaceDbNameInFile      = $true
}
Restore-DbaDatabase @splat1 -WhatIf
# Sau khi -WhatIf in đúng dự định, bỏ -WhatIf

# ============================================================
# 2) Restore CHỈ in script (an toàn tuyệt đối)
# ============================================================
Restore-DbaDatabase @splat1 -OutputScriptOnly

# ============================================================
# 3) Chain restore: Full -> Diff -> Log (NoRecovery -> Continue)
# ============================================================
# Giả sử có C:\dbatoolslab\Backup\chain với .bak/.trn theo thứ tự
$chainDir = "$backupRoot\chain"
if (Test-Path $chainDir) {
    # Step 1: Full + Diff với NoRecovery
    Restore-DbaDatabase -SqlInstance $instance `
        -Path "$chainDir\WideWorldImporters-Full.bak" `
        -DatabaseName WWI_chain -NoRecovery -WithReplace `
        -DestinationDataDirectory $restoreData -DestinationLogDirectory $restoreLog -WhatIf

    Restore-DbaDatabase -SqlInstance $instance `
        -Path "$chainDir\WideWorldImporters-Diff.bak" `
        -Database WWI_chain -NoRecovery -Continue -WhatIf

    # Step 2: Log cuối với recover
    Restore-DbaDatabase -SqlInstance $instance `
        -Path "$chainDir\WideWorldImporters-Log.trn" `
        -Database WWI_chain -Continue -WhatIf
}

# ============================================================
# 4) Point-in-time tới 5 phút trước
# ============================================================
Restore-DbaDatabase -SqlInstance $instance `
    -Path $chainDir `
    -DatabaseName WWI_pit `
    -RestoreTime (Get-Date).AddMinutes(-5) `
    -WithReplace `
    -DestinationDataDirectory $restoreData -DestinationLogDirectory $restoreLog `
    -WhatIf

# ============================================================
# 5) Kiểm tra DB sau khi restore
# ============================================================
Get-DbaDatabase -SqlInstance $instance |
    Where-Object Name -like "WWI_*" |
    Select-Object Name, Status, RecoveryModel, CreateDate
```

## Self-check (3 câu)

1. **Định nghĩa:** Tham số nào của `Restore-DbaDatabase` bắt buộc khi DB đích đã tồn tại? Khi nào KHÔNG nên dùng tham số đó?
2. **Thực hành:** Chạy restore với `-OutputScriptOnly`, đếm số câu `RESTORE ... WITH NORECOVERY` trong output. Vì sao tất cả trừ câu cuối đều có `NORECOVERY`?
3. **Liên hệ:** Khác biệt nghiệp vụ giữa `-RestoreTime` (PIT bằng datetime) và `-StopMark -StopBefore` (PIT bằng named mark) là gì? Trường hợp nào chỉ mark giải quyết được, datetime không?

## Bài tập mở rộng

- **Bài 1:** Viết hàm `Invoke-LabRestoreDryRun` nhận đường dẫn backup folder + tên DB đích, in ra script T-SQL bằng `-OutputScriptOnly`, lưu vào file `.sql` có timestamp. Dùng cho audit trail.
- **Bài 2:** Demo "restore tới ngay trước transaction xấu" — tạo mark trong WideWorldImporters bằng `BEGIN TRAN ... WITH MARK`, làm 1 thay đổi nhỏ, backup log, rồi restore với `-StopMark -StopBefore` ra DB khác. Verify thay đổi đã bị rollback.
- **Bài 3:** Viết script kiểm tra "DR readiness" — với mỗi user DB trên `dbatoolslab\sql2017`, đếm số backup mới nhất trong `C:\dbatoolslab\Backup` và print RPO (recovery point objective) thực tế. Cảnh báo nếu Log gần nhất > 1 giờ.


---

!!! info "Nguồn gốc"
    `book_lab/dbatools-lab/bookcode/chapter11.notes.md`
