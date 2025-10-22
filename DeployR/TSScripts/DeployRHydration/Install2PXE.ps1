try {
    Import-Module DeployR.Utility -ErrorAction SilentlyContinue
}
catch {
    Write-Warning "DeployR.Utility module not found. Environment variables will be set in the standard environment."
}

if (Get-Module -name "DeployR.Utility"){
    write-Host "Using DeployR.Utility Module to get FQDN and Install2PXE values" -ForegroundColor Green
    $FQDN = ${TSEnv:FormFQDN}
    $Install2PXE = ${TSEnv:FormInstall2PXE}
    write-Host "FQDN = $(${TSEnv:FormFQDN})" -ForegroundColor Green
    write-Host "Install2PXE = $Install2PXE" -ForegroundColor Green
}
else{
    Write-Host "Using Test Values for FQDN and Install2PXE" -ForegroundColor Yellow
    $FQDN = "DeployR.2PintLabs.com"
    $Install2PXE = $true
    write-Host "FQDN = $FQDN" -ForegroundColor Yellow
    write-Host "Install2PXE = $Install2PXE" -ForegroundColor Yellow
}

Function Install-2PXE {
    [CmdletBinding()]
    param (
    [string]$domain,
    [string]$fqdn,
    #This one is required - path to the 2PXE MSI file
    [Parameter(Mandatory=$true)]
    [string]$msifile
    )
    <#
    .Synopsis
    Install the 2PXE service and sets all the optional parameters
    
    .Description
    Use this to automate the install.
    
    .Notes
    Author          : Phil Wilcock <senior@2PintSoftware.com>
    Last Updated By : Mike Terrill
    Web             : https://2pintsoftware.com
    Date            : 20/07/2025
    Version         : 1.1
    
    IMPORTANT Requires PS -Version 3.0
    
    This script must be run from the same folder as the  2PXE Installer .MSI
    Tested with version 3.7
    
    Example: Run from the Powershell console - .\install_2pxe.ps1
    
    This script contains ALL config parameters. The Mandatory ones are enabled, and all others are commented out, 
    so simply choose the ones that you want to configure and uncomment them + insert the correct config parameter.
    NOTE: Parameters in "quotes" need to be escaped - don't delete the escape ```` chars in there!
    
    Problems? Check the Full Documentation for descriptions of the install paramters etc.
    Still stuck? - Email support@2pintsoftware.com      
    
    #>
    
    # Set path to MSI file
    #$msifile = "$PSScriptRoot\2Pint Software 2PXE Service (x64).msi"
    if (-not $msifile) {
    Write-Error "Please provide the path to the StifleR Dashboard MSI file."
    exit 1
}
if (!(Test-Path $msifile)) {
    Write-Error "MSI file not found at $msifile. Please provide the correct path to the StifleR Dashboard MSI."
    exit 1
}

    # This will use the connection specific suffix for the fqdn - useful when system is not domain joined
    if (!$domain) {
        $domain = [string](Get-DnsClient | Select-Object -ExpandProperty ConnectionSpecificSuffix)
    }
    if ($($domain.Trim()) -eq ""){
        Write-Host "No domain suffix found. Please provide a domain name."
        #prompt user for domain name
        $domain = Read-Host "Enter the domain name to use for FQDN (e.g., example.com)"
    }
    Write-Host "Using Domain: $domain"
    if (!$fqdn) {
        $fqdn = "$($env:COMPUTERNAME.Trim()).$($domain.Trim())"
    }
    Write-Host "Using FQDN: $fqdn"
    $iPXEWSURL = "https://$($fqdn):8051"
    # Grabs the IPv4 address - used for teh BINDTOIP property
    $IPv4 = Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration -Filter "IPEnabled = 1" | % { $_.IPAddress | ? { -not $_.Contains(":") } }
    
    $arguments = @(
    #Mandatory msiexec Arguments
    
    "/i"
    
    "`"$msiFile`""
    
    #Mandatory 2Pint Arguments
    
    "INSTALLTYPE=`"1`""                  # <- 1 is PowerShell integration (NO CONFIGMGR), 2 is with MS ConfigMgr integration.
    "SERVICE_USERNAME=`"LocalSystem`""   # or "domain\username" if you want to use a domain account
    # "SERVICE_PASSWORD=`"Password`""        # (Can be skipped if SERVICE_USERNAME is LocalSystem)
    "BINDTOIP=`"$IPv4`""                 # Enter the server NIC IP address to which to bind the service
    
    #Non Mandatory 2Pint Arguments - Uncomment+change the settings that you need - otherwise the default will be used.
    
    ### MS CONFIGMGR SQL SETTINGS ##### 
    
    #"CONFIGMGRSQL=`"1`"" #  1 to enable a SQL connection to the  ConfigMgr DB, 0 to use HTTP via the Management Point (no menu)
    
    ### If CONFIGMGRSQL is set to 1 the following paramemeters MUST be set###
    
    # "RUNTIME_DATABASE_LOGON_TYPE=`"WinAuthCurrentUser`""     # "SqlAuth" if using SQL Accounts. "WinAuthCurrentUser" uses Integrated Security
    # "ODBC_SERVER=`"server.domain.local`""                   # FQDN of the ConfigMgr Database Server
    # "RUNTIME_DATABASE_NAME=`"CONFIGMGR_CEN`""               # Database Name, typically CONFIGMGR_<SITECODE>
    
    #####If CREATE_DATABASE_LOGON_TYPE is set to "SqlAuth" the follow parameters MUST be set
    
    # "CREATE_DATABASE_USERNAME=`"myusername`""              #<SQL Auth Username>
    # "CREATE_DATABASE_PASSWORD=`"mypassword`""              #<SQL Auth password>
    
    #Other Non-Mandatory 2Pint Settings
    
    # "REMOTEINSTALL_PATH=`"C:\myremoteinstallpath`""          # Set an alternate remoteinstall path - 
    # "DEBUGLOG_PATH=`"C:\MyLogfiles\2PXE.log`""               # Path to the logfile 
    # "DEBUGLOG=`"1`""                                         # 1 to enable and 0 to disable verbose logging
    # "RUN_ON_DHCP_PORT=`"1`""                                 # By default, 2PXE answers on both the DHCP (67) port and PXE (4011) port
    # "RUN_ON_PXE_PORT=`"1`""                                  # You can control this by setting the values to "0" for off or "1" for on
    # "RUN_TFTP_SERVER=`"1`""                                  # 2PXE has a built-in TFTP server 1 for ON 0 for OFF
    # "RUN_HTTP_SERVER=`"1`""                                  # 2PXE WebService for iPXE integration 1 for ON 0 for OFF
    "EMBEDDEDSDI=`"0`""                                      # Use an embedded boot.sdi image. See full documentation for more info
    # "F12TIMEOUT=`"10000`""                                   # F12 prompt timout for iPXE loaders for non mandatory deployements in milliseconds.
    # "IPXELOADERS=`"1`""                                      # Use iPXE Boot Loaders 1 to enable and 0 to disable. If 0 2PXE will use Windows boot loaders
    # "UNKNOWNSUPPORT=`"1`""                                   # 1 for enable (default) 0 to disable - enables Unknown Machine support in ConfigMgr
    # "PORTNUMBER=`"8050`""                                    # 2PXE Http Service Port -  8050 by default
    # "POWERSHELLSCRIPTALLOWBOOTH_PATH=`"c:\myscripts`""       # Set only if using custom path location for .ps1 scripts
    # "POWERSHELLSCRIPTIMAGES_PATH=`"c:\myscripts`""           # Set only if using custom path location for .ps1 scripts
    # "INSTALLFOLDER=`"C:\MyInstallPath`""                     # Default is C:\Program Files\2pint Software 
    # "ENABLESCCMMENUCOUNTDOWN=`"10000`""                      # Countdown for menu timeout if nothing is selcted (in Millisecs)
    # "ENABLESCCMMANDATORYCOUNTDOWN=`"30000`""                 # Countdown for Mandatory deployments - the deployment will be executed  after this expires (in Millisecs)
    # "SCCMREPORTSTATE=`"1`""                                  # Instructs 2PXE to send SCCM state messages for mandatory deployments. 1 to send, 0 to not send.
    # "WIMBOOTPARAMS=`"gui`""                                  # command line for wimboot, possible paramteres are: gui, pause, pause=quiet, rawbcd, index=x For details see: http://ipxe.org/appnote/wimboot_architecture
    "ENABLEIPXEANYWHEREWEBSERVICE=`"573`""                   # Specifies to use iPXE Anywhere Web Service. 0 to disable and various BIT values for various Reporting options 
    "IPXEANYWHEREWEBSERVICEURI=`"$iPXEWSURL`""               # "http://url:Port" Specifies the address and Port for the iPXE Anywhere Web Service 
    # "NETWORKACCESS_USERNAME="[%USERDOMAIN]\[%USERNAME]"      # User name to access IIS paths 
    # "NETWORKACCESS_PASSWORD=“A123456!"                       # Password for above account
    # "FWTFTP=`"1`""                                           # Allow the installer to create the Port 69 UDP Firewall exception
    # "FWDHCP=`"1`""                                           # Allow the installer to create the Port 67 UDP Firewall exception
    # "FWPROXYDHCP=`"1`""                                      # Allow the installer to create the Port 4011 UDP Firewall exception
    # "FWHTTP=`"1`""                                           # Allow the installer to create the Port 8050 TCP Firewall exception
    # "USEHYPERTHREAD=`"1`""                                   # Enabel Hyperthread
    
    #Other MSIEXEC params
    "/qn" #Quiet - with basic interface - for NO interface use /qn instead
    
    "/norestart"
    
    "/l*v $env:TEMP\2PXEInstall.log"    #Optional logging for the install
    
    )
    
    write-host "Using the following install commands: $arguments" #uncomment this line to see the command line
    
    #Install the 2PXE Service
    start-process "msiexec.exe" -arg $arguments -Wait
}

Function Import-2PXERootCA {
    <#
.SYNOPSIS
    PowerShell script to import the 2Pint 2PXE root certificate into the Trusted Root Certification Authorities store
.DESCRIPTION
    This script automates importing of the 2Pint 2PXE root certificate
    It verifies the import, and handles common errors.
.NOTES
    Author: Mike Terrill/2Pint Software
    Date: July 20, 2025
    Version: 25.07.22
    Requires: Administrative privileges, 64-bit Windows
    #>
    
    # Default 2Pint 2PXE path to the certificate file
    $certFilePath = "C:\Program Files\2Pint Software\2PXE\x64\ca.crt"
    
    # Check if the certificate file exists
    if (-not (Test-Path -Path $certFilePath)) {
        Write-Error "Certificate file not found at: $certFilePath"
        exit 1
    }
    
    try {
        # Load the certificate
        $certificate = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($certFilePath)
        
        # Display certificate details for verification
        Write-Host "Importing certificate: $($certificate.Subject)"
        Write-Host "Issuer: $($certificate.Issuer)"
        Write-Host "Thumbprint: $($certificate.Thumbprint)"
        
        # Open the Trusted Root Certification Authorities store for the Local Machine
        $store = New-Object System.Security.Cryptography.X509Certificates.X509Store(
        [System.Security.Cryptography.X509Certificates.StoreName]::Root,
        [System.Security.Cryptography.X509Certificates.StoreLocation]::LocalMachine
        )
        
        # Open the store with read/write access
        $store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)
        
        # Check if the certificate already exists in the store
        $existingCert = $store.Certificates | Where-Object { $_.Thumbprint -eq $certificate.Thumbprint }
        if ($existingCert) {
            Write-Warning "Certificate with thumbprint $($certificate.Thumbprint) already exists in the Trusted Root store."
        } else {
            # Add the certificate to the store
            $store.Add($certificate)
            Write-Host "Certificate successfully imported to Trusted Root Certification Authorities store."
        }
        
        # Close the store
        $store.Close()
    }
    catch {
        Write-Error "Failed to import certificate: $_"
        $store.Close()
        exit 1
    }
    
    # Verify the certificate was added
    $store = New-Object System.Security.Cryptography.X509Certificates.X509Store(
    [System.Security.Cryptography.X509Certificates.StoreName]::Root,
    [System.Security.Cryptography.X509Certificates.StoreLocation]::LocalMachine
    )
    $store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadOnly)
    $certInStore = $store.Certificates | Where-Object { $_.Thumbprint -eq $certificate.Thumbprint }
    $store.Close()
    
    if ($certInStore) {
        Write-Host "Verification: Certificate with thumbprint $($certificate.Thumbprint) is present in the Trusted Root store."
    } else {
        Write-Warning "Verification: Certificate with thumbprint $($certificate.Thumbprint) was not found in the Trusted Root store."
    }
}

$MSIFiles = Get-ChildItem -Path C:\Windows\Temp\2Pint -Filter *.msi

$2PXE = $MSIFiles | Where-Object { $_.Name -like "*2PXE*.msi" } | Select-Object -First 1

Install-2PXE -msifile $2PXE.FullName -fqdn $FQDN
Import-2PXERootCA