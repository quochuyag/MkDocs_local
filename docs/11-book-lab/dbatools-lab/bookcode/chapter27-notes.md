---
title: Chapter 27 — Cloud & Azure SQL với dbatools
course: 11-book-lab
source: book_lab/dbatools-lab/bookcode/chapter27.notes.md
---

# Chapter 27 — Cloud & Azure SQL với dbatools

> Tham chiếu code gốc: [chapter27.ps1](chapter27.ps1)

> **Cảnh báo môi trường:** Toàn bộ chapter này yêu cầu một Azure subscription thật, một Azure SQL Database/Managed Instance, và (cho ví dụ Service Principal) một App Registration ở Azure AD/Entra ID. **Không chạy được trong devcontainer hoặc lab Docker SQL Server bình thường.** Bạn có hai cách học:
>
> 1. **Đọc-hiểu only:** Đi qua từng đoạn code, hiểu tham số và workflow auth — đủ cho mục tiêu chứng chỉ và phỏng vấn.
> 2. **Chạy thật:** Tạo Azure SQL Database free tier (hoặc dùng tài khoản công ty có quyền), thay thế các placeholder bằng giá trị thật. Tốn tối thiểu vài USD nếu để chạy quá free tier.

## Mục tiêu
- Hiểu ba mô hình xác thực Azure SQL mà `dbatools` hỗ trợ: AAD password, Renewable Service Principal token, và `Az` module access token.
- Biết cách `Connect-DbaInstance` đối với Azure SQL Database khác với SQL Server on-prem ở điểm nào (port 1433 over TLS, không có Windows auth, FQDN `*.database.windows.net`).
- Sử dụng `New-DbaAzAccessToken` để lấy token mà không phụ thuộc module `Az.Accounts` đã cài.
- Hiểu khi nào dùng `RenewableServicePrincipal` (long-running script) thay vì token tĩnh (one-shot).
- Áp dụng các cmdlet quen thuộc (`Invoke-DbaQuery`, `Import-DbaCsv`) lên đối tượng `$server` đã connect Azure — workflow giống hệt on-prem.

## Tóm tắt 5 ý chính
1. **Azure SQL chỉ chấp nhận TCP/IP + TLS qua port 1433.** Phải có firewall rule cho IP của client; `dbatools` không quản lý firewall — dùng `Az.Sql` hoặc Azure Portal.
2. **`SqlCredential` với Azure SQL** truyền dạng `user@tenant.onmicrosoft.com` cho AAD password auth, KHÔNG phải SQL login. Nếu muốn dùng SQL login truyền thống (server admin), vẫn được nhưng AAD là khuyến nghị.
3. **Service Principal (App Registration)** = service account ở Azure AD. ID là một GUID; secret là password/cert. `New-DbaAzAccessToken -Type RenewableServicePrincipal` tự lấy token mới khi hết hạn (mặc định 1 giờ) — tránh script bị fail giữa chừng.
4. **`Get-AzAccessToken`** (module `Az.Accounts`) là cách thay thế khi bạn đã login tương tác bằng `Connect-AzAccount` — phù hợp với người vận hành tay; ít phù hợp cho automation/CI.
5. **Khi đã có `$server`** từ `Connect-DbaInstance`, các cmdlet downstream (`Invoke-DbaQuery`, `Import-DbaCsv`, `Backup-DbaDatabase` cho Managed Instance…) dùng nguyên xi như on-prem — đây là sức mạnh của abstraction.

## Giải thích từng đoạn code

### Đoạn 1: dòng 18–24 — Kết nối Azure SQL bằng AAD password
```powershell
$params = @{
  SqlInstance = "myserver.database.windows.net"
  Database = "mydb"
  SqlCredential = "me@mydomain.onmicrosoft.com"
}
$server = Connect-DbaInstance @params
Invoke-DbaQuery -SqlInstance $server -Query "select 1 as test"
```
- **Ý nghĩa:** Kết nối tới logical server Azure SQL `myserver.database.windows.net`, database `mydb`, xác thực bằng tài khoản AAD (Azure AD / Entra ID).
- **Workflow auth:** Khi gán `SqlCredential` là một string `user@tenant`, `dbatools` sẽ prompt password khi chạy lần đầu (giống `Get-Credential`). Token sau đó cache trong session.
- **Đổi cho lab (giả lập):** Không có Azure SQL thật thì không chạy được. Nếu muốn "test khô" workflow, bạn có thể tạo một Azure SQL Free (12 tháng) hoặc Serverless với compute auto-pause để giảm chi phí.
- **Lưu ý quan trọng:**
  - Server FQDN phải đúng `*.database.windows.net` (Azure SQL DB), `*.<region>.database.windows.net` (cũ), hoặc `*.<dns-zone>.database.windows.net` (Managed Instance).
  - Tài khoản AAD phải được map làm AAD admin hoặc có CREATE USER/permission trong database mục tiêu.
  - Nếu MFA bật, password auth sẽ fail — phải chuyển sang interactive hoặc service principal.

### Đoạn 2: dòng 28–40 — Kết nối bằng Renewable Service Principal token
```powershell
$params = @{
  Type = "RenewableServicePrincipal"
  Tenant = "mytenant.onmicrosoft.com"
  Credential = "ee590f55-9b2b-55d4-8bca-38ab123db670"
}
$token = New-DbaAzAccessToken @params
$params = @{
  SqlInstance = "myserver.database.windows.net"
  Database = "mydb"
  AccessToken = $token
}
$server = Connect-DbaInstance @params
Invoke-DbaQuery -SqlInstance $server -Query "select 1 as test"
```
- **Ý nghĩa:** Lấy access token theo cơ chế "renewable" — `dbatools` giữ secret và tự refresh token khi hết hạn. Sau đó truyền `$token` vào `Connect-DbaInstance` thay vì `SqlCredential`.
- **Tham số:**
  - `Type RenewableServicePrincipal` — tạo wrapper object có method refresh; cần thiết cho job chạy lâu (>1 giờ).
  - `Tenant` — directory ID hoặc verified domain của Azure AD.
  - `Credential` — Application (client) ID của App Registration. **Khi cmdlet prompt password sẽ là client secret.** Có thể truyền `[pscredential]` object đã sẵn để tự động hoá (không tương tác).
- **Đổi cho lab:** Để chạy thật cần:
  1. App Registration ở Azure Portal → copy Application (client) ID + Tenant ID.
  2. Tạo client secret (lưu ngay, sẽ ẩn sau).
  3. Cấp quyền cho App này trên Azure SQL: `CREATE USER [appname] FROM EXTERNAL PROVIDER; ALTER ROLE db_owner ADD MEMBER [appname];` (chạy từ AAD admin connection).
- **Lưu ý:** Tránh hard-code secret trong script — dùng `Get-Secret` (SecretManagement), Key Vault, hoặc env var.

### Đoạn 3: dòng 44–54 — Kết nối bằng Az module access token
```powershell
$azureAccount = Connect-AzAccount
$azureToken = Get-AzAccessToken -ResourceUrl  https://database.windows.net

$params = @{
  SqlInstance = "myserver.database.windows.net"
  Database = "mydb"
  AccessToken = $azuretoken
}

$server = Connect-DbaInstance @params
Invoke-DbaQuery -SqlInstance $server -Query "select 1 as test"
```
- **Ý nghĩa:** Cách "developer-friendly" — bạn đã `Connect-AzAccount` (mở browser, login MFA bình thường) thì có thể xin token cho resource `https://database.windows.net` và đưa cho `dbatools` dùng.
- **Đổi cho lab:** Yêu cầu cài module `Az.Accounts` (`Install-Module Az.Accounts -Scope CurrentUser`). Không phụ thuộc App Registration.
- **Lưu ý:**
  - Token này KHÔNG tự renew — sau ~1 giờ phải gọi lại `Get-AzAccessToken`. Không phù hợp script chạy lâu/automation.
  - `-ResourceUrl https://database.windows.net` là audience bắt buộc cho Azure SQL. Sai resource → token hợp lệ nhưng SQL từ chối.
  - Lỗi chính tả trong code gốc: `$azuretoken` (line 50) vs `$azureToken` (line 45) — PowerShell case-insensitive nên vẫn chạy, nhưng nên đồng nhất.

### Đoạn 4: dòng 58–82 — Workflow đầy đủ: token + load CSV + query
```powershell
$params = @{
  Type = "RenewableServicePrincipal"
  Tenant = "mytenant.onmicrosoft.com"
  Credential = "ee590f55-9b2b-55d4-8bca-38ab123db670"
}
$token = New-DbaAzAccessToken @params
$params = @{
  SqlInstance = "myserver.database.windows.net"
  Database = "mydb"
  AccessToken = $token
}
$server = Connect-DbaInstance @params
$params = @{
  SqlInstance = $server
  Database = "mydb"
  Path = "C:\temp\customers.csv"
  AutoCreateTable = $true
}
Import-DbaCsv @params
$params = @{
  SqlInstance = $server
  Database = "mydb"
  Query = "select * from customers"
}
Invoke-DbaQuery @params
```
- **Ý nghĩa:** End-to-end demo: lấy token → connect → import CSV (tự tạo bảng) → query lại bảng vừa import.
- **Quan trọng — truyền `$server` thay vì string instance name:** Sau khi `Connect-DbaInstance` trả về `$server`, các cmdlet downstream nhận tham số `-SqlInstance $server` sẽ tái sử dụng connection + token, không phải auth lại. Đây là pattern tiết kiệm token call (đắt với AAD) và đảm bảo nhất quán.
- **`AutoCreateTable`:** `Import-DbaCsv` sẽ suy luận schema từ header CSV → tạo bảng nếu chưa có (cột mặc định `NVARCHAR(MAX)`, không tối ưu). Production nên tạo bảng thủ công với data types đúng.
- **Đổi cho lab:** Nếu bạn có Azure SQL thật, có thể dùng `bookcode/sample_customers.csv` (xem `samples/csv/`) để thử workflow.

## Lệnh thay vào lab của bạn

**Nếu bạn KHÔNG có Azure subscription** — chỉ chạy demo workflow tương đương trên `dbatoolslab\sql2017`:

```powershell
# 1) Simulate "Connect rồi tái dùng $server" — concept giống hệt Azure
$server = Connect-DbaInstance -SqlInstance 'dbatoolslab\sql2017'
Invoke-DbaQuery -SqlInstance $server -Query "select @@SERVERNAME as srv, suser_sname() as login_used"

# 2) Simulate workflow load CSV (chapter 27 đoạn 4) trên SQL Server local
$params = @{
    SqlInstance     = $server
    Database        = 'WideWorldImporters'
    Path            = (Join-Path $PSScriptRoot '..\samples\csv\customers.csv')
    AutoCreateTable = $true
    Table           = 'Staging_Customers'
}
Import-DbaCsv @params -WhatIf   # bỏ -WhatIf khi đã review
Invoke-DbaQuery -SqlInstance $server -Database WideWorldImporters -Query "select top 5 * from Staging_Customers"
```

**Nếu bạn CÓ Azure subscription** — đoạn code chạy thật, an toàn:

```powershell
# 1) Cài module Az.Accounts nếu chưa có
if (-not (Get-Module -ListAvailable Az.Accounts)) {
    Install-Module Az.Accounts -Scope CurrentUser
}

# 2) Login Azure tương tác (sẽ mở browser)
Connect-AzAccount

# 3) Lấy token và connect Azure SQL
$azureToken = (Get-AzAccessToken -ResourceUrl https://database.windows.net).Token
$server = Connect-DbaInstance -SqlInstance '<your>.database.windows.net' -Database '<yourdb>' -AccessToken $azureToken

# 4) Verify
Invoke-DbaQuery -SqlInstance $server -Query "select @@VERSION as v, db_name() as db"

# 5) Cleanup token (đảm bảo không log ra)
Remove-Variable azureToken
```

## Self-check (3 câu)
1. **Định nghĩa:** Khác biệt thực tế giữa `New-DbaAzAccessToken -Type RenewableServicePrincipal` và `Get-AzAccessToken` là gì? Khi nào phải dùng cái nào?
2. **Thực hành:** Giả sử bạn cần chạy một script PowerShell trên Azure DevOps pipeline kéo dài 3 giờ để ETL dữ liệu vào Azure SQL. Bạn chọn auth pattern nào trong 3 pattern của chapter? Vì sao?
3. **Liên hệ:** Cmdlet `Import-DbaCsv` ở đoạn 4 hoạt động giống hệt khi `$server` là Azure SQL hay SQL Server on-prem — abstraction này được `dbatools` xây dựng nhờ vào điểm chung nào ở cả hai platform? (Gợi ý: TDS protocol, SMO).

## Bài tập mở rộng
- **Bài 1 (đọc-hiểu, không tốn tiền):** Đọc help của `Connect-DbaInstance` (`Get-Help Connect-DbaInstance -Full`) và liệt kê TẤT CẢ tham số liên quan đến cloud/Azure: `AccessToken`, `Tenant`, `AzureUnsupported`, `ConnectTimeout`, `ApplicationIntent`. Viết 1 câu giải thích mỗi cái.
- **Bài 2 (chạy thật, ~1 USD):** Tạo Azure SQL Database Serverless ở free tier, làm sạch toàn bộ 4 đoạn code chapter với placeholder thật của bạn, screenshot kết quả `Invoke-DbaQuery`. Sau đó **xoá resource group** (`Remove-AzResourceGroup`) để khỏi cháy ví.
- **Bài 3 (nâng cao):** Viết một function `Connect-LabOrAzure -Environment <Lab|Azure>` tự động chọn pattern auth phù hợp dựa trên tham số, trả về `$server` object thống nhất cho code downstream.


---

!!! info "Nguồn gốc"
    `book_lab/dbatools-lab/bookcode/chapter27.notes.md`
