function Enable-DomainController {
<#
.SYNOPSIS
    Promotes Windows Server 2025 to a Primary Domain Controller with DNS.

.DESCRIPTION
    This function installs the Active Directory Domain Services (AD DS) and DNS Server features,
    then promotes the server to be the first Domain Controller in a new forest for the domain
    2PintLabs.local. The DNS Server role is installed and configured as part of the promotion.

.PARAMETER DomainName
    The fully qualified domain name for the new forest. Default is "2PintLabs.local".

.PARAMETER DomainNetbiosName
    The NetBIOS name for the domain. Default is "2PINTLABS".

.PARAMETER SafeModeAdministratorPassword
    The Directory Services Restore Mode (DSRM) password as a SecureString. 
    If not provided, defaults to "P@ssw0rd".

.PARAMETER SkipReboot
    If specified, the server will not reboot automatically after promotion.

.PARAMETER AutoAccept
    If specified, skips all confirmation prompts and proceeds automatically.

.EXAMPLE
    Enable-DomainController
    Promotes the server to a DC with default settings, prompting for confirmation.

.EXAMPLE
    Enable-DomainController -AutoAccept
    Promotes the server to a DC automatically without prompts.

.EXAMPLE
    $password = ConvertTo-SecureString "MyP@ssw0rd!" -AsPlainText -Force
    Enable-DomainController -SafeModeAdministratorPassword $password -AutoAccept

.EXAMPLE
    Enable-DomainController -DomainName "MyDomain.local" -DomainNetbiosName "MYDOMAIN" -AutoAccept

.NOTES
    Author: Gary Blok
    Date: November 5, 2025
    
    Requirements:
    - Windows Server 2025
    - Administrative privileges
    - Server name should be set before running this function
    
    After running this function, the server will reboot automatically unless -SkipReboot is specified.

    Changes:
    - 25.11.5 - Set Static IP to .200 if DHCP is detected
    - 25.11.5 - Converted to function
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$DomainName = "2PintLabs.local",
    
    [Parameter(Mandatory=$false)]
    [string]$DomainNetbiosName = "2PINTLABS",
    
    [Parameter(Mandatory=$false)]
    [SecureString]$SafeModeAdministratorPassword,
    
    [Parameter(Mandatory=$false)]
    [switch]$SkipReboot,
    
    [Parameter(Mandatory=$false)]
    [switch]$AutoAccept
)

# Set error action preference
$ErrorActionPreference = "Stop"

# Function to write colored output
function Write-ColorOutput {
    param(
        [string]$Message,
        [string]$Color = "White"
    )
    Write-Host $Message -ForegroundColor $Color
}

# Function to check if running as administrator
function Test-Administrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Function to get or create Safe Mode password
function Get-SafeModePassword {
    if ($SafeModeAdministratorPassword) {
        return $SafeModeAdministratorPassword
    }
    
    # Use default password if not provided
    Write-ColorOutput "`nUsing default Directory Services Restore Mode (DSRM) password: P@ssw0rd" -Color Yellow
    Write-ColorOutput "This password is used to start AD DS in Safe Mode." -Color Yellow
    Write-ColorOutput "You can change this by providing -SafeModeAdministratorPassword parameter." -Color Gray
    
    $defaultPassword = ConvertTo-SecureString "P@ssw0rd" -AsPlainText -Force
    return $defaultPassword
}

# Main script execution
try {
    Write-ColorOutput "`n========================================" -Color Cyan
    Write-ColorOutput "Domain Controller Promotion Script" -Color Cyan
    Write-ColorOutput "========================================`n" -Color Cyan
    
    # Check if running as administrator
    if (-not (Test-Administrator)) {
        Write-ColorOutput "ERROR: This function must be run as Administrator!" -Color Red
        return
    }
    
    # Display current configuration
    Write-ColorOutput "Server Information:" -Color Yellow
    Write-ColorOutput "  Computer Name: $env:COMPUTERNAME" -Color White
    Write-ColorOutput "  Domain Name: $DomainName" -Color White
    Write-ColorOutput "  NetBIOS Name: $DomainNetbiosName" -Color White
    
    # Get network adapter information
    $adapter = Get-NetAdapter | Where-Object {$_.Status -eq "Up"} | Select-Object -First 1
    $ipConfig = Get-NetIPAddress -InterfaceIndex $adapter.InterfaceIndex -AddressFamily IPv4
    
    Write-ColorOutput "`nNetwork Configuration:" -Color Yellow
    Write-ColorOutput "  Current IP Address: $($ipConfig.IPAddress)" -Color White
    Write-ColorOutput "  Interface: $($adapter.Name)" -Color White
    
    # Check if IP is static
    $ipInterface = Get-NetIPInterface -InterfaceIndex $adapter.InterfaceIndex -AddressFamily IPv4
    if ($ipInterface.Dhcp -eq "Enabled") {
        Write-ColorOutput "`nDHCP detected. Converting to static IP..." -Color Yellow
        
        # Calculate new IP with .200 as last octet
        $currentIP = $ipConfig.IPAddress
        $ipParts = $currentIP.Split('.')
        $ipParts[3] = "200"
        $newStaticIP = $ipParts -join '.'
        
        # Get current gateway and DNS
        $gateway = (Get-NetRoute -InterfaceIndex $adapter.InterfaceIndex -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue).NextHop
        $dnsServers = (Get-DnsClientServerAddress -InterfaceIndex $adapter.InterfaceIndex -AddressFamily IPv4).ServerAddresses
        
        Write-ColorOutput "  Setting static IP: $newStaticIP" -Color Cyan
        Write-ColorOutput "  Subnet Mask: 255.255.255.0 (/24)" -Color Gray
        if ($gateway) {
            Write-ColorOutput "  Gateway: $gateway" -Color Gray
        }
        
        try {
            # Remove existing IP configuration
            Remove-NetIPAddress -InterfaceIndex $adapter.InterfaceIndex -AddressFamily IPv4 -Confirm:$false -ErrorAction SilentlyContinue
            Remove-NetRoute -InterfaceIndex $adapter.InterfaceIndex -DestinationPrefix "0.0.0.0/0" -Confirm:$false -ErrorAction SilentlyContinue
            
            # Set new static IP
            New-NetIPAddress -InterfaceIndex $adapter.InterfaceIndex `
                -IPAddress $newStaticIP `
                -PrefixLength 24 `
                -DefaultGateway $gateway -ErrorAction Stop | Out-Null
            
            # Set DNS to point to itself (this server will be the DNS server)
            Set-DnsClientServerAddress -InterfaceIndex $adapter.InterfaceIndex -ServerAddresses $newStaticIP
            
            Write-ColorOutput "  ✓ Static IP configured successfully" -Color Green
            Write-ColorOutput "  ✓ DNS set to point to this server: $newStaticIP" -Color Green
            
            # Update ipConfig variable with new configuration
            Start-Sleep -Seconds 2
            $ipConfig = Get-NetIPAddress -InterfaceIndex $adapter.InterfaceIndex -AddressFamily IPv4
            
        } catch {
            Write-ColorOutput "  ✗ Failed to set static IP" -Color Red
            Write-ColorOutput "  Error: $($_.Exception.Message)" -Color Red
            return
        }
    } else {
        Write-ColorOutput "  ✓ Static IP already configured" -Color Green
    }
    
    # Confirm before proceeding
    Write-ColorOutput "`nThis script will:" -Color Yellow
    Write-ColorOutput "  1. Install AD DS and DNS Server features" -Color White
    Write-ColorOutput "  2. Promote this server to a Domain Controller" -Color White
    Write-ColorOutput "  3. Create a new forest: $DomainName" -Color White
    Write-ColorOutput "  4. Configure DNS Server" -Color White
    Write-ColorOutput "  5. Reboot the server" -Color White
    
    if (-not $AutoAccept) {
        $confirm = Read-Host "`nDo you want to continue? (yes/no)"
        if ($confirm -ne "yes") {
            Write-ColorOutput "Script cancelled by user." -Color Red
            return
        }
    } else {
        Write-ColorOutput "`nAuto-accept enabled. Continuing automatically..." -Color Green
    }
    
    # Get Safe Mode password
    $dsrmPassword = Get-SafeModePassword
    
    # Step 1: Install AD DS and DNS Server features
    Write-ColorOutput "`n[Step 1/3] Installing Active Directory Domain Services and DNS Server features..." -Color Cyan
    
    $features = @(
        "AD-Domain-Services",
        "DNS",
        "RSAT-AD-Tools",
        "RSAT-ADDS",
        "RSAT-ADDS-Tools",
        "RSAT-AD-PowerShell",
        "RSAT-DNS-Server"
    )
    
    foreach ($feature in $features) {
        Write-ColorOutput "  Installing feature: $feature" -Color Gray
    }
    
    $installResult = Install-WindowsFeature -Name $features -IncludeManagementTools
    
    if ($installResult.Success) {
        Write-ColorOutput "  ✓ Features installed successfully" -Color Green
        
        if ($installResult.RestartNeeded -eq "Yes") {
            Write-ColorOutput "  Note: A restart will be required after domain promotion" -Color Yellow
        }
    } else {
        Write-ColorOutput "  ✗ Failed to install features" -Color Red
        return
    }
    
    # Step 2: Import AD DS Deployment module
    Write-ColorOutput "`n[Step 2/3] Importing AD DS Deployment module..." -Color Cyan
    Import-Module ADDSDeployment -ErrorAction Stop
    Write-ColorOutput "  ✓ Module imported successfully" -Color Green
    
    # Step 3: Promote to Domain Controller
    Write-ColorOutput "`n[Step 3/3] Promoting server to Primary Domain Controller..." -Color Cyan
    Write-ColorOutput "  Domain Name: $DomainName" -Color Gray
    Write-ColorOutput "  NetBIOS Name: $DomainNetbiosName" -Color Gray
    Write-ColorOutput "  Forest Functional Level: WinThreshold (Windows Server 2016 or higher)" -Color Gray
    Write-ColorOutput "  Domain Functional Level: WinThreshold (Windows Server 2016 or higher)" -Color Gray
    Write-ColorOutput "`n  This process may take several minutes..." -Color Yellow
    
    # Prepare promotion parameters
    $promotionParams = @{
        DomainName = $DomainName
        DomainNetbiosName = $DomainNetbiosName
        DomainMode = "WinThreshold"
        ForestMode = "WinThreshold"
        InstallDns = $true
        CreateDnsDelegation = $false
        DatabasePath = "C:\Windows\NTDS"
        LogPath = "C:\Windows\NTDS"
        SysvolPath = "C:\Windows\SYSVOL"
        SafeModeAdministratorPassword = $dsrmPassword
        Force = $true
        NoRebootOnCompletion = $SkipReboot
    }
    
    # Perform the promotion
    try {
        Install-ADDSForest @promotionParams
        
        Write-ColorOutput "`n========================================" -Color Green
        Write-ColorOutput "Domain Controller Promotion Complete!" -Color Green
        Write-ColorOutput "========================================" -Color Green
        
        Write-ColorOutput "`nDomain Information:" -Color Yellow
        Write-ColorOutput "  Domain: $DomainName" -Color White
        Write-ColorOutput "  NetBIOS: $DomainNetbiosName" -Color White
        Write-ColorOutput "  DNS Server: Installed and configured" -Color White
        
        if ($SkipReboot) {
            Write-ColorOutput "`nNOTE: You must restart the server manually to complete the promotion." -Color Yellow
        } else {
            Write-ColorOutput "`nThe server will now restart automatically..." -Color Yellow
        }
        
    } catch {
        Write-ColorOutput "`n✗ Failed to promote server to Domain Controller" -Color Red
        Write-ColorOutput "Error: $($_.Exception.Message)" -Color Red
        
        # Log detailed error
        $errorLog = "C:\Temp\DC_Promotion_Error.log"
        if (-not (Test-Path "C:\Temp")) {
            New-Item -Path "C:\Temp" -ItemType Directory -Force | Out-Null
        }
        $_ | Out-File -FilePath $errorLog -Append
        Write-ColorOutput "`nError details have been logged to: $errorLog" -Color Yellow
        
        return
    }
    
} catch {
    Write-ColorOutput "`nAn unexpected error occurred:" -Color Red
    Write-ColorOutput $_.Exception.Message -Color Red
    Write-ColorOutput "`nStack Trace:" -Color Red
    Write-ColorOutput $_.ScriptStackTrace -Color Red
    return
}
} # End of Enable-DomainController function

#Do the Stuff

Enable-DomainController -AutoAccept -SkipReboot