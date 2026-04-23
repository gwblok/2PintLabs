<#
Idea was to circumvent the default security in DeployR for the Offline Domain Join step.
If you read the docs, ODJ via DeployR will NOT overwrite an existing computer account, UNLESS it was orginally created by DeployR via DeployR OSD
If it was joined by any other process, you'd have to MANUALLY change the owner of the computer account to the DeployR Server's computer account or 
delete the object and let DeployR create it during the ODJ step.


NOTE, this SCRIPT does NOT work with the default delegation of permissions in AD, 
you must give the DeployR Server's computer account permissions to modify the computer account in AD, 
otherwise it will fail with an access denied error. 
This is because the script needs to change the owner of the computer account to the DeployR Server's computer account, 
and if it doesn't have permissions to do that, it will fail.

2PINT SOFTWARE DOES NOT SUPPORT THIS!  

#>


param(
    [string]$ComputerName,
    [string]$NewOwner,
    [string]$OU,
    [string]$DryRun
)
$ouPath = $OU

#Convert $DryRun to boolean
if ($DryRun) {
    $DryRun = [System.Convert]::ToBoolean($DryRun)
} else {
    $DryRun = $false
}

Write-Information "Received ComputerName: $ComputerName, NewOwner: $NewOwner, OU: $OU, DryRun: $DryRun"


if ($computerName -and $ouPath) {
    try {
        # Get the computer object
        $computerDN = "CN=$computerName,$ouPath"
        $computer = [ADSI]"LDAP://$computerDN"

        # Get the new owner's SID
        $searcher = New-Object System.DirectoryServices.DirectorySearcher
        $searcher.Filter = "(&(objectClass=computer)(sAMAccountName=$newOwner))"
        $ownerObject = $searcher.FindOne()

        if ($ownerObject) {
            $ownerSID = New-Object System.Security.Principal.SecurityIdentifier($ownerObject.Properties["objectsid"][0], 0)

            # Get current ACL
            $acl = $computer.ObjectSecurity

            if ($DryRun -eq $true) {
                Write-Output 'Dry Run Mode - No changes will be made'
                Write-Information "[DRY RUN] Would change owner of $computerName to $newOwner"
                Write-Information "[DRY RUN] No changes committed to AD"
            } else {
                # Set new owner
                $acl.SetOwner($ownerSID)
                $computer.CommitChanges()
                Write-Information "SUCCESS: Changed owner of $computerName to $newOwner"
            }
        } else {
            Write-Warning "Could not find machine account $newOwner"
        }
    } catch {
        Write-Error "Failed to process ownership - $($_.Exception.Message)"
    }
} else {
    Write-Warning "Missing COMPUTERNAME or OU variable, skipping ownership change"
} 
