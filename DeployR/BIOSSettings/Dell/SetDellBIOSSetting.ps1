


#Set this to your BIOS Password or Delete if you have none.  Feel free to make this more secure, however you want to do that.  This is NOT best practice to have passwords in scripts.
# Grab Content Location for Import of Module
<#
.SYNOPSIS
    Set multiple Dell BIOS settings using Dell CCTK (CCTK.exe) in a Task Sequence or standalone.

DESCRIPTION
    This script locates the CCTK executable in the script content directory (or TSEnv when
    executed inside a Task Sequence), and applies a list of BIOS settings by calling
    Set-DellBIOSSettingWithCCTK for each SettingName/SettingValue pair.

PARAMETERS
    $BIOSPassword - Optional plain-text BIOS password used by CCTK's --ValSetupPwd parameter.
                   Consider passing a SecureString or PSCredential in production for better
                   security; this script uses a simple string for compatibility with CCTK.

USAGE
    - Run inside a Task Sequence: the content location is read from the TSEnv variable.
    - Run standalone: the script folder is used as the content location.

NOTES
    - CCTK must be placed in the same folder as this script (or in the Task Sequence content
      location) as CCTK.exe. The script will report if CCTK is not found.
    - The script currently accepts a plain-text password; converting to SecureString/PSCredential
      is recommended and can be implemented if desired.

      THINGS YOU SHOULD EDIT IF NEEDED:  
      $BIOSPassword
      $BIOSSettings Object

#>
$BIOSPassword = 'P@ssw0rd'  #Feel free to make this more secure, however you want to do that.  This is NOT best practice to have passwords in scripts.  Just here for demo purposes.

# Define BIOS settings as an array of objects (SettingName, SettingValue)
$BIOSSettings = @(
    [pscustomobject]@{ SettingName = 'BlockSleep'; SettingValue = 'Disabled' },
    [pscustomobject]@{ SettingName = 'AutoOn';     SettingValue = 'Weekdays' },
    [pscustomobject]@{ SettingName = 'AutoOnHr';   SettingValue = '6'       },
    [pscustomobject]@{ SettingName = 'AutoOnMn';   SettingValue = '59'      },
    [pscustomobject]@{ SettingName = 'Fastboot';   SettingValue = 'Thorough'},
    [pscustomobject]@{ SettingName = 'FnLock';     SettingValue = 'Enabled' },
    [pscustomobject]@{ SettingName = 'WakeOnLan';  SettingValue = 'LanOnly' }
)



#Import DeployR.Utility Module when in a Task Sequence
try {
    Import-Module DeployR.Utility -ErrorAction Stop
}
catch {}

#Confirm if in TS or not, and set content location accordingly
if (Get-Module -name "DeployR.Utility" -ErrorAction SilentlyContinue){
    $ContentLocation = ${TSEnv:CONTENT-CONTENT}
    Write-Host "Running in TS, getting content location from TSEnv: $ContentLocation"
}
else{
    if (Test-Path -Path "C:\Program Files (x86)\Dell\Command Configure\X86_64\cctk.exe"){
        $ContentLocation = "C:\Program Files (x86)\Dell\Command Configure\X86_64"
    }
    else {
        $ContentLocation = Split-Path -Path $MyInvocation.MyCommand.Definition -Parent
    }
    Write-Host "Running outside of TS, setting content location to script folder: $ContentLocation"
}
#Set CCTK Path & confirm it exists
$CCTKPath = "$ContentLocation\CCTK.exe"
if (Test-Path -Path $CCTKPath){
    Write-Host "CCTK found at $CCTKPath"
}
else{
    Write-Host "CCTK NOT found at expected location: $CCTKPath"
}

#Start to Set BIOS Settings!

Function Set-DellBIOSSettingWithCCTK {
    [CmdletBinding()]
    param (
        [string]$SettingName,
        [string]$SettingValue,
        [string]$CCTKPath,
        [string]$BIOSPassword
    )

    if ($BIOSPassword){
        $Result = Start-Process -FilePath $CCTKPath -ArgumentList "--$($SettingName)=$($SettingValue) --ValSetupPwd=$($BIOSPassword)" -Wait -NoNewWindow -RedirectStandardOutput "$env:windir\Temp\CCTK_$($SettingName)_Set.log" -PassThru
    }
    else{
        $Result = Start-Process -FilePath $CCTKPath -ArgumentList "--$($SettingName)=$($SettingValue)" -Wait -NoNewWindow -RedirectStandardOutput "$env:windir\Temp\CCTK_$($SettingName)_Set.log" -PassThru
    }
    if ($Result.ExitCode -eq 0){
        Write-Host "Successfully Set $SettingName to $SettingValue"
    }
    else{
        Write-Host "Failed to Set Value" -ForegroundColor Red
        $ResultText = Get-Content -Path "$env:windir\Temp\CCTK_$($SettingName)_Set.log"
        Write-Host $ResultText
    }

}


# Apply each setting using the Set-DellBIOSSettingWithCCTK function
foreach ($s in $BIOSSettings) {
    try {
        Set-DellBIOSSettingWithCCTK -SettingName $s.SettingName -SettingValue $s.SettingValue -CCTKPath $CCTKPath -BIOSPassword $BIOSPassword
    }
    catch {
        Write-Warning "Failed to apply setting $($s.SettingName): $_"
    }
}