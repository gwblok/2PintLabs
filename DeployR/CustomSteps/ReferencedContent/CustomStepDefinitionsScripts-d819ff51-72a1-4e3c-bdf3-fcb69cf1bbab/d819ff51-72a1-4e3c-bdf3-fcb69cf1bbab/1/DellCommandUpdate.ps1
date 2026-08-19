<#Gary Blok - @gwblok - 2PintSoftware.com

DISCLAIMER: THIS IS NOT AN OFFICIAL DELL SCRIPT. I DO NOT WORK FOR DELL. 
USE AT YOUR OWN RISK. I TAKE NO RESPONSIBILITY FOR ANYTHING THIS SCRIPT DOES. TEST IN A LAB FIRST.
ALL INFORMATION IS PUBLICLY AVAILABLE ON THE INTERNET. I JUST CONSOLIDATED IT INTO ONE SCRIPT.


#https://dl.dell.com/content/manual13608255-dell-command-update-version-5-x-reference-guide.pdf?language=en-us


#>
if ($env:SystemDrive -eq "X:"){
    Write-Host "Running in WinPE, this step requires a full Windows environment to run properly."
    exit 0
}

#Pull Vars from TS:
try {
    Import-Module DeployR.Utility
}
catch {}
if (Get-Module -name "DeployR.Utility"){
    $inTS = $true
    # Get the provided variables
    $updateTypeBIOSFirmware = ${TSEnv:updateTypeBIOSFirmware}
    $updateTypeDrivers = ${TSEnv:updateTypeDrivers}
    $updateTypeApplications = ${TSEnv:updateTypeApplications}
    $updateSeverityRating = ${TSEnv:updateSeverityRating}
    $ScanOnly = ${TSEnv:ScanOnly}
}
else {
    #Testing outside of DeployR
    $updateTypeBIOSFirmware = "False"
    $updateTypeDrivers = "True"
    $updateTypeApplications = "False"
    $updateSeverityRating = "All"
    $ScanOnly = "False"
}

$LogPath = "$env:SystemDrive\_2P\Logs"

#As of DCU 5.7, it needed 8.0, not 10 (which is in DeployR 1.3+)
$WindowsDesktopRuntimeVerRequired = "8.0"

[String]$MakeAlias = ${TSEnv:MakeAlias}
if ($MakeAlias -ne "Dell") {
    Write-Host "MakeAlias must be Dell. Exiting script."
    Exit 0
}

#Convert the string values to boolean
if ($updateTypeBIOSFirmware -eq "true") {[bool]$updateTypeBIOSFirmware = $true} 
else {[bool]$updateTypeBIOSFirmware = $false}
if ($updateTypeDrivers -eq "true") {[bool]$updateTypeDrivers = $true} 
else {[bool]$updateTypeDrivers = $false}
if ($updateTypeApplications -eq "true") {[bool]$updateTypeApplications = $true} 
else {[bool]$updateTypeApplications = $false}
if ($ScanOnly -eq "true") {[bool]$ScanOnly = $true} 
else {[bool]$ScanOnly = $false}

#Write Info to Log
Write-Host "=============================================================================="
Write-Host "Current DCU Settings selected from Task Sequence" 
Write-Host "updateTypeBIOSFirmware: $updateTypeBIOSFirmware"
Write-Host "updateTypeDrivers: $updateTypeDrivers"
Write-Host "updateTypeApplications: $updateTypeApplications"
Write-Host "updateSeverityRating: $updateSeverityRating"
Write-Host "ScanOnly: $ScanOnly"

if ($updateTypeBIOSFirmware-eq $false -and $updateTypeDrivers -eq $false -and $updateTypeApplications -eq $false){
    Write-Host "!!Since no boxes are checked, running all updates!!"
    Write-Host "This is totally logical, ok! It's based on the DCU documentation."
}
Write-Host "=============================================================================="


#region functions
function Get-DellSupportedModels {
    [CmdletBinding()]
    
    $CabPathIndex = "$env:ProgramData\EMPS\DellCabDownloads\CatalogIndexPC.cab"
    $DellCabExtractPath = "$env:ProgramData\EMPS\DellCabDownloads\DellCabExtract"
    
    # Pull down Dell XML CAB used in Dell Command Update ,extract and Load
    if (!(Test-Path $DellCabExtractPath)){$null = New-Item -Path $DellCabExtractPath -ItemType Directory -Force}
    Write-Verbose "Downloading Dell Cab"
    Invoke-WebRequest -Uri "https://downloads.dell.com/catalog/CatalogIndexPC.cab" -OutFile $CabPathIndex -UseBasicParsing -Proxy $ProxyServer
    If(Test-Path "$DellCabExtractPath\DellSDPCatalogPC.xml"){Remove-Item -Path "$DellCabExtractPath\DellSDPCatalogPC.xml" -Force}
    Start-Sleep -Seconds 1
    if (test-path $DellCabExtractPath){Remove-Item -Path $DellCabExtractPath -Force -Recurse}
    $null = New-Item -Path $DellCabExtractPath -ItemType Directory
    Write-Verbose "Expanding the Cab File..." 
    $null = expand $CabPathIndex $DellCabExtractPath\CatalogIndexPC.xml
    
    Write-Verbose "Loading Dell Catalog XML.... can take awhile"
    [xml]$XMLIndex = Get-Content "$DellCabExtractPath\CatalogIndexPC.xml"
    
    
    $SupportedModels = $XMLIndex.ManifestIndex.GroupManifest
    $SupportedModelsObject = @()
    foreach ($SupportedModel in $SupportedModels){
        $SPInventory = New-Object -TypeName PSObject
        $SPInventory | Add-Member -MemberType NoteProperty -Name "SystemID" -Value "$($SupportedModel.SupportedSystems.Brand.Model.systemID)" -Force
        $SPInventory | Add-Member -MemberType NoteProperty -Name "Model" -Value "$($SupportedModel.SupportedSystems.Brand.Model.Display.'#cdata-section')"  -Force
        $SPInventory | Add-Member -MemberType NoteProperty -Name "URL" -Value "$($SupportedModel.ManifestInformation.path)" -Force
        $SPInventory | Add-Member -MemberType NoteProperty -Name "Date" -Value "$($SupportedModel.ManifestInformation.version)" -Force		
        $SupportedModelsObject += $SPInventory 
    }
    return $SupportedModelsObject
}
Function Get-DCUVersion {
    $DCU=(Get-ItemProperty "HKLM:\SOFTWARE\Dell\UpdateService\Clients\CommandUpdate\Preferences\Settings" -ErrorVariable err -ErrorAction SilentlyContinue)
    if ($err.Count -eq 0) {
        $DCU = $DCU.ProductVersion
    }else{
        $DCU = $false
    }
    return $DCU
}
Function Get-DCUInstallDetails {
    #Declare Variables for Universal app if RegKey AppCode is Universal or if Regkey AppCode is Classic and declares their variables otherwise reports not installed
    If((Get-ItemPropertyValue HKLM:\SOFTWARE\DELL\UpdateService\Clients\CommandUpdate\Preferences\Settings -Name AppCode -ErrorAction SilentlyContinue) -eq "Universal"){
        $Version = Get-ItemPropertyValue HKLM:\SOFTWARE\DELL\UpdateService\Clients\CommandUpdate\Preferences\Settings -Name ProductVersion -ErrorAction SilentlyContinue
        $AppType = Get-ItemPropertyValue HKLM:\SOFTWARE\DELL\UpdateService\Clients\CommandUpdate\Preferences\Settings -Name AppCode -ErrorAction SilentlyContinue
        #Add DCU-CLI.exe as Environment Variable for Universal app type
        $DCUPath = 'C:\Program Files\Dell\CommandUpdate\'
    }
    ElseIf((Get-ItemPropertyValue HKLM:\SOFTWARE\DELL\UpdateService\Clients\CommandUpdate\Preferences\Settings -Name AppCode -ErrorAction SilentlyContinue) -eq "Classic"){
        
        $Version = Get-ItemPropertyValue HKLM:\SOFTWARE\DELL\UpdateService\Clients\CommandUpdate\Preferences\Settings -Name ProductVersion
        $AppType = Get-ItemPropertyValue HKLM:\SOFTWARE\DELL\UpdateService\Clients\CommandUpdate\Preferences\Settings -Name AppCode
        #Add DCU-CLI.exe as Environment Variable for Classic app type
        $DCUPath = 'C:\Program Files (x86)\Dell\CommandUpdate\'
    }
    Else{
        $DCU =  "DCU is not installed"
    }
    if ($Version){
        $DCU = [PSCustomObject]@{
            Version = $Version
            AppType = $AppType
            DCUPath = $DCUPath
        }
    }
    return $DCU
}
#https://www.dell.com/support/manuals/en-us/command-update/dellcommandupdate_rg/command-line-interface-error-codes?guid=guid-fbb96b06-4603-423a-baec-cbf5963d8948&lang=en-us
Function Get-DCUExitInfo {
    [CmdletBinding()]
    param(
    [ValidateRange(0,4000)]
    [int]$DCUExit
    )
    $DCUExitInfo = @(
    @{ExitCode = 2; Description = "None"; Resolution = "None"}
    # Generic application return codes
    @{ExitCode = 0; Description = "Success"; Resolution = "The operation completed successfully."}
    @{ExitCode = 1; Description = "A reboot was required from the execution of an operation."; Resolution = "Reboot the system to complete the operation."}
    @{ExitCode = 2; Description = "An unknown application error has occurred."; Resolution = "None"}
    @{ExitCode = 3; Description = "The current system manufacturer is not Dell."; Resolution = "Dell Command | Update can only be run on Dell systems."}
    @{ExitCode = 4; Description = "The CLI was not launched with administrative privilege"; Resolution = "Invoke the Dell Command | Update CLI with administrative privileges"}
    @{ExitCode = 5; Description = "A reboot was pending from a previous operation."; Resolution = "Reboot the system to complete the operation."}
    @{ExitCode = 6; Description = "Another instance of the same application (UI or CLI) is already running."; Resolution = "Close any running instance of Dell Command | Update UI or CLI and retry the operation."}
    @{ExitCode = 7; Description = "The application does not support the current system model."; Resolution = "Contact your administrator if the current system model in not supported by the catalog."}
    @{ExitCode = 8; Description = "No update filters have been applied or configured."; Resolution = "Supply at least one update filter."}
    # Return codes while evaluating various input validations
    @{ExitCode = 100; Description = "While evaluating the command line parameters, no parameters were detected."; Resolution = "A command must be specified on the command line."}
    @{ExitCode = 101; Description = "While evaluating the command line parameters, no commands were detected."; Resolution = "Provide a valid command and options."}
    @{ExitCode = 102; Description = "While evaluating the command line parameters, invalid commands were detected."; Resolution = "Provide a command along with the supported options for that command"}
    @{ExitCode = 103; Description = "While evaluating the command line parameters, duplicate commands were detected."; Resolution = "Remove any duplicate commands and rerun the command."}
    @{ExitCode = 104; Description = "While evaluating the command line parameters, the command syntax was incorrect."; Resolution = "Ensure that you follow the command syntax: /<command name>. "}
    @{ExitCode = 105; Description = "While evaluating the command line parameters, the option syntax was incorrect."; Resolution = "Ensure that you follow the option syntax: -<option name>."}
    @{ExitCode = 106; Description = "While evaluating the command line parameters, invalid options were detected."; Resolution = "Ensure to provide all required or only supported options."}
    @{ExitCode = 107; Description = "While evaluating the command line parameters, one or more values provided to the specific option was invalid."; Resolution = "Provide an acceptable value."}
    @{ExitCode = 108; Description = "While evaluating the command line parameters, all mandatory options were not detected."; Resolution = "If a command requires mandatory options to run, provide them."}
    @{ExitCode = 109; Description = "While evaluating the command line parameters, invalid combination of options were detected."; Resolution = "Remove any mutually exclusive options and rerun the command."}
    @{ExitCode = 110; Description = "While evaluating the command line parameters, multiple commands were detected."; Resolution = "Except for /help and /version, only one command can be specified in the command line."}
    @{ExitCode = 111; Description = "While evaluating the command line parameters, duplicate options were detected."; Resolution = "Remove any duplicate options and rerun the command"}
    @{ExitCode = 112; Description = "An invalid catalog was detected."; Resolution = "Ensure that the file path provided exists, has a valid extension type, is a valid SMB, UNC, or URL, does not have invalid characters, does not exceed 255 characters and has required permissions. "}
    @{ExitCode = 113; Description = "While evaluating the command line parameters, one or more values provided exceeds the length limit."; Resolution = "Ensure to provide the values of the options within the length limit."}
    # Return codes while running the /scan command
    @{ExitCode = 500; Description = "No updates were found for the system when a scan operation was performed."; Resolution = "The system is up to date or no updates were found for the provided filters. Modify the filters and rerun the commands."}
    @{ExitCode = 501; Description = "An error occurred while determining the available updates for the system, when a scan operation was performed."; Resolution = "Retry the operation."}
    @{ExitCode = 502; Description = "The cancellation was initiated, Hence, the scan operation is canceled."; Resolution = "Retry the operation."}
    @{ExitCode = 503; Description = "An error occurred while downloading a file during the scan operation."; Resolution = "Check your network connection, ensure there is Internet connectivity and Retry the command."}
    # Return codes while running the /applyUpdates command
    @{ExitCode = 1000; Description = "An error occurred when retrieving the result of the apply updates operation."; Resolution = "Retry the operation."}
    @{ExitCode = 1001; Description = "The cancellation was initiated, Hence, the apply updates operation is canceled."; Resolution = "Retry the operation."}
    @{ExitCode = 1002; Description = "An error occurred while downloading a file during the apply updates operation."; Resolution = "Check your network connection, ensure there is Internet connectivity, and retry the command."}
    # Return codes while running the /configure command
    @{ExitCode = 1505; Description = "An error occurred while exporting the application settings."; Resolution = "Verify that the folder exists or have permissions to write to the folder."}
    @{ExitCode = 1506; Description = "An error occurred while importing the application settings."; Resolution = "Verify that the imported file is valid."}
    # Return codes while running the /driverInstall command
    @{ExitCode = 2000; Description = "An error occurred when retrieving the result of the Advanced Driver Restore operation."; Resolution = "Retry the operation."}
    @{ExitCode = 2001; Description = "The Advanced Driver Restore process failed."; Resolution = "Retry the operation."}
    @{ExitCode = 2002; Description = "Multiple driver CABs were provided for the Advanced Driver Restore operation."; Resolution = "Ensure that you provide only one driver CAB file."}
    @{ExitCode = 2003; Description = "An invalid path for the driver CAB was provided as in input for the driver install command."; Resolution = "Ensure that the file path provided exists, has a valid extension type, is a valid SMB, UNC, or URL, does not have invalid characters, does not exceed 255 characters and has required permissions"}
    @{ExitCode = 2004; Description = "The cancellation was initiated, Hence, the driver install operation is canceled."; Resolution = "Retry the operation."}
    @{ExitCode = 2005; Description = "An error occurred while downloading a file during the driver install operation."; Resolution = "Check your network connection, ensure there is Internet connectivity, and retry the command."}
    @{ExitCode = 2006; Description = "Indicates that the Advanced Driver Restore feature is disabled."; Resolution = "Enable the feature using /configure -advancedDriverRestore=enable"}
    @{ExitCode = 2007; Description = "Indicates that the Advanced Diver Restore feature is not supported."; Resolution = "Disable FIPS mode on the system."}
    # Return codes while evaluating the inputs for password encryption
    @{ExitCode = 2500; Description = "An error occurred while encrypting the password during the generate encrypted password operation."; Resolution = "Retry the operation."}
    @{ExitCode = 2501; Description = "An error occurred while encrypting the password with the encryption key provided."; Resolution = "Provide a valid encryption key and Retry the operation. "}
    @{ExitCode = 2502; Description = "The encrypted password provided does not match the current encryption method."; Resolution = "The provided encrypted password used an older encryption method. Reencrypt the password."}
    # Return codes if there are issues with the Dell Client Management Service
    @{ExitCode = 3000; Description = "The Dell Client Management Service is not running."; Resolution = "Start the Dell Client Management Service in the Windows services if stopped."}
    @{ExitCode = 3001; Description = "The Dell Client Management Service is not installed."; Resolution = "Download and install the Dell Client Management Service from the Dell support site."}
    @{ExitCode = 3002; Description = "The Dell Client Management Service is disabled."; Resolution = "Enable the Dell Client Management Service from Windows services if disabled."}
    @{ExitCode = 3003; Description = "The Dell Client Management Service is busy."; Resolution = "Wait until the service is available to process new requests."}
    @{ExitCode = 3004; Description = "The Dell Client Management Service has initiated a self-update install of the application."; Resolution = "Wait until the service is available to process new requests."}
    @{ExitCode = 3005; Description = "The Dell Client Management Service is installing pending updates."; Resolution = "Wait until the service is available to process new requests."}
    )
    $DCUExitInfo | Where-Object {$_.ExitCode -eq $DCUExit}
}
#https://www.dell.com/support/kbdoc/en-us/000148745/dup-bios-updates
Function Get-DUPExitInfo {
    [CmdletBinding()]
    param(
    [ValidateRange(0,4000)]
    [int]$DUPExit
    )
    $DUPExitInfo = @(
    # Generic application return codes
    @{ExitCode = -1; DisplayName = "Unsuccessful"; Description = "DCU terminating the BIOS execution due to timeout."}
    @{ExitCode = 0; DisplayName = "Success"; Description = "The operation completed successfully."}
    @{ExitCode = 1; DisplayName = "Unsuccessful"; Description = "An error occurred during the update process; the update was not successful."}
    @{ExitCode = 2; DisplayName = "Reboot required"; Description = "Reboot the system to complete the operation."}
    @{ExitCode = 3; DisplayName = "Soft dependency error"; Description = "You attempted to update to the same version of the software or You tried to downgrade to a previous version of the software."}
    @{ExitCode = 4; DisplayName = "Hard dependency error"; Description = "The required prerequisite software was not found on your computer."}
    @{ExitCode = 5; DisplayName = "Qualification error"; Description = "A QUAL_HARD_ERROR cannot be suppressed by using the /f switch."}
    @{ExitCode = 6; DisplayName = "Rebooting computer"; Description = "The computer is being rebooted."}
    @{ExitCode = 7; DisplayName = "Password validation error"; Description = "Password not provided or incorrect password provided for BIOS execution"}
    @{ExitCode = 8; DisplayName = "Requested Downgrade is not allowed."; Description = "Downgrading the BIOS to the version run is not allowed."}
    @{ExitCode = 8; DisplayName = "RPM verification has failed"; Description = "The Linux DUP framework uses RPM verification to ensure the security of all DUP-dependent Linux utilities. If security is compromised, the framework displays a message and an RPM Verify Legend, and then exits with exit code 9."}
    @{ExitCode = 8; DisplayName = "Some other error"; Description = "This exit code is for all errors that have not been specified in BIOS exit codes 0-9. That is, battery error, EC error, HW failure, so forth."}
    )
    $DUPExitInfo | Where-Object {$_.ExitCode -eq $DUPExit}
}
Function Get-DCUAppUpdates {
    [CmdletBinding()]
    param (
    [Parameter(Mandatory=$False)]
    [ValidateLength(4,4)]    
    [string]$SystemSKUNumber,
    [switch]$Latest,
    [switch]$Install,
    [switch]$UseWebRequest
    )
    
    $Manufacturer = (Get-CimInstance -ClassName Win32_ComputerSystem).Manufacturer
    if (!($SystemSKUNumber)) {
        if ($Manufacturer -notmatch "Dell"){return "This Function is only for Dell Systems"}
        $SystemSKUNumber = (Get-CimInstance -ClassName Win32_ComputerSystem).SystemSKUNumber
    }
    $temproot = "$env:windir\temp"
    $DellCabExtractPath = "$temproot\DellCabDownloads\DellCabExtract"
    
    $Apps = Get-DCUUpdateList -SystemSKUNumber $SystemSKUNumber -updateType application | Select-Object -Property PackageID, Name, ReleaseDate, DellVersion, VendorVersion, Path
    $CommandUpdateApps = $Apps | Where-Object {$_.Name -like "*Command | Update*"} | Sort-Object -Property VendorVersion
    $CommandUpdateAppsLatest = $CommandUpdateApps | Select-Object -Last 1
    if ($CommandUpdateAppsLatest){
        if ($Install){
            [Version]$DCUVersion = $CommandUpdateAppsLatest.vendorVersion
            Write-Output "Found DCU Version $DCUVersion"
            $DCUVersionInstalled = Get-DCUVersion
            If ($DCUVersionInstalled -ne $false){[Version]$CurrentVersion = $DCUVersionInstalled}
            Else {[Version]$CurrentVersion = 0.0.0.0}
            if ($DCUVersion -gt $CurrentVersion){
                $temproot = "$env:windir\temp"
                $DellCabDownloadsPath = "$temproot\DellCabDownloads"
                if (!(Test-Path $DellCabExtractPath)){$null = New-Item -Path $DellCabExtractPath -ItemType Directory -Force}
                $LogFilePath = "$env:ProgramData\EMPS\Logs"
                $TargetFileName = ($CommandUpdateAppsLatest.path).Split("/") | Select-Object -Last 1
                $TargetLink = $CommandUpdateAppsLatest.path
                $TargetFilePathName = "$($DellCabDownloadsPath)\$($TargetFileName)"
                if ($UseWebRequest){
                    Write-Output "Using WebRequest to download the file"
                    Invoke-WebRequest -Uri $TargetLink -OutFile $TargetFilePathName -UseBasicParsing -Verbose
                }
                else{
                    Write-Output "Using BITS to download the file"
                    Start-BitsTransfer -Source $TargetLink -Destination $TargetFilePathName -DisplayName $TargetFileName -Description "Downloading Dell Command Update" -ErrorAction SilentlyContinue
                }
                
                if (!(Test-Path $TargetFilePathName)){
                    Invoke-WebRequest -Uri $TargetLink -OutFile $TargetFilePathName -UseBasicParsing -Verbose
                }
                #Confirm Download
                if (Test-Path $TargetFilePathName){
                    $LogFileName = ($TargetFilePathName.replace(".exe",".log")).Replace(".EXE",".log")
                    $Arguments = "/s /l=$LogFileName"
                    Write-Output "Starting DCU Install"
                    Write-Progress -Activity "Installing Dell Command Update" -Status "Installing $TargetFileName" -PercentComplete 10
                    write-output "Log file = $LogFileName"
                    [int]$PercentComplete = 10
                    $Process = Start-Process "$TargetFilePathName" $Arguments -PassThru
                    do {
                        
                        Start-Sleep -Seconds 5
                        $PercentComplete += 2
                        Write-Progress -Activity "Installing Dell Command Update" -Status "Installing $TargetFileName" -PercentComplete $PercentComplete
                    }
                    until ($Process.HasExited)
                    
                    write-output "Update Complete with Exitcode: $($Process.ExitCode)"
                    Write-Progress -Activity "Installing Dell Command Update" -Status "Installing $TargetFileName" -PercentComplete 100
                    If($Process -ne $null -and $Process.ExitCode -eq '2'){
                        Write-Verbose "Reboot Required"
                    }
                }
                else{
                    Write-Verbose " FAILED TO DOWNLOAD DCU"
                }
            }
            else{
                Write-Output "Installed DCU: $CurrentVersion, Skipping Install"
                
            }
        }
        else{
            if ($Latest){
                Return $CommandUpdateAppsLatest
            }
            else{
                return $CommandUpdateApps
            }
        }
    }
    else{
        return "No DCU Found"
    }
    
}
function Invoke-DCU {
    [CmdletBinding()]
    
    param (
    
    #[ValidateSet('bios','firmware','driver','application','others')]
    #[String[]]$updateType,
    [ValidateSet('audio','video','network','chipset','storage','input','others')]
    [String[]]$updateDeviceCategory,
    [ValidateSet('security','critical','recommended','optional','all')]
    [String[]]$updateSeverity,
    [ValidateSet('Enable','Disable')]
    [string]$autoSuspendBitLocker = 'Enable',
    [ValidateSet('Enable','Disable')]
    [string]$reboot = 'Disable',
    [ValidateSet('Enable','Disable')]
    [string]$forceupdate = 'Disable',
    [string]$LogPath,
    [switch]$updateTypeBIOSFirmware,
    [switch]$updateTypeDrivers,
    [Switch]$updateTypeApplications,
    [switch]$ScanOnly
    
    )
    $DCUPath = (Get-DCUInstallDetails).DCUPath
    #$LogPath = "$env:SystemDrive\Users\Dell\EMPS\Logs"
    if (!($LogPath)){
        $LogPath = "$env:SystemDrive\_2P\Logs"
    }
    #Build Argument Strings for each parameter
    if ($updateSeverity){
        if ($updateSeverity -ne "all"){
            [String]$updateSeverity = $($updateSeverity -join ",").ToString()
            $updateSeverityVar = "-updateSeverity=$updateSeverity"
        }
    }
    if (get-variable | Where-Object {$_.Name -match "updateType" -and $_.Value -eq $true}){
        $updateTypeVar = "-updateType=`""
        if ($updateTypeBIOSFirmware){
            $updateTypeVar += "bios,"
            $updateTypeVar += "firmware,"
        }
        if ($updateTypeDrivers){
            $updateTypeVar += "driver,"
        }
        if ($updateTypeApplications){
            $updateTypeVar += "application,"
        }
        if ($updateType -and $updateType -ne 'others'){
            $updateTypeVar += ($updateType -join ",") + ","
        }
        $updateTypeVar = $updateTypeVar.TrimEnd(",")
        $updateTypeVar += "`""
    }
    else {
        $updateTypeVar = ""
    }
    
    if ($updateDeviceCategory){
        [String]$updateDeviceCategory = $($updateDeviceCategory -join ",").ToString()
        $updateDeviceCategoryVar = "-updateDeviceCategory=$updateDeviceCategory"
    }
    
    #Pick Action, Scan or ApplyUpdates if both are selected, ApplyUpdates will be the action, if neither are selected, Scan will be the action
    if ($scanOnly){
        $ActionVar = "/scan -report=$LogPath"
    }
    else{
        $ActionVar = "/applyUpdates"
    }
    
    $DateStamp = (Get-Date -Format "yyyyMMddHHmmss")
    $LogFile = "$LogPath\DCU-CLI-$DateStamp.log"
    Write-Host "Log File: $LogFile"
    #Create Arugment List for Dell Command Update CLI
    $ArgList = "$ActionVar $updateSeverityVar $updateTypeVar $updateDeviceCategoryVar -outputlog=`"$LogFile`" -forceUpdate=enable -reboot=disable"
    Write-Host $ArgList
    #$DCUApply = Start-Process -FilePath "$DCUPath\dcu-cli.exe" -ArgumentList $ArgList -NoNewWindow -PassThru -Wait
    
    #Testing Write-Progress
    Write-Progress -Activity "Running Dell Command Update" -Status "Applying Updates" -CurrentOperation "Running DCU CLI" -PercentComplete 0
    $DCUApply = Start-Process -FilePath "$DCUPath\dcu-cli.exe" -ArgumentList $ArgList -NoNewWindow -PassThru
    $SameLastLine = $null
    if (Get-Process -Name dcu-cli -ErrorAction SilentlyContinue){
        Write-Output "Found Process for DCU-CLI"
        start-sleep -Seconds 1
        if (Test-Path -Path $LogFile){
            Write-Output "Found Log: $LogFile"
        }
        else {
            Write-Output "Failed to find DCU-CLI log"
        }
    }
    else {
        Write-Output "Failed to find Process for DCU-CLI"
    }
    do {  #Continous loop while DCU-CLI is running
        Start-Sleep -Milliseconds 300
        
        #Read in the DISM Logfile
        $Content = Get-Content -Path $LogFile -ReadCount 1 -ErrorAction SilentlyContinue
        $LastLine = $Content | Select-Object -Last 1
        #$LastLine = ($LastLine.Split(':') | Select-Object -Last 1).Trim()
        if ($LastLine){
            if ($SameLastLine -ne $LastLine){ #Only continue if DISM log has changed
                $SameLastLine = $LastLine
                Write-Output $LastLine
                if ($LastLine -match "Checking" -or $LastLine -match "Scanning"  -or $LastLine -match "Determining" ){
                    #Write-Output $LastLine
                    $LastLine = ($LastLine.Split(':') | Select-Object -Last 1).Trim()
                    Write-Progress -Activity "DCU" -Status $LastLine -PercentComplete 1
                    #Show-TSActionProgress -Message $LastLine -Step 1 -MaxStep 100 -ErrorAction SilentlyContinue
                    Start-Sleep -Seconds 1
                }
                elseif ($LastLine -match "updates were selected"){
                    $LastLine = ($LastLine.Split(':') | Select-Object -Last 1).Trim()
                    Write-Progress -Activity "DCU" -Status $LastLine -PercentComplete 10
                    #Show-TSActionProgress -Message $LastLine -Step 5 -MaxStep 100 -ErrorAction SilentlyContinue
                    Start-Sleep -Seconds 3
                }
                elseif ($LastLine -match "Downloading updates"){
                    #Write-Output $LastLine
                    $Message = $Content | Where-Object {$_ -match "Downloading updates"} | Select-Object -Last 1
                    if ($Message){
                        $Message = ($Message.Split(':') | Select-Object -Last 1).trim()
                        $Message = $Message.Replace("...","")
                        $CounterPart = (($Message -split "of")[0]).Trim()
                        [int]$Counter = $CounterPart.Substring($CounterPart.Length-1)
                        if ($Counter -eq "0"){$Counter = 1} #If the counter is 0, set it to 1
                        #Write-Output $Counter
                        $Total = ((($Message -split "of")[1]).Trim()).substring(0,1)
                        [int]$Total = [int]$Total + 1 #So that when it gets to 3 of 3, it doesn't show 100% complete while it is still downloading
                        #Write-Output $Message
                        $PercentComplete = [math]::Round(($Counter / $Total) * 100)
                        Write-Progress -Activity "DCU Downloading" -Status $Message -PercentComplete $PercentComplete
                        #Show-TSActionProgress -Message $Message -Step $Counter -MaxStep $Total -ErrorAction SilentlyContinue
                    }
                }
                elseif ($LastLine -match "Installing updates"){
                    #Write-Output $LastLine
                    $Message = $Content | Where-Object {$_ -match "Installing updates"} | Select-Object -Last 1
                    if ($Message){
                        $ToKeep = $Message.Split(':') | Select-Object -last 2
                        $Message = "$($ToKeep[0]) -$($ToKeep[1])"
                        $Message = $Message.trim()
                        $CounterPart = (($Message -split "of")[0]).Trim()
                        [int]$Counter = $CounterPart.Substring($CounterPart.Length-1)
                        if ($Counter -eq "0"){$Counter = 1} #If the counter is 0, set it to 1
                        $Total = ((($Message -split "of")[1]).Trim()).substring(0,1)
                        [int]$Total = [int]$Total + 1 #So that when it gets to 3 of 3, it doesn't show 100% complete while it is still installing
                        #Write-Output $Message
                        $PercentComplete = [math]::Round(($Counter / $Total) * 100)
                        Write-Progress -Activity "DCU Installing" -Status $Message -PercentComplete $PercentComplete
                        #Show-TSActionProgress -Message $Message -Step $Counter -MaxStep $Total -ErrorAction SilentlyContinue
                    }
                }
                elseif ($LastLine -match "Execution completed." -or $LastLine -match "Finished installing the updates."  -or $LastLine -match "successfully installed"){
                    $LastLine = ($LastLine.Split(':') | Select-Object -Last 1).Trim()
                    Write-Progress -Activity "DCU Complete" -Status $Message -PercentComplete 100
                    #Show-TSActionProgress -Message $LastLine -Step 1 -MaxStep 1 -ErrorAction SilentlyContinue
                    Start-Sleep -Seconds 3
                }
                else{
                    #Show-TSActionProgress -Message $LastLine -Step 1 -MaxStep 100 -ErrorAction SilentlyContinue
                }
            }
        }
        
    }
    until (!(Get-Process -Name dcu-cli -ErrorAction SilentlyContinue))
    
    
    
    
    
    if ($DCUApply.ExitCode -ne 0){
        $ExitInfo = Get-DCUExitInfo -DCUExit $DCUApply.ExitCode
        Write-Host "Exit: $($DCUApply.ExitCode)"
        Write-Host "Description: $($ExitInfo.Description)"
        Write-Host "Resolution: $($ExitInfo.Resolution)"
    }
    return $DCUApply.ExitCode
}
function Get-DCUUpdateList {
    [CmdletBinding()]
    param (
    [Parameter(Mandatory=$False)]
    [ValidateLength(4,4)]    
    [string]$SystemSKUNumber,
    [ValidateSet('bios','firmware','driver','application')]
    [String[]]$updateType,
    [ValidateSet('audio','video','network','chipset','storage','BIOS','Application')]
    [String[]]$updateDeviceCategory,
    [switch]$RAWXML,
    [switch]$Latest,
    [switch]$TLDR
    )
    
    
    $temproot = "$env:windir\temp"
    #$SystemSKUNumber = (Get-CimInstance -ClassName Win32_ComputerSystem).SystemSKUNumber
    $Manufacturer = (Get-CimInstance -ClassName Win32_ComputerSystem).Manufacturer
    $CabPathIndexModel = "$temproot\DellCabDownloads\CatalogIndexModel.cab"
    $DellCabExtractPath = "$temproot\DellCabDownloads\DellCabExtract"
    if (!(Test-Path $DellCabExtractPath)){$null = New-Item -Path $DellCabExtractPath -ItemType Directory -Force}
    
    
    if (!($SystemSKUNumber)) {
        if ($Manufacturer -notmatch "Dell"){return "This Function is only for Dell Systems"}
        $SystemSKUNumber = (Get-CimInstance -ClassName Win32_ComputerSystem).SystemSKUNumber
    }
    $DellSKU = Get-DellSupportedModels | Where-Object {$_.systemID -match $SystemSKUNumber} | Select-Object -First 1
    if (!($DellSKU)){
        return "System SKU not found"
    }
    if (Test-Path $CabPathIndexModel){Remove-Item -Path $CabPathIndexModel -Force}
    
    
    Invoke-WebRequest -Uri "http://downloads.dell.com/$($DellSKU.URL)" -OutFile $CabPathIndexModel -UseBasicParsing
    if (Test-Path $CabPathIndexModel){
        $null = expand $CabPathIndexModel $DellCabExtractPath\CatalogIndexPCModel.xml
        [xml]$XMLIndexCAB = Get-Content "$DellCabExtractPath\CatalogIndexPCModel.xml"
        
        #DCUAppsAvailable = $XMLIndexCAB.Manifest.SoftwareComponent | Where-Object {$_.ComponentType.value -eq "APAC"}
        #$AppNames = $DCUAppsAvailable.name.display.'#cdata-section' | Select-Object -Unique
        $BaseURL = "https://$($XMLIndexCAB.Manifest.baseLocation)"
        $Components = $XMLIndexCAB.Manifest.SoftwareComponent
        if ($RAWXML){
            return $Components
        }
        $ComponentsObject = @()
        foreach ($Component in $Components){
            $Item = New-Object -TypeName PSObject
            $Item | Add-Member -MemberType NoteProperty -Name "PackageID" -Value "$($Component.packageID)"  -Force
            $Item | Add-Member -MemberType NoteProperty -Name "Category" -Value "$($Component.Category.Display.'#cdata-section')"  -Force
            $Item | Add-Member -MemberType NoteProperty -Name "Type" -Value "$($component.ComponentType.Display.'#cdata-section')"  -Force
            $Item | Add-Member -MemberType NoteProperty -Name "Name" -Value "$($Component.Name.Display.'#cdata-section')" -Force
            $Item | Add-Member -MemberType NoteProperty -Name "ReleaseDate" -Value $([DateTime]($Component.releaseDate)) -Force
            $Item | Add-Member -MemberType NoteProperty -Name "DellVersion" -Value "$($Component.dellVersion)"  -Force
            $Item | Add-Member -MemberType NoteProperty -Name "VendorVersion" -Value "$($Component.vendorVersion)"  -Force
            $Item | Add-Member -MemberType NoteProperty -Name "PackageType" -Value "$($Component.packageType)"  -Force
            $Item | Add-Member -MemberType NoteProperty -Name "Path" -Value "$BaseURL/$($Component.path)" -Force		
            $Item | Add-Member -MemberType NoteProperty -Name "Description" -Value "$($component.Description.Display.'#cdata-section')" -Force		
            $ComponentsObject += $Item 
        }
        if ($updateType){
            $ComponentsObject = $ComponentsObject | Where-Object {$_.Type -in $updateType}
        }
        if ($updateDeviceCategory){
            $ComponentsObject = $ComponentsObject | Where-Object {$_.Category -in $updateDeviceCategory}
        }
        if ($TLDR) {
            $ComponentsObject = $ComponentsObject | Select-Object -Property Name,ReleaseDate,DellVersion,Path
        }
        if ($Latest){
            $ComponentsObject = $ComponentsObject | Sort-Object -Property ReleaseDate -Descending
            $hash = @{}
            foreach ($ComponentObject in $ComponentsObject) {
                if (-not $hash.ContainsKey($ComponentObject.Name)) {
                    $hash[$ComponentObject.Name] = $ComponentObject
                }
            }
            $ComponentsObject = $hash.Values 
        }
        return $ComponentsObject
    }
}
function Get-DellDeviceDetails {
    [CmdletBinding()]
    param (
    [Parameter(Mandatory=$False)]
    [ValidateLength(4,4)]    
    [string]$SystemSKUNumber,
    [string]$ModelLike
    )
    
    $Manufacturer = (Get-CimInstance -ClassName Win32_ComputerSystem).Manufacturer
    
    
    if ((!($SystemSKUNumber)) -and (!($ModelLike))) {
        if ($Manufacturer -notmatch "Dell"){return "This Function is only for Dell Systems, or please provide a SKU"}
        $SystemSKUNumber = (Get-CimInstance -ClassName Win32_ComputerSystem).SystemSKUNumber
    }
    <#
    if (!($ModelLike)){
    $DellSKU = Get-DellSupportedModels | Where-Object {$_.systemID -match $SystemSKUNumber} | Select-Object -First 1
    }
    else {
    $DellSKU = Get-DellSupportedModels | Where-Object { $_.Model -match $ModelLike}
    }
    
    return $DellSKU | Select-Object -Property SystemID,Model
    #>
    $MoreData = Get-DellDriverPackXML
    if (!($ModelLike)){
        $DrillDown = $MoreData.DriverPackManifest.DriverPackage.SupportedSystems.brand.model | Where-Object {$_.systemid -eq $SystemSKUNumber} | Select-Object -First 1
        $RDSDate = [DATETIME]"$($DrillDown.rtsDate)"
        $DeviceOutput = New-Object -TypeName PSObject
        $DeviceOutput | Add-Member -MemberType NoteProperty -Name "SystemID" -Value "$($DrillDown.systemID)" -Force
        $DeviceOutput | Add-Member -MemberType NoteProperty -Name "Model" -Value "$($DrillDown.name)"  -Force
        $DeviceOutput | Add-Member -MemberType NoteProperty -Name "RTSDate" -Value $([DATETIME]$RDSDate) -Force
        return $DeviceOutput		
    }
    else{
        $DrillDown = $MoreData.DriverPackManifest.DriverPackage.SupportedSystems.brand.model | Where-Object {$_.name -match $ModelLike}
        if ($DrillDown.count -gt 1){
            $SystemIDs = $DrillDown.systemID | Select-Object -Unique
            $DeviceOutputObject = @()
            foreach ($SystemID in $SystemIDs){
                $DrillDown = $MoreData.DriverPackManifest.DriverPackage.SupportedSystems.brand.model | Where-Object {$_.systemid -eq $SystemID}| Select-Object -First 1
                $RDSDate = [DATETIME]"$($DrillDown.rtsDate)"
                $DeviceOutput = New-Object -TypeName PSObject
                $DeviceOutput | Add-Member -MemberType NoteProperty -Name "SystemID" -Value "$($DrillDown.systemID)" -Force
                $DeviceOutput | Add-Member -MemberType NoteProperty -Name "Model" -Value "$($DrillDown.name)"  -Force
                $DeviceOutput | Add-Member -MemberType NoteProperty -Name "RTSDate" -Value $([DATETIME]$RDSDate) -Force
                $DeviceOutputObject += $DeviceOutput 
            }
            return $DeviceOutputObject | Sort-Object -Property RTSDate
        }
    }
}

# Function to check for Windows Desktop Runtime
function Test-WindowsDesktopRuntime {
    param(
        [string]$RequiredBaseVersion
    )

    $requiredBaseVersion = $RequiredBaseVersion
    [version]$requiredVersion = $null
    $requiredVersionParsed = [version]::TryParse($requiredBaseVersion, [ref]$requiredVersion)

    if (-not $requiredVersionParsed) {
        Write-Host "Required Windows Desktop Runtime base version '$requiredBaseVersion' is not a valid version format." -ForegroundColor Red
        return $false
    }

    $requiredMajor = $requiredVersion.Major
    $requiredMinor = $requiredVersion.Minor

    function Convert-ToNormalizedRuntimeVersion {
        param(
            [string]$VersionText
        )

        if ([string]::IsNullOrWhiteSpace($VersionText)) {
            return $null
        }

        # WMI/uninstall entries sometimes encode major/minor as 80.x => 8.0.x, 100.x => 10.0.x
        $m = [regex]::Match($VersionText, '^(\d{2,3})\.(\d+)\.(\d+)$')
        if ($m.Success) {
            $enc = [int]$m.Groups[1].Value
            if ($enc -ge 20) {
                $major = [math]::Floor($enc / 10)
                $minor = $enc % 10
                $normalized = "$major.$minor.$($m.Groups[2].Value).$($m.Groups[3].Value)"
                [version]$vNorm = $null
                if ([version]::TryParse($normalized, [ref]$vNorm)) {
                    return $vNorm
                }
            }
        }

        [version]$candidateVersion = $null
        if ([version]::TryParse($VersionText, [ref]$candidateVersion)) {
            return $candidateVersion
        }
        return $null
    }

    function Add-VersionCandidate {
        param(
            [string]$VersionText,
            [string]$Source,
            [bool]$IncludeInMatch = $true
        )

        if ([string]::IsNullOrWhiteSpace($VersionText)) {
            return
        }

        $null = $installedVersionObjects.Add([PSCustomObject]@{
            VersionText = $VersionText
            Source = $Source
        })

        $v = Convert-ToNormalizedRuntimeVersion -VersionText $VersionText
        if ($IncludeInMatch -and $null -ne $v -and $v.Major -eq $requiredMajor -and $v.Minor -eq $requiredMinor) {
            $null = $matchingVersionObjects.Add([PSCustomObject]@{
                VersionText = $VersionText
                Source = $Source
            })
        }
    }

    $installedVersionObjects = New-Object System.Collections.ArrayList
    $matchingVersionObjects = New-Object System.Collections.ArrayList

    # Primary: dotnet CLI runtime list (most reliable across modern .NET installs)
    try {
        $dotnetLines = & dotnet --list-runtimes 2>$null
        foreach ($line in $dotnetLines) {
            if ($line -match '^Microsoft\.WindowsDesktop\.App\s+([0-9]+\.[0-9]+(?:\.[0-9]+(?:\.[0-9]+)?)?)\s+') {
                Add-VersionCandidate -VersionText $matches[1] -Source 'dotnet-cli'
            }
        }
    } catch {}

    # Fallback: shared runtime folder versions
    $desktopSharedPath = Join-Path -Path $env:ProgramFiles -ChildPath 'dotnet\shared\Microsoft.WindowsDesktop.App'
    if (Test-Path $desktopSharedPath) {
        Get-ChildItem -Path $desktopSharedPath -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            Add-VersionCandidate -VersionText $_.Name -Source 'shared-folder'
        }
    }

    # Fallback: registry paths where .NET Runtime info may be stored
    $registryPaths = @(
        'HKLM:\SOFTWARE\dotnet\Setup\InstalledVersions\x64\sharedfx\Microsoft.WindowsDesktop.App',
        'HKLM:\SOFTWARE\dotnet\Setup\InstalledVersions\x86\sharedfx\Microsoft.WindowsDesktop.App'
    )
    foreach ($path in $registryPaths) {
        if (Test-Path $path) {
            Get-ChildItem -Path $path -ErrorAction SilentlyContinue | ForEach-Object {
                Add-VersionCandidate -VersionText $_.PSChildName -Source 'registry'
            }
        }
    }

    # Last resort: installed products list (avoid Win32_Product side effects)
    $uninstallPaths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    foreach ($upath in $uninstallPaths) {
        Get-ItemProperty -Path $upath -ErrorAction SilentlyContinue |
            ForEach-Object {
                $displayNameProp = $_.PSObject.Properties['DisplayName']
                $displayVersionProp = $_.PSObject.Properties['DisplayVersion']

                $displayName = if ($null -ne $displayNameProp) { [string]$displayNameProp.Value } else { $null }
                $displayVersion = if ($null -ne $displayVersionProp) { [string]$displayVersionProp.Value } else { $null }

                if (-not [string]::IsNullOrWhiteSpace($displayName) -and
                    $displayName -like 'Microsoft Windows Desktop Runtime*' -and
                    -not [string]::IsNullOrWhiteSpace($displayVersion)) {
                    # Keep uninstall entries for diagnostics only; they can use non-runtime encoding.
                    Add-VersionCandidate -VersionText $displayVersion -Source 'uninstall-registry' -IncludeInMatch $false
                }
            }
    }

    $runtimesFound = ($installedVersionObjects.Count -gt 0)
    
    # Output results
    if ($runtimesFound) {
        Write-Host "Microsoft Windows Desktop Runtime is installed." -ForegroundColor Green
        Write-Host "Required base version: $requiredBaseVersion"
        Write-Host "Found versions:"
        $installedVersionObjects |
            Sort-Object -Property VersionText, Source -Unique |
            ForEach-Object {
                Write-Host "- Version $($_.VersionText) [$($_.Source)]"
        }

        if ($matchingVersionObjects.Count -gt 0) {
            Write-Host "Required base version $requiredBaseVersion found." -ForegroundColor Green
        }
        else {
            Write-Host "Required base version $requiredBaseVersion was not found in installed runtimes." -ForegroundColor Red
        }
    }
    else {
        Write-Host "Microsoft Windows Desktop Runtime is not installed." -ForegroundColor Red
        Write-Host "Required base version: $requiredBaseVersion" -ForegroundColor Yellow
        Write-Host "Please install Microsoft Windows Desktop Runtime $requiredBaseVersion.x and rerun this step." -ForegroundColor Yellow
    }
    
    return ($matchingVersionObjects.Count -gt 0)
}
#endregion functions


# Main Script Logic

<#
# If there is an Intel Management Controller Installer, do that manually, as it will crash the system if run via DCU
#$IntelMCInstaller = Get-DCUUpdateList -SystemSKUNumber '0B04' -Latest | Where-Object {$_.name -match "Intel Management Engine Components"}
$IntelMCInstaller = Get-DCUUpdateList -Latest | Where-Object {$_.name -match "Intel Management Engine Components"}

if ($IntelMCInstaller) {
    Write-Host "Found Intel Management Engine Components installer, running it manually."
    $DownloadContentPath = "$env:SystemDrive\Drivers\Dls"
    if (!(Test-Path -Path $DownloadContentPath)) {
        New-Item -ItemType Directory -Path $DownloadContentPath -Force | Out-Null
    }
    
    #Download the installer
    $Name = $IntelMCInstaller.Name
    $ID = $IntelMCInstaller.PackageID
    $URL = $IntelMCInstaller.Path
    try {
        #Request-DeployRCustomContent -ContentName $($Driver.Id) -ContentFriendlyName $($Driver.Name) -URL "$($Driver.PackageExe)" -DestinationPath $DownloadContentPath -ErrorAction SilentlyContinue
        $destFile = Request-DeployRCustomContent -ContentName $ID -ContentFriendlyName $NAME -URL $URL -DestinationPath $DownloadContentPath -ErrorAction SilentlyContinue
        $GetItemOutFile = Get-Item $destFile
        $ExpandFile = $GetItemOutFile.FullName
        if (Test-Path -path $ExpandFile) {
            Write-Host "Downloaded driver to: $ExpandFile" -ForegroundColor Green
        }
    } catch {
        Write-Host "Failed to download driver: $Name" -ForegroundColor red
        Write-Host "Going to try again with Invoke-WebRequest" -ForegroundColor Yellow
        $ExpandFile = Join-Path -Path $DownloadContentPath -ChildPath "$ID.exe"
        Invoke-WebRequest -Uri $URL -OutFile $ExpandFile -UseBasicParsing
    }
    Write-Host "Installing Intel Management Engine Components: $Name"
    #Install the Intel Management Engine Components Silently
    $InstallProcess = Start-Process -FilePath $ExpandFile -ArgumentList "/s /l=$env:systemdrive\_2p\logs\$ID.log" -Wait -PassThru
    if ($InstallProcess.ExitCode -eq 0) {
        Write-Host "Installed Intel Management Engine Components successfully." -ForegroundColor Green
    } else {
        Write-Host "Failed to install Intel Management Engine Components. Exit Code: $($InstallProcess.ExitCode)" -ForegroundColor Red
    }
}
#>
if ((Get-DCUVersion) -match "False"){
    # Do the Stuff
    write-host "Checking for Dell Command Update Latest Version"
    $DCU = Get-DCUAppUpdates -Latest
    
    #Write-Host "=============================================================================="
    Write-Host "Check for Desktop Runtime Dependencies"
    $RunTimeInstalled = Test-WindowsDesktopRuntime -RequiredBaseVersion $WindowsDesktopRuntimeVerRequired
    
    if (!$RunTimeInstalled) {
        Write-Host "Microsoft Windows Desktop Runtime is not installed, please install it before running Dell Command Update" -ForegroundColor Red
        exit 1
    }
    
    Write-Host "Installing Dell Command Update"
    $DCU
    try {
        Get-DCUAppUpdates -Install
        Write-Host "Dell Command Update Installed Successfully"
        $DCUVersion = Get-DCUVersion
        Write-Host "Dell Command Update Version: $DCUVersion"
    }
    catch {
        Write-Host "One More Try to Install Dell Command Update"
        Get-DCUAppUpdates -Install -UseWebRequest
    }
}
else {
    Write-Host "Dell Command Update is already installed, version: $(Get-DCUVersion)"
}


if ((Get-DCUVersion) -match "False"){
    Write-Host "Dell Command Update is not getting installed, do some extra testing.."
    exit ($DCU.VendorVersion).replace(".","")
}
else {
    
    Write-Host "=============================================================================="
    Write-Host "Invoke Dell Command Update"
    write-host "Invoke-DCU -updateTypeBIOSFirmware:$updateTypeBIOSFirmware -updateTypeDrivers:$updateTypeDrivers -updateTypeApplications:$updateTypeApplications -ScanOnly:$ScanOnly -updateSeverity $updateSeverityRating -LogPath $LogPath"
    $RunDCU = Invoke-DCU -updateTypeBIOSFirmware:$updateTypeBIOSFirmware -updateTypeDrivers:$updateTypeDrivers -updateTypeApplications:$updateTypeApplications -ScanOnly:$ScanOnly -updateSeverity $updateSeverityRating -LogPath $LogPath
    Write-Host "Run Dell Command Update Step Complete"
    if ($RunDCU -eq 1){
        Write-Host "Dell Command Update completed with exit code 1, indicating a reboot is required." -ForegroundColor Yellow
        # If running in a task sequence, set the SMSTSRebootRequested variable
        if ($inTS) {
            Write-Host "Setting SMSTSRebootRequested to true for task sequence." -ForegroundColor Yellow
            ${TSEnv:SMSTSRebootRequested} = $true
        }
        else {
            Write-Host "Please reboot the system to apply changes." -ForegroundColor Yellow
        }
        
    }
    Write-Host "=============================================================================="
}

