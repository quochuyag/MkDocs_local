---
title: Chapter 28 — `dbatools` configuration system
course: 11-book-lab
source: book_lab/dbatools-lab/bookcode/chapter28.notes.md
---

# Chapter 28 — `dbatools` configuration system

> Tham chiếu code gốc: [chapter28.ps1](chapter28.ps1)

> **Cảnh báo side-effect:** `Set-DbatoolsConfig` và `Reset-DbatoolsConfig` thay đổi setting áp dụng cho TOÀN BỘ session/user — có thể ảnh hưởng cả các script khác. Khi học, ưu tiên `-WhatIf` và `-Register` (persist) chỉ khi đã chắc chắn. Đặc biệt `Get-DbatoolsConfig | Reset-DbatoolsConfig` (dòng 34) sẽ **reset hết** mọi config bạn đã set — chỉ chạy khi muốn "về factory default".

## Mục tiêu
- Hiểu mô hình config hai-tầng của `dbatools`: `Module` (namespace) + `FullName` (dot-notation).
- Biết phân biệt 3 cmdlet đọc config: `Get-DbatoolsConfig` (object đầy đủ), `Get-DbatoolsConfigValue` (chỉ value), `Get-DbatoolsConfig | Where Module -eq X` (lọc).
- Biết cách reset config về mặc định và rủi ro khi làm điều này.
- Tìm được nơi `dbatools` lưu log/telemetry trên đĩa và mở thư mục đó để debug.
- Áp dụng `-WhatIf` trước bất kỳ `Set-DbatoolsConfig` nào để tránh persist setting sai.

## Tóm tắt 4 ý chính
1. **Config = key/value store trong session.** `dbatools` đẻ ra hàng trăm setting (~200+) nhóm theo `Module` (ví dụ `Logging`, `sql.connection`, `path`). Mỗi setting có `FullName` dạng `module.key` (lowercase, dot-separated).
2. **Đọc với 2 cmdlet:** `Get-DbatoolsConfig` trả `Sqlcollaborative.Dbatools.Configuration.Config` object (có Description, Validation, Value, Hidden, Initialized…); `Get-DbatoolsConfigValue` trả thẳng giá trị — tiện nhúng vào script.
3. **Ghi với `Set-DbatoolsConfig`** (không xuất hiện ở chapter này nhưng quan trọng) — mặc định chỉ tồn tại trong session. Thêm `-Register` để persist qua restart (lưu vào user registry/JSON).
4. **`Reset-DbatoolsConfig` đưa value về default.** Pipe `Get-DbatoolsConfig | Reset-DbatoolsConfig` = reset toàn bộ — destructive với setting đã `-Register`. Reset một key cụ thể an toàn hơn: `Get-DbatoolsConfig -FullName logging.maxlogfileage | Reset-DbatoolsConfig`.

## Giải thích từng đoạn code

### Đoạn 1: dòng 18–19 — Liệt kê config của module Logging
```powershell
Get-DbatoolsConfig -Module Logging |
Select-Object FullName, Description
```
- **Ý nghĩa:** Lấy tất cả config thuộc namespace `Logging` (log path, retention, level…), chỉ hiện 2 cột `FullName` và `Description` cho gọn.
- **Output mẫu:**
  ```
  FullName                          Description
  --------                          -----------
  logging.errorlogfileenabled       Whether or not to write the error log to file
  logging.errorlogfilepath          Path to write the error log to
  logging.maxerrorfilebytes         Maximum size of the error log
  logging.maxlogfileage             Days to keep log files
  logging.maxmessagefilebytes       Maximum size of the message log
  logging.messagelogfileenabled     Whether or not to write messages to file
  ...
  ```
- **Đổi cho lab:** Giữ nguyên. Module này không phụ thuộc instance.
- **Lưu ý:** Có nhiều module khác đáng khám phá:
  - `sql.connection` — timeout, ApplicationIntent, encrypt defaults.
  - `path` — backup path, log path, export path defaults.
  - `Import` — auto-create table behavior.
  - `Formatting` — table format ouput defaults.

### Đoạn 2: dòng 24 — Đọc một setting cụ thể (full object)
```powershell
Get-DbatoolsConfig -FullName logging.maxlogfileage
```
- **Ý nghĩa:** Lấy object đầy đủ của setting "số ngày giữ log file".
- **Các property hữu ích:**
  - `Value` — giá trị hiện tại.
  - `Default` — giá trị factory default.
  - `Description` — chú thích.
  - `Validation` — script block kiểm tra value khi set (ngăn set bậy bạ).
  - `Initialized` — đã set chưa (false = đang dùng default).
  - `PolicySet` / `PolicyEnforced` — group policy có ép buộc không.
- **Đổi cho lab:** Giữ nguyên.
- **Lưu ý:** Đây là cmdlet nên dùng khi debug — `Get-DbatoolsConfigValue` chỉ cho value, mất hết metadata.

### Đoạn 3: dòng 30 — Đọc value (cho script)
```powershell
Get-DbatoolsConfigValue -FullName sql.connection.timeout
```
- **Ý nghĩa:** Trả về raw value của `sql.connection.timeout` (số giây timeout khi `Connect-DbaInstance`).
- **Đổi cho lab:** Giữ nguyên — kiểm tra timeout mặc định trên máy của bạn (thường 15s).
- **Lưu ý:**
  - Dùng cmdlet này trong script:
    ```powershell
    if ((Get-DbatoolsConfigValue -FullName sql.connection.timeout) -lt 30) {
        Set-DbatoolsConfig -FullName sql.connection.timeout -Value 30 -WhatIf
    }
    ```
  - Trả `$null` nếu setting không tồn tại — kiểm tra `-FullName` đúng chính tả.

### Đoạn 4: dòng 34 — Reset TOÀN BỘ config (nguy hiểm)
```powershell
Get-DbatoolsConfig | Reset-DbatoolsConfig
```
- **Ý nghĩa:** Lấy tất cả config rồi reset từng cái về `Default`. Side effect: mọi tùy biến bạn đã làm bị xoá.
- **Đổi cho lab — BẮT BUỘC dùng `-WhatIf` trước:**
  ```powershell
  # Xem sẽ reset cái gì trước khi reset thật
  Get-DbatoolsConfig | Reset-DbatoolsConfig -WhatIf
  ```
- **Lưu ý:**
  - Nếu chỉ muốn reset 1-2 setting: `Get-DbatoolsConfig -FullName logging.maxlogfileage | Reset-DbatoolsConfig`.
  - `-Register` setting (persist) cũng bị reset nếu bạn xoá file `dbatools_config.xml` ở `$env:APPDATA\PowerShell\dbatools\` (Windows) hoặc `~/.config/PowerShell/dbatools/` (Linux).
  - Không có "undo" — nếu cần backup, export trước: `Get-DbatoolsConfig | Export-Clixml ./dbatools-config-backup.xml`.

### Đoạn 5: dòng 38–39 — Tìm thư mục log và liệt kê file
```powershell
Get-DbatoolsConfigValue -FullName path.dbatoolslogpath -OutVariable dir
Get-ChildItem $dir
```
- **Ý nghĩa:** Đọc path log + đồng thời gán vào `$dir` (qua `-OutVariable` common parameter), rồi `ls` thư mục đó.
- **`-OutVariable`:** Common parameter của PowerShell — pipe value vào biến mà không phá output. Tương đương:
  ```powershell
  $dir = Get-DbatoolsConfigValue -FullName path.dbatoolslogpath
  Get-ChildItem $dir
  ```
- **Đổi cho lab:** Giữ nguyên. Output:
  - Windows: `$env:LOCALAPPDATA\dbatools\` hoặc `$env:APPDATA\PowerShell\dbatools\Logs`.
  - Linux: `~/.local/share/PowerShell/dbatools/`.
- **File trong thư mục:**
  - `debug-*.log` — log chi tiết của cmdlet (bật bằng `Set-DbatoolsConfig -FullName message.consoleoutput.disable -Value $false`).
  - `error-*.log` — exception trace, hữu ích khi báo bug với upstream.
  - `messages-*.csv` — toàn bộ verbose message của session.

## Lệnh thay vào lab của bạn

```powershell
# 1) Khám phá: có bao nhiêu module config?
Get-DbatoolsConfig | Group-Object Module | Sort-Object Count -Descending | Select-Object -First 10 Count, Name

# 2) Đọc các setting về connection (rất hay dùng)
Get-DbatoolsConfig -Module sql.connection | Select-Object FullName, Value, Default | Format-Table -AutoSize

# 3) Đọc nhanh timeout hiện tại
$currentTimeout = Get-DbatoolsConfigValue -FullName sql.connection.timeout
"Timeout hiện tại: $currentTimeout giây"

# 4) Set thử (DÙNG -WhatIf trước, đừng -Register)
Set-DbatoolsConfig -FullName sql.connection.timeout -Value 30 -WhatIf
# Khi ổn rồi mới chạy thật (không -WhatIf), nhưng KHÔNG -Register để chỉ ảnh hưởng session
Set-DbatoolsConfig -FullName sql.connection.timeout -Value 30

# 5) Verify ảnh hưởng tới Connect-DbaInstance
Measure-Command { Test-DbaConnection -SqlInstance 'dbatoolslab\sql2017' }

# 6) Reset chỉ setting vừa đổi (an toàn)
Get-DbatoolsConfig -FullName sql.connection.timeout | Reset-DbatoolsConfig -WhatIf
Get-DbatoolsConfig -FullName sql.connection.timeout | Reset-DbatoolsConfig

# 7) Tìm thư mục log và mở
$logDir = Get-DbatoolsConfigValue -FullName path.dbatoolslogpath
Get-ChildItem $logDir -Filter '*.log' | Sort-Object LastWriteTime -Descending | Select-Object -First 5

# 8) BACKUP config trước khi thử nghiệm rộng
Get-DbatoolsConfig | Export-Clixml "$HOME/dbatools-config-backup-$(Get-Date -Format yyyyMMdd).xml"
```

## Self-check (3 câu)
1. **Định nghĩa:** Khác biệt giữa `Get-DbatoolsConfig` và `Get-DbatoolsConfigValue` là gì? Khi nào bạn nên dùng cái nào trong một script automation?
2. **Thực hành:** Chạy `Get-DbatoolsConfig -FullName logging.maxlogfileage` rồi `Get-DbatoolsConfig -FullName logging.maxlogfileage | Format-List *`. Liệt kê tất cả property của config object — cái nào là metadata, cái nào là value runtime?
3. **Liên hệ:** Tại sao chapter 28 (config) lại đặt SAU chapter 27 (cloud)? Có setting nào ở chapter 28 ảnh hưởng trực tiếp tới scenario chapter 27 không? (Gợi ý: `sql.connection.timeout`, `sql.connection.encrypt`, `path.dbatoolslogpath`).

## Bài tập mở rộng
- **Bài 1 (~5 phút):** Viết function `Show-DbatoolsModifiedConfig` — liệt kê tất cả setting có `Initialized -eq $true` (tức bạn đã chủ động set, khác default). Hữu ích để biết "máy mình có gì đặc biệt".
- **Bài 2 (sâu hơn):** Viết script `Export-LabConfig.ps1` / `Import-LabConfig.ps1` — export config hiện tại ra file JSON, và import lại trên máy khác (dùng `Set-DbatoolsConfig -FullName X -Value Y -Register` cho từng key). Đây là cách share standard config giữa các máy DBA trong team.
- **Bài 3 (production-aware):** Đọc `Get-Help Set-DbatoolsConfig -Examples` và liệt kê 3 setting bạn sẽ `-Register` ngay trên máy work để khớp policy team (ví dụ: bật `sql.connection.encrypt`, set default backup path, tắt telemetry).


---

!!! info "Nguồn gốc"
    `book_lab/dbatools-lab/bookcode/chapter28.notes.md`
