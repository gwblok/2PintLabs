# Script to launch things that I find useful for DeployR

#Functions

Write-Host "Loading DeployR Functions" -ForegroundColor Cyan
write-host "Function: Get-DeployRGather" -ForegroundColor Green
function Get-DeployRGather {
    iex (irm "https://gather.garytown.com")
}

write-host "Function: Get-CMOSDGather" -ForegroundColor Green
function Get-CMOSDGather {
    $Script = Invoke-RestMethod -Uri "https://raw.githubusercontent.com/Josch62/Gather-Script-For-ConfigMgr-TS/refs/heads/main/Gather.ps1" -UseBasicParsing
    $Script | Out-File -FilePath "$env:temp\CMOSD-Gather.ps1" -Force -Encoding UTF8
    powershell.exe "$env:temp\CMOSD-Gather.ps1" -debug $true
}
write-host "===================================================================="
write-Host "DeployR Pre-Reqs Functions" -ForegroundColor Green
write-Host ""
Write-Host -ForegroundColor Green "[+] Test-DeployRPreReqs"
function Test-DeployRPreReqs {
    iex (irm https://raw.githubusercontent.com/gwblok/2PintLabs/refs/heads/main/DeployR/ServerSideScripts/Check-DeployRPreReqs.ps1)
}
Write-Host -ForegroundColor Green "[+] Enable-RequiredWindowsOptionalFeatures"
function Enable-RequiredWindowsOptionalFeatures {
    Install-WindowsFeature -Name Web-Server, Web-Windows-Auth, BranchCache -IncludeManagementTools
}

Write-Host -ForegroundColor Green "[+] Install-PowerShell74X"
function Install-PowerShell74X {
    iex (irm https://raw.githubusercontent.com/gwblok/2PintLabs/refs/heads/main/DeployR/TSScripts/Functions/Install-PowerShell74X.ps1)
}
Write-Host -ForegroundColor Green "[+] Install-DotNetRuntimes80X"
function Install-DotNetRuntimes80X {
    iex (irm https://raw.githubusercontent.com/gwblok/2PintLabs/refs/heads/main/DeployR/TSScripts/Functions/Install-DotNetRuntimes80X.ps1)
}


Write-Host -ForegroundColor Green "[+] Install-WindowsADK"
function Install-WindowsADK {
    iex (irm https://raw.githubusercontent.com/materrill/miketerrill.net/refs/heads/master/Software%20Install%20Scripts/Install-WindowsADK.ps1)
}
Write-Host -ForegroundColor Green "[+] Install-WinPEAddOn"
function Install-WinPEAddOn {
    iex (irm https://raw.githubusercontent.com/materrill/miketerrill.net/refs/heads/master/Software%20Install%20Scripts/Install-WinPEAddOn.ps1)
}
Write-Host -ForegroundColor Green "[+] Install-VCRedist-x64"
function Install-VCRedist-x64 {
    iex (irm https://raw.githubusercontent.com/materrill/miketerrill.net/refs/heads/master/Software%20Install%20Scripts/Install-VCRedist-x64.ps1)
}
write-Host -ForegroundColor Green "[+] Install-SQLExpress2022"
function Install-SQLExpress2022 {
    iex (irm https://raw.githubusercontent.com/materrill/miketerrill.net/refs/heads/master/Software%20Install%20Scripts/Install-SQLExpress2022.ps1)
}
write-Host -ForegroundColor Green "[+] Configure-SQLExpress"
function Configure-SQLExpress { 
    iex (irm https://raw.githubusercontent.com/materrill/miketerrill.net/refs/heads/master/Software%20Install%20Scripts/Configure-SQLExpress.ps1)
}
write-Host -ForegroundColor Green "[+] Install-SSMS21"
function Install-SSMS21 {
    iex (irm https://raw.githubusercontent.com/materrill/miketerrill.net/refs/heads/master/Software%20Install%20Scripts/Install-SSMS21.ps1)
}
Write-Host ""
Write-Host "===================================================================="
Write-Host "2Pint Software Install Scripts, Requires you have the MSI Path" -ForegroundColor Green

Write-Host -ForegroundColor Green "[+] Install-2PXE"
iex (irm https://raw.githubusercontent.com/gwblok/2PintLabs/refs/heads/main/DeployR/TSScripts/Functions/Install-2PXE.ps1)

Write-Host -ForegroundColor Green "[+] Create-FQDN2PXECert"
iex (irm https://raw.githubusercontent.com/gwblok/2PintLabs/refs/heads/main/DeployR/TSScripts/Functions/Create-FQDN2PXECert.ps1)

Write-Host -ForegroundColor Green "[+] Create-IIS443Binding"
iex (irm https://raw.githubusercontent.com/gwblok/2PintLabs/refs/heads/main/DeployR/TSScripts/Functions/Create-IIS443Binding.ps1)

Write-Host -ForegroundColor Green "[+] Install-iPXEWS"
iex (irm https://raw.githubusercontent.com/gwblok/2PintLabs/refs/heads/main/DeployR/TSScripts/Functions/Install-iPXEWS.ps1)



write-Host "===================================================================="
write-host "Function: Invoke-DeployRTS" -ForegroundColor Green
write-host " Common Servers I Use:" -ForegroundColor magenta
write-host "  - 214-deployr.2p.garytown.com" -ForegroundColor Green
write-host "  - recover01.2pintsoftware.com" -ForegroundColor Green
write-host "  - dr.2pintlabs.com" -ForegroundColor Green
write-host "===================================================================="
function Invoke-DeployRTS{
    param(
        [string]$ServerName,
        [string]$TSID
    )


    Write-Host "Invoking DeployR TS" -ForegroundColor Cyan
    if (-not $ServerName) {
        Write-Host "ServerName is not provided, using default: 214-deployr.2p.garytown.com" -ForegroundColor Yellow
        $ServerName = "214-deployr.2p.garytown.com"
    }
    if (($ServerName) -and (-not $TSID)) {
        Write-Host "ServerName: $ServerName" -ForegroundColor Yellow
        iex (irm "https://$($ServerName):7281/v1/Service/Bootstrap")
    }
    if (($ServerName) -and ($TSID)) {
        Write-Host "ServerName: $ServerName" -ForegroundColor Yellow
        Write-Host "TSID: $TSID" -ForegroundColor Yellow
        iex (irm "https://$($ServerName):7281/v1/Service/Bootstrap?tsid=$($TSID):1")
    }
    # Add logic here to use $ServerName and $TSID as needed
}
