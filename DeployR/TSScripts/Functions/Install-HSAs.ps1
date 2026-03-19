
if ($env:SystemDrive -eq "X:"){
    $WinPE = $true
    $ContentPath = "S:\_2P\content"
}
else {
    $ContentPath = "C:\_2P\content"
}
    
$HSAsPath = Get-ChildItem -Path "$ContentPath\DriverPacks" -Recurse | Where-Object {$_.Name -like "HSAs" -and $_.Attributes -eq "Directory"} | Sort-Object -Descending | Select-Object -First 1
If ($HSAsPath) {
    Test-Path -Path "$($HSAsPath.FullName)\InstallAllApps.cmd" -ErrorAction SilentlyContinue
    Write-Output "Installing HSAs from $($HSAsPath.FullName)"
    if ($WinPE) {
        Start-Process cmd.exe -ArgumentList "/c `"$($HSAsPath.FullName)\InstallAllApps.cmd`" S:\" -Wait -PassThru -NoNewWindow
    }
    else {
        Start-Process cmd.exe -ArgumentList "/c `"$($HSAsPath.FullName)\InstallAllApps.cmd`""  -Wait -PassThru -NoNewWindow
    }

}
else {
    Write-Output "No HSAs found in $ContentPath\DriverPacks"
}

