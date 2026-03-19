function Get-WindowsOEMProductKey {
    $ProductKey = (Get-CimInstance -ClassName SoftwareLicensingService).OA3xOriginalProductKey
    return $ProductKey
}

function Set-WindowsOEMActivation {
    $ProductKey = Get-WindowsOEMProductKey
    Write-Output "Starting Process to Set Windows License to OEM Value in BIOS"
    if ($ProductKey) {
        try {
            Write-Output " Setting Key: $ProductKey" 
            $service = get-wmiObject -query "select * from SoftwareLicensingService"
            if ($service){
                $service.InstallProductKey($ProductKey) | Out-Null
                $service.RefreshLicenseStatus() | Out-Null
                $service.RefreshLicenseStatus() | Out-Null
                Write-Output  " Successfully Applied Key"
            }
            else {
                Write-Output " Failed to connect to Service to Apply Key"
            }
        }
        catch {
            Write-Output " Failed try statement to Apply Key"
        }
    }
    else{
	    Write-Output ' Key not found!'
    }
}
#Run the Functions
Set-WindowsOEMActivation 