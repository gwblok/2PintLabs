write-Host "Running Enable-PSRemoting to enable PowerShell Remoting"
try {Enable-PSRemoting -Force -SkipNetworkProfileCheck -ErrorAction Stop}
catch {Write-Host "Failed to enable PSRemoting. Error: $_"}

Write-Host "Running Set-ItemProperty to enable Remote Desktop connections"
Write-Host " Setting fDenyTSConnections to 0 (allow remote desktop connections)"
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name "fDenyTSConnections" -Value 0 -Force
Write-Host " Setting UserAuthentication to 1 (require NLA for remote desktop connections)"
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name 'UserAuthentication' -Value 1 -Force

Write-Host "Running Set-NetFirewallProfile to disable Windows Firewall (for all profiles)"
Set-NetFirewallProfile -All -Enabled False