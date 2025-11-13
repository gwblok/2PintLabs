 
# Import Dell BIOS module
Import-Module DellBIOSProvider
 
# Check for BIOS password
$varBIOSPassword = (Get-Item -Path DellSmbios:\Security\IsAdminPasswordSet | select -expand CurrentValue)
 
# Check for asset tag
$varAssetTag = (Get-Item -Path DellSmbios:\SystemInformation\Asset | select -expand CurrentValue)
 
# Grab computer name and pull asset tag info in preparation to have to set later on
$newAsset=$env:computername.substring(0,5)
 
# Read out variables
$varBIOSPassword
$varAsseteTag
$newAsset
 
# Determine if BIOS password is set, if not set BIOS password
If ($varBIOSPassword -eq "True") {Write-Host 'BIOS password set, moving on...'}
    elseif ($varBIOSPassword -eq "False") {Write-Host 'BIOS password not set, setting...' (Set-Item -Path DellSmbios:\Security\AdminPassword "tspecial")}
 
# Determine if Asset Tag is set, if not set the Asset Tag
if ($varAssetTag) {Write-Host 'Asset Tag set, moving on...'}
    elseif (!$varAssetTag) {Write-Host 'Asset Tag not set, setting...' (Set-Item -path DellSmbios:\SystemInformation\Asset "$newAsset" -Password "tspecial")}