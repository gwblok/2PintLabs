<#
.SYNOPSIS
    Enables Debug/Analytic ETW logging on all TwoPintSoftware Event Viewer sub-logs.

.DESCRIPTION
    Enumerates all event logs under the TwoPintSoftware provider and enables any
    Debug or Analytic logs that are currently disabled.

.NOTES
    Must be run as Administrator.
    Enabling Debug/Analytic logs requires the log to be disabled first if it's already enabled
    with different settings, but this script only enables logs that are currently disabled.
#>

#Requires -RunAsAdministrator

# Get all event logs under TwoPintSoftware
$twoPintLogs = Get-WinEvent -ListLog "TwoPintSoftware*" -Force -ErrorAction SilentlyContinue

if (-not $twoPintLogs) {
    Write-Warning "No TwoPintSoftware event logs found on this system."
    return
}

Write-Host "Found $($twoPintLogs.Count) TwoPintSoftware event log(s):" -ForegroundColor Cyan

$enabledCount = 0
$alreadyEnabledCount = 0
$failedCount = 0

foreach ($log in $twoPintLogs) {
    $logName = $log.LogName
    $logType = $log.LogType  # Administrative, Operational, Analytic, Debug

    if ($log.IsEnabled) {
        Write-Host "  [Already Enabled] $logName ($logType)" -ForegroundColor Green
        $alreadyEnabledCount++
    }
    else {
        try {
            $log.IsEnabled = $true
            $log.SaveChanges()
            Write-Host "  [Enabled] $logName ($logType)" -ForegroundColor Yellow
            $enabledCount++
        }
        catch {
            Write-Host "  [Failed] $logName ($logType) - $($_.Exception.Message)" -ForegroundColor Red
            $failedCount++
        }
    }
}

Write-Host ""
Write-Host "Summary:" -ForegroundColor Cyan
Write-Host "  Already enabled : $alreadyEnabledCount" -ForegroundColor Green
Write-Host "  Newly enabled   : $enabledCount" -ForegroundColor Yellow
if ($failedCount -gt 0) {
    Write-Host "  Failed          : $failedCount" -ForegroundColor Red
}
