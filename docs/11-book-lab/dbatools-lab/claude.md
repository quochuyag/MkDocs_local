---
title: CLAUDE.md
course: 11-book-lab
source: book_lab/dbatools-lab/CLAUDE.md
---

# CLAUDE.md

Tài liệu định hướng cho Claude khi làm việc trong repo này. Mục đích: hỗ trợ nghiên cứu, phân tích, và mở rộng lab học `dbatools` theo sách *Learn dbatools in a Month of Lunches*.

> Tài liệu chi tiết hơn về cấu trúc và lộ trình học đã có sẵn ở:
> - [PROJECT_GUIDE.md](PROJECT_GUIDE.md) — English
> - [PROJECT_GUIDE_VI.md](PROJECT_GUIDE_VI.md) — Tiếng Việt
> CLAUDE.md không lặp lại nội dung đó; chỉ bổ sung context cần thiết cho agent.

---

## 1) Bản chất dự án

- **Loại repo:** Learning lab (không phải sản phẩm production).
- **Mục tiêu:** Dựng môi trường SQL Server + `dbatools` để học theo 28 chapter của cuốn *Learn dbatools in a Month of Lunches* (Chrissy LeMaire, Rob Sewell, Jess Pomfret, Cláudio Silva).
- **Ngôn ngữ chính:** PowerShell (.ps1, .psd1), Jupyter Notebooks (.ipynb cho ADS), YAML (CI + Docker compose).
- **Nguồn sách:** `Learn dbatools in a Month of Lu - Chrissy LeMaire, Rob Sewell, Je.pdf` ở root — dùng làm chuẩn đối chiếu chapter/lunch.

## 2) Bản đồ thư mục (rút gọn cho agent)

| Đường dẫn | Vai trò | Ghi chú phân tích |
|---|---|---|
| [config/Config.psd1](config/config.psd1) | Cấu hình dùng chung (`InstallMediaPath`, `BackupPath`) | Mặc định `Z:\Install` và `C:\dbatoolslab\Backup` — thường cần sửa cho từng máy |
| [scripts/](scripts/) | 4 script setup theo thứ tự `00 → 01 → 02 → 99` | `99_Cleanup_Lab.ps1` **đang rỗng** — gap đã biết |
| [bookcode/](bookcode/) | `chapter02.ps1` → `chapter29.ps1` + `AllTheCode.ps1` | `chapter29.ps1` là bài thực hành bổ sung của lab (không có trong sách); các chapter khác dùng tên instance mẫu (`spsql01`, `sql01`, `mssql1`) cần đổi cho lab thật |
| [notebooks/DotNet/](notebooks/DotNet/) | Track notebook hiện đại (.NET Interactive) | Có `docker-compose.yml` riêng, ảnh trong `images/` |
| [notebooks/NotDotNet/](notebooks/NotDotNet/) | Track notebook legacy, truyền `-SqlCredential` rõ ràng | Có thêm `Update-Ola-Without-Breaking-Jobs.ipynb` |
| [tests/](tests/) | 4 file Pester — **chỉ `install.tests.ps1` có khung sơ sài, các file khác rỗng** | `tests/setup/docker-compose.yml` dùng cho CI |
| [.devcontainer/](.devcontainer/) | Dev container build từ `mcr.microsoft.com/mssql/server:2019-latest` + cài pwsh, Pester 4.4.3, dbatools | Compose chạy 2 instance `dbatoolslab` (1401) và `dbatoolslab2` (1402) |
| [.github/workflows/pestering.yml](github/workflows/pestering.yml) | CI manual `workflow_dispatch`: docker compose up → `Invoke-DbcCheck InstanceConnection` | Chưa chạy theo PR/push |
| [.github/agents/](.github/agents/) | 2 agent định nghĩa: `claude-researcher` và `dbatools-book-tutor` (bằng tiếng Việt) | Đây là agent VS Code Copilot, không phải sub-agent Claude Code |
| [advanced/](advanced/) | Placeholder cho Terraform/Azure VM | Chỉ có readme |
| [backup_copilot/](backup_copilot/) | 2 file zip do user backup ngoài repo flow | Không cần đụng tới trừ khi user yêu cầu |
| [csv/](csv/) | Thư mục dữ liệu mẫu, hiện trống | |

## 3) Workflow chuẩn (rút gọn)

```
00_Install_Prereqs.ps1  →  cài module + tải .bak (cần internet + chocolatey)
01_Install_Lab.ps1      →  Install-DbaInstance SQL 2019 default + SQL 2017 named (\sql2017)
02_Configure_Lab.ps1    →  Restore WWI + AdventureWorks2017, tạo login WWI_*, jobs, Ola, sp_configure
99_Cleanup_Lab.ps1      →  (TRỐNG — cần implement nếu user yêu cầu teardown)
```

Sample DB chính: **WideWorldImporters**, **AdventureWorks2017** — restore lên `dbatoolslab\sql2017`.
Sample login: `WWI_ReadOnly`, `WWI_ReadWrite`, `WWI_Owner` (password hard-code `N0t@SecureP@ssw0rd!` — chỉ dùng cho lab, **không bao giờ đề xuất pattern này cho production**).

## 4) Quy ước & conventions để tuân theo

- **PowerShell style:** Splatting (`@hashtable`) đã được dùng nhất quán trong `02_Configure_Lab.ps1`. Giữ pattern này khi sửa.
- **Đặt tên instance:** Lab thật dùng `dbatoolslab` và `dbatoolslab\sql2017`. Chapter scripts dùng tên mẫu khác — **khi user chạy chapter cần đổi instance name trước**.
- **An toàn lệnh dbatools:** Ưu tiên `-WhatIf` cho mọi lệnh có khả năng ghi (Backup, Restore, Remove, New-Db*). Pattern này đã có trong `chapter29.ps1`.
- **Encoding:** Repo dùng tiếng Việt không dấu trong các file `.md` cũ (PROJECT_GUIDE_VI). Khi viết tài liệu mới, có thể dùng dấu đầy đủ — không cần ép theo style không dấu.
- **Không commit `.bak`:** `.gitignore` đã loại trừ.

## 5) Gaps đã biết (cơ hội cải thiện)

| Gap | Vị trí | Ghi chú |
|---|---|---|
| Cleanup script trống | [scripts/99_Cleanup_Lab.ps1](scripts/99-cleanup-lab.ps1) | Cần `Remove-DbaDatabase`, `Remove-DbaLogin`, `Remove-DbaAgentJob`, xoá Ola jobs |
| 3/4 file Pester rỗng | [tests/](tests/) | `prereq.tests.ps1`, `configure.tests.ps1`, `cleanup.tests.ps1` — chỉ là placeholder |
| `install.tests.ps1` có khung sai cú pháp | [tests/install.tests.ps1:6](tests/install-tests.ps1#L6) | `[Parameter]` thiếu `()`, `[ValidateNotNullOrEmpty]` thiếu `()`, `It` block rỗng |
| Chapter01 thiếu | `bookcode/` bắt đầu từ chapter02 | Có thể là cố ý (chapter 1 là intro lý thuyết) — đối chiếu PDF khi cần |
| `csv/` rỗng | [csv/](csv/) | README đề cập sample data nhưng chưa có |
| Compose có lỗi reference | [.devcontainer/docker-compose.yml:18](devcontainer/docker-compose.yml#L18) | `depends_on: dbatoolslab1` nhưng service tên là `dbatoolslab` — có thể là bug |
| CI chỉ chạy thủ công | [.github/workflows/pestering.yml](github/workflows/pestering.yml) | `workflow_dispatch` only, chưa có trigger theo PR |

## 6) Khi user hỏi/nhờ làm gì

- **"Học chapter X"** → mở `bookcode/chapterXX.ps1`, đối chiếu với PDF nếu cần xác nhận lunch number. Đưa Mục tiêu / Giải thích / Demo lệnh / Bài tập theo style của agent `dbatools-book-tutor`.
- **"Phân tích / nghiên cứu repo"** → bắt đầu từ tài liệu này, sau đó `PROJECT_GUIDE.md`, không cần grep lại cấu trúc.
- **"Setup lab"** → kiểm tra `config/Config.psd1` trước; nhắc user đổi `InstallMediaPath` nếu khác `Z:\Install`.
- **"Sửa cleanup / test"** → đây là vùng có gap thực sự, có thể viết code mới (xem mục 5).
- **Chạy lệnh thực tế:** Nếu user chưa xác nhận môi trường, dùng `-WhatIf` hoặc đề nghị verify trước khi chạy lệnh có side-effect (Install-DbaInstance, Restore-DbaDatabase, Remove-*).

## 7) Tham chiếu nhanh

- Module bắt buộc: `dbatools`, `dbachecks`, `Pester` (4.4.3 trong devcontainer).
- Backup gốc:
  - `https://github.com/Microsoft/sql-server-samples/releases/download/wide-world-importers-v1.0/WideWorldImporters-Full.bak`
  - `https://github.com/Microsoft/sql-server-samples/releases/download/adventureworks/AdventureWorks2017.bak`
- Tham khảo notebook gốc: [SQLDBAWithABeard/JupyterNotebooks](https://github.com/SQLDBAWithABeard/JupyterNotebooks).
- Khi cần tra cứu cú pháp `dbatools`, dùng MCP **Context7** (resolve-library-id → query-docs) thay vì đoán theo trí nhớ.

## 8) Phạm vi không nên tự ý thay đổi

- Không tự thêm production-grade hardening (LDAP, AD auth, secret store) — đây là lab học, password yếu là cố ý.
- Không refactor lớn `bookcode/` — code đó phải khớp với sách.
- Không xoá `backup_copilot/` — đó là backup do user tạo ngoài flow chính.


---

!!! info "Nguồn gốc"
    `book_lab/dbatools-lab/CLAUDE.md`
