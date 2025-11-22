
Import-Module DeployR.Utility
$FORMFQDN = ${TSEnv:FORMFQDN}

[GC]::Collect()
Write-Host "Mounting Default User Registry Hive (REG LOAD HKLM\Default C:\Users\Default\NTUSER.DAT)"
REG LOAD HKLM\Default C:\Users\Default\NTUSER.DAT


    Write-Host "Attempting to Set Run Once Value to Approve DeployR Infra on next user login"
    $RegKey = "HKLM:\Default\Software\Microsoft\Windows\CurrentVersion\RunOnce"
    if (-not(Test-Path $RegKey )) {
        $reg = New-Item $RegKey -Force | Out-Null
        try { $reg.Handle.Close() } catch {}
    }
    $reg = New-ItemProperty $RegKey -Name "ApproveDeployR"  -Value "powershell.exe -WindowStyle hidden -command $deployR = Invoke-RestMethod `"https://$($FORMFQDN):9000/api/infrastructureService/type/11`" -UseDefaultCredentials ; Invoke-RestMethod `"https://$($FORMFQDN):9000/api/infrastructureService/$($deployR.id)/approve`" -Method PUT -UseDefaultCredentials" -PropertyType String -Force
    try { $reg.Handle.Close() } catch {}

[GC]::Collect()
Write-Host "Unmounting Default User Registry Hive (REG UNLOAD HKLM\Default)"
REG UNLOAD HKLM\Default