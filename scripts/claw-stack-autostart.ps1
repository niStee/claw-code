#Requires -Version 5.1
<#
.SYNOPSIS
    Manage an optional Windows logon task for the local Claw stack.
.DESCRIPTION
    Installs, removes, or inspects a per-user Scheduled Task that starts
    scripts\claw-stack.ps1 start at logon. This starts the local Codex proxy
    and unified LiteLLM proxy; VS Code LM remains owned by VS Code.
#>

param(
    [ValidateSet("Status", "Install", "Remove", "Start", "Stop")]
    [string]$Action = "Status",
    [string]$TaskName = "ClawCodeLocalStack"
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$StackScript = Join-Path $ScriptDir "claw-stack.ps1"

function Get-ClawTask {
    Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
}

function Show-Status {
    $task = Get-ClawTask
    if (-not $task) {
        Write-Host "Autostart task '$TaskName': not installed"
        return
    }
    $info = Get-ScheduledTaskInfo -TaskName $TaskName -ErrorAction SilentlyContinue
    Write-Host "Autostart task '$TaskName': installed"
    Write-Host ("  State:       {0}" -f $task.State)
    if ($info) {
        Write-Host ("  Last run:    {0}" -f $info.LastRunTime)
        Write-Host ("  Last result: {0}" -f $info.LastTaskResult)
        Write-Host ("  Next run:    {0}" -f $info.NextRunTime)
    }
}

function Install-Task {
    if (-not (Test-Path -LiteralPath $StackScript)) {
        throw "Stack script not found: $StackScript"
    }
    $existing = Get-ClawTask
    if ($existing) {
        Write-Host "Autostart task '$TaskName' already exists."
        Show-Status
        return
    }

    $ps = (Get-Command powershell.exe -ErrorAction Stop).Source
    $argument = "-NoProfile -ExecutionPolicy Bypass -File `"$StackScript`" start"
    $action = New-ScheduledTaskAction -Execute $ps -Argument $argument -WorkingDirectory (Split-Path -Parent $ScriptDir)
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -ExecutionTimeLimit (New-TimeSpan -Hours 12)
    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings -Description "Start local Claw proxy stack at user logon." | Out-Null
    Write-Host "Installed autostart task '$TaskName'."
    Show-Status
}

function Remove-Task {
    $task = Get-ClawTask
    if (-not $task) {
        Write-Host "Autostart task '$TaskName' is not installed."
        return
    }
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    Write-Host "Removed autostart task '$TaskName'."
}

function Start-TaskIfInstalled {
    $task = Get-ClawTask
    if (-not $task) {
        Write-Host "Autostart task '$TaskName' is not installed."
        return
    }
    Start-ScheduledTask -TaskName $TaskName
    Show-Status
}

function Stop-TaskIfInstalled {
    $task = Get-ClawTask
    if (-not $task) {
        Write-Host "Autostart task '$TaskName' is not installed."
        return
    }
    Stop-ScheduledTask -TaskName $TaskName
    Show-Status
}

switch ($Action) {
    "Status" { Show-Status }
    "Install" { Install-Task }
    "Remove" { Remove-Task }
    "Start" { Start-TaskIfInstalled }
    "Stop" { Stop-TaskIfInstalled }
}
