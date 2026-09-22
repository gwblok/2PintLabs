<#
.SYNOPSIS
    Restores IIS read access to the StifleR client download and optionally schedules the repair nightly.

.DESCRIPTION
    Ensures IIS_IUSRS has ReadAndExecute access to StifleR-ClientApp.zip. Use
    -RegisterScheduledTask once to create or update a SYSTEM task that runs every night.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$DownloadPath = 'C:\inetpub\wwwroot\3.0\StifleR-ClientApp.zip',
    [string]$TaskName = 'Repair StifleR Client Download ACL',
    [string]$TaskPath = '\2Pint Software\',
    [datetime]$RunAt = '02:00',
    [switch]$RegisterScheduledTask
)

$ErrorActionPreference = 'Stop'
$LogDirectory = Join-Path $env:ProgramData '2Pint Software\Logs'
$LogPath = Join-Path $LogDirectory 'Repair-StifleRClientDownloadAcl.log'

function Write-RepairLog {
    param([string]$Message)

    if (-not (Test-Path -LiteralPath $LogDirectory)) {
        New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null
    }

    $entry = '{0:u} {1}' -f (Get-Date), $Message
    $entry | Tee-Object -FilePath $LogPath -Append
}

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Repair-DownloadAcl {
    if (-not (Test-Path -LiteralPath $DownloadPath -PathType Leaf)) {
        throw "The StifleR client download was not found: $DownloadPath"
    }

    $acl = Get-Acl -LiteralPath $DownloadPath
    $hasReadAccess = $acl.Access | Where-Object {
        $_.IdentityReference.Value -eq 'BUILTIN\IIS_IUSRS' -and
        $_.AccessControlType -eq 'Allow' -and
        (($_.FileSystemRights -band [Security.AccessControl.FileSystemRights]::ReadAndExecute) -eq [Security.AccessControl.FileSystemRights]::ReadAndExecute)
    }

    if ($hasReadAccess) {
        Write-RepairLog "IIS_IUSRS already has ReadAndExecute access to $DownloadPath."
        return
    }

    $rule = [Security.AccessControl.FileSystemAccessRule]::new(
        'IIS_IUSRS',
        [Security.AccessControl.FileSystemRights]::ReadAndExecute,
        [Security.AccessControl.AccessControlType]::Allow
    )

    if ($PSCmdlet.ShouldProcess($DownloadPath, 'Grant IIS_IUSRS ReadAndExecute access')) {
        $acl.AddAccessRule($rule)
        Set-Acl -LiteralPath $DownloadPath -AclObject $acl
        Write-RepairLog "Granted IIS_IUSRS ReadAndExecute access to $DownloadPath."
    }
}

function Register-RepairScheduledTask {
    $taskService = New-Object -ComObject Schedule.Service
    $taskService.Connect()

    try {
        $taskService.GetFolder($TaskPath) | Out-Null
    }
    catch {
        $taskService.GetFolder('\').CreateFolder($TaskPath.Trim('\')) | Out-Null
    }

    $scriptPath = $PSCommandPath
    $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""
    $trigger = New-ScheduledTaskTrigger -Daily -At $RunAt
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest

    if ($PSCmdlet.ShouldProcess("$TaskPath$TaskName", 'Register nightly ACL repair task')) {
        Register-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -Action $action -Trigger $trigger -Principal $principal -Description 'Repairs IIS read access to StifleR-ClientApp.zip.' -Force | Out-Null
        Write-RepairLog "Registered scheduled task $TaskPath$TaskName for $($RunAt.ToString('HH:mm'))."
    }
}

if (-not (Test-IsAdministrator)) {
    throw 'Run this script from an elevated PowerShell session.'
}

Repair-DownloadAcl

if ($RegisterScheduledTask) {
    Register-RepairScheduledTask
}