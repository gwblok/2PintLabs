try {
    Import-Module DeployR.Utility -ErrorAction SilentlyContinue
}
catch {
    Write-Warning "DeployR.Utility module not found. Environment variables will be set in the standard environment."
}

if (Get-Module -name "DeployR.Utility"){
    write-Host "Using DeployR.Utility Module to get FQDN" -ForegroundColor Green
    $FQDN = ${TSEnv:FormFQDN}
    write-Host "FQDN = $(${TSEnv:FormFQDN})" -ForegroundColor Green
}
else{
    Write-Host "Using Test Values for FQDN" -ForegroundColor Yellow
    $FQDN = "DeployR.2PintLabs.com"
    write-Host "FQDN = $FQDN" -ForegroundColor Yellow
}

#Get the Current IP Address of the machine
$CurrentIP = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notlike "169.254.*" -and $_.IPAddress -ne "127.0.0.1" }).IPAddress | Select-Object -First 1


#This Script will be used to add computer names & IPs to the hosts file
$Servers2Add = @(
    @{SERVERNAME = $FQDN ; IPAddress = $CurrentIP}
)



function Test-HostFileEntry{
    param (
        [string]$ServerName,
        [string]$IPAddress
    )

    $HostFilePath = "$env:SystemRoot\System32\drivers\etc\hosts"
    $HostFileEntry = "$IPAddress   $ServerName"
    
    # Check if the entry already exists in the hosts file
    if (Select-String -Path $HostFilePath -Pattern $ServerName) {

        Write-Output "Entry for $ServerName already exists in the hosts file."
        return $true
    } else {
        Write-Output "Entry for $ServerName does not exist in the hosts file."
        return $false
    }
}
function Add-HostFileEntry {
    param (
        [string]$ServerName,
        [string]$IPAddress
    )

    $HostFilePath = "$env:SystemRoot\System32\drivers\etc\hosts"
    $HostFileBackupPath = "$env:SystemRoot\System32\drivers\etc\hosts.bak"
    $HostFileEntry = "$IPAddress   $ServerName"
    
    # Check if the entry already exists in the hosts file
    if (Select-String -Path $HostFilePath -Pattern $ServerName) {
        Write-Output "Entry for $ServerName already exists in the hosts file."
    } else {
        # Backup the hosts file before modifying it
        Copy-Item -Path $HostFilePath -Destination $HostFileBackupPath -Force
        
        # Add the entry to the hosts file
        Add-Content -Path $HostFilePath -Value $HostFileEntry
        Write-Output "Added entry for $ServerName to the hosts file."
    }
}


# Loop through each server and add the entry to the hosts file
foreach ($Server in $Servers2Add) {
    $ServerName = $Server.SERVERNAME
    $IPAddress = $Server.IPAddress
    if ((Test-HostFileEntry -ServerName $ServerName -IPAddress $IPAddress) -eq $true) {
        # If the entry exists, we do not need to do anything
    }
    else {
        Add-HostFileEntry -ServerName $ServerName -IPAddress $IPAddress
    }
}
