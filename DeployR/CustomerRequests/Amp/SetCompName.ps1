

Import-Module DeployR.Utility
$WorkingDir = ${TSEnv:Content-Content}

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
    $TSEnv:COMPUTERNAME = $CurrentCompInfo.computerName
}