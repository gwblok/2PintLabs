

Import-Module DeployR.Utility
$WorkingDir = ${TSEnv:_Content-Content}

#Gather UUID From Current Machine
$uuid = (Get-CimInstance Win32_ComputerSystemProduct).UUID
$compactUuid = ($uuid -replace '-', '').ToLower()
Write-Output "UUID (MachineUUID)(hyphenated): $uuid"
Write-Output "UUID (MachineUUIDcompact) (compact for DB): $compactUuid"
${TSEnv:MachineUUID} = $uuid
${TSEnv:MachineUUIDcompact} = $compactUuid


$CSVFile = Get-ChildItem -Path $WorkingDir -Filter "*.csv" -File
if ($CSVFile.Count -eq 0) {
    Write-Host "No CSV files found in $WorkingDir. Cannot gather information." -ForegroundColor Red
    # Set a default language if desired, or exit with an error
}
else {
    Write-Host "Found CSV file(s) in $WorkingDir. Gathering language information from the first one." -ForegroundColor Green
    $AllCompinfo = Import-csv -Path $CSVFile[0].FullName
    $CurrentCompInfo = $AllCompinfo | Where-Object { $_.uuid -eq $compactUuid }
    if ($CurrentCompInfo) {
        Write-Host "Found matching computer information for UUID $compactUuid." -ForegroundColor Green
        Write-Host "Setting Computer Name to $($CurrentCompInfo.computerName)" -ForegroundColor Cyan
        $TSEnv:COMPUTERNAME = $CurrentCompInfo.computerName
    }
    else {
        Write-Host "No matching computer information found for UUID $compactUuid in the CSV file." -ForegroundColor Yellow
        # Set a default language if desired, or exit with an error
    }
    
}