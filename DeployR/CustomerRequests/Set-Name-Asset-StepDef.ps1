$varSerialNumber = (Get-CimInstance -ClassName Win32_BIOS).SerialNumber.Trim()
$varAssetTag = (Get-CimInstance -ClassName Win32_SystemEnclosure).SMBIOSAssetTag.Trim()

if ($varAssetTag -ne $null -and $varAssetTag -ne "" ) {
    if ($varAssetTag -ne "To be filled by O.E.M.") {
        $NewName = $varAssetTag
    } 
}
else {
    Write-Output "Asset Tag is empty or not set, using Serial Number instead."    
    $NewName = $varSerialNumber
}
if ($NewName.Length -gt 15) {
    $NewName = $NewName.Substring(0,15)
}
Rename-Computer -NewName $NewName -Force -ErrorAction Stop
Write-Output "Computer renamed to: $NewName"