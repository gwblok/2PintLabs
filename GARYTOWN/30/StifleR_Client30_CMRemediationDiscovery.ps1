# StifleR Client Intune Remediation Detection Script

$Compliance = $true
#Gather Current Info (as long as I remember to update it)
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
    Write-Host "StifleR Client is installed. Version: $($StifleRClientAppInfo.DisplayVersion)" -ForegroundColor Green
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

if ($MatchedEntryInfo) {
    try {
        $MatchedVersion = [version]($MatchedEntryInfo.Version.ToString())
    } catch {
        $MatchedVersion = $null
    }

    if ($MatchedVersion) {
        if ($MatchedVersion -gt $CurrentVersion) {
            #Write-Host "Found newer matched version: $MatchedVersion (installed: $CurrentVersion)" -ForegroundColor Yellow
            $Compliance = $false
        } else {
            #Write-Host "Already Compliant: Target version: $MatchedVersion matches installed: $CurrentVersion" -ForegroundColor Green
            #Machine is already compliant, just exit 0 now
            return $Compliance
        }
    } else {
        #Write-Host "Matched entry found but version could not be parsed." -ForegroundColor Red
    }
} else {
    #Write-Host "No matched major-version entry found; using target version $TargetVersion." -ForegroundColor Yellow
    $Compliance = $false
}

#Confirm Service
$StifleRService = get-service -Name StifleRClient -ErrorAction SilentlyContinue
if ($null -eq $StifleRService){
    #Write-Host "StifleR Client Service not installed - Trigger Remediation" -ForegroundColor Red
    $Compliance = $false
    return $Compliance
}
if ($StifleRService.Status -ne 'Running'){
    Start-Service -Name StifleRClient
}
if ($StifleRService.StartType -ne 'Automatic'){
    Set-Service -Name StifleRClient -StartupType Automatic
}

#Final Compliance Check
if ($Compliance -eq $true){
    #Write-Host "Machine is compliant" -ForegroundColor Green
    return $Compliance
} else {
    #Write-Host "Machine is not compliant - Trigger Remediation" -ForegroundColor Red
    return $Compliance
}