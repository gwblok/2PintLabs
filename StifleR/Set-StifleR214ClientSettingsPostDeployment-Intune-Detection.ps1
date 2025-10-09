#Settings you want to check
$DesiredServerName = 'DR.2PintLabs.com' #Replaces this information into the StiflerServers registry key
$DesiredVPNClient = 'WireGuard'  #Appends this information into the VPNStrings registry key
$DesiredDefaultDisconnectedBITSPolicy = '51200' #This is really High, but it's what I want in my Lab because I'm in flux between test servers
$DesiredDefaultDisconnectedDOPolicy = '51200' #This is really High, but it's what I want in my Lab because I'm in flux between test servers
$DefaultNonRedLeaderBITSPolicy = '2560' #This is 2.5MB, which is what I want for non-red leaders
$DefaultNonRedLeaderDOPolicy = '2560' #This is 2.5MB, which is what I want for non-red leaders

#Script Content:
$StifleRRegPath = 'HKLM:\SOFTWARE\2Pint Software\StifleR\Client\SettingsOptions'
if (Test-Path -Path $StifleRRegPath){
    $StifleRSettings = Get-Item -Path $StifleRRegPath
    [STRING]$StifleRServerString = $StifleRSettings.GetValue('StiflerServers')
    [STRING]$StifleRVPNClientString = $StifleRSettings.GetValue('VPNStrings')
    [STRING]$StifleRDefaultDisconnectedBITSPolicy = $StifleRSettings.GetValue('DefaultDisconnectedBITSPolicy')
    [STRING]$StifleRDefaultDisconnectedDOPolicy = $StifleRSettings.GetValue('DefaultDisconnectedDOPolicy')
    [STRING]$StifleRDefaultNonRedLeaderBITSPolicy = $StifleRSettings.GetValue('DefaultNonRedLeaderBITSPolicy')
    [STRING]$StifleRDefaultNonRedLeaderDOPolicy = $StifleRSettings.GetValue('DefaultNonRedLeaderDOPolicy')

    
    #Confirm Server Name
    if ($StifleRServerString -match $DesiredServerName){
        Write-Host -ForegroundColor Green "StifleR Server Name is already set to $DesiredServerName"
    }
    else {
        Write-Host -ForegroundColor Red "Request Value: $DesiredServerName |  Current Value: $StifleRServerString"
        Exit 1
    }

    #Confirm VPN Client
    if ($StifleRVPNClientString -match $DesiredVPNClient){
        Write-Host -ForegroundColor Green "StifleR VPN Client is already set to $DesiredVPNClient"
    }
    else {
        Write-Host -ForegroundColor Red "Request Value: $DesiredVPNClient |  Current Value: $StifleRVPNClientString"
        Exit 1
    }
    #Confirm Default Disconnected BITS Policy
    if ($StifleRDefaultDisconnectedBITSPolicy -eq $DesiredDefaultDisconnectedBITSPolicy){
        Write-Host -ForegroundColor Green "StifleR Default Disconnected BITS Policy is already set to $DesiredDefaultDisconnectedBITSPolicy"
    }
    else {
        Write-Host -ForegroundColor Red "Request Value: $DesiredDefaultDisconnectedBITSPolicy |  Current Value: $StifleRDefaultDisconnectedBITSPolicy"
        Exit 1
    }
    #Confirm Default Disconnected DO Policy
    if ($StifleRDefaultDisconnectedDOPolicy -eq $DesiredDefaultDisconnectedDOPolicy){
        Write-Host -ForegroundColor Green "StifleR Default Disconnected DO Policy is already set to $DesiredDefaultDisconnectedDOPolicy"
    }
    else {
        Write-Host -ForegroundColor Red "Request Value: $DesiredDefaultDisconnectedDOPolicy |  Current Value: $StifleRDefaultDisconnectedDOPolicy"
        Exit 1
    }

    #Confirm Default Non-Red Leader BITS Policy
    if ($StifleRDefaultNonRedLeaderBITSPolicy -eq $DefaultNonRedLeaderBITSPolicy){
        Write-Host -ForegroundColor Green "StifleR Default Non-Red Leader BITS Policy is already set to $DefaultNonRedLeaderBITSPolicy"
    }
    else {
        Write-Host -ForegroundColor Red "Request Value: $DefaultNonRedLeaderBITSPolicy |  Current Value: $StifleRDefaultNonRedLeaderBITSPolicy"
        Exit 1
    }
    #Confirm Default Non-Red Leader DO Policy
    if ($StifleRDefaultNonRedLeaderDOPolicy -eq $DefaultNonRedLeaderDOPolicy){
        Write-Host -ForegroundColor Green "StifleR Default Non-Red Leader DO Policy is already set to $DefaultNonRedLeaderDOPolicy"
    }
    else {
        Write-Host -ForegroundColor Red "Request Value: $DefaultNonRedLeaderDOPolicy |  Current Value: $StifleRDefaultNonRedLeaderDOPolicy"
        Exit 1
    }
}
else {
    Write-Host -ForegroundColor Red "StifleR Registry Path not found: $StifleRRegPath"
}
