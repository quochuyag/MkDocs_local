---
title: 🔑 Hướng dẫn Cấu hình Google Drive API
course: 02-rman-backup-recovery
source: Oracle-Database-Backup-and-Recovery-using-RMAN/tools/SETUP_GDRIVE.md
---

# 🔑 Hướng dẫn Cấu hình Google Drive API

## Mục đích
Lấy file `credentials.json` để script `upload_to_drive.py` có thể upload file lên Google Drive.
Chỉ cần làm **1 lần duy nhất**.

---

## Các bước thực hiện

### Bước 1: Tạo Google Cloud Project

1. Truy cập: https://console.cloud.google.com/
2. Click **"Select a project"** → **"New Project"**
3. Đặt tên: `RMAN-NotebookLM` → Click **"Create"**

---

### Bước 2: Bật Google Drive API

1. Vào menu: **APIs & Services → Library**
2. Tìm kiếm: `Google Drive API`
3. Click vào kết quả → Click **"Enable"**

---

### Bước 3: Tạo OAuth2 Credentials

1. Vào: **APIs & Services → Credentials**
2. Click **"+ Create Credentials"** → chọn **"OAuth client ID"**
3. Nếu được hỏi Configure Consent Screen:
   - Chọn **"External"** → Fill in App name: `RMAN Uploader`
   - Email: email của bạn → Save
   - **Scopes**: Add scope → tìm `drive.file` → Add → Save
   - **Test users**: Add email của bạn → Save
4. Quay lại **Credentials** → **"+ Create Credentials"** → **"OAuth client ID"**
5. Application type: **"Desktop app"**
6. Name: `RMAN VSCode Uploader` → Click **"Create"**
7. Click **"Download JSON"**
8. **Đổi tên file** thành `credentials.json`
9. **Copy vào thư mục**: `tools/credentials.json`

---

### Bước 4: Chạy lần đầu (xác thực)

```powershell
# Mở Terminal trong VS Code (Ctrl + `)
pip install google-api-python-client google-auth-httplib2 google-auth-oauthlib

# Chạy upload lần đầu → trình duyệt sẽ mở để login Google
python tools/upload_to_drive.py --list
```

- Trình duyệt mở → Đăng nhập Google Account của bạn → Click **"Allow"**
- Token được lưu tại `tools/token.json` → **Lần sau không cần login lại**

---

## Sử dụng từ VS Code

### Cách 1: Chạy qua Task (Ctrl+Shift+P)
1. Nhấn `Ctrl+Shift+P`
2. Gõ: `Tasks: Run Task`
3. Chọn task muốn chạy:

| Task | Chức năng |
|------|-----------|
| `📤 Upload ALL Guides → Google Drive` | Upload tất cả file .md |
| `📤 Upload Current File → Google Drive` | Upload file đang mở |
| `📤 Upload modules/ → Google Drive` | Chỉ upload thư mục modules |
| `📤 Upload reviews_all/ → Google Drive` | Chỉ upload thư mục reviews |
| `📋 List Files on Google Drive` | Xem file đã upload |

### Cách 2: Chạy trực tiếp từ Terminal
```powershell
# Upload tất cả
python tools/upload_to_drive.py

# Upload file đang làm việc
python tools/upload_to_drive.py --file modules/module_16_guide.md

# Upload 1 thư mục
python tools/upload_to_drive.py --folder reviews_all

# Xem danh sách file đã upload
python tools/upload_to_drive.py --list
```

---

## Thêm vào NotebookLM

Sau khi upload xong:
1. Vào: https://notebooklm.google.com
2. Mở notebook → **"+ Add source"**
3. Chọn **"Google Drive"**
4. Tìm folder: **`RMAN_NotebookLM`**
5. Chọn các file muốn thêm → **"Insert"**

---

## Cấu trúc file sau khi setup

```
tools/
├── upload_to_drive.py    ✅ Script upload chính
├── credentials.json      ⚠️  Bạn cần tạo (xem Bước 3)
└── token.json            🔄 Tự tạo sau lần login đầu
.vscode/
└── tasks.json            ✅ VS Code Tasks đã cấu hình
```

---

> ⚠️ **Bảo mật**: Đừng commit `credentials.json` và `token.json` lên Git.
> File `.gitignore` đã được cập nhật để loại trừ 2 file này.


---

!!! info "Nguồn gốc"
    `Oracle-Database-Backup-and-Recovery-using-RMAN/tools/SETUP_GDRIVE.md`
