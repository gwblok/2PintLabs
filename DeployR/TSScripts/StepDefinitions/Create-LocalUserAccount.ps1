#Simple Script to Create an Admin User and Set the Password. (PLAIN TEXT)

if ($env:SystemDrive -eq "X:"){

    Write-Host "Running in WinPE environment, this step requires a full Windows environment to run properly."
    exit 0
}


#Pull Vars from TS:
try {
    Import-Module DeployR.Utility
}
catch {}


# Get the provided variables
if (Get-Module -name "DeployR.Utility"){
    $ConfigUserName = ${TSEnv:ConfigUserName}
    $ConfigUserPassword = ${TSEnv:ConfigUserPassword}
}
else{
    $ConfigUserName = "BC Bob"
    $ConfigUserPassword = "P@ssw0rd"
}

Write-Host "Importing Microsoft.PowerShell.LocalAccounts module, required in OS pre 24H2"
import-module microsoft.powershell.localaccounts -UseWindowsPowerShell

# Create local user
$Password = ConvertTo-SecureString $ConfigUserPassword -AsPlainText -Force

Write-Host "Creating local user account: $ConfigUserName"
New-LocalUser -Name $ConfigUserName -Password $Password -FullName $ConfigUserName -Description "Custom Local Admin Account" -PasswordNeverExpires:$true

# Add to Administrators group
Write-Host "Adding $ConfigUserName to Administrators group"
Add-LocalGroupMember -Group "Administrators" -Member $ConfigUserName

# Verify user creation and group membership
Write-Host "Verifying user creation and group membership:"
Get-LocalUser -Name $ConfigUserName | Select-Object Name,Enabled,PasswordExpires
Get-LocalGroupMember -Group "Administrators" | Where-Object {$_.Name -like "*$ConfigUserName*"} | Select-Object Name
