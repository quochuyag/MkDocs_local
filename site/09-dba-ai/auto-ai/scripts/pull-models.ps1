# Pull các model Ollama mặc định.
# Sửa mảng $models bên dưới để thêm/bớt.

. "$PSScriptRoot\_common.ps1"
$ErrorActionPreference = 'Stop'

# Danh sách model (tag → mô tả)
$models = @(
    @{ Name = 'qwen2.5-coder:7b';        Desc = 'Code chat & edit chính' },
    @{ Name = 'qwen2.5-coder:1.5b-base'; Desc = 'Tab autocomplete (nhẹ)' },
    @{ Name = 'nomic-embed-text';        Desc = 'Embedding cho codebase index' }
    # gemma4:latest đã có sẵn trên máy → dùng làm chat tổng quát + base cho auto_ai-tutor.
    # Bỏ comment nếu cần thêm:
    # @{ Name = 'llama3.1:8b';           Desc = 'Chat tổng quát alt' }
    # @{ Name = 'deepseek-coder-v2:16b'; Desc = 'Coder mạnh hơn (~10GB)' }
    # @{ Name = 'qwen2.5:14b';           Desc = 'Reasoning tổng quát (~9GB)' }
)

if (-not (Test-HttpEndpoint 'http://localhost:11434/api/tags')) {
    Write-Err "Ollama chưa chạy. Khởi động: .\scripts\start-all.ps1 (Docker) hoặc .\scripts\start-native.ps1"
    exit 1
}

# Tự phát hiện: nếu container auto_ai_ollama đang chạy → dùng docker exec.
# Ngược lại (Ollama native trên Windows) → gọi `ollama` trực tiếp.
$useDocker = $false
if (Test-Command docker) {
    $running = docker ps --format '{{.Names}}' 2>$null
    if ($running -contains 'auto_ai_ollama') { $useDocker = $true }
}

function Invoke-Ollama {
    param([Parameter(ValueFromRemainingArguments)][string[]]$ArgList)
    if ($useDocker) {
        docker exec auto_ai_ollama ollama @ArgList
    } else {
        & ollama @ArgList
    }
}

foreach ($m in $models) {
    Write-Step "Pull $($m.Name) — $($m.Desc)"
    Invoke-Ollama pull $m.Name
    if ($LASTEXITCODE -ne 0) {
        Write-Warn2 "Pull $($m.Name) thất bại — bỏ qua"
    } else {
        Write-Ok $m.Name
    }
}

Write-Host ""
Write-Step "Model hiện có:"
Invoke-Ollama list
