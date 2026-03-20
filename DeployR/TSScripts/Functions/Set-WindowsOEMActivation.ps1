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
            $service = Get-CimInstance -Query "select * from SoftwareLicensingService"
            if ($service){
                Invoke-CimMethod -InputObject $service -MethodName "InstallProductKey" -Arguments @{ProductKey = $ProductKey} | Out-Null
                Invoke-CimMethod -InputObject $service -MethodName "RefreshLicenseStatus" | Out-Null
                Invoke-CimMethod -InputObject $service -MethodName "RefreshLicenseStatus" | Out-Null
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