$JSONContent = Invoke-RestMethod -Uri "https://raw.githubusercontent.com/gwblok/2PintLabs/refs/heads/main/GARYTOWN/StifleR-ClientApp.json"

function Get-InstalledApps
{
    if (![Environment]::Is64BitProcess) {
        $regpath = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
    }
    else {
        $regpath = @(
            'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
            'HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
        )
    }
    Get-ItemProperty $regpath | .{process{if($_.DisplayName -and $_.UninstallString) { $_ } }} | Select DisplayName, Publisher, InstallDate, DisplayVersion, UninstallString |Sort DisplayName
}

$StifleRClientAppInfo = Get-InstalledApps | Where-Object {$_.DisplayName -match "StifleR Client"}
if ($StifleRClientAppInfo) {
    #Write-Host "StifleR Client is installed. Version: $($StifleRClientAppInfo.DisplayVersion)" -ForegroundColor Green
    [Version]$CurrentVersion = $StifleRClientAppInfo.DisplayVersion
    
    # collect versions from JSONContent
    $VERSIONS = $JSONContent |
        ForEach-Object {
            try { [version]($_.Version.ToString()) } catch { $null }
        } |
        Where-Object { $_ -ne $null } |
        Sort-Object -Unique

    # find JSON entry that matches the installed major version
    $MatchedEntry = $JSONContent |
        Where-Object {
            try { ([version]($_.Version.ToString())).Major -eq $CurrentVersion.Major } catch { $false }
        } |
        Select-Object -First 1

    if ($MatchedEntry) {
        $TargetVersion = ([version]($MatchedEntry.Version.ToString())).ToString()
        $MatchedEntryInfo = $MatchedEntry
    } else {
        # fallback: pick the highest available version if no major match
        $TargetVersion = ($VERSIONS | Sort-Object -Descending | Select-Object -First 1).ToString()
        $MatchedEntryInfo = $null
    }
} else {
    Write-Host "StifleR Client is not installed." -ForegroundColor Red
}
if ($StifleRClientAppInfo.DisplayVersion -ge $TargetVersion){
    Write-Host "StifleR Client version $($StifleRClientAppInfo.DisplayVersion) is the target version $TargetVersion - No remediation required" -ForegroundColor Green
    exit 0
}
else {
    Write-Host "StifleR Client version $($StifleRClientAppInfo.DisplayVersion) is not the target version $TargetVersion - Trigger Remediation" -ForegroundColor Red
    exit 1
}