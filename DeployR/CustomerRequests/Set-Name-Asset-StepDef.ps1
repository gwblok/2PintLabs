$varSerialNumber = (Get-CimInstance -ClassName Win32_BIOS).SerialNumber.Trim()
$varAssetTag = (Get-CimInstance -ClassName Win32_SystemEnclosure).SMBIOSAssetTag.Trim()

if ($varAssetTag -ne $null -and $varAssetTag -ne "" ) {
    if ($varAssetTag -ne "To be filled by O.E.M.") {
        $NewName = $varAssetTag
        Write-Output "Using Asset Tag for computer name: $NewName"
    }
    else {
        Write-Output "Asset Tag is set to default 'To be filled by O.E.M.', using Serial Number instead."
        $NewName = $varSerialNumber
    }
}
else {
    Write-Output "Asset Tag is empty or not set, using Serial Number instead."    
    $NewName = $varSerialNumber
}
if ($NewName.Length -gt 15) {
    $NewName = $NewName.Substring(0,15)
    Write-Output "Trimming computer name to 15 characters: $NewName"
}
Rename-Computer -NewName $NewName -Force -ErrorAction Stop
Write-Output "Computer renamed to: $NewName"