<#
    This is an additional practice chapter for dbatools-lab.
    Goal: reinforce chapter02-28 concepts using safe, guided checks.

    Adjust instance names for your environment as needed.
#>

$instance = 'dbatoolslab\sql2017'

Write-Host "=== Chapter 29 Practice: Discovery ===" -ForegroundColor Cyan
Get-Command -Module dbatools | Select-Object -First 10 Name
Find-DbaCommand -Pattern Backup | Select-Object -First 5

Write-Host "=== Chapter 29 Practice: Connectivity ===" -ForegroundColor Cyan
Test-DbaConnection -SqlInstance $instance

Write-Host "=== Chapter 29 Practice: Database Inventory ===" -ForegroundColor Cyan
Get-DbaDatabase -SqlInstance $instance -ExcludeSystem |
    Select-Object Name, Status, RecoveryModel, LastFullBackup

Write-Host "=== Chapter 29 Practice: Backup WhatIf (safe) ===" -ForegroundColor Cyan
$backupPath = 'C:\dbatoolslab\Backup'
Backup-DbaDatabase -SqlInstance $instance -Database 'WideWorldImporters' -Path $backupPath -WhatIf

Write-Host "=== Chapter 29 Practice: Agent Jobs ===" -ForegroundColor Cyan
Get-DbaAgentJob -SqlInstance $instance |
    Select-Object Name, Enabled, LastRunOutcome

Write-Host "=== Chapter 29 Practice: Self-check Questions ===" -ForegroundColor Yellow
Write-Host "1) Which dbatools command helps you discover commands by topic?"
Write-Host "2) Which instance in this lab holds the restored sample databases?"
Write-Host "3) Why do we use -WhatIf before a write operation in learning labs?"
