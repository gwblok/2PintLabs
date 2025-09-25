# Set-WinNetworkSettings.ps1

if ($env:SystemDrive -eq "X:"){
    Write-Host "Running in WinPE, this step requires a full Windows environment to run properly."
    exit 0
}

Import-Module DeployR.Utility


# Variables - Set these to $true or $false as needed
[string]$FastStartup = ${TSEnv:FastStartup}
[string]$Hibernation = ${TSEnv:Hibernation}


# Write out which script is running, and the variables being used
write-host "==================================================================="
write-host "Set-WinNetworkSettings Script" 
write-host "Reporting Variables:"
write-host "FastStartup: $FastStartup"  
write-host "Hibernation: $Hibernation"


if ($FastStartup -eq "Enable") {
    #This is Default, do nothing
}
else {
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power" -Name "HiberbootEnabled" -Value 0 -Force | Out-Null
    Write-Host "Fast Startup is disabled."
}

if ($Hibernation -eq "Enable") {
    #This is Default, do nothing
}
else {
    # Disable Hibernation
    Write-Host "Disabling Hibernation..."
    powercfg /h off | Out-Null
    Write-Host "Hibernation has been disabled."
}   


Write-Host "Power settings updated."
write-host "==================================================================="