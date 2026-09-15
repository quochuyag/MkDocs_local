# MkDocs_local — Thư viện khóa học DBA

Quản lý tập trung **578 bài học tiếng Việt** từ **11 khóa học** nằm rải rác trong `D:\Dba_project`.

> Site hiện **chỉ lấy bài có nội dung tiếng Việt**. Muốn lấy lại toàn bộ
> (kể cả tiếng Anh, 1.097 bài / 14 khóa), sửa `manifest/courses.yml`:
> `vietnamese_only.enabled: false` rồi chạy `.\serve.ps1 -Sync`.

## Chạy

Cách nhanh nhất: **bấm đúp vào `start.bat`** — tự tạo venv nếu chưa có,
chạy server và tự mở trình duyệt khi site sẵn sàng.

```powershell
.\start.bat              # chạy server -> http://127.0.0.1:8000
.\start.bat sync         # đồng bộ lại bài học từ nguồn, rồi chạy
.\start.bat 8080         # chạy ở port khác
.\start.bat sync 8080    # đồng bộ + đổi port

.\serve.ps1              # tương đương, nhưng không tự mở trình duyệt
.\serve.ps1 -Sync -Port 8080
```

> Lần build đầu mất khoảng 30 giây (gần 600 bài). Trình duyệt chỉ mở
> khi server thật sự lên, nên không gặp trang lỗi.

## Nguyên tắc quan trọng

**File gốc không bao giờ bị thay đổi.** Thư mục `docs/` là bản sinh tự động,
xoá lúc nào cũng được vì `sync.py` dựng lại được 100%.

```
D:\Dba_project\<khóa học>\*.md   (giữ nguyên)
            |
            v
   manifest\courses.yml          (khai báo 14 khóa — sửa ở đây)
            |
            v
   scripts\sync.py               (chuẩn hoá tên + viết lại link)
            |
            v
   docs\                         (bản sinh — không commit)
            |
            v
   mkdocs serve                  (site xem được)
```

## Quy ước đặt tên

Tên file trong `docs/` chỉ dùng `a-z`, `0-9`, `-`. Không khoảng trắng,
không dấu tiếng Việt, không viết hoa.

| File gốc | Trong docs/ |
|---|---|
| `055 - 058 - Managing Tablespaces/Managing Tablespaces.md` | `055-managing-tablespaces.md` |
| `04_huong_dan_swingbench.md` | `04-huong-dan-swingbench.md` |
| `About Oracle Database Administrator (DBA).md` | `about-oracle-database-administrator-dba.md` |

Prefix số được giữ lại để **sắp xếp tăng dần** đúng thứ tự học.
Tiêu đề hiển thị vẫn có dấu tiếng Việt đầy đủ, lấy từ `# H1` của bài
và lưu trong front-matter `title:`.

Mỗi trang có hộp **"Nguồn gốc"** ở cuối, chỉ rõ file gốc nằm đâu.

## Thêm / sửa khóa học

Mở `manifest\courses.yml`:

```yaml
  - id: "15-khoa-moi"          # tên thư mục trong docs/ (quyết định thứ tự)
    title: "15. Tên hiển thị"   # tên trên thanh điều hướng
    path: "Ten-Thu-Muc-Goc"     # thư mục trong D:\Dba_project
    desc: "Mô tả ngắn."
```

Rồi chạy `.\serve.ps1 -Sync`.

Muốn đổi thứ tự khóa → đổi số `id` (`01-`, `02-`, …).
Muốn bỏ qua thư mục rác ở mọi khóa → thêm vào `exclude_dirs`.

## Cấu trúc

| Đường dẫn | Vai trò |
|---|---|
| `mkdocs.yml` | Cấu hình site (theme, search tiếng Việt, plugin) |
| `manifest/courses.yml` | Khai báo 14 khóa học — **file cần sửa nhiều nhất** |
| `scripts/sync.py` | Gom bài học, chuẩn hoá tên, viết lại link, copy ảnh |
| `start.bat` | Bấm đúp để chạy — gọi `serve.ps1` rồi mở trình duyệt |
| `serve.ps1` | Chạy nhanh (tạo venv, sync, serve) |
| `docs/` | Bản sinh tự động (trong `.gitignore`) |
| `site/` | HTML build ra (trong `.gitignore`) |

## Ghi chú

- `sync.py` tự bỏ file trùng **byte-for-byte trong cùng một khóa**
  (khóa RMAN: bỏ 17 bản trùng).
- Trùng lặp **giữa các khóa** được giữ nguyên, vì mỗi khóa là một đơn vị độc lập.
- 367 file ảnh/script đi kèm bài học được copy sang `docs/` và link đã được sửa.
- Còn 42 link hỏng — là link chết sẵn trong tài liệu gốc (trỏ tới file không tồn tại).
