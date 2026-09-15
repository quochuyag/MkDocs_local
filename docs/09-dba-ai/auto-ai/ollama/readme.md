---
title: Ollama — LLM cục bộ
course: 09-dba-ai
source: dba_ai/auto_ai/ollama/README.md
---

# Ollama — LLM cục bộ

## Khởi động

```powershell
# Khởi động Ollama qua Docker (cùng với Open-WebUI)
.\..\scripts\start-all.ps1

# Chỉ Ollama
docker compose -f docker-compose.yml up -d
```

## Pull model mặc định

```powershell
.\..\scripts\pull-models.ps1
```

Danh sách model trong [../scripts/pull-models.ps1](../scripts/pull-models.ps1) — chỉnh nếu muốn thêm/bớt.

## Build custom model từ Modelfile

```powershell
.\..\scripts\build-custom-models.ps1
```

Tạo các model:
- `auto_ai-coder` — coder với system prompt tiếng Việt ([Modelfile.coder](Modelfile.coder))
- `auto_ai-tutor` — gia sư Socratic ([Modelfile.tutor](Modelfile.tutor))
- `auto_ai-reviewer` — code reviewer structured output ([Modelfile.reviewer](Modelfile.reviewer))

## Test thủ công

```powershell
# Liệt kê model đã có
ollama list

# Chat thử
ollama run auto_ai-coder "Viết hàm Python tính fibonacci đệ quy"

# Gọi qua API
curl http://localhost:11434/api/generate -d '{\"model\":\"auto_ai-coder\",\"prompt\":\"hello\",\"stream\":false}'
```

## GPU

Mặc định docker-compose chạy CPU. Nếu có GPU NVIDIA:

1. Cài [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html).
2. Mở [docker-compose.yml](docker-compose.yml), bỏ comment block `deploy.resources`.
3. Restart: `docker compose down && docker compose up -d`.

## Tham khảo model

| Tên                         | Size  | Use case                           |
|-----------------------------|-------|------------------------------------|
| `qwen2.5-coder:7b`          | ~5GB  | Code chat / edit chính              |
| `qwen2.5-coder:1.5b-base`   | ~1GB  | Tab autocomplete                    |
| `deepseek-coder-v2:16b`     | ~10GB | Coder mạnh hơn (cần RAM/VRAM)       |
| `llama3.1:8b`               | ~5GB  | Chat tổng quát, học tập             |
| `nomic-embed-text`          | ~270M | Embedding cho codebase              |
| `qwen2.5:14b`               | ~9GB  | Reasoning tốt hơn 7b                |


---

!!! info "Nguồn gốc"
    `dba_ai/auto_ai/ollama/README.md`
