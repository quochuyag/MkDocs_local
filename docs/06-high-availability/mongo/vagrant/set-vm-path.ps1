# set-vm-path.ps1 — đổi default machine folder của VirtualBox để VM lab lưu vào đường dẫn mong muốn.
# Chạy 1 lần TRƯỚC `vagrant up` lần đầu.
#
# Usage:
#   .\set-vm-path.ps1                                   # mặc định D:\VM VirtualBox\mongo-ha
#   .\set-vm-path.ps1 -Path "E:\Labs\mongo-ha"
#   .\set-vm-path.ps1 -Reset                            # khôi phục default của VirtualBox
[CmdletBinding()]
param(
    [string]$Path = "D:\VM VirtualBox\mongo-ha",
    [switch]$Reset
)

$ErrorActionPreference = "Stop"

# Tìm VBoxManage
$vbm = Get-Command VBoxManage -ErrorAction SilentlyContinue
if (-not $vbm) {
    $candidates = @(
        "$env:ProgramFiles\Oracle\VirtualBox\VBoxManage.exe",
        "${env:ProgramFiles(x86)}\Oracle\VirtualBox\VBoxManage.exe"
    )
    $vbm = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $vbm) {
        Write-Error "Không tìm thấy VBoxManage. Cài VirtualBox 7.0+ trước."
        exit 1
    }
}
$vbmPath = if ($vbm -is [System.Management.Automation.CommandInfo]) { $vbm.Source } else { $vbm }

if ($Reset) {
    & $vbmPath setproperty machinefolder default
    Write-Host "Đã reset machinefolder về default của VirtualBox." -ForegroundColor Green
} else {
    if (-not (Test-Path $Path)) {
        New-Item -ItemType Directory -Force -Path $Path | Out-Null
        Write-Host "Đã tạo thư mục: $Path" -ForegroundColor Yellow
    }
    & $vbmPath setproperty machinefolder $Path
    Write-Host "Đã đặt machinefolder = $Path" -ForegroundColor Green
}

Write-Host ""
Write-Host "Verify:" -ForegroundColor Cyan
& $vbmPath list systemproperties | Select-String "Default machine folder"
Write-Host ""
Write-Host "Tiếp theo: cd vagrant; make full-bootstrap (hoặc vagrant up)" -ForegroundColor Cyan
