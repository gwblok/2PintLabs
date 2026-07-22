write-host "Installing HP BIOS Update Module" using pwsh.exe -command "install-module -name HPCMSL -AcceptLicense -SkipPublisherCheck -Force"
write-host "This workaround is needed as running the install-module directly will throw error The 'Install-Module' command was found in the module 'PowerShellGet', but the module could not be loaded."
pwsh.exe -command "install-module -name HPCMSL -AcceptLicense -SkipPublisherCheck -Force"


#import Module
Write-Host "Importing HP BIOS Update Module"
Import-Module HPCMSL -ErrorAction Stop
Get-Module -Name HPCMSL

$CurrentBIOSVersion = Get-HPBIOSVersion
$LatestBIOSVersion = Get-HPBIOSUpdates -Latest

Write-Host "Current BIOS Version: $CurrentBIOSVersion"
Write-Host "Latest BIOS Version: $($LatestBIOSVersion.Ver) from $($LatestBIOSVersion.Date)"

Write-Host "Checking for HP BIOS Updates (Get-HPBIOSUpdates -Check)"

if ((Get-HPBIOSUpdates -Check) -eq $false){
    Write-Host "HP BIOS Update found, running Command: Get-HPBIOSUpdates -Flash -Yes -Bitlocker Ignore"
    Get-HPBIOSUpdates -Flash -Yes -Bitlocker Ignore
}
else {
    Write-Host "No HP BIOS Updates found"

}