---
title: Chapter 06 — Khám phá instance trong mạng với `Find-DbaInstance`
course: 11-book-lab
source: book_lab/dbatools-lab/bookcode/chapter06.notes.md
---

# Chapter 06 — Khám phá instance trong mạng với `Find-DbaInstance`

> Tham chiếu code gốc: [chapter06.ps1](chapter06.ps1)

## Mục tiêu
- Hiểu khi nào cần `Find-DbaInstance` thay vì `Connect-DbaInstance` (chưa biết có instance nào).
- Nắm các **discovery type**: `ComputerName`, `DataSourceEnumeration`, `Domain`, `IPRange`.
- Biết khác biệt giữa **discovery type** (cách tìm host) và **scan type** (cách verify có SQL trên host đó).
- Đọc được property `Availability`, `Confidence`, `Services`, `DnsResolution` trong output.
- Phân biệt `Find-DbaInstance` (dbatools, đa kênh) vs `SqlDataSourceEnumerator` (.NET native, chỉ UDP 1434 broadcast).

## Tóm tắt 4 ý chính
1. **`Find-DbaInstance` là Swiss-army knife discovery** — gọi nhiều kỹ thuật song song (SQL Browser, WMI, port scan, AD query, SPN…) rồi gộp kết quả.
2. **Discovery vs Scan:**
   - `-DiscoveryType` quyết định **danh sách host candidate** (lấy ở đâu).
   - `-ScanType` quyết định **kiểm tra host đó có SQL** bằng cách nào (Browser, WMI, TCPPort, SqlConnect…).
3. **`Confidence`** trong output: `Low/Medium/High` — báo dbatools tự tin mức nào về việc host thật sự đang chạy SQL. Confidence cao đến từ việc nhiều scan type cùng confirm.
4. **Production usage:** đầu mỗi audit chạy `Find-DbaInstance -DiscoveryType Domain` lưu vào DB → đối chiếu với danh sách CMDB → phát hiện instance "lậu" team khác cài mà DBA không biết.

## Giải thích từng đoạn code

### Đoạn 1: dòng 18
```powershell
Find-DbaInstance -ComputerName dbatoolslab
```
- **Ý nghĩa:** Quét máy `dbatoolslab` để tìm tất cả SQL instance đang chạy. Đây là cách dùng đơn giản nhất.
- **Đổi cho lab:** Giữ nguyên — `dbatoolslab` đã đúng tên máy lab.
- **Output mong đợi:** Ít nhất 2 dòng — default instance (`MSSQLSERVER`, port 1433) và named instance (`SQL2017`, port động).

### Đoạn 2: dòng 22-25
```powershell
Get-Content -Path C:\temp\serverlist.txt | Find-DbaInstance

# Pipe in computers from Active Directory
Get-ADComputer -Filter "*" | Find-DbaInstance
```
- **Ý nghĩa:** Lấy danh sách máy từ file text hoặc từ AD, pipe vào `Find-DbaInstance`. Pattern enterprise-scale discovery.
- **Đổi cho lab:**
  ```powershell
  "dbatoolslab" | Find-DbaInstance
  # hoặc tạo file
  "dbatoolslab" | Out-File -Path .\serverlist.txt
  Get-Content .\serverlist.txt | Find-DbaInstance
  ```
- **Lưu ý:** `Get-ADComputer` yêu cầu module `ActiveDirectory` (RSAT) và máy join domain. Lab home thường không có → skip.

### Đoạn 3: dòng 29-31
```powershell
Find-DbaInstance -DiscoveryType DataSourceEnumeration -ScanType Browser

ComputerName InstanceName Port  Availability Confidence ScanTypes
```
- **Ý nghĩa:** Phát hiện instance bằng cách **broadcast UDP 1434** ra cả subnet, lắng nghe ai trả lời. Cách cũ kiểu SSMS "Browse for more". Dòng dưới là **header output mẫu**.
- **Đổi cho lab:** Giữ nguyên — chạy được trên cùng subnet với SQL Browser service đang chạy.
- **Lưu ý:** UDP 1434 thường bị firewall chặn → đôi khi không thấy gì kể cả khi SQL đang chạy. Đó là lý do nên kết hợp nhiều discovery type.

### Đoạn 4: dòng 35
```powershell
[System.Data.Sql.SqlDataSourceEnumerator]::Instance.GetDataSources()
```
- **Ý nghĩa:** Gọi trực tiếp **.NET API** thay cho cmdlet dbatools. Cùng cơ chế (UDP broadcast) nhưng output là `DataTable` thô.
- **Bài học:** Đôi khi đọc code .NET native giúp hiểu dbatools đang wrap cái gì bên dưới.

### Đoạn 5: dòng 39
```powershell
Find-DbaInstance -DiscoveryType Domain
```
- **Ý nghĩa:** Hỏi AD tìm máy có **SPN** dạng `MSSQLSvc/*` đăng ký — chính xác nhất, không phụ thuộc network broadcast.
- **Đổi cho lab:** Chỉ chạy được khi máy join domain. Lab home dùng workgroup → skip hoặc test bằng `-DiscoveryType All` (cẩn thận tốn thời gian).
- **Lưu ý:** Cần quyền đọc AD (mọi domain user thường có).

### Đoạn 6: dòng 43-48
```powershell
$splatFindInstance = @{
        DiscoveryType = "Domain"
        DomainController = "dc.devad.local"
        Credential = "devad\admin"
}
Find-DbaInstance @splatFindInstance
```
- **Ý nghĩa:** Discovery với **alternate credential** và DC cụ thể — hữu ích khi audit nhiều domain.
- **Đổi cho lab:** Skip nếu không có domain.

### Đoạn 7: dòng 52
```powershell
Find-DbaInstance -DiscoveryType IPRange
```
- **Ý nghĩa:** Quét **toàn bộ subnet hiện tại** của máy chạy lệnh. dbatools tự lấy subnet từ network adapter.
- **Cảnh báo:** Chạy lâu (vài phút) và có thể bị **IDS/firewall coi là port scan**. Trong môi trường công ty xin phép trước.

### Đoạn 8: dòng 56-59
```powershell
Find-DbaInstance -DiscoveryType IPRange -IpAddress 172.20.0.77

# Specify a range
Find-DbaInstance -DiscoveryType IPRange -IpAddress 172.20.0.1/24
```
- **Ý nghĩa:** Hạn chế scope — chỉ scan 1 IP hoặc 1 subnet CIDR cụ thể.
- **Đổi cho lab:**
  ```powershell
  # 1 IP cụ thể
  Find-DbaInstance -DiscoveryType IPRange -IpAddress 127.0.0.1
  # Subnet lab (đổi theo `ipconfig` của bạn, vd 192.168.1.0/24)
  Find-DbaInstance -DiscoveryType IPRange -IpAddress 192.168.1.0/24
  ```

### Đoạn 9: dòng 63-64
```powershell
Find-DbaInstance -ComputerName SQLDEV01 | Select *
```
- **Ý nghĩa:** Xem **tất cả property** của object output. Sẽ thấy nhiều property nested: `Services`, `DnsResolution`, `SystemServices`…
- **Đổi cho lab:** `Find-DbaInstance -ComputerName dbatoolslab | Select *`.

### Đoạn 10: dòng 68-70
```powershell
Find-DbaInstance -ComputerName SQLDEV01 |
        Select -ExpandProperty DnsResolution
```
- **Ý nghĩa:** **Expand** property nested `DnsResolution` thành object riêng → xem được FQDN, IPv4, IPv6.
- **Đổi cho lab:** `Find-DbaInstance -ComputerName dbatoolslab | Select -ExpandProperty DnsResolution`.

### Đoạn 11: dòng 74-76
```powershell
Find-DbaInstance -ComputerName SQLDEV01 |
        Select -ExpandProperty Services
```
- **Ý nghĩa:** Expand `Services` — danh sách service SQL trên máy đó. Tương đương output `Get-DbaService` nhưng đến qua đường discovery.
- **Đổi cho lab:** `Find-DbaInstance -ComputerName dbatoolslab | Select -ExpandProperty Services`.

## Lệnh thay vào lab của bạn

```powershell
# Phiên bản đã đổi instance name cho lab dbatoolslab + dbatoolslab\sql2017

# 1) Quét đơn giản — máy lab
Find-DbaInstance -ComputerName dbatoolslab |
    Select-Object ComputerName, InstanceName, Port, Availability, Confidence, ScanTypes

# 2) Broadcast UDP 1434 (giả sử SQL Browser đang chạy)
Find-DbaInstance -DiscoveryType DataSourceEnumeration -ScanType Browser

# 3) Đối chiếu với .NET API (cùng kết quả về mặt nguyên lý)
[System.Data.Sql.SqlDataSourceEnumerator]::Instance.GetDataSources()

# 4) IPRange — chỉ scope hẹp tránh tốn thời gian
Find-DbaInstance -DiscoveryType IPRange -IpAddress 127.0.0.1

# 5) Khám phá chi tiết
Find-DbaInstance -ComputerName dbatoolslab | Select-Object *
Find-DbaInstance -ComputerName dbatoolslab | Select-Object -ExpandProperty DnsResolution
Find-DbaInstance -ComputerName dbatoolslab | Select-Object -ExpandProperty Services

# 6) (Tuỳ chọn — chỉ chạy khi máy join domain)
# Find-DbaInstance -DiscoveryType Domain
```

## Self-check (3 câu)
1. **Định nghĩa:** Phân biệt `-DiscoveryType` và `-ScanType` của `Find-DbaInstance`. Cho 1 ví dụ kết hợp.
2. **Thực hành:** Chạy `Find-DbaInstance -ComputerName dbatoolslab`. Trong output, cột `Confidence` cho giá trị gì? Nếu `Low`, nguyên nhân thường là gì (gợi ý: SQL Browser, firewall)?
3. **Liên hệ:** Chapter 04 dạy `Connect-DbaInstance` khi đã biết instance name. Chapter này dạy `Find-DbaInstance` khi chưa biết. Trong audit của 1 công ty mới tiếp quản, bạn sẽ chạy cái nào trước? Tại sao?

## Bài tập mở rộng
- **Bài 1 (~5 phút):** Pipe `Find-DbaInstance -ComputerName dbatoolslab` vào `Connect-DbaInstance` — verify mỗi instance vừa discover đều connect được. Output gom thành bảng với cột `InstanceName, Connected, Version`.
- **Bài 2 (sâu hơn):** Viết script `Audit-SqlEstate.ps1` nhận `-Subnet` (vd `192.168.1.0/24`), chạy `Find-DbaInstance -IpAddress $Subnet`, lưu kết quả vào bảng `DBAEstate.dbo.DiscoveredInstances` qua `Write-DbaDataTable`. Mỗi lần chạy thêm cột `ScanDate = (Get-Date)`. Sau 7 ngày, query bảng để xem có instance mới xuất hiện không (gợi ý: `SELECT InstanceName, MIN(ScanDate), MAX(ScanDate) FROM ... GROUP BY InstanceName`).


---

!!! info "Nguồn gốc"
    `book_lab/dbatools-lab/bookcode/chapter06.notes.md`
