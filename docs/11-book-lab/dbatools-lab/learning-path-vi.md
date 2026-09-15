---
title: Lộ trình học dbatools-lab — Hướng dẫn bắt đầu
course: 11-book-lab
source: book_lab/dbatools-lab/LEARNING_PATH_VI.md
---

# Lộ trình học dbatools-lab — Hướng dẫn bắt đầu

Tài liệu này trả lời 3 câu hỏi: **bắt đầu thế nào**, **có nên thêm chú thích vào `chapter*.ps1` không**, và **mô hình học khuyến nghị**.

> Đây là tài liệu **hành động** (làm gì, theo thứ tự nào).
> Tài liệu cấu trúc repo: [PROJECT_GUIDE_VI.md](PROJECT_GUIDE_VI.md).
> Tài liệu cho agent Claude: [CLAUDE.md](claude.md).

---

## 1) Hai đường bắt đầu — chọn 1

### Đường A — Devcontainer Docker (khuyến nghị 2 tuần đầu)

**Khi nào dùng:** Bạn chỉ có laptop, chưa có Windows Server hoặc media SQL, muốn chạy được lệnh `dbatools` ngay trong ngày.

**Cần có:**
- Docker Desktop (Windows/Mac/Linux)
- VS Code + extension "Dev Containers"

**Bước:**
1. Mở repo này trong VS Code → `F1` → `Dev Containers: Reopen in Container`.
2. Container `dbatoolslab` (SQL 2019 trên Linux) sẽ build từ [.devcontainer/dockerfile](.devcontainer/dockerfile). Compose còn 1 container thứ hai `dbatoolslab2` (đang có lỗi `depends_on: dbatoolslab1` ở [.devcontainer/docker-compose.yml:18](devcontainer/docker-compose.yml#L18) — nếu lỗi, sửa thành `dbatoolslab`).
3. Trong terminal pwsh của container:
   ```powershell
   $secpass = ConvertTo-SecureString 'dbatools.IO' -AsPlainText -Force
   $cred = New-Object System.Management.Automation.PSCredential('sa', $secpass)
   Connect-DbaInstance -SqlInstance localhost -SqlCredential $cred
   ```
4. Test bằng `Get-Command -Module dbatools | Measure-Object`.

**Giới hạn:** SQL trên Linux không có SQL Server Agent đầy đủ tính năng, không có một số module legacy. Các chapter về Agent/Windows-only sẽ phải bỏ qua hoặc chuyển sang Đường B.

### Đường B — Full Windows Lab

**Khi nào dùng:** Bạn cần học migration, Agent jobs phức tạp, hoặc chapter có dùng tính năng Windows-only.

**Cần có:**
- Máy Windows (10/11 hoặc Server) với ≥16GB RAM, ≥80GB ổ trống
- Media cài SQL Server 2017 + 2019 (giải nén vào `Z:\Install\2017` và `Z:\Install\2019`)
- Quyền admin
- Kết nối internet (để `00_Install_Prereqs.ps1` chạy chocolatey)

**Bước:**
1. Sửa [config/Config.psd1](config/config.psd1) nếu `Z:\Install` hoặc `C:\dbatoolslab\Backup` không khớp môi trường.
2. Chạy lần lượt (từ thư mục root repo, pwsh as Administrator):
   ```powershell
   .\scripts\00_Install_Prereqs.ps1   # cài module + tải 2 file .bak
   .\scripts\01_Install_Lab.ps1       # cài 2 instance
   .\scripts\02_Configure_Lab.ps1     # restore DB + tạo login/job
   ```
3. Verify:
   ```powershell
   Find-DbaInstance -ComputerName dbatoolslab
   Get-DbaDatabase -SqlInstance dbatoolslab\sql2017 | Select Name, Status
   ```

**Cảnh báo:** `99_Cleanup_Lab.ps1` đang **rỗng** — không có teardown tự động. Nếu muốn dẹp lab, phải làm thủ công hoặc viết thêm.

### Quyết định nhanh

| Tình huống | Đường |
|---|---|
| Chỉ muốn thử lệnh dbatools, không cần đủ feature | A |
| Học chapter02-12 (foundations, backup/restore) | A đủ |
| Học chapter13-17 (migration), chapter18-20 (Agent) | B (hoặc A + giới hạn) |
| Tự bỏ tiền dựng VM Azure | Xem [advanced/readme.md](advanced/readme.md) (chỉ là placeholder) |

---

## 2) Có nên thêm chú thích vào `chapter*.ps1`?

**Khuyến nghị: KHÔNG sửa file gốc. Tạo file companion riêng.**

**Lý do:**
- Các file `chapter*.ps1` có disclaimer rõ ràng "code from the book". Sửa trực tiếp = mất khả năng đối chiếu lại sách.
- Code gốc còn dùng tên instance mẫu (`spsql01`, `sql01`, `mssql1`) khác lab thật — nếu chú thích lẫn vào, ranh giới "code book" và "ghi chú của tôi" sẽ mờ đi.
- Khi `dbatools` ra version mới, chỉ cần pull lại code book không lo conflict.

**Đề xuất:** Tạo file `bookcode/chapterXX.notes.md` ngay cạnh `chapterXX.ps1`. Một file `.ps1` ↔ một file `.notes.md`.

**Template companion file** (xem mẫu cụ thể ở mục 4):
```
# Chapter XX — Tên chủ đề

## Mục tiêu chapter này
## Tóm tắt 3-5 ý chính
## Giải thích từng đoạn code
## Lệnh tự thay vào lab của bạn (đổi instance name)
## Self-check (3 câu hỏi)
## Bài tập mở rộng
```

**Lợi ích:**
- Đọc song song `.ps1` (code gốc) + `.notes.md` (lời giải thích của bạn).
- Sau này mở `bookcode/` thấy ngay file `.notes.md` nào đã viết → biết đã học đến đâu.
- Có thể commit ghi chú riêng mà không đụng code book.

---

## 3) Mô hình học — Vòng lặp 4 bước cho mỗi chapter

```
┌─────────────────────────────────────────────────────────────┐
│  Bước 1: PRE-READ   →  Đọc chapter trong PDF (~20-30 phút)  │
│           Mục tiêu: nắm khái niệm trước khi gõ lệnh         │
├─────────────────────────────────────────────────────────────┤
│  Bước 2: RUN CODE   →  Chạy bookcode/chapterXX.ps1          │
│           - Mở .ps1 trong VS Code                           │
│           - Đổi instance name cho khớp lab                  │
│           - Chạy TỪNG block (giữa các ########)             │
│           - Ghi output bất thường vào .notes.md             │
├─────────────────────────────────────────────────────────────┤
│  Bước 3: REFLECT    →  Mở notebook cùng chủ đề (nếu có)     │
│           Ví dụ: chapter11 (backup) ↔                       │
│           notebooks/DotNet/02-BackupsRestores.ipynb         │
│           So sánh: code book vs cách dùng tương tác         │
├─────────────────────────────────────────────────────────────┤
│  Bước 4: SELF-CHECK →  Trả lời 3 câu hỏi tự ra              │
│           - 1 câu định nghĩa (gọi lệnh gì để làm X?)        │
│           - 1 câu thực hành (chạy thử lệnh không dùng -WhatIf)│
│           - 1 câu liên hệ (lệnh này khác lệnh chapter trước ở đâu?)│
└─────────────────────────────────────────────────────────────┘
```

**Thời gian khuyến nghị/chapter:** 60-90 phút (đọc 25 + chạy 30 + reflect 15 + self-check 15).

**Nguyên tắc an toàn:**
- Mọi lệnh có thể ghi dữ liệu (`Backup-*`, `Restore-*`, `Remove-*`, `Set-*`, `New-Db*`) **chạy với `-WhatIf` trước**, rồi mới chạy thật.
- Không học chapter migration trên DB production. Chỉ làm trên sample DB (WideWorldImporters, AdventureWorks2017).
- Nếu hỏng lab: xoá container (Đường A) hoặc gỡ instance thủ công (Đường B) rồi chạy lại `01_` + `02_`.

---

## 4) Lộ trình 7 tuần (đã có sẵn, đặt lại theo model 4 bước)

> Lộ trình gốc xem [PROJECT_GUIDE_VI.md mục 7](PROJECT_GUIDE_VI.md). Bảng dưới gắn cụ thể bước thực hành.

| Tuần | Chapter | Notebook đi kèm | Output bạn cần tạo |
|---|---|---|---|
| 1 | Setup lab + 02-04 | — | `chapter02.notes.md`, `chapter03.notes.md`, `chapter04.notes.md` |
| 2 | 05-08 | `01-Introduction.ipynb` | 4 notes file |
| 3 | 09-12 | `02-BackupsRestores.ipynb` | 4 notes file + 1 sample backup thật trong `BackupPath` |
| 4 | 13-17 | `04-LoginsAndUsers.ipynb` | 5 notes file |
| 5 | 18-20 | `06-AgentJobs.ipynb` | 3 notes file + ít nhất 1 Agent job tự tạo |
| 6 | 21-26 | `05-ExtendedEvents.ipynb` | 6 notes file |
| 7 | 27-29 | — | 3 notes file + checklist self-review |

---

## 5) Mẫu companion file — `chapter02.notes.md`

> Khi user thấy mẫu này OK, tôi có thể sinh hàng loạt template trống cho 28 chapter còn lại.

```markdown
# Chapter 02 — Setting up your PowerShell environment for dbatools

## Mục tiêu
- Biết cách kiểm tra PowerShell có thể load dbatools.
- Hiểu `$Env:PSModulePath` và vai trò của PSGallery repository.
- Cài đặt + import được dbatools trong môi trường lab.

## Tóm tắt 3 ý chính
1. **PowerShell remoting** (`Invoke-Command`) là nền tảng để chạy lệnh trên server khác — chapter sau sẽ dùng nhiều.
2. **`$Env:PSModulePath`** quyết định PowerShell tìm module ở đâu. Nếu dbatools không load được, kiểm tra biến này trước.
3. **PSGallery phải Trusted** thì `Install-Module` không hỏi xác nhận từng lần.

## Giải thích từng đoạn code (theo file chapter02.ps1)

### Đoạn 1: dòng 18
\`\`\`powershell
Invoke-Command -ComputerName spsql01 -ScriptBlock { $Env:COMPUTERNAME }
\`\`\`
- **Ý nghĩa:** Chạy `$Env:COMPUTERNAME` trên máy `spsql01` từ xa, kết quả trả về máy local.
- **Đổi cho lab:** Thay `spsql01` bằng `dbatoolslab` (hoặc `localhost` nếu đang trong devcontainer).
- **Yêu cầu:** WinRM phải bật ở máy đích (chapter này chưa setup → có thể fail, bình thường).

### Đoạn 2: dòng 22
\`\`\`powershell
$Env:PSModulePath -Split ";"
\`\`\`
- **Ý nghĩa:** Liệt kê các thư mục PowerShell sẽ quét để tìm module.
- **Quan sát:** Thường thấy `C:\Program Files\WindowsPowerShell\Modules` và `C:\Users\<you>\Documents\PowerShell\Modules`.

### Đoạn 3: dòng 26
\`\`\`powershell
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
\`\`\`
- **Ý nghĩa:** Đánh dấu PSGallery là nguồn tin cậy → `Install-Module` không hỏi prompt.
- **An toàn:** OK với lab. Trên production cân nhắc kỹ.

### Đoạn 4: dòng 30
\`\`\`powershell
Import-Module dbatools
\`\`\`
- **Ý nghĩa:** Nạp module vào session hiện tại. Nếu đã `Install-Module dbatools` ở [scripts/00_Install_Prereqs.ps1](scripts/00-install-prereqs.ps1#L19) thì PowerShell 5.1+ thường tự import khi gọi cmdlet đầu tiên.

## Lệnh thay vào lab của bạn

\`\`\`powershell
# Verify dbatools đã sẵn sàng
Get-Module -ListAvailable dbatools | Select-Object Name, Version
Get-Command -Module dbatools | Measure-Object  # ~600+ commands là OK

# Test ping instance lab
Test-DbaConnection -SqlInstance dbatoolslab\sql2017
\`\`\`

## Self-check (3 câu)
1. **Định nghĩa:** Lệnh nào để xem PSGallery hiện đang Trusted hay Untrusted?
2. **Thực hành:** Chạy `Get-Module dbatools` (không có `-ListAvailable`). Output khác `Get-Module -ListAvailable` ở điểm gì?
3. **Liên hệ:** Tại sao chapter này lại đứng trước chapter cài instance? (Gợi ý: dùng dbatools cho việc gì ở chapter sau?)

## Bài tập mở rộng
- Viết 1 function `Test-LabReady` trả về `$true` nếu cả `dbatools` đã import và `Test-DbaConnection -SqlInstance dbatoolslab\sql2017` thành công.
- Lưu function vào `$PROFILE` để mỗi lần mở pwsh tự load.
```

---

## 6) Checklist hành động ngay hôm nay

- [ ] Quyết định Đường A hay Đường B (mục 1).
- [ ] Setup môi trường theo đường đã chọn.
- [ ] Đọc lướt 5 phút phần Chapter 2 trong PDF.
- [ ] Tạo file `bookcode/chapter02.notes.md` từ template mục 5.
- [ ] Chạy từng block trong [bookcode/chapter02.ps1](bookcode/chapter02.ps1), ghi quan sát vào notes file.
- [ ] Tự trả lời 3 câu self-check.
- [ ] Bắt đầu chapter 3.

---

## 7) Khi bạn muốn tôi giúp tiếp

Nhắn 1 trong các yêu cầu sau:
- *"Sinh template trống `chapterXX.notes.md` cho tất cả 28 chapter"* — tôi sẽ tạo hàng loạt.
- *"Viết notes file chi tiết cho chapter X"* — tôi đọc `chapterX.ps1` và viết đầy đủ như mẫu mục 5.
- *"Sửa file devcontainer bị lỗi `depends_on`"* — fix bug đã ghi ở [CLAUDE.md mục 5](claude.md).
- *"Viết script `99_Cleanup_Lab.ps1`"* — implement teardown logic.
- *"Viết Pester tests đầy đủ cho install/configure"* — bổ sung 3 file test hiện rỗng.


---

!!! info "Nguồn gốc"
    `book_lab/dbatools-lab/LEARNING_PATH_VI.md`
