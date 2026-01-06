$DesiredStifleRServer = "dr.2pintlabs.com"

$ClientRegPath = "HKLM:\SOFTWARE\2Pint Software\StifleR\Client\SettingsOptions"
if (Test-Path $ClientRegPath) {
    $Key = Get-Item -Path $ClientRegPath
    $StifleRServer = $Key.GetValue("StiflerServers")
    if ($StifleRServer -match $DesiredStifleRServer) {
        Write-Host "StifleR Client is configured to use the desired StifleR Server: $DesiredStifleRServer" -ForegroundColor Green
        return $true
    } else {
        Write-Host "StifleR Client is NOT configured to use the desired StifleR Server. Current Server: $StifleRServer, Desired Server: $DesiredStifleRServer" -ForegroundColor Red
        return $false
    }
} else {
    Write-Host "StifleR Client registry path not found. Cannot proceed with detection." -ForegroundColor Red
    return $false
}