try {
    Import-Module DeployR.Utility -ErrorAction SilentlyContinue
}
catch {
    Write-Warning "DeployR.Utility module not found. Environment variables will be set in the standard environment."
}

if (Get-Module -name "DeployR.Utility"){
    $ContentLocation = ${TSEnv:_CONTENT-CONTENT}
}
else{
    $ContentLocation = Split-Path -Path $MyInvocation.MyCommand.Definition -Parent
}

<#
.SYNOPSIS
    Downloads and installs Microsoft SQL Server 2022 Express (x64) on Windows.
.DESCRIPTION
    This is used to install SQL Server 2022 Express edition in an from an offline installer you already downloaded and placed in the same location as this script
.NOTES
    Author: Mike Terrill/2Pint Software & Gary Blok
    Date: August 4, 2025
    Version: 25.08.04
    Requires: Administrative privileges, 64-bit Windows, internet access

CHANGELOG
    25.08.04 - Initial version
    25.10.22 - Modified to use with Offline Installer and skip downloading

#>

# Configuration
#$DownloadUrl = "https://go.microsoft.com/fwlink/?linkid=2215160"  # Official Microsoft URL for SQL Server 2022 Express


$SQLInstallerFile = Get-ChildItem -Path $ContentLocation -Filter "SQLEXPR_x64_ENU.exe" | Select-Object -First 1
write-Host "Using SQL Installer File: $($SQLInstallerFile.FullName)"
$LogFile = "$env:TEMP\SQL_Express_Install_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$InstanceName = "SQLEXPRESS"  # Default instance name

# Function to write to log file
function Write-Log {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [Parameter(Mandatory = $true)]
        [string]$LogFile
    )
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$Timestamp - $Message" | Out-File -FilePath $LogFile -Append
}

# Function to check if the script is running as administrator
function Test-Admin {
    $CurrentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $Principal = New-Object Security.Principal.WindowsPrincipal($CurrentUser)
    return $Principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function New-SQLExpressConfigFile {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]$ConfigFilePath = "C:\Windows\Temp\SQLExpress\Configuration.ini",
        [Parameter(Mandatory = $true)]
        [string]$LogFile
    )

    Write-Log -Message "Creating SQL Server 2022 Express Configuration.ini file at $ConfigFilePath" -LogFile $LogFile

    # Define the configuration content
    $ConfigContent = @"
;SQL Server 2022 Configuration File
[OPTIONS]

; Specifies a Setup work flow, like INSTALL, UNINSTALL, or UPGRADE. This is a required parameter. 
ACTION="Install"

; Use the /ENU parameter to install the English version of SQL Server on your localized Windows operating system. 
ENU="True"

; Setup roles install SQL Server in a predetermined configuration. 
ROLE="AllFeatures_WithDefaults"

; Indicates whether the supplied product key is covered by Service Assurance. 
PRODUCTCOVEREDBYSA="False"

; Specifies that SQL Server Setup should not display the privacy statement when ran from the command line. 
SUPPRESSPRIVACYSTATEMENTNOTICE="True"

; Setup will not display any user interface. 
QUIET="True"

; Setup will display progress only, without any user interaction. 
QUIETSIMPLE="False"

; Parameter that controls the user interface behavior. Valid values are Normal for the full UI,AutoAdvance for a simplied UI, and EnableUIOnServerCore for bypassing Server Core setup GUI block. 
;UIMODE="AutoAdvance"

; Specify whether SQL Server Setup should discover and include product updates. The valid values are True and False or 1 and 0. By default SQL Server Setup will include updates that are found. 
UpdateEnabled="False"

; If this parameter is provided, then this computer will use Microsoft Update to check for updates. 
USEMICROSOFTUPDATE="False"

; Specifies that SQL Server Setup should not display the paid edition notice when ran from the command line. 
SUPPRESSPAIDEDITIONNOTICE="False"

; Specify the location where SQL Server Setup will obtain product updates. The valid values are "MU" to search Microsoft Update, a valid folder path, a relative path such as .\MyUpdates or a UNC share. By default SQL Server Setup will search Microsoft Update or a Windows Update service through the Window Server Update Services. 
UpdateSource="MU"

; Specifies features to install, uninstall, or upgrade. The list of top-level features include SQL, AS, IS, MDS, and Tools. The SQL feature will install the Database Engine, Replication, Full-Text, and Data Quality Services (DQS) server. The Tools feature will install shared components. 
FEATURES=SQLENGINE

; Displays the command line parameters usage. 
HELP="False"

; Specifies that the detailed Setup log should be piped to the console. 
INDICATEPROGRESS="False"

; Specify a default or named instance. MSSQLSERVER is the default instance for non-Express editions and SQLExpress for Express editions. This parameter is required when installing the SQL Server Database Engine (SQL), or Analysis Services (AS). 
INSTANCENAME="SQLEXPRESS"

; Specify the root installation directory for shared components.  This directory remains unchanged after shared components are already installed. 
INSTALLSHAREDDIR="C:\Program Files\Microsoft SQL Server"

; Specify the root installation directory for the WOW64 shared components.  This directory remains unchanged after WOW64 shared components are already installed. 
INSTALLSHAREDWOWDIR="C:\Program Files (x86)\Microsoft SQL Server"

; Specify the Instance ID for the SQL Server features you have specified. SQL Server directory structure, registry structure, and service names will incorporate the instance ID of the SQL Server instance. 
INSTANCEID="SQLEXPRESS"

; Startup type for the SQL Server CEIP service. 
SQLTELSVCSTARTUPTYPE="Automatic"

; Account for SQL Server CEIP service: Domain\User or system account. 
SQLTELSVCACCT="NT Service\SQLTELEMETRY`$SQLEXPRESS"

; Specify the installation directory. 
INSTANCEDIR="C:\Program Files\Microsoft SQL Server"

; Agent account name. 
AGTSVCACCOUNT="NT AUTHORITY\NETWORK SERVICE"

; Auto-start service after installation.  
AGTSVCSTARTUPTYPE="Disabled"

; Startup type for the SQL Server service. 
SQLSVCSTARTUPTYPE="Automatic"

; Level to enable FILESTREAM feature at (0, 1, 2 or 3). 
FILESTREAMLEVEL="0"

; The max degree of parallelism (MAXDOP) server configuration option. 
SQLMAXDOP="0"

; Set to "1" to enable RANU for SQL Server Express. 
ENABLERANU="True"

; Specifies a Windows collation or an SQL collation to use for the Database Engine. 
SQLCOLLATION="SQL_Latin1_General_CP1_CI_AS"

; Account for SQL Server service: Domain\User or system account. 
SQLSVCACCOUNT="NT Service\MSSQL`$SQLEXPRESS"

; Set to "True" to enable instant file initialization for SQL Server service. If enabled, Setup will grant Perform Volume Maintenance Task privilege to the Database Engine Service SID. This may lead to information disclosure as it could allow deleted content to be accessed by an unauthorized principal. 
SQLSVCINSTANTFILEINIT="True"

; Windows account(s) to provision as SQL Server system administrators. 
SQLSYSADMINACCOUNTS="BUILTIN\Administrators"

; The number of Database Engine TempDB files. 
SQLTEMPDBFILECOUNT="1"

; Specifies the initial size of a Database Engine TempDB data file in MB. 
SQLTEMPDBFILESIZE="8"

; Specifies the automatic growth increment of each Database Engine TempDB data file in MB. 
SQLTEMPDBFILEGROWTH="64"

; Specifies the initial size of the Database Engine TempDB log file in MB. 
SQLTEMPDBLOGFILESIZE="8"

; Specifies the automatic growth increment of the Database Engine TempDB log file in MB. 
SQLTEMPDBLOGFILEGROWTH="64"

; Provision current user as a Database Engine system administrator for SQL Server 2022 Express. 
ADDCURRENTUSERASSQLADMIN="True"

; Specify 0 to disable or 1 to enable the TCP/IP protocol. 
TCPENABLED="0"

; Specify 0 to disable or 1 to enable the Named Pipes protocol. 
NPENABLED="0"

; Startup type for Browser Service. 
BROWSERSVCSTARTUPTYPE="Disabled"

; Use SQLMAXMEMORY to minimize the risk of the OS experiencing detrimental memory pressure. 
SQLMAXMEMORY="2147483647"

; Use SQLMINMEMORY to reserve a minimum amount of memory available to the SQL Server Memory Manager. 
SQLMINMEMORY="0"
"@

    try {
        # Ensure the target directory exists
        $ConfigDir = Split-Path -Path $ConfigFilePath -Parent
        if (-not (Test-Path $ConfigDir)) {
            New-Item -Path $ConfigDir -ItemType Directory -Force | Out-Null
            Write-Log -Message "Created directory: $ConfigDir" -LogFile $LogFile
        }

        # Write the configuration file
        $ConfigContent | Out-File -FilePath $ConfigFilePath -Encoding ASCII -ErrorAction Stop
        Write-Log -Message "Successfully created Configuration.ini at $ConfigFilePath" -LogFile $LogFile
        Write-Output $true
    } catch {
        Write-Log -Message "ERROR: Failed to create Configuration.ini at $ConfigFilePath. Error: $($_.Exception.Message)" -LogFile $LogFile
        Write-Error "Failed to create Configuration.ini at $ConfigFilePath. Error: $($_.Exception.Message)"
        return $false
    }
}

# Function to verify SQL Server Express installation
function Test-SQLExpressInstalled {
    param (
        [Parameter(Mandatory = $true)]
        [string]$LogFile,
        [Parameter(Mandatory = $true)]
        [string]$InstanceName
    )

    $ServiceName = "MSSQL`$$InstanceName"
    Write-Log -Message "Checking if SQL Server Express ($ServiceName) is installed..." -LogFile $LogFile

    try {
        $Service = Get-Service -Name $ServiceName -ErrorAction Stop
        if ($Service.Status -eq "Running" -or $Service.Status -eq "Stopped") {
            Write-Log -Message "SQL Server Express instance $InstanceName is installed and service is $($Service.Status)." -LogFile $LogFile
            return $true
        } else {
            Write-Log -Message "SQL Server Express instance $InstanceName found but service status is $($Service.Status)." -LogFile $LogFile
            return $false
        }
    } catch {
        Write-Log -Message "ERROR: SQL Server Express instance $InstanceName not found. Error: $($_.Exception.Message)" -LogFile $LogFile
        return $false
    }
}

# Start logging
Write-Log -Message "Starting SQL Server 2022 Express installation script." -LogFile $LogFile

# Check for administrative privileges
if (-not (Test-Admin)) {
    Write-Log -Message "ERROR: Script must be run as an administrator." -LogFile $LogFile
    Write-Error "This script requires administrative privileges. Please run PowerShell as an administrator."
    exit 1
}

# Check if SQL Server Express is already installed
if (Test-SQLExpressInstalled -LogFile $LogFile -InstanceName $InstanceName) {
    Write-Host "SQL Server 2022 Express ($InstanceName) is already installed. Exiting."
    Write-Log -Message "Script terminated: SQL Server 2022 Express is already installed." -LogFile $LogFile
    exit 0
}

# Check for .NET Framework 4.7.2 or later
Write-Log -Message "Checking for .NET Framework 4.7.2 or later..." -LogFile $LogFile
$DotNetVersion = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full" -Name Release -ErrorAction SilentlyContinue).Release
if ($DotNetVersion -ge 461808) {  # 461808 corresponds to .NET 4.7.2
    Write-Log -Message ".NET Framework version $DotNetVersion (4.7.2 or later) detected." -LogFile $LogFile
} else {
    Write-Log -Message "ERROR: .NET Framework 4.7.2 or later is required but not detected." -LogFile $LogFile
    Write-Error ".NET Framework 4.7.2 or later is required. Please install it and retry."
    exit 1
}

<# Download the installer
Write-Log -Message "Downloading SQL Server 2022 Express from $DownloadUrl..." -LogFile $LogFile
try {
    $ProgressPreference = 'SilentlyContinue'  # Suppress progress bar for faster download
    Invoke-WebRequest -Uri $DownloadUrl -OutFile $InstallerPath -ErrorAction Stop
    Write-Log -Message "Download successful: $InstallerPath" -LogFile $LogFile
} catch {
    Write-Log -Message "ERROR: Failed to download installer. Error: $($_.Exception.Message)" -LogFile $LogFile
    Write-Error "Failed to download SQL Server 2022 Express. Error: $($_.Exception.Message)"
    exit 1
}
#>

# Verify the downloaded file exists
if (-not (Test-Path $SQLInstallerFile.FullName)) {
    Write-Log -Message "ERROR: Installer file not found at $($SQLInstallerFile.FullName)." -LogFile $LogFile
    Write-Error "Installer file not found at $($SQLInstallerFile.FullName)."
    exit 1
}

#Extract SQL Installer to get Setup
Write-Log -Message "Starting Extraction of $($SQLInstallerFile.FullName) to c:\Windows\Temp\SQLExpress" -LogFile $LogFile
$Extract = Start-Process -FilePath $SQLInstallerFile.FullName -ArgumentList "/x:`"c:\Windows\Temp\SQLExpress`" /q" -Wait -PassThru -NoNewWindow

if ($Extract.ExitCode -eq 0){
    Write-Host "Successful Extraction"
}

#Find Setup
$SQLSetupFile = Get-ChildItem -Path "C:\Windows\Temp\SQLExpress" -Filter "setup.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1

#configure SQL Installation File
if (-not $SQLSetupFile) {
    Write-Log -Message "ERROR: setup.exe not found in extracted files." -LogFile $LogFile
    Write-Error "setup.exe not found in extracted files."
    exit 1
}

# Create the Configuration.ini file
$Result = New-SQLExpressConfigFile -LogFile $LogFile

# Check result
if ($Result) {
    Write-Log "Configuration.ini created successfully at C:\Windows\Temp\SQLExpress\Configuration.ini" -LogFile $LogFile
} else {
    Write-Log "Failed to create Configuration.ini." -LogFile $LogFile
}

# Install SQL Server Express silently
Write-Log -Message "Installing SQL Server 2022 Express..." -LogFile $LogFile
try {
    $Arguments = "/IAcceptSqlServerLicenseTerms /Q /Action=Install /ConfigurationFile=C:\Windows\Temp\SQLExpress\Configuration.ini"
    $Process = Start-Process -FilePath $SQLSetupFile.FullName -ArgumentList $Arguments -Wait -PassThru -ErrorAction Stop -NoNewWindow
    Write-Log -Message "Installation exit code: $($Process.ExitCode)" -LogFile $LogFile
    
    if ($Process.ExitCode -eq 0) {
        Write-Log -Message "Installation completed successfully." -LogFile $LogFile
    } elseif ($Process.ExitCode -eq 3010) {
        Write-Log -Message "Installation completed successfully, but a reboot is required." -LogFile $LogFile
        Write-Host "Installation completed successfully, but a reboot is required."
    } else {
        Write-Log -Message "ERROR: Installation failed with exit code $($Process.ExitCode). Check logs in C:\Program Files\Microsoft SQL Server\160\Setup Bootstrap\Log" -LogFile $LogFile
        Write-Error "Installation failed with exit code $($Process.ExitCode). Check logs in C:\Program Files\Microsoft SQL Server\160\Setup Bootstrap\Log"
        exit $Process.ExitCode
    }
} catch {
    Write-Log -Message "ERROR: Installation process failed. Error: $($_.Exception.Message)" -LogFile $LogFile
    Write-Error "Installation process failed. Error: $($_.Exception.Message)"
    exit 1
}

# Verify installation
if (Test-SQLExpressInstalled -LogFile $LogFile -InstanceName $InstanceName) {
    Write-Host "SQL Server 2022 Express ($InstanceName) installed successfully."
    Write-Log -Message "Verification: SQL Server 2022 Express ($InstanceName) installed successfully." -LogFile $LogFile
} else {
    Write-Log -Message "ERROR: Verification failed. SQL Server Express instance $InstanceName not detected." -LogFile $LogFile
    Write-Error "Verification failed. SQL Server Express instance $InstanceName not detected."
    exit 1
}

Write-Log -Message "Script completed successfully." -LogFile $LogFile
Write-Host "SQL Server 2022 Express installed. Log file: $LogFile"
