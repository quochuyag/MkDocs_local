#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Control script for OpenClaw gateway: start, stop, restart, reload, status.

.DESCRIPTION
  Wrap around `openclaw daemon` (schtasks-based service on Windows) plus a
  few extras: validate config before reload, list cron + MCP + channels,
  tail logs. Use after editing openclaw.json or paired.json.

.PARAMETER Action
  start    - start gateway service (no-op if already running)
  stop     - stop gateway service
  restart  - stop + start
  reload   - alias of restart, runs `openclaw config validate` first
  status   - daemon status + cron + MCP + channels
  logs     - tail latest log file

.EXAMPLE
  pwsh -File scripts/openclaw-ctl.ps1 reload
  pwsh -File scripts/openclaw-ctl.ps1 status

.NOTES
  If PowerShell blocks the script with "running scripts is disabled":
    Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
  Or invoke once with: pwsh -NoProfile -ExecutionPolicy Bypass -File ...
#>

[CmdletBinding()]
param(
  [Parameter(Mandatory = $true, Position = 0)]
  [ValidateSet('start', 'stop', 'restart', 'reload', 'status', 'logs')]
  [string]$Action
)

$ErrorActionPreference = 'Stop'

function Invoke-Openclaw {
  param([Parameter(ValueFromRemainingArguments = $true)] [string[]]$Args)
  & openclaw @Args
  if ($LASTEXITCODE -ne 0) { throw "openclaw $($Args -join ' ') exited $LASTEXITCODE" }
}

function Step($msg) {
  Write-Host ""
  Write-Host "[ctl] $msg" -ForegroundColor Cyan
}

function Test-Config {
  Step "openclaw config validate"
  Invoke-Openclaw config validate
}

function Show-Status {
  Step "openclaw daemon status"
  Invoke-Openclaw daemon status

  Step "openclaw cron list"
  Invoke-Openclaw cron list

  Step "openclaw mcp list"
  Invoke-Openclaw mcp list

  Step "openclaw channels list"
  Invoke-Openclaw channels list
}

switch ($Action) {
  'start' {
    Step "openclaw daemon start"
    Invoke-Openclaw daemon start
  }
  'stop' {
    Step "openclaw daemon stop"
    Invoke-Openclaw daemon stop
  }
  'restart' {
    Step "openclaw daemon restart"
    Invoke-Openclaw daemon restart
    Start-Sleep -Seconds 2
    Show-Status
  }
  'reload' {
    Test-Config
    Step "openclaw daemon restart (reload)"
    Invoke-Openclaw daemon restart
    Start-Sleep -Seconds 2
    Show-Status
  }
  'status' {
    Show-Status
  }
  'logs' {
    $logDir = Join-Path $env:USERPROFILE '.openclaw\logs'
    $latest = Get-ChildItem -Path $logDir -Filter '*.log' -ErrorAction SilentlyContinue |
      Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $latest) {
      Write-Host "No .log files in $logDir; falling back to: openclaw logs --follow" -ForegroundColor Yellow
      Invoke-Openclaw logs --follow
    } else {
      Step "tail -f $($latest.FullName)"
      Get-Content -Path $latest.FullName -Tail 50 -Wait
    }
  }
}
