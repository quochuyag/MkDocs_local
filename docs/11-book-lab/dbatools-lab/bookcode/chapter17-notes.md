---
title: Chapter 17 — Log Shipping và High Availability cơ bản
course: 11-book-lab
source: book_lab/dbatools-lab/bookcode/chapter17.notes.md
---

# Chapter 17 — Log Shipping và High Availability cơ bản

## Mục tiêu
- Hiểu cơ chế log shipping: full backup ban đầu + chuỗi log backup ship liên tục từ primary sang secondary.
- Dùng `Invoke-DbaDbLogShipping` để thiết lập log shipping toàn bộ pipeline trong một lệnh.
- Theo dõi lỗi log shipping bằng `Get-DbaDbLogShipError`.
- Thực hiện cutover (đưa secondary online thành primary mới) bằng `Invoke-DbaDbLogShipRecovery`.
- Bước đầu làm quen với Availability Group: tạo AG bằng `New-DbaAvailabilityGroup`, kiểm tra với `Get-DbaAvailabilityGroup`, `Get-DbaAgReplica`, `Get-DbaAgDatabase`, failover bằng `Invoke-DbaAgFailover`, suspend/resume data movement.
- Biết các cmdlet WSFC cluster (`Get-DbaWsfcNode`, `Get-DbaWsfcResource`).

## Tóm tắt 3-5 ý chính
1. **Log shipping = full + log chain liên tục** — primary backup log đều đặn, ship qua share, secondary restore với `NORECOVERY`. Đến lúc cutover thì `RESTORE...WITH RECOVERY`.
2. **`Invoke-DbaDbLogShipping` orchestrates** — tạo job backup, job copy, job restore, lịch chạy, monitor instance — chỉ cần `Source`, `Destination`, `Database`, `SharedPath`.
3. **`Get-DbaDbLogShipError` để giám sát** — chuỗi log shipping dễ "đứt" (file path sai, permission, backup file bị xoá). Cmdlet này đọc log table `msdb.dbo.log_shipping_monitor_error_detail`.
4. **`Invoke-DbaDbLogShipRecovery` là nút cutover** — apply log cuối cùng và recover DB. Chạy được trên cả batch nhiều DB.
5. **AG là tiến hoá của log shipping** — synchronous/async replicas, automatic failover qua WSFC. dbatools có cả họ `*-DbaAg*` để quản lý AG end-to-end.

## Giải thích từng đoạn code

### Đoạn 1: dòng 18-24 — Log shipping cho một database
```powershell
$params = @{
    SourceSqlInstance      = "dbatoolslab\sql2017"
    DestinationSqlInstance = "dbatoolslab"
    Database               = "AdventureWorks"
    SharedPath             = "\\dbatoolslab\logship"
}
Invoke-DbaDbLogShipping @params
```
- **Ý nghĩa:** Thiết lập log shipping cho `AdventureWorks` từ named instance `dbatoolslab\sql2017` (primary) sang default instance `dbatoolslab` (secondary). dbatools tạo:
  - Backup share folder
  - Full backup ban đầu trên `SharedPath`
  - Restore full vào secondary với `NORECOVERY`
  - 3 Agent job: Backup, Copy, Restore — chạy định kỳ
  - Cấu hình monitor instance.
- **Đổi cho lab:** Đoạn này đã đúng cho lab. Đảm bảo folder `\\dbatoolslab\logship` (hoặc local path `C:\dbatoolslab\logship`) tồn tại và cả hai SQL service account đọc/ghi được.
- **Lưu ý:** **CẢNH BÁO** — sau khi chạy, DB ở secondary sẽ ở trạng thái `STANDBY/READ-ONLY` hoặc `RESTORING`. Application không kết nối được vào secondary để ghi cho đến khi recovery. Backup target trước nếu DB cùng tên đã tồn tại — `-Force` sẽ overwrite.

### Đoạn 2: dòng 29-35 — Log shipping nhiều database
```powershell
$params = @{
    SourceSqlInstance      = "dbatoolslab\sql2017"
    DestinationSqlInstance = "dbatoolslab"
    Database               = "AdventureWorks","WideWorldImporters"
    SharedPath             = "\\dbatoolslab\logship"
}
Invoke-DbaDbLogShipping @params
```
- **Ý nghĩa:** Cùng pattern nhưng truyền mảng `-Database`. dbatools loop qua từng DB, mỗi DB có bộ job riêng. Tất cả dùng chung share.
- **Đổi cho lab:** Đã phù hợp. Đảm bảo recovery model của `WideWorldImporters` là `FULL` (log shipping yêu cầu `FULL` hoặc `BULK_LOGGED`).
- **Lưu ý:** **CẢNH BÁO** — log shipping nhiều DB tạo nhiều Agent job. Dễ làm Agent quá tải nếu instance nhỏ. Cân nhắc lịch staggered.

### Đoạn 3: dòng 39-40 — Theo dõi lỗi log shipping
```powershell
Get-DbaDbLogShipError -SqlInstance dbatoolslab\sql2017, dbatoolslab |
Select-Object SqlInstance, LogTime, Message
```
- **Ý nghĩa:** Đọc lỗi từ monitor table trên cả primary và secondary, hiển thị thời gian + thông báo. Dùng để debug khi DB không cập nhật.
- **Đổi cho lab:** Dùng nguyên.
- **Lưu ý:** Không có output = không có lỗi (tốt). Trên môi trường thật nên có alert email khi `Get-DbaDbLogShipError` trả về row.

### Đoạn 4: dòng 46-50 — Cutover một database
```powershell
$logShipSplat = @{
    SqlInstance = "dbatoolslab"
    Database    = "AdventureWorks"
}
Invoke-DbaDbLogShipRecovery @logShipSplat
```
- **Ý nghĩa:** Trên secondary, apply log cuối cùng và `RESTORE WITH RECOVERY` — DB chuyển từ `STANDBY/RESTORING` sang `ONLINE`, sẵn sàng nhận write.
- **Đổi cho lab:** Đã đúng. Sau lệnh này, `AdventureWorks` trên `dbatoolslab` (cũ secondary) trở thành DB chính.
- **Lưu ý:** **CẢNH BÁO CỰC MẠNH** — đây là điểm "không quay lại" của log shipping. Sau khi recover, không thể tiếp tục ship log từ primary cũ. Phải coordinate cutover với application team. Nếu cần rollback, phải re-seed log shipping ngược chiều.

### Đoạn 5: dòng 55-59 — Cutover nhiều database
```powershell
$logShipSplat = @{
    SqlInstance = "dbatoolslab"
    Database    = "AdventureWorks","WideWorldImporters"
}
Invoke-DbaDbLogShipRecovery @logShipSplat
```
- **Ý nghĩa:** Cutover hàng loạt. Đặt một transaction window, recover tất cả DB cùng lúc.
- **Đổi cho lab:** Đã đúng.
- **Lưu ý:** **CẢNH BÁO** — nếu một DB recover lỗi, các DB còn lại trong list vẫn tiếp tục được xử lý (dbatools không atomic). Kiểm tra `Get-DbaDatabase` sau cutover xem có DB nào vẫn ở `RESTORING`.

### Đoạn 6: dòng 63 — Liệt kê cmdlet WSFC
```powershell
Get-Command *wsfc* -Module dbatools
```
- **Ý nghĩa:** List các cmdlet liên quan Windows Server Failover Cluster (`Get-DbaWsfcCluster`, `Get-DbaWsfcNode`, `Get-DbaWsfcResource`, ...). Dùng để inventory cluster mà không cần đăng nhập từng node.
- **Đổi cho lab:** Chạy nguyên (read-only).
- **Lưu ý:** Lab không có cluster — cmdlet này sẽ fail nếu chạy thật. Chỉ để biết.

### Đoạn 7: dòng 68 — Xem node trong cluster
```powershell
Get-DbaWsfcNode -ComputerName sql1
```
- **Ý nghĩa:** Trả về danh sách node trong WSFC mà `sql1` đang tham gia, state (Up/Down/Paused), version.
- **Đổi cho lab:** Lab không có cluster → bỏ qua hoặc chỉ đọc help.
- **Lưu ý:** Yêu cầu remote PowerShell + quyền admin trên cluster.

### Đoạn 8: dòng 73-75 — Xem resource cluster
```powershell
Get-DbaWsfcResource -ComputerName sql1 |
Select-Object ClusterName, Name, State, Type, OwnerGroup, OwnerNode |
Format-Table
```
- **Ý nghĩa:** Liệt kê resource (SQL Server, IP, Network Name, listener AG...) trong cluster, ai đang sở hữu node nào. Báo cáo quick health.
- **Đổi cho lab:** Bỏ qua.
- **Lưu ý:** Dùng `Format-Table` để output gọn — luôn đặt cuối pipeline.

### Đoạn 9: dòng 80-88 — Tạo Availability Group
```powershell
$agSplat = @{
    Primary     = "sql1"
    Secondary   = "sql2"
    Name        = "agpoc01"
    Database    = "AdventureWorks"
    ClusterType = "Wsfc"
    SharedPath  = "\\sql1\backup"
}
New-DbaAvailabilityGroup @agsplat
```
- **Ý nghĩa:** Tạo AG có tên `agpoc01` với primary `sql1`, secondary `sql2`, một DB `AdventureWorks`. dbatools tự seed DB sang secondary qua `SharedPath`. `ClusterType = "Wsfc"` cho cluster Windows truyền thống (cũng có `"None"` cho cluster-less AG ở SQL 2017+).
- **Đổi cho lab:** **Lab không hỗ trợ AG full** vì cần WSFC. Có thể thử `ClusterType = "None"` trên SQL 2017 nếu lab có hai instance trên hai host khác nhau — nhưng instance trong cùng container thì không.
- **Lưu ý:** **CẢNH BÁO RẤT NGHIÊM TRỌNG** — `New-DbaAvailabilityGroup` thay đổi cấu hình cả hai instance, tạo endpoint mirroring, listener, certificate. Phải `-WhatIf` trước, có change ticket, backup cả primary lẫn secondary. Lệnh trong sách còn lỗi case: `@agsplat` (s thường) khác `$agSplat` (S hoa) — PowerShell case-insensitive nên vẫn chạy, nhưng cẩn thận khi copy.

### Đoạn 10: dòng 93-94 — Kết nối instance
```powershell
$sql1 = Connect-DbaInstance -SqlInstance = "sql01,15592" -SqlCredential sa
$sql1
```
- **Ý nghĩa:** Tạo object connection reuse. `sql01,15592` là `host,port`. **Lưu ý lỗi syntax sách:** `-SqlInstance = "sql01,15592"` có `=` thừa, đúng là `-SqlInstance "sql01,15592"`.
- **Đổi cho lab:** `$conn = Connect-DbaInstance -SqlInstance dbatoolslab\sql2017`.
- **Lưu ý:** Reuse `$sql1` qua nhiều cmdlet tiết kiệm việc mở connection lại.

### Đoạn 11: dòng 99 — Liệt kê AG
```powershell
Get-DbaAvailabilityGroup -SqlInstance $sql1
```
- **Ý nghĩa:** Xem các AG mà instance này tham gia.
- **Đổi cho lab:** Bỏ qua (không có AG).
- **Lưu ý:** Read-only, an toàn chạy bất cứ lúc nào.

### Đoạn 12: dòng 104-105 — Liệt kê replica
```powershell
Get-DbaAgReplica -SqlInstance $sql1 | Select-Object SqlInstance,
AvailabilityGroup, Name, Role, AvailabilityMode, FailoverMode
```
- **Ý nghĩa:** Liệt kê các replica của tất cả AG: Role (Primary/Secondary), AvailabilityMode (Synchronous/Async), FailoverMode (Automatic/Manual).
- **Đổi cho lab:** Bỏ qua.
- **Lưu ý:** AvailabilityMode + FailoverMode quyết định hành vi: chỉ Synchronous + Automatic mới failover tự động.

### Đoạn 13: dòng 110 — Liệt kê database trong AG
```powershell
Get-DbaAgDatabase -SqlInstance $sql1
```
- **Ý nghĩa:** Xem từng DB trong AG: trạng thái sync, queue size, redo rate. Dùng để giám sát "có lag không".
- **Đổi cho lab:** Bỏ qua.
- **Lưu ý:** Output rất chi tiết — dùng `| Format-Table -Property Name,SynchronizationState,IsSuspended,LogSendQueueSize`.

### Đoạn 14: dòng 114 — Failover thủ công
```powershell
Invoke-DbaAgFailover -SqlInstance $sql2 -AvailabilityGroup ACME_01
```
- **Ý nghĩa:** Đứng trên secondary `$sql2`, yêu cầu nó trở thành primary của AG `ACME_01`. Primary cũ trở thành secondary.
- **Đổi cho lab:** Bỏ qua.
- **Lưu ý:** **CẢNH BÁO MẠNH** — failover thủ công gây downtime ngắn (đứt connection). Cần `-Force` nếu là async mode (có thể mất data — data loss). Test trong môi trường staging.

### Đoạn 15: dòng 118 — Tạm dừng data movement
```powershell
Suspend-DbaAgDbDataMovement -SqlInstance $sql1 -AvailabilityGroup ACME_01
```
- **Ý nghĩa:** Tạm ngưng việc đẩy log từ primary sang secondary. Hữu ích khi cần làm bảo trì secondary (patch OS, restart) mà không muốn build up log queue quá lớn.
- **Đổi cho lab:** Bỏ qua.
- **Lưu ý:** **CẢNH BÁO** — khi suspend, primary tiếp tục ghi log nhưng không ship → log file primary có thể phồng to. Phải `Resume` đúng lúc.

### Đoạn 16: dòng 122 — Tiếp tục data movement
```powershell
Resume-DbaAgDbDataMovement -SqlInstance $sql1 -AvailabilityGroup ACME_01
```
- **Ý nghĩa:** Khôi phục data movement. Secondary catch-up từ log primary.
- **Đổi cho lab:** Bỏ qua.
- **Lưu ý:** Có thể mất thời gian catch-up tuỳ log queue accumulate trong lúc suspend. Theo dõi bằng `Get-DbaAgDatabase`.

## Lệnh thay vào lab của bạn

```powershell
$source = "dbatoolslab\sql2017"
$target = "dbatoolslab"
$share  = "C:\dbatoolslab\logship"   # đảm bảo folder tồn tại

# 0) Chuẩn bị: đảm bảo DB ở recovery model FULL
Set-DbaDbRecoveryModel -SqlInstance $source -Database AdventureWorks2017 `
    -RecoveryModel Full -Confirm:$false

# Tạo folder logship nếu chưa có
if (-not (Test-Path $share)) { New-Item -ItemType Directory -Path $share }

# 1) WhatIf trước
$params = @{
    SourceSqlInstance      = $source
    DestinationSqlInstance = $target
    Database               = "AdventureWorks2017"
    SharedPath             = $share
    WhatIf                 = $true
}
Invoke-DbaDbLogShipping @params

# 2) Thực hiện log shipping cho một DB
$params.Remove("WhatIf")
Invoke-DbaDbLogShipping @params

# 3) Giám sát lỗi
Get-DbaDbLogShipError -SqlInstance $source, $target |
    Select-Object SqlInstance, LogTime, Message

# 4) Kiểm tra state DB ở secondary
Get-DbaDatabase -SqlInstance $target -Database AdventureWorks2017 |
    Select-Object Name, Status, RecoveryModel

# 5) Khi quyết định cutover: Recovery
Invoke-DbaDbLogShipRecovery -SqlInstance $target -Database AdventureWorks2017 -WhatIf
# Xác nhận log dự kiến apply, sau đó bỏ -WhatIf:
Invoke-DbaDbLogShipRecovery -SqlInstance $target -Database AdventureWorks2017

# 6) Kiểm tra AG (lab không có cluster nên đoạn này chỉ chạy được nếu bạn dựng AG
#    với ClusterType=None trên hai container/host khác nhau)
# Get-DbaAvailabilityGroup -SqlInstance $source
# Get-DbaAgReplica -SqlInstance $source
# Get-DbaAgDatabase -SqlInstance $source
```

## Self-check
1. **Định nghĩa:** Phân biệt log shipping, mirroring, và Availability Group. Cái nào cho automatic failover, cái nào chỉ manual?
2. **Thực hành:** Sau khi setup log shipping `AdventureWorks2017` từ `dbatoolslab\sql2017` sang `dbatoolslab`, thử tạo một row mới ở primary rồi đợi job copy/restore chạy (mặc định mỗi 15 phút) — kiểm tra row có xuất hiện ở secondary không (cần `STANDBY` mode để query secondary).
3. **Liên hệ:** Khi nào nên dùng log shipping thay vì Availability Group? Cho ít nhất 2 tiêu chí so sánh (chi phí license Enterprise, độ phức tạp cluster, RPO/RTO).

## Bài tập mở rộng
- **Bài 1:** Setup log shipping cho **hai database** đồng thời (`AdventureWorks2017`, `WideWorldImporters`). Sau đó dùng `Get-DbaAgentJob` xem có bao nhiêu job mới được tạo (backup/copy/restore × số DB). Đặt schedule cách nhau 2-3 phút để giảm spike I/O.
- **Bài 2:** Mô phỏng cutover hoàn chỉnh: (a) tạo bảng mới ở primary, (b) chạy job backup log thủ công, (c) `Invoke-DbaDbLogShipRecovery` ở secondary, (d) verify bảng mới có ở secondary, (e) viết script "reverse log shipping" để chuyển chiều primary↔secondary.


---

!!! info "Nguồn gốc"
    `book_lab/dbatools-lab/bookcode/chapter17.notes.md`
