#DeployR Registry Path:
$DRRegPath = "HKLM:\SOFTWARE\2Pint Software\DeployR\GeneralSettings"


#DeployR ClientURL Registry Value Name:
$RegValueName = "ClientURL"
$DeployRHost = (Get-ItemProperty -Path $DRRegPath -Name $RegValueName -ErrorAction SilentlyContinue).$RegValueName
$JSON = @"
{"Variables":{"DeployRHost":"$DeployRHost","Anonymous":"true","Custom":"true","Debug":"true","TSID":""}}
"@


$JSOFileLocation = "C:\Program Files\2Pint Software\DeployR\Client\Bootstrap.json"
if (-not(Test-Path -Path $JSOFileLocation)) {
    Write-Host "Missing Bootstrap.json file. Creating new file at $JSOFileLocation" -ForegroundColor Yellow
    $JSON | Out-File -FilePath $JSOFileLocation -Encoding ASCII -Force
    Get-Service -Name DeployRService | Restart-Service -Force -ErrorAction SilentlyContinue
}
else{
    Write-Host "Bootstrap.json file found Here: $JSOFileLocation" -ForegroundColor Green
}
