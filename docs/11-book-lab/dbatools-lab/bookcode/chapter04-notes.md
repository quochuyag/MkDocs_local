---
title: Chapter 04 — Kết nối SQL Server với `Connect-DbaInstance` & xem dịch vụ với `Get-DbaService`
course: 11-book-lab
source: book_lab/dbatools-lab/bookcode/chapter04.notes.md
---

# Chapter 04 — Kết nối SQL Server với `Connect-DbaInstance` & xem dịch vụ với `Get-DbaService`

> Tham chiếu code gốc: [chapter04.ps1](chapter04.ps1)

## Mục tiêu
- Nắm 4 cách truyền instance vào cmdlet dbatools: tham số trực tiếp, mảng, pipeline string, kết quả của lệnh khác.
- Hiểu cách dbatools chấp nhận credential: `-SqlCredential <username>`, `Get-Credential`, hoặc lưu sẵn `$cred`.
- Biết cú pháp instance đặc biệt: named instance (`HOST\NAME`), TCP port (`host,port` hoặc `host:port`), Azure SQL DB, Azure AD app credential.
- Sử dụng `Get-DbaService` để xem trạng thái các SQL service trên máy đích.
- Phân biệt **`-SqlInstance`** (parameter của cmdlet SQL: connect TDS) vs **`-ComputerName`** (parameter của cmdlet OS: connect WMI/WinRM).

## Tóm tắt 5 ý chính
1. **`Connect-DbaInstance` là cmdlet "linh hồn"** — hầu hết cmdlet dbatools đều chấp nhận output của nó làm `-SqlInstance`, giúp tránh reconnect nhiều lần.
2. **Pipeline-friendly:** truyền nhiều instance qua mảng hoặc pipe được. dbatools chạy song song nội bộ với một số cmdlet (xem `Get-Help -Full` mục Parameters).
3. **Cú pháp port:** SQL Server hiểu cả `host,port` (dấu phẩy — SSMS quen thuộc) và `host:port` (dấu hai chấm — kiểu URL). Cả hai cùng cho ra TCP connection.
4. **`Get-DbaService` không phải SQL command** — nó dùng CIM/WMI để query SCM trên máy đích → cần **Local Admin** trên target, không phải SQL permission.
5. **Azure SQL** kết nối được qua cùng `Connect-DbaInstance` với thêm `-Tenant` (Azure AD) hoặc App credential — không cần module Az.

## Giải thích từng đoạn code

### Đoạn 1: dòng 18
```powershell
Get-Help Test-DbaConnection -Detailed
```
- **Ý nghĩa:** Xem help đầy đủ của cmdlet test connection — show syntax, examples, parameters.
- **Lưu ý:** Chapter này dùng nhiều `Get-Help` — chapter 03 (trong sách thật, không phải file `chapter03.ps1`) đào sâu help. Đây là phản xạ cần luyện: **luôn `Get-Help <cmdlet> -Examples` trước khi chạy**.

### Đoạn 2: dòng 22
```powershell
Test-DbaConnection -SqlInstance $Env:ComputerName
```
- **Ý nghĩa:** Test kết nối tới SQL instance trên máy local. Output gồm: ping OK, TCP OK, SQL auth OK, version, edition…
- **Đổi cho lab:** Thay `$Env:ComputerName` bằng `dbatoolslab\sql2017` để test instance lab. Hoặc giữ `$Env:ComputerName` nếu chạy từ chính máy host của lab.
- **Lưu ý:** Lệnh **read-only**, an toàn chạy bất kỳ lúc nào.

### Đoạn 3: dòng 26
```powershell
Get-DbaDatabase -SqlInstance SQLDEV01
```
- **Ý nghĩa:** Liệt kê database trên instance. Đây là cmdlet được dùng nhiều nhất xuyên suốt sách.
- **Đổi cho lab:** `Get-DbaDatabase -SqlInstance dbatoolslab\sql2017`.

### Đoạn 4: dòng 30
```powershell
Connect-DbaInstance -SqlInstance PRODSQL01\SHAREPOINT
```
- **Ý nghĩa:** Kết nối tới **named instance** `SHAREPOINT` trên máy `PRODSQL01`. Định dạng `HOST\NAME` là chuẩn.
- **Đổi cho lab:** `Connect-DbaInstance -SqlInstance dbatoolslab\sql2017`.

### Đoạn 5: dòng 34
```powershell
Connect-DbaInstance -SqlInstance PRODSQL01, PRODSQL02, PRODSQL03\ShoeFactory
```
- **Ý nghĩa:** Kết nối nhiều instance cùng lúc bằng cách truyền **mảng** vào `-SqlInstance`.
- **Đổi cho lab:** `Connect-DbaInstance -SqlInstance dbatoolslab, dbatoolslab\sql2017`.

### Đoạn 6: dòng 38
```powershell
"PRODSQL01", "PRODSQL02", "PRODSQL03\ShoeFactory" | Connect-DbaInstance
```
- **Ý nghĩa:** Đẩy mảng string qua **pipeline** vào `Connect-DbaInstance`. Tương đương đoạn 5.
- **Đổi cho lab:** `"dbatoolslab", "dbatoolslab\sql2017" | Connect-DbaInstance`.

### Đoạn 7: dòng 42-43
```powershell
$instances = "PRODSQL01", "PRODSQL02", "PRODSQL03\ShoeFactory"
Connect-DbaInstance -SqlInstance $instances
```
- **Ý nghĩa:** Lưu mảng vào biến trước, sau đó truyền vào `-SqlInstance`. Cùng kết quả.
- **Đổi cho lab:** Thay nội dung mảng bằng `"dbatoolslab", "dbatoolslab\sql2017"`.

### Đoạn 8: dòng 47-48
```powershell
$instances = "PRODSQL01", "PRODSQL02", "PRODSQL03\ShoeFactory"
$instances | Connect-DbaInstance
```
- **Ý nghĩa:** Biến → pipeline. Đây là pattern hay dùng khi danh sách instance đến từ file/DB/AD.

### Đoạn 9: dòng 52-53
```powershell
$instances = (Invoke-DbaQuery -SqlInstance ConfigInstance -Database DbaConfig -Query "SELECT InstanceName FROM Config.Instances C JOIN Project.People P ON C.InstanceID = P.InstanceID WHERE P.Name = 'Shawn Melton'").InstanceName
$instances | Connect-DbaInstance
```
- **Ý nghĩa:** Lấy danh sách instance từ **inventory DB** (CMDB nội bộ), rồi connect hết. Pattern enterprise điển hình.
- **Đổi cho lab:** Lab nhỏ nên không có CMDB. Thay bằng đọc CSV: `Import-Csv .\instances.csv | Select-Object -ExpandProperty Name`.
- **Cú pháp:** Cặp `(...).InstanceName` lấy property của kết quả — nhanh nhưng load toàn bộ vào memory trước.

### Đoạn 10: dòng 57-58
```powershell
$instances = Invoke-DbaQuery -SqlInstance ConfigInstance -Database DbaConfig -Query "SELECT InstanceName FROM Config.Instances C JOIN Project.People P ON C.InstanceID = P.InstanceID WHERE P.Name = 'Shawn Melton'" | Select-Object -ExpandProperty InstanceName
$instances | Connect-DbaInstance
```
- **Ý nghĩa:** Cùng đoạn 9, nhưng dùng `Select-Object -ExpandProperty` thay vì `(...).InstanceName`. Pipeline thuần, **streaming** thay vì load hết.
- **Lưu ý:** Best practice cho dataset lớn.

### Đoạn 11: dòng 62
```powershell
Connect-DbaInstance -SqlInstance "sqldev04,57689"
```
- **Ý nghĩa:** Kết nối qua **port số 57689** với cú pháp `host,port` (kiểu SSMS).
- **Đổi cho lab:** Không cần — lab default instance dùng port 1433. Để test cú pháp này, có thể chạy `Connect-DbaInstance -SqlInstance "dbatoolslab,1433"`.

### Đoạn 12: dòng 66
```powershell
Connect-DbaInstance -SqlInstance sqldev04:57689
```
- **Ý nghĩa:** Cú pháp port kiểu URL `host:port`. Tương đương đoạn 11.

### Đoạn 13: dòng 70
```powershell
Connect-DbaInstance -SqlInstance CORPSQL01 -SqlCredential devadmin
```
- **Ý nghĩa:** Kết nối với SQL login `devadmin` — dbatools sẽ **prompt password** vì chỉ truyền tên user, không có password.
- **Đổi cho lab:** `Connect-DbaInstance -SqlInstance dbatoolslab\sql2017 -SqlCredential WWI_ReadOnly`.

### Đoạn 14: dòng 74
```powershell
Connect-DbaInstance -SqlInstance CORPSQL01 -SqlCredential devadmin
```
- **Ý nghĩa:** Code lặp lại đoạn 13 (file gốc có 2 lần) — chỉ để minh hoạ ngữ cảnh trong sách.

### Đoạn 15: dòng 79-81
```powershell
$cred = Get-Credential
# Connect to the local machine using the credential
Connect-DbaInstance -SqlInstance $Env:ComputerName -SqlCredential $cred
```
- **Ý nghĩa:** Lưu credential vào `$cred` rồi tái sử dụng. Hữu ích khi chạy nhiều lệnh trong cùng session.
- **Đổi cho lab:**
  ```powershell
  $cred = Get-Credential WWI_ReadOnly
  Connect-DbaInstance -SqlInstance dbatoolslab\sql2017 -SqlCredential $cred
  ```

### Đoạn 16: dòng 85
```powershell
$cred = Get-Credential
```
- **Ý nghĩa:** Chỉ tạo `$cred`, không gắn user — dialog sẽ hỏi cả username + password.

### Đoạn 17: dòng 90-92
```powershell
Connect-DbaInstance -SqlInstance $Env:ComputerName -SqlCredential $cred

Name    Product              Version   Platform IsAzure IsClustered ConnectedAs
```
- **Ý nghĩa:** Dùng lại `$cred` đoạn 16. Dòng dưới là **header output mẫu**.

### Đoạn 18: dòng 96-99
```powershell
$query = "EXEC GetPasswordFromPasswordStore @UserName='AD\dbatools'"
$securepassword = ConvertTo-SecureString (Invoke-DbaQuery -SqlInstance VerySecure -Database NoPasswordsHere -Query $query) -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential ( "AD\dbatools", $securepassword)
Test-DbaConnection -SqlInstance $Env:ComputerName -SqlCredential $cred
```
- **Ý nghĩa:** Mẫu **lấy password từ password store** (DB nội bộ, secret vault), build `PSCredential` rồi dùng. Production pattern.
- **Đổi cho lab:** Lab không có store. Thay bằng Azure Key Vault hoặc `SecretManagement` module:
  ```powershell
  $securepw = Get-Secret -Name WWI_ReadOnly_pw -Vault MyVault
  $cred = New-Object PSCredential('WWI_ReadOnly', $securepw)
  ```
- **Cảnh báo:** `ConvertTo-SecureString -AsPlainText -Force` là dấu hiệu password đang ở plaintext trong source — chỉ chấp nhận trong code lab/throw-away.

### Đoạn 19: dòng 103
```powershell
Connect-DbaInstance -SqlInstance SQLDEV01 -SqlCredential ad\sander.stad
```
- **Ý nghĩa:** Truyền **Windows credential** dạng `DOMAIN\user`. Khi không truyền `-SqlCredential` thì dbatools dùng Integrated Security của user hiện tại.

### Đoạn 20: dòng 107-109
```powershell
$server = Connect-DbaInstance -SqlInstance dbatools.database.windows .net -SqlCredential dbatools@mycorp.onmicrosoft.com -Database inventory
# Use server connection to query the database using our query command, Invoke-DbaQuery
Invoke-DbaQuery -SqlInstance $server -Database inventory -Query "select name from instances"
```
- **Ý nghĩa:** Kết nối **Azure SQL DB** bằng Azure AD account (UPN), lưu `$server`, reuse cho `Invoke-DbaQuery`.
- **Lưu ý lab:** Lab không có Azure SQL → skip block này. Chỉ nhớ pattern reuse `$server` để tránh reconnect.
- **Bug nhỏ trong code gốc:** chuỗi `windows .net` có space thừa, copy nguyên xi sẽ fail. Sửa thành `database.windows.net`.

### Đoạn 21: dòng 113-115
```powershell
Connect-DbaInstance -SqlInstance dbatools.database.windows.net -SqlCredential 52c1fbca-24ed-4353-bbf1-6dd52f535027 -Tenant ec46e088-2707-4b0a-ab0d-dee0b52fc5c8 -Database inventory

Name                                Product Version   Platform IsAzure IsClustered ConnectedAs
```
- **Ý nghĩa:** Azure AD **service principal** login: GUID là Application (client) ID, `-Tenant` là Directory ID.
- **Lưu ý:** Cần app secret được prompt riêng. Production thường dùng pattern đoạn 22.

### Đoạn 22: dòng 119-125
```powershell
$appcred = Get-Credential 52c1fbca-24ed-4353-bbf1-6dd52f535027

# Establish a connection
$server = Connect-DbaInstance -SqlInstance dbatools.database.windows .net -Database inventory -SqlCredential $appcred -Tenant 6b73c0ef-114d-43ad-94c9-85a4a82cde8b

# Now that the connection is established, use it to perform a query
Invoke-DbaQuery -SqlInstance $server -Database dbatools -Query "SELECT Name FROM sys.objects"

Name
```
- **Ý nghĩa:** Mẫu **production pattern** kết nối Azure SQL DB: lưu app secret vào `PSCredential`, kết nối lần duy nhất, reuse cho mọi query sau.

### Đoạn 23: dòng 131-143
```powershell
Get-Help Get-DbaService

Synopsis
Gets the SQL Server related services on a computer.
...
Syntax
Get-DbaService [[-ComputerName] <DbaInstanceParameter[]>] [-InstanceName <String[]>] [-Credential <PSCredential>] [-Type <String[]>] [-AdvancedProperties] [-EnableException] [<CommonParameters>]
```
- **Ý nghĩa:** Help của `Get-DbaService`. Chú ý parameter **`-ComputerName`** (không phải `-SqlInstance`) — vì lệnh hoạt động qua WMI/CIM, không qua TDS.

### Đoạn 24: dòng 147-183
```powershell
Get-DbaService -ComputerName CORPSQL

ComputerName : CORPSQL
ServiceName  : MsDtsServer140
...
```
- **Ý nghĩa:** Liệt kê tất cả SQL service trên máy `CORPSQL`. Output gồm Engine, Agent, Browser, SSIS, Reporting…
- **Đổi cho lab:** `Get-DbaService -ComputerName dbatoolslab`. **Cần Local Admin trên máy đích.**
- **Lưu ý:** Trên Linux/devcontainer lệnh này **không hoạt động** (SQL Linux không quản lý qua SCM/WMI). Đó là giới hạn chính của Đường A.

### Đoạn 25: dòng 187-198
```powershell
Get-DbaService -ComputerName SQL01, SQL02

# Computer Names piped to a command
"SQL01", "SQL02" | Get-DbaService

# Computer Names stored in a variable
$servers = "SQL01", "SQL02"
Get-DbaService -ComputerName $servers

# Computer Names stored in a variable and piped to a command
$servers = "SQL01", "SQL02"
$servers | Get-DbaService
```
- **Ý nghĩa:** 4 cách truyền nhiều `ComputerName` — đối xứng với 4 cách cho `-SqlInstance` ở đầu chapter.

### Đoạn 26: dòng 202
```powershell
Get-DbaService -ComputerName CORPSQL -Credential AD\wdurkin
```
- **Ý nghĩa:** Truyền **Windows credential** cho lệnh OS-level. Khác `-SqlCredential` ở chỗ đây là quyền OS (admin máy), không phải SQL.

### Đoạn 27: dòng 207
```powershell
$cred = Get-Credential
```
- **Ý nghĩa:** Lưu Windows credential.

### Đoạn 28: dòng 212
```powershell
Get-DbaService -ComputerName CORPSQL -Credential $cred
```
- **Ý nghĩa:** Reuse `$cred` đoạn 27. Pattern quen thuộc.

### Đoạn 29: dòng 216
```powershell
Get-DbaService -ComputerName CORPSQL -Type Engine
```
- **Ý nghĩa:** Filter chỉ Engine service (bỏ Agent/Browser/SSIS/SSRS). Các giá trị `-Type` khác: `Agent`, `Browser`, `SSIS`, `SSRS`, `SSAS`, `FullText`, `PolyBase`.

### Đoạn 30: dòng 220
```powershell
Get-DbaService -ComputerName CORPSQL -InstanceName BOLTON
```
- **Ý nghĩa:** Filter service liên quan đến **named instance** `BOLTON`. Hữu ích khi máy có nhiều instance.

## Lệnh thay vào lab của bạn

```powershell
# Phiên bản đã đổi instance name cho lab dbatoolslab + dbatoolslab\sql2017

# 1) Test kết nối — luôn chạy trước
Test-DbaConnection -SqlInstance dbatoolslab\sql2017 |
    Select-Object SqlInstance, ConnectSuccess, IsPingable, AuthType, AuthScheme

# 2) 4 cách truyền nhiều instance (chọn 1 — pipeline khuyến nghị)
$lab = "dbatoolslab", "dbatoolslab\sql2017"
$lab | Connect-DbaInstance | Select-Object Name, Product, Version

# 3) Kết nối với SQL credential
$cred = Get-Credential WWI_ReadOnly   # nhập password đã set ở chapter03
Connect-DbaInstance -SqlInstance dbatoolslab\sql2017 -SqlCredential $cred -Database WideWorldImporters

# 4) Cú pháp port (chỉ test cú pháp, lab dùng 1433 mặc định)
Connect-DbaInstance -SqlInstance "dbatoolslab,1433"

# 5) Xem dịch vụ SQL trên máy host (cần Local Admin; không chạy trong devcontainer Linux)
Get-DbaService -ComputerName dbatoolslab |
    Select-Object ComputerName, ServiceName, ServiceType, State, StartMode
Get-DbaService -ComputerName dbatoolslab -Type Engine, Agent
Get-DbaService -ComputerName dbatoolslab -InstanceName SQL2017
```

## Self-check (3 câu)
1. **Định nghĩa:** Phân biệt **`-SqlCredential`** vs **`-Credential`**. Khi nào dùng cái nào?
2. **Thực hành:** Chạy `Connect-DbaInstance -SqlInstance dbatoolslab\sql2017` (không param khác), gán vào `$srv`. Sau đó chạy `$srv | Get-Member`. Liệt kê 3 property/method bạn nghĩ sẽ dùng nhiều trong các chapter sau.
3. **Liên hệ:** Tại sao chapter 02 chỉ giới thiệu `Invoke-Command` mà không dùng nó cho ví dụ kết nối SQL? Lệnh `Connect-DbaInstance` thay thế `Invoke-Command` ở điểm gì?

## Bài tập mở rộng
- **Bài 1 (~5 phút):** Tạo file `instances.txt` chứa 2 dòng `dbatoolslab` và `dbatoolslab\sql2017`. Đọc file bằng `Get-Content`, pipe vào `Connect-DbaInstance`, format output thành bảng có cột `Name, Version, Edition, ProductLevel`.
- **Bài 2 (sâu hơn):** Viết function `Get-LabInstance` trả về object `{ Sql, Os }` cho mỗi instance: phần `Sql` từ `Connect-DbaInstance`, phần `Os` từ `Get-DbaService -InstanceName ...`. Trên devcontainer Linux, phần `Os` sẽ thất bại — function nên catch và set `$null` thay vì throw.


---

!!! info "Nguồn gốc"
    `book_lab/dbatools-lab/bookcode/chapter04.notes.md`
