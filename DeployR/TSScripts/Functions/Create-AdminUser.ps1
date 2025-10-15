#Simple Script to Create an Admin User and Set the Password. (PLAIN TEXT)

import-module microsoft.powershell.localaccounts -UseWindowsPowerShell

# Create local user
$Username = "BC Bob"
$Password = ConvertTo-SecureString "P@ssw0rd" -AsPlainText -Force

New-LocalUser -Name $Username -Password $Password -FullName "BC Bob" -Description "Local Admin Account" -PasswordNeverExpires:$true

# Add to Administrators group
Add-LocalGroupMember -Group "Administrators" -Member $Username

# Verify user creation and group membership
Get-LocalUser -Name $Username | Select-Object Name,Enabled,PasswordExpires
Get-LocalGroupMember -Group "Administrators" | Where-Object {$_.Name -like "*$Username"} | Select-Object Name
