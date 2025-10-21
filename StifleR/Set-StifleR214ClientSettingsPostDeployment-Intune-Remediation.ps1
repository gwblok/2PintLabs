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
        Write-Host -ForegroundColor Yellow "Changing StifleR Server Name from $StifleRServerString to [`"https://$($DesiredServerName):1414`"]"
        Set-ItemProperty -Path $StifleRRegPath -Name 'StiflerServers' -Value "[`"https://$($DesiredServerName):1414`"]" -force
    }
    #Confirm VPN Client
    if ($StifleRVPNClientString -match $DesiredVPNClient){
        Write-Host -ForegroundColor Green "StifleR VPN Client is already set to $DesiredVPNClient"
    }
    else {
        $UpdatedString = $StifleRVPNClientString.Replace("]", ",`"$DesiredVPNClient`"]")
        Write-Host -ForegroundColor Yellow "Changing StifleR VPN Client from $StifleRVPNClientString to $UpdatedString"
        Set-ItemProperty -Path $StifleRRegPath -Name 'VPNStrings' -Value $UpdatedString -force
    }
    #Confirm Default Disconnected BITS Policy
    if ($StifleRDefaultDisconnectedBITSPolicy -eq $DesiredDefaultDisconnectedBITSPolicy){
        Write-Host -ForegroundColor Green "StifleR Default Disconnected BITS Policy is already set to $DesiredDefaultDisconnectedBITSPolicy"
    }
    else {
        Write-Host -ForegroundColor Yellow "Changing StifleR Default Disconnected BITS Policy from $StifleRDefaultDisconnectedBITSPolicy to $DesiredDefaultDisconnectedBITSPolicy"
        Set-ItemProperty -Path $StifleRRegPath -Name 'DefaultDisconnectedBITSPolicy' -Value $DesiredDefaultDisconnectedBITSPolicy -force
    }
    #Confirm Default Disconnected DO Policy
    if ($StifleRDefaultDisconnectedDOPolicy -eq $DesiredDefaultDisconnectedDOPolicy){
        Write-Host -ForegroundColor Green "StifleR Default Disconnected DO Policy is already set to $DesiredDefaultDisconnectedDOPolicy"
    }
    else {
        Write-Host -ForegroundColor Yellow "Changing StifleR Default Disconnected DO Policy from $StifleRDefaultDisconnectedDOPolicy to $DesiredDefaultDisconnectedDOPolicy"
        Set-ItemProperty -Path $StifleRRegPath -Name 'DefaultDisconnectedDOPolicy' -Value $DesiredDefaultDisconnectedDOPolicy -force
    }
    #Confirm Default Non-Red Leader BITS Policy
    if ($StifleRDefaultNonRedLeaderBITSPolicy -eq $DefaultNonRedLeaderBITSPolicy){
        Write-Host -ForegroundColor Green "StifleR Default Non-Red Leader BITS Policy is already set to $DefaultNonRedLeaderBITSPolicy"
    }
    else {
        Write-Host -ForegroundColor Yellow "Changing StifleR Default Non-Red Leader BITS Policy from $StifleRDefaultNonRedLeaderBITSPolicy to $DefaultNonRedLeaderBITSPolicy"
        Set-ItemProperty -Path $StifleRRegPath -Name 'DefaultNonRedLeaderBITSPolicy' -Value $DefaultNonRedLeaderBITSPolicy -force
    }
    #Confirm Default Non-Red Leader DO Policy
    if ($StifleRDefaultNonRedLeaderDOPolicy -eq $DefaultNonRedLeaderDOPolicy){
        Write-Host -ForegroundColor Green "StifleR Default Non-Red Leader DO Policy is already set to $DefaultNonRedLeaderDOPolicy"
    }
    else {
        Write-Host -ForegroundColor Yellow "Changing StifleR Default Non-Red Leader DO Policy from $StifleRDefaultNonRedLeaderDOPolicy to $DefaultNonRedLeaderDOPolicy"
        Set-ItemProperty -Path $StifleRRegPath -Name 'DefaultNonRedLeaderDOPolicy' -Value $DefaultNonRedLeaderDOPolicy -force
    }
    #Confirm Default Non-Red Leader BITS Policy
    if ($StifleRDefaultNonRedLeaderBITSPolicy -eq $DefaultNonRedLeaderBITSPolicy){
        Write-Host -ForegroundColor Green "StifleR Default Non-Red Leader BITS Policy is already set to $DefaultNonRedLeaderBITSPolicy"
    }
    else {
        Write-Host -ForegroundColor Yellow "Changing StifleR Default Non-Red Leader BITS Policy from $StifleRDefaultNonRedLeaderBITSPolicy to $DefaultNonRedLeaderBITSPolicy"
        Set-ItemProperty -Path $StifleRRegPath -Name 'DefaultNonRedLeaderBITSPolicy' -Value $DefaultNonRedLeaderBITSPolicy -force
    }

    Restart-Service -Name StifleRClient -Force
}
