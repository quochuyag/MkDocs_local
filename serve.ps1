# Chay MkDocs local. Mo trinh duyet tai http://127.0.0.1:8000
# Cach dung:  .\serve.ps1          -> chay server
#             .\serve.ps1 -Sync    -> dong bo lai bai hoc roi chay

param(
    [switch]$Sync,
    [int]$Port = 8000
)

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

$py = Join-Path $PSScriptRoot ".venv\Scripts\python.exe"
if (-not (Test-Path $py)) {
    Write-Host "Chua co venv. Dang tao..." -ForegroundColor Yellow
    python -m venv .venv
    & $py -m pip install --upgrade pip --quiet
    & $py -m pip install -r requirements.txt --quiet
}

if ($Sync) {
    Write-Host "Dang dong bo bai hoc tu D:\Dba_project ..." -ForegroundColor Cyan
    & $py scripts\sync.py
    Write-Host ""
}

Write-Host "MkDocs dang chay tai http://127.0.0.1:$Port  (Ctrl+C de dung)" -ForegroundColor Green
& $py -m mkdocs serve --dev-addr "127.0.0.1:$Port"
