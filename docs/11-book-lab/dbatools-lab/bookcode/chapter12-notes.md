---
title: Chapter 12 — Database snapshot (tạo, restore, xoá)
course: 11-book-lab
source: book_lab/dbatools-lab/bookcode/chapter12.notes.md
---

# Chapter 12 — Database snapshot (tạo, restore, xoá)

> Lưu ý: User mapping gọi chapter 12 là "Restore operations & snapshots", nhưng nội dung thực tế của `chapter12.ps1` **chỉ tập trung vào DB snapshot** (`New-DbaDbSnapshot`, `Restore-DbaDbSnapshot`, `Remove-DbaDbSnapshot`, `Get-DbaDbSnapshot`). Restore database thông thường đã ở chapter 11. Notes này theo nội dung file thực tế (rất ngắn — chỉ ~36 dòng).

## Mục tiêu

- Hiểu DB snapshot là gì, khi nào dùng (testing, refresh dữ liệu nhanh, rollback transaction ETL).
- Tạo snapshot bằng `New-DbaDbSnapshot`.
- Restore (revert) DB về trạng thái snapshot bằng `Restore-DbaDbSnapshot`.
- Đảm bảo không có connection còn sống trước khi revert (`Stop-DbaProcess`).
- Dọn snapshot khi không còn cần (`Remove-DbaDbSnapshot`).

## Tóm tắt 5 ý chính

1. **DB snapshot là "ảnh tĩnh read-only"** của DB tại một thời điểm. Cơ chế copy-on-write: SQL chỉ ghi vào snapshot những page bị thay đổi trong DB gốc kể từ lúc snapshot.
2. **Snapshot dung lượng nhỏ ban đầu** (chỉ chứa NTFS sparse file), nhưng phình ra khi DB gốc bị sửa đổi nhiều. Theo dõi `Get-DbaDbFile` cho file snapshot.
3. **`Restore-DbaDbSnapshot` revert** DB gốc về trạng thái snapshot — **xoá tất cả thay đổi** sau lúc snapshot. Đây là rollback toàn DB siêu nhanh (không restore từ `.bak`).
4. **Phải kill connection trước khi revert** — `Stop-DbaProcess` (hoặc thủ công `KILL spid`). Connection đang dùng DB sẽ block revert.
5. **Giới hạn:** Edition Enterprise/Developer. DB gốc không được FILESTREAM container, không được Memory-Optimized table (SQL 2014+). Không thay thế backup cho DR — snapshot phụ thuộc DB gốc, mất DB gốc → mất snapshot.

## CẢNH BÁO trước khi chạy

- `New-DbaDbSnapshot` an toàn (chỉ tạo file), nhưng vẫn `-WhatIf` lần đầu để biết file `.ss` sẽ vào đâu.
- `Restore-DbaDbSnapshot` **PHÁ HUỶ THAY ĐỔI** trên DB gốc — không thể undo. Luôn `-WhatIf`.
- `Remove-DbaDbSnapshot` xoá snapshot — nếu DB gốc cần revert, mất snapshot là mất cơ hội. `-WhatIf` trước.
- Snapshot KHÔNG phải backup. Vẫn phải `Backup-DbaDatabase` bình thường.

## Giải thích từng đoạn code

### Đoạn 1: dòng 18 — Tạo snapshot

```powershell
New-DbaDbSnapshot -SqlInstance mssql1 -Database AdventureWorks
```

- **Ý nghĩa:** Tạo snapshot cho DB `AdventureWorks`. Tên snapshot tự sinh dạng `AdventureWorks_snap_<timestamp>` hoặc tương tự. File `.ss` đặt cạnh `.mdf` gốc theo mặc định.
- **Đổi cho lab:**
  ```powershell
  New-DbaDbSnapshot -SqlInstance dbatoolslab\sql2017 -Database AdventureWorks2017 -WhatIf
  ```
  Sau khi xác nhận output, bỏ `-WhatIf`. Mặc định file snapshot ghi cùng folder data của DB gốc — kiểm tra:
  ```powershell
  Get-DbaDbFile -SqlInstance dbatoolslab\sql2017 -Database AdventureWorks2017 |
      Select-Object LogicalName, PhysicalName
  ```
- **Tham số hữu ích:**
  - `-Name <string>` — đặt tên cụ thể (vd `AdventureWorks2017_beforeETL`).
  - `-Path <folder>` — chỉ định folder lưu snapshot (file `.ss`).
- **Lưu ý:** SQL 2017 Standard cũng tạo được snapshot trong nhiều ngữ cảnh, nhưng REVERT thì chỉ trên Enterprise/Developer. Kiểm tra edition: `Get-DbaInstanceProperty -SqlInstance dbatoolslab\sql2017 -InstanceProperty Edition`.

### Đoạn 2: dòng 22-28 — Revert DB về snapshot

```powershell
Get-DbaProcess -SqlInstance mssql1 -Database AdventureWorks |
    Stop-DbaProcess
$splatRestoreSnapshot = @{
    SqlInstance = "mssql1"
    Snapshot = "AdventureWorks_20210530_071605"
}
Restore-DbaDbSnapshot @splatRestoreSnapshot
```

- **Ý nghĩa:** Hai bước:
  1. Liệt kê process đang dùng DB → kill hết (không có connection nào còn dùng DB).
  2. Revert DB gốc về snapshot. SQL thay nội dung DB gốc bằng nội dung snapshot.
- **Đổi cho lab:**
  ```powershell
  $instance = "dbatoolslab\sql2017"
  $snapName = (Get-DbaDbSnapshot -SqlInstance $instance -Database AdventureWorks2017 |
      Sort-Object CreateDate -Descending | Select-Object -First 1).Name

  # Kill mọi session đang dùng DB
  Get-DbaProcess -SqlInstance $instance -Database AdventureWorks2017 |
      Stop-DbaProcess -WhatIf
  # Sau khi check, bỏ -WhatIf

  # Revert
  $splat = @{
      SqlInstance = $instance
      Snapshot    = $snapName
  }
  Restore-DbaDbSnapshot @splat -WhatIf
  # Sau khi -WhatIf in đúng snapshot đích, bỏ -WhatIf
  ```
- **CẢNH BÁO CỰC MẠNH:**
  - Sau revert: **mọi thay đổi trong DB gốc sau snapshot bị MẤT**. Không có undo.
  - Tất cả snapshot KHÁC của cùng DB bị DROP tự động — chỉ snapshot dùng để revert được giữ lại.
  - Log chain bị ngắt — phải backup Full ngay sau revert nếu muốn point-in-time tiếp.
- **Lưu ý:** Tên snapshot trong code book là `AdventureWorks_20210530_071605` (timestamp 30/05/2021 07:16:05) — đây là kiểu mặc định khi không đặt `-Name`. Trong lab bạn phải tra tên thật trước.

### Đoạn 3: dòng 32-33 — Xoá snapshot

```powershell
Get-DbaDbSnapshot -SqlInstance mssql1 -Database AdventureWorks |
    Remove-DbaDbSnapshot
```

- **Ý nghĩa:** Lấy mọi snapshot của DB → pipe vào xoá. Sau khi xoá, file `.ss` được giải phóng.
- **Đổi cho lab:**
  ```powershell
  Get-DbaDbSnapshot -SqlInstance dbatoolslab\sql2017 -Database AdventureWorks2017 |
      Remove-DbaDbSnapshot -WhatIf
  # Bỏ -WhatIf khi chắc chắn không cần revert nữa
  ```
- **Lưu ý:**
  - `Remove-DbaDbSnapshot` PROMPT confirmation mặc định (`SupportsShouldProcess`). Thêm `-Confirm:$false` nếu chạy trong script tự động.
  - Lab có ít DB — chạy `Get-DbaDbSnapshot -SqlInstance dbatoolslab\sql2017` (không truyền `-Database`) để liệt kê tất cả snapshot trên instance, đảm bảo không sót.

### Dòng 36-37 — file kết thúc

File `chapter12.ps1` chỉ có 36 dòng — kết thúc sau `Remove-DbaDbSnapshot`. Không có demo nâng cao như nested snapshot hay snapshot cho TempDB (vốn không hỗ trợ).

## Lệnh thay vào lab của bạn

```powershell
# ============================================================
# Pre-req: AdventureWorks2017 đã restore vào dbatoolslab\sql2017
# (xem scripts\02_Configure_Lab.ps1)
# ============================================================
$instance = "dbatoolslab\sql2017"
$db       = "AdventureWorks2017"

# ============================================================
# 1) Xem DB và file hiện tại
# ============================================================
Get-DbaDatabase -SqlInstance $instance -Database $db |
    Select-Object Name, Status, RecoveryModel, Owner
Get-DbaDbFile -SqlInstance $instance -Database $db |
    Select-Object LogicalName, PhysicalName, Size

# ============================================================
# 2) Tạo snapshot có tên rõ ràng — LUÔN -WhatIf
# ============================================================
$snapName = "${db}_beforeETL_$(Get-Date -Format yyyyMMdd_HHmmss)"
New-DbaDbSnapshot -SqlInstance $instance -Database $db -Name $snapName -WhatIf
# Sau khi -WhatIf in OK, bỏ -WhatIf

# Xác nhận snapshot đã tạo
Get-DbaDbSnapshot -SqlInstance $instance -Database $db |
    Select-Object Name, CreateDate, Status

# ============================================================
# 3) Demo: thay đổi data trên DB gốc, rồi revert về snapshot
# ============================================================
# (a) Tạo thay đổi
Invoke-DbaQuery -SqlInstance $instance -Database $db `
    -Query "SELECT TOP 5 BusinessEntityID FROM Person.Person ORDER BY BusinessEntityID"

Invoke-DbaQuery -SqlInstance $instance -Database $db `
    -Query "UPDATE TOP (5) Person.Person SET FirstName = 'CHANGED_' + FirstName"

# (b) Xác nhận thay đổi
Invoke-DbaQuery -SqlInstance $instance -Database $db `
    -Query "SELECT TOP 5 FirstName FROM Person.Person WHERE FirstName LIKE 'CHANGED_%'"

# (c) Kill connection đang dùng
Get-DbaProcess -SqlInstance $instance -Database $db |
    Stop-DbaProcess -WhatIf
# Bỏ -WhatIf khi chắc

# (d) Revert
Restore-DbaDbSnapshot -SqlInstance $instance -Snapshot $snapName -WhatIf
# Bỏ -WhatIf khi chắc — KHÔNG UNDO ĐƯỢC

# (e) Verify đã revert
Invoke-DbaQuery -SqlInstance $instance -Database $db `
    -Query "SELECT COUNT(*) AS ChangedRows FROM Person.Person WHERE FirstName LIKE 'CHANGED_%'"
# Phải là 0 nếu revert thành công

# ============================================================
# 4) Dọn snapshot khi xong
# ============================================================
# Lưu ý: Sau khi revert, dbatools/SQL có thể đã drop snapshot tự động.
# Lệnh dưới chỉ xoá nếu còn:
Get-DbaDbSnapshot -SqlInstance $instance -Database $db |
    Remove-DbaDbSnapshot -WhatIf
# Bỏ -WhatIf để xoá thật

# ============================================================
# 5) Backup ngay sau revert (log chain đã đứt)
# ============================================================
Backup-DbaDatabase -SqlInstance $instance -Database $db `
    -Path C:\dbatoolslab\Backup -Type Full -CompressBackup -WhatIf
```

## Self-check (3 câu)

1. **Định nghĩa:** Trên SQL Server Enterprise, sau khi `Restore-DbaDbSnapshot` revert thành công, trạng thái log chain của DB gốc ra sao? Phải làm gì tiếp theo để đảm bảo có thể point-in-time?
2. **Thực hành:** Tạo 2 snapshot liên tiếp (snap1, snap2) cho `AdventureWorks2017`. Revert về snap1. Snap2 còn không? Vì sao?
3. **Liên hệ:** Snapshot khác backup ở 3 điểm — kể tên (gợi ý: phụ thuộc DB gốc, dung lượng, thời gian tạo).

## Bài tập mở rộng

- **Bài 1:** Viết hàm `Invoke-LabSafeETL` nhận tên DB + scriptblock ETL. Logic:
  1. Tạo snapshot `_pre_<timestamp>`.
  2. Chạy scriptblock ETL.
  3. Nếu lỗi → tự revert về snapshot, ném exception.
  4. Nếu OK → drop snapshot.
  Dùng `try/catch/finally`.
- **Bài 2:** Demo "snapshot làm read-only reporting source":
  - Tạo snapshot `AdventureWorks2017_reporting_<date>`.
  - Query snapshot (không phải DB gốc) bằng `Invoke-DbaQuery -Database AdventureWorks2017_reporting_<date>`.
  - Quan sát: query vào snapshot không bị block bởi UPDATE đang chạy ở DB gốc.
- **Bài 3:** Đo "snapshot growth" — tạo snapshot, chạy 100k INSERT vào DB gốc, theo dõi kích thước file `.ss` mỗi 30s bằng `Get-DbaDbFile`. Vẽ biểu đồ growth bằng PowerShell `Out-Chart` (module `PSGraph`) hoặc xuất CSV cho Excel.


---

!!! info "Nguồn gốc"
    `book_lab/dbatools-lab/bookcode/chapter12.notes.md`
