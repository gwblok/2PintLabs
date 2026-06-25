#This Script is used to generate the SetupComplete.cmd file that will be used to call the Bootstrap.ps1 script with the SetupComplete method.

$SetupCompleteScript = @"
@ECHO OFF

powershell.exe -executionpolicy bypass -noprofile -WindowStyle Minimized -file %SystemDrive%\_2P\Client\Bootstrap.ps1 -Method SetupComplete
"@


# Check if the S:\Windows\Setup\Scripts folder exists, if not create it
if (-not (Test-Path -Path "S:\Windows\Setup\Scripts")) {
    Write-Host "Creating S:\Windows\Setup\Scripts folder"
    New-Item -ItemType Directory -Path "S:\Windows\Setup\Scripts" -Force | Out-Null
}
# Copy the template SetupComplete.cmd file to the correct location
if (-not (Test-Path -Path "S:\Windows\Setup\Scripts\SetupComplete.cmd")) {
    Write-Host "Copying template SetupComplete.cmd to S:\Windows\Setup\Scripts"
    $SetupCompleteScript | Out-File "S:\Windows\Setup\Scripts\SetupComplete.cmd" -Force -Encoding utf8
}