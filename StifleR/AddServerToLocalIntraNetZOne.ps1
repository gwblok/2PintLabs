# Creates a DeployR dashboard URL shortcut on the desktop for all users

$url         = 'https://deployr.2p.garytown.com:9000/dashboard'
$shortcutName = 'DeployR Dashboard.url'
$commonDesktop = [Environment]::GetFolderPath('CommonDesktopDirectory')
$shortcutPath  = Join-Path $commonDesktop $shortcutName

$content = @"
[InternetShortcut]
URL=$url
"@

Set-Content -Path $shortcutPath -Value $content -Encoding ASCII -Force
Write-Host "Shortcut created: $shortcutPath"

# Add deployr.2p.garytown.com to the Local Intranet zone (Zone 1) for all users.
# inetcpl.cpl only shows HKCU entries, so we write directly into each user's NTUSER.DAT
# and into the Default User hive (for accounts created in the future).
# HKLM is also set as a silent fallback for browsers that honour it.

# -- HKLM fallback (Domains + EscDomains for IE ESC / Windows Server) --
foreach ($mapKey in 'Domains', 'EscDomains') {
    $hklmZonePath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings\ZoneMap\$mapKey\2p.garytown.com\deployr"
    if (-not (Test-Path $hklmZonePath)) { New-Item -Path $hklmZonePath -Force | Out-Null }
    New-ItemProperty -Path $hklmZonePath -Name 'https' -Value 1 -PropertyType DWORD -Force | Out-Null
}

# -- Per-user NTUSER.DAT helper --
# Writes to both Domains and EscDomains so the entry appears in inetcpl.cpl
# regardless of whether IE Enhanced Security Configuration (ESC) is on or off.
$zoneSubKeyBase = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings\ZoneMap'

function Set-ZoneInHive {
    param([string]$HiveRoot)   # e.g. 'HKLM\TempUser123'
    foreach ($mapKey in 'Domains', 'EscDomains') {
        $regPath = "Registry::$HiveRoot\$zoneSubKeyBase\$mapKey\2p.garytown.com\deployr"
        if (-not (Test-Path $regPath)) { New-Item -Path $regPath -Force | Out-Null }
        New-ItemProperty -Path $regPath -Name 'https' -Value 1 -PropertyType DWORD -Force | Out-Null
    }
}

# -- Default User (new accounts created after this script runs) --
$defaultNTUser = 'C:\Users\Default\NTUSER.DAT'
if (Test-Path $defaultNTUser) {
    $defaultHive = 'HKLM\TempDefaultUser_ZoneMap'
    reg load $defaultHive $defaultNTUser | Out-Null
    Set-ZoneInHive -HiveRoot $defaultHive
    [GC]::Collect()
    reg unload $defaultHive | Out-Null
    Write-Host "Updated Local Intranet zone in Default User hive"
}

# -- All existing user profiles --
Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList' | ForEach-Object {
    $profilePath = $_.GetValue('ProfileImagePath')
    # Skip built-in system accounts, Windows service profiles, and the Default profile (already handled above)
    if ($profilePath -notmatch 'systemprofile|LocalService|NetworkService|Default|ServiceProfiles') {
        $ntUserDat = Join-Path $profilePath 'NTUSER.DAT'
        if (Test-Path $ntUserDat) {
            $sid    = $_.PSChildName
            $hkuKey = "Registry::HKU\$sid"

            if (Test-Path $hkuKey) {
                # Hive is already loaded (user is currently logged on) â€” write directly via HKU
                foreach ($mapKey in 'Domains', 'EscDomains') {
                    $hkuZonePath = "$hkuKey\$zoneSubKeyBase\$mapKey\2p.garytown.com\deployr"
                    if (-not (Test-Path $hkuZonePath)) { New-Item -Path $hkuZonePath -Force | Out-Null }
                    New-ItemProperty -Path $hkuZonePath -Name 'https' -Value 1 -PropertyType DWORD -Force | Out-Null
                }
                Write-Host "Updated Local Intranet zone for active profile: $profilePath"
            } else {
                # Hive is not loaded â€” temporarily mount it
                $tempHive = "HKLM\TempUser_ZoneMap_$($sid -replace '[^a-zA-Z0-9]','_')"
                $regOut   = reg load $tempHive $ntUserDat 2>&1
                if ($LASTEXITCODE -eq 0) {
                    Set-ZoneInHive -HiveRoot $tempHive
                    [GC]::Collect()
                    reg unload $tempHive | Out-Null
                    Write-Host "Updated Local Intranet zone for profile: $profilePath"
                } else {
                    Write-Warning "Could not load hive for '$profilePath' - $regOut"
                }
            }
        }
    }
}
 