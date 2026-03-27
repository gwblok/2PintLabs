

#https://dl.dell.com/content/manual17524146-dell-command-update-version-5-x-reference-guide.pdf?language=en-us


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
    [string]$installationDeferral = ${TSEnv:installationDeferral} #Enable or Disable
    [int]$deferralInstallInterval = ${TSEnv:deferralInstallInterval} #1-9
    [int]$deferralInstallCount = ${TSEnv:deferralInstallCount}  #1-9
    [string]$systemRestartDeferral = ${TSEnv:systemRestartDeferral} #Enable or Disable
    [int]$deferralRestartInterval = ${TSEnv:deferralRestartInterval} #1-99
    [int]$deferralRestartCount = ${TSEnv:deferralRestartCount} #1-9
    [int]$delayDays = ${TSEnv:delayDays} #0-45
    [string]$scheduleAction = ${TSEnv:scheduleAction}
    [string]$schedule = ${TSEnv:schedule}
    [string]$scheduleDaily = ${TSEnv:scheduleDaily}
    [string]$scheduleWeekly = ${TSEnv:scheduleWeekly}
    [string]$scheduleMonthly = ${TSEnv:scheduleMonthly}
    
    #Device Categories
    [string]$updateDeviceCategoryFilter = ${TSEnv:updateDeviceCategoryFilter} #Enable or Disable
    [string]$updateDeviceCategoryAudio = ${TSEnv:updateDeviceCategoryAudio}
    [string]$updateDeviceCategoryVideo = ${TSEnv:updateDeviceCategoryVideo}
    [string]$updateDeviceCategoryNetwork = ${TSEnv:updateDeviceCategoryNetwork}
    [string]$updateDeviceCategoryStorage = ${TSEnv:updateDeviceCategoryStorage}
    [string]$updateDeviceCategoryInput = ${TSEnv:updateDeviceCategoryInput}
    [string]$updateDeviceCategoryChipset = ${TSEnv:updateDeviceCategoryChipset}
    [string]$updateDeviceCategoryOthers = ${TSEnv:updateDeviceCategoryOthers}
    
    #Update Severities
    [string]$updateSeverityFilter = ${TSEnv:updateSeverityFilter} #Enable or Disable
    [String]$updateSeveritySecurity = ${TSEnv:updateSeveritySecurity}
    [String]$updateSeverityCritical = ${TSEnv:updateSeverityCritical}
    [String]$updateSeverityRecommended = ${TSEnv:updateSeverityRecommended}
    [String]$updateSeverityOptional = ${TSEnv:updateSeverityOptional}
    
    #Update Types
    [string]$updateTypeFilter = ${TSEnv:updateTypeFilter} #Enable or Disable
    [String]$updateTypeBIOS = ${TSEnv:updateTypeBIOS}
    [String]$updateTypeFirmware = ${TSEnv:updateTypeFirmware}
    [String]$updateTypeDriver = ${TSEnv:updateTypeDriver}
    [String]$updateTypeApplication = ${TSEnv:updateTypeApplication}
    [String]$updateTypeOthers = ${TSEnv:updateTypeOthers}
    [String]$updateTypeUtility = ${TSEnv:updateTypeUtility}

}
else {
    #Testing outside of DeployR
    [string]$installationDeferral = "Enable"
    [int]$deferralInstallInterval = 3
    [int]$deferralInstallCount = $5
    [string]$systemRestartDeferral = "Enable"
    [int]$deferralRestartInterval = 4
    [int]$deferralRestartCount = 6
    [int]$delayDays = 14
    [string]$scheduleAction = 'DownloadInstallAndNotify'
    [string]$schedule = 'scheduleDaily'
    [string]$scheduleDaily = '12:30'
    [string]$scheduleWeekly = 'Wed'
    [string]$scheduleMonthly = 'third'
    
    #Device Categories
    [string]$updateDeviceCategoryFilter = "Disable"
    [string]$updateDeviceCategoryAudio = "True"
    [string]$updateDeviceCategoryVideo = "True"
    [string]$updateDeviceCategoryNetwork = "True"
    [string]$updateDeviceCategoryStorage = "False"
    [string]$updateDeviceCategoryInput = "False"
    [string]$updateDeviceCategoryChipset = "True"
    [string]$updateDeviceCategoryOthers = "False"
    #Update Severities
    [string]$updateSeverityFilter = "Disable"
    [String]$updateSeveritySecurity = "True"
    [String]$updateSeverityCritical = "True"
    [String]$updateSeverityRecommended = "False"
    [String]$updateSeverityOptional = "False"
    #Update Types
    [string]$updateTypeFilter = "Disable"
    [String]$updateTypeBIOS = "True"
    [String]$updateTypeFirmware = "True"
    [String]$updateTypeDriver = "True"
    [String]$updateTypeApplication = "False"
    [String]$updateTypeOthers = "False"
    [String]$updateTypeUtility = "False"

}



$Manufacturer = Get-CimInstance -ClassName Win32_ComputerSystem | Select-Object -ExpandProperty Manufacturer
[String]$MakeAlias = ${TSEnv:MakeAlias}
if ($MakeAlias -eq "Dell" -or $Manufacturer -match "Dell"){
    #Confirmed the device is a Dell
}
else {
    Write-Host "This script is designed to run on Dell systems only. Exiting."
    exit 0
}


#Write Info to Log
Write-Host "=============================================================================="
Write-Host "Current DCU Settings selected from Task Sequence" 
Write-Host "Schedule Action: $scheduleAction"
Write-Host "Schedule: $schedule"
Write-Host "DelayDays: $delayDays"
Write-Host "Installation Deferral: $installationDeferral"
Write-Host "Deferral Install Interval: $deferralInstallInterval"
Write-Host "Deferral Install Count: $deferralInstallCount"
Write-Host "System Restart Deferral: $systemRestartDeferral"
Write-Host "Deferral Restart Interval: $deferralRestartInterval"
Write-Host "Deferral Restart Count: $deferralRestartCount"



#Report Device Category Filters
Write-Host "-----------------------------------------------------"
Write-Host "Device Category Filters: $updateDeviceCategoryFilter"
if ($updateDeviceCategoryFilter -eq "Enable"){
    Write-Host "  Audio: $updateDeviceCategoryAudio"
    Write-Host "  Video: $updateDeviceCategoryVideo"
    Write-Host "  Network: $updateDeviceCategoryNetwork"
    Write-Host "  Storage: $updateDeviceCategoryStorage"
    Write-Host "  Input: $updateDeviceCategoryInput"
    Write-Host "  Chipset: $updateDeviceCategoryChipset"
    Write-Host "  Others: $updateDeviceCategoryOthers"
}
#Report Severity Filters
Write-Host "-----------------------------------------------------"
Write-Host "Severity Filters: $updateSeverityFilter"
if ($updateSeverityFilter -eq "Enable"){
    Write-Host "  Security: $updateSeveritySecurity"
    Write-Host "  Critical: $updateSeverityCritical"
    Write-Host "  Recommended: $updateSeverityRecommended"
    Write-Host "  Optional: $updateSeverityOptional"
}
#Report Update Type Filters
Write-Host "-----------------------------------------------------"
Write-Host "Update Type Filters: $updateTypeFilter"
if ($updateTypeFilter -eq "Enable"){
    Write-Host "  BIOS: $updateTypeBIOS"
    Write-Host "  Firmware: $updateTypeFirmware"
    Write-Host "  Driver: $updateTypeDriver"
    Write-Host "  Application: $updateTypeApplication"
    Write-Host "  Others: $updateTypeOthers"
    Write-Host "  Utility: $updateTypeUtility"
}



Write-Host "=============================================================================="


#region functions

function Get-DellSupportedModels {
    [CmdletBinding()]
    
    $CabPathIndex = "$env:ProgramData\EMPS\DellCabDownloads\CatalogIndexPC.cab"
    $DellCabExtractPath = "$env:ProgramData\EMPS\DellCabDownloads\DellCabExtract"
    
    # Pull down Dell XML CAB used in Dell Command Update ,extract and Load
    if (!(Test-Path $DellCabExtractPath)){$null = New-Item -Path $DellCabExtractPath -ItemType Directory -Force}
    Write-Host "Downloading Dell Cab"
    Invoke-WebRequest -Uri "https://downloads.dell.com/catalog/CatalogIndexPC.cab" -OutFile $CabPathIndex -UseBasicParsing -Proxy $ProxyServer
    If(Test-Path "$DellCabExtractPath\DellSDPCatalogPC.xml"){Remove-Item -Path "$DellCabExtractPath\DellSDPCatalogPC.xml" -Force}
    Start-Sleep -Seconds 1
    if (test-path $DellCabExtractPath){Remove-Item -Path $DellCabExtractPath -Force -Recurse}
    $null = New-Item -Path $DellCabExtractPath -ItemType Directory
    Write-Host "Expanding the Cab File..." 
    $null = expand $CabPathIndex $DellCabExtractPath\CatalogIndexPC.xml
    
    Write-Host "Loading Dell Catalog XML.... can take awhile"
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
    @{ExitCode = 3006; Description = "Currently the system is in Windows Out of Box Experience (OOBE) State"; Resolution = "Please try again after sometime"}
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
                        Write-Host "Reboot Required"
                    }
                }
                else{
                    Write-Host " FAILED TO DOWNLOAD DCU"
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
    # Registry paths where .NET Runtime info is typically stored
    $registryPaths = @(
    "HKLM:\SOFTWARE\dotnet\Setup\InstalledVersions\x64\sharedfx\Microsoft.WindowsDesktop.App",
    "HKLM:\SOFTWARE\dotnet\Setup\InstalledVersions\x86\sharedfx\Microsoft.WindowsDesktop.App"
    )
    
    $runtimesFound = $false
    $installedVersions = @()
    
    foreach ($path in $registryPaths) {
        if (Test-Path $path) {
            # Get all version subkeys
            $versions = Get-ChildItem -Path $path -ErrorAction SilentlyContinue | 
            ForEach-Object { $_.PSChildName }
            
            foreach ($version in $versions) {
                $runtimesFound = $true
                $installedVersions += $version
            }
        }
    }
    
    # Check via Get-WmiObject as alternative method
    $wmiApps = Get-WmiObject -Class Win32_Product | 
    Where-Object { $_.Name -like "*Microsoft Windows Desktop Runtime*" }
    
    if ($wmiApps) {
        $runtimesFound = $true
        $wmiVersions = $wmiApps | ForEach-Object { 
            [PSCustomObject]@{
                Version = $_.Version
                Name = $_.Name
            }
        }
        $installedVersions += $wmiVersions
    }
    
    # Output results
    if ($runtimesFound) {
        Write-Host "Microsoft Windows Desktop Runtime is installed." -ForegroundColor Green
        Write-Host "Found versions:"
        $installedVersions | Sort-Object -Unique | ForEach-Object {
            if ($_ -is [PSCustomObject]) {
                Write-Host "- $($_).Name ($($_).Version)"
            }
            else {
                Write-Host "- Version $_"
            }
        }
    }
    else {
        Write-Host "Microsoft Windows Desktop Runtime is not installed." -ForegroundColor Red
    }
    
    return $runtimesFound
}
#endregion functions


#region Confirm DCU Installed
if ((Get-DCUVersion) -match "False"){
    # Do the Stuff
    write-host "Checking for Dell Command Update Latest Version"
    $DCU = Get-DCUAppUpdates -Latest
    
    #Write-Host "=============================================================================="
    Write-Host "Check for Desktop Runtime Dependencies"
    $RunTimeInstalled = Test-WindowsDesktopRuntime
    
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
#endregion Confirm DCU Installed

if ((Get-DCUVersion) -match "False"){
    Write-Host "Dell Command Update is not getting installed, do some extra testing.."
    exit ($DCU.VendorVersion).replace(".","")
}
else {
    
    Write-Host "=============================================================================="
    Write-Host "Set Dell Command Update Settings"
    
    #Find DCU and Set Log Path
    $DCUPath = (Get-DCUInstallDetails).DCUPath
    Write-Host "DCU Path: $DCUPath"
    $LogPath = "$env:SystemDrive\Users\Dell\EMPS\Logs"
    Write-Host "Log Path: $LogPath"
    $DateTimeStamp = Get-Date -Format "yyyyMMdd-HHmmss"
    
    #Always set Suspend Bitlocker Enable
    $autoSuspendBitLocker = 'Enable'
    $autoSuspendBitLockerVar = "-autoSuspendBitLocker=$autoSuspendBitLocker -outputlog=`"$LogPath\DCU-CLI-$($DateTimeStamp)-Configure-autoSuspendBitLocker.log`""
    $ArgList = "/configure $autoSuspendBitLockerVar"
    Write-Host $ArgList
    $DCUCOnfig = Start-Process -FilePath "$DCUPath\dcu-cli.exe" -ArgumentList $ArgList -NoNewWindow -PassThru -Wait
    if ($DCUConfig.ExitCode -ne 0){
        $ExitInfo = Get-DCUExitInfo -DCUExit $DCUConfig.ExitCode
        Write-Host "Exit: $($DCUConfig.ExitCode)"
        Write-Host "Description: $($ExitInfo.Description)"
        Write-Host "Resolution: $($ExitInfo.Resolution)"
    }
    #Always set User Consent Disable
    <# - Not working in 5.5
    $userConsent = 'disable'
    $userConsentVar = "-userConsent=$userConsent -outputlog=`"$LogPath\DCU-CLI-$($DateTimeStamp)-Configure-userConsent.log`""
    $ArgList = "/configure $userConsentVar"
    Write-Host $ArgList
    $DCUCOnfig = Start-Process -FilePath "$DCUPath\dcu-cli.exe" -ArgumentList $ArgList -NoNewWindow -PassThru -Wait
    if ($DCUConfig.ExitCode -ne 0){
        $ExitInfo = Get-DCUExitInfo -DCUExit $DCUConfig.ExitCode
        Write-Host "Exit: $($DCUConfig.ExitCode)"
        Write-Host "Description: $($ExitInfo.Description)"
        Write-Host "Resolution: $($ExitInfo.Resolution)"
    }
    #>    
    if ($scheduleAction){
        $scheduleActionVar = "-scheduleAction=$scheduleAction"
        $ArgList = "/configure $scheduleActionVar -outputlog=`"$LogPath\DCU-CLI-$($DateTimeStamp)-Configure-scheduleAction.log`""
        Write-Host $ArgList
        $DCUCOnfig = Start-Process -FilePath "$DCUPath\dcu-cli.exe" -ArgumentList $ArgList -NoNewWindow -PassThru -Wait
        if ($DCUConfig.ExitCode -ne 0){
            $ExitInfo = Get-DCUExitInfo -DCUExit $DCUConfig.ExitCode
            Write-Host "Exit: $($DCUConfig.ExitCode)"
            Write-Host "Description: $($ExitInfo.Description)"
            Write-Host "Resolution: $($ExitInfo.Resolution)"
        }
    }

    #Schedule Settings
    if ($schedule -eq 'scheduleAuto'){
        $scheduleVar = "-$schedule"
    }
    elseif ($schedule -eq 'scheduleManual'){
        $scheduleVar = "-$schedule"
    }
    elseif ($schedule -eq 'scheduleDaily'){
        $scheduleVar = "-$schedule=$scheduleDaily"
    }
    elseif ($schedule -eq 'scheduleWeekly'){
        $scheduleVar = "-$schedule=$scheduleWeekly,$scheduleDaily"
    }    
    elseif ($schedule -eq 'scheduleMonthly'){
        $scheduleVar = "-$schedule=$scheduleMonthly,$scheduleWeekly,$scheduleDaily"
    }   
    
    $ArgList = "/configure $scheduleVar -outputlog=`"$LogPath\DCU-CLI-$($DateTimeStamp)-Configure-schedule.log`""
    Write-Host $ArgList
    $DCUCOnfig = Start-Process -FilePath "$DCUPath\dcu-cli.exe" -ArgumentList $ArgList -NoNewWindow -PassThru -Wait
    if ($DCUConfig.ExitCode -ne 0){
        $ExitInfo = Get-DCUExitInfo -DCUExit $DCUConfig.ExitCode
        Write-Host "Exit: $($DCUConfig.ExitCode)"
        Write-Host "Description: $($ExitInfo.Description)"
        Write-Host "Resolution: $($ExitInfo.Resolution)"
    }
    
    #Installation Deferral
    if ($installationDeferral){
        if ($scheduleAction -ne 'DownloadInstallAndNotify'){
            Write-Host "Schedule Action must be set to DownloadInstallAndNotify to use Installation Deferral"
            
        }
        else {
            if ($installationDeferral -eq 'Enable'){
                $installationDeferralVar = "-installationDeferral=$installationDeferral"
                if ($deferralInstallInterval){
                    [string]$deferralInstallIntervalVar = "-deferralInstallInterval=$deferralInstallInterval"
                }
                else {
                    [string]$deferralInstallIntervalVar = "-deferralInstallInterval=5"
                }
                if ($deferralInstallCount){
                    [string]$deferralInstallCountVar = "-deferralInstallCount=$deferralInstallCount"
                }
                else {
                    [string]$deferralInstallCountVar = "-deferralInstallCount=5"
                }
                $ArgList = "/configure $installationDeferralVar $deferralInstallIntervalVar $deferralInstallCountVar -outputlog=`"$LogPath\DCU-CLI-$($DateTimeStamp)-Configure-installationDeferral.log`""
                Write-Host $ArgList
                $DCUCOnfig = Start-Process -FilePath "$DCUPath\dcu-cli.exe" -ArgumentList $ArgList -NoNewWindow -PassThru -Wait
                if ($DCUConfig.ExitCode -ne 0){
                    $ExitInfo = Get-DCUExitInfo -DCUExit $DCUConfig.ExitCode
                    Write-Host "Exit: $($DCUConfig.ExitCode)"
                    Write-Host "Description: $($ExitInfo.Description)"
                    Write-Host "Resolution: $($ExitInfo.Resolution)"
                }
                
            }
            else {
                [string]$installationDeferralVar = "-installationDeferral=$installationDeferral"
                $ArgList = "/configure $installationDeferralVar -outputlog=`"$LogPath\DCU-CLI-$($DateTimeStamp)-Configure-installationDeferral.log`""
                Write-Host $ArgList
                $DCUCOnfig = Start-Process -FilePath "$DCUPath\dcu-cli.exe" -ArgumentList $ArgList -NoNewWindow -PassThru -Wait
                if ($DCUConfig.ExitCode -ne 0){
                    $ExitInfo = Get-DCUExitInfo -DCUExit $DCUConfig.ExitCode
                    Write-Host "Exit: $($DCUConfig.ExitCode)"
                    Write-Host "Description: $($ExitInfo.Description)"
                    Write-Host "Resolution: $($ExitInfo.Resolution)"
                }
            }
        }
    }
    #System Reboot Deferral
    if ($systemRestartDeferral){
        if ($scheduleAction -ne 'DownloadInstallAndNotify'){
            Write-Host "Schedule Action must be set to DownloadInstallAndNotify to use Installation Deferral"
            
        }
        else {
            if ($systemRestartDeferral -eq 'Enable'){
                $systemRestartDeferralVar = "-systemRestartDeferral=$systemRestartDeferral"
                if ($deferralRestartInterval){
                    [string]$deferralRestartIntervalVar = "-deferralRestartInterval=$deferralRestartInterval"
                }
                else {
                    [string]$deferralRestartIntervalVar = "-deferralRestartInterval=5"
                }
                if ($deferralRestartCount){
                    [string]$deferralRestartCountVar = "-deferralRestartCount=$deferralRestartCount"
                }
                else {
                    [string]$deferralRestartCountVar = "-deferralRestartCount=5"
                }
                $ArgList = "/configure $systemRestartDeferralVar $deferralRestartIntervalVar $deferralRestartCountVar -outputlog=`"$LogPath\DCU-CLI-$($DateTimeStamp)-Configure-RestartDeferral.log`""
                Write-Host $ArgList
                $DCUCOnfig = Start-Process -FilePath "$DCUPath\dcu-cli.exe" -ArgumentList $ArgList -NoNewWindow -PassThru -Wait
                if ($DCUConfig.ExitCode -ne 0){
                    $ExitInfo = Get-DCUExitInfo -DCUExit $DCUConfig.ExitCode
                    Write-Host "Exit: $($DCUConfig.ExitCode)"
                    Write-Host "Description: $($ExitInfo.Description)"
                    Write-Host "Resolution: $($ExitInfo.Resolution)"
                }
                
            }
            else {
                [string]$systemRestartDeferralVar = "-systemRestartDeferral=$systemRestartDeferral"
                $ArgList = "/configure $systemRestartDeferralVar -outputlog=`"$LogPath\DCU-CLI-$($DateTimeStamp)-Configure-RestartDeferral.log`""
                Write-Host $ArgList
                $DCUCOnfig = Start-Process -FilePath "$DCUPath\dcu-cli.exe" -ArgumentList $ArgList -NoNewWindow -PassThru -Wait
                if ($DCUConfig.ExitCode -ne 0){
                    $ExitInfo = Get-DCUExitInfo -DCUExit $DCUConfig.ExitCode
                    Write-Host "Exit: $($DCUConfig.ExitCode)"
                    Write-Host "Description: $($ExitInfo.Description)"
                    Write-Host "Resolution: $($ExitInfo.Resolution)"
                }
            }
        }
    }

    if ($delayDays){
        $delayDaysVar = "-delayDays=$delayDays"
        $ArgList = "/configure $delayDaysVar -outputlog=`"$LogPath\DCU-CLI-$($DateTimeStamp)-Configure-delayDays.log`""
        Write-Host $ArgList
        $DCUCOnfig = Start-Process -FilePath "$DCUPath\dcu-cli.exe" -ArgumentList $ArgList -NoNewWindow -PassThru -Wait
        if ($DCUConfig.ExitCode -ne 0){
            $ExitInfo = Get-DCUExitInfo -DCUExit $DCUConfig.ExitCode
            Write-Host "Exit: $($DCUConfig.ExitCode)"
            Write-Host "Description: $($ExitInfo.Description)"
            Write-Host "Resolution: $($ExitInfo.Resolution)"
        }
    }
    #update Device Category
    if ($updateDeviceCategoryFilter -eq "Disable"){
        #do nothing, as default is ALl
    }
    else {
        if ($updateDeviceCategoryAudio -eq "True"){
            $DCAudio = "audio,"
        }
        if ($updateDeviceCategoryVideo -eq "True"){
            $DCVideo = "video,"
        }
        if ($updateDeviceCategoryNetwork -eq "True"){
            $DCNetwork = "network,"
        }
        if ($updateDeviceCategoryStorage -eq "True"){
            $DCStorage = "storage,"
        }
        if ($updateDeviceCategoryInput -eq "True"){
            $DCInput = "input,"
        }
        if ($updateDeviceCategoryChipset -eq "True"){
            $DCChipset = "chipset,"
        }
        if ($updateDeviceCategoryOthers -eq "True"){
            $DCOthers = "others,"
        }
        $updateDeviceCategoryString="$DCAudio$DCVideo$DCNetwork$DCStorage$DCInput$DCChipset$DCOthers"
        #Trim Last ,
        $updateDeviceCategoryString = $updateDeviceCategoryString.TrimEnd(',')
        [string]$updateDeviceCategoryvar = "-updateDeviceCategory=$updateDeviceCategoryString"
        $ArgList = "/configure $updateDeviceCategoryvar -outputlog=`"$LogPath\DCU-CLI-$($DateTimeStamp)-Configure-updateDeviceCategory.log`""
        Write-Host $ArgList
        $DCUCOnfig = Start-Process -FilePath "$DCUPath\dcu-cli.exe" -ArgumentList $ArgList -NoNewWindow -PassThru -Wait
        if ($DCUConfig.ExitCode -ne 0){
            $ExitInfo = Get-DCUExitInfo -DCUExit $DCUConfig.ExitCode
            Write-Host "Exit: $($DCUConfig.ExitCode)"
            Write-Host "Description: $($ExitInfo.Description)"
            Write-Host "Resolution: $($ExitInfo.Resolution)"
        }
    }
    
    #Update Severity
    #Confirm something is set
    if ($updateSeverityFilter -eq "Disable"){
        #do nothing, as default is All
    }
    else {
        if ($updateSeveritySecurity -eq "True"){
            $DCUSecurity = "security,"
        }
        if ($updateSeverityCritical -eq "True"){
            $DCUCritical = "critical,"
        }
        if ($updateSeverityRecommended -eq "True"){
            $DCURecommended = "recommended,"
        }
        if ($updateSeverityOptional -eq "True"){
            $DCUOptional = "optional,"
        }
        $updateSeverityString="$DCUSecurity$DCUCritical$DCURecommended$DCUOptional"
        #Trim Last ,
        $updateSeverityString = $updateSeverityString.TrimEnd(',')
        [string]$updateSeverityVar = "-updateSeverity=$updateSeverityString"
        $ArgList = "/configure $updateSeverityVar -outputlog=`"$LogPath\DCU-CLI-$($DateTimeStamp)-Configure-updateSeverity.log`""
        Write-Host $ArgList
        $DCUCOnfig = Start-Process -FilePath "$DCUPath\dcu-cli.exe" -ArgumentList $ArgList -NoNewWindow -PassThru -Wait
        if ($DCUConfig.ExitCode -ne 0){
            $ExitInfo = Get-DCUExitInfo -DCUExit $DCUConfig.ExitCode
            Write-Host "Exit: $($DCUConfig.ExitCode)"
            Write-Host "Description: $($ExitInfo.Description)"
            Write-Host "Resolution: $($ExitInfo.Resolution)"
        }
    }
    
    #Update Type, confirm something is set
    if ($updateTypeFilter -eq "Disable"){
        #do nothing, as default is All
    }
    else {
        if ($updateTypeBIOS -eq "True"){
            $DCUBIOS = "bios,"
        }
        if ($updateTypeFirmware -eq "True"){
            $DCUFirmware = "firmware,"
        }
        if ($updateTypeDriver -eq "True"){
            $DCUDriver = "driver,"
        }
        if ($updateTypeApplication -eq "True"){
            $DCUApplication = "application,"
        }
        if ($updateTypeOthers -eq "True"){
            $DCUOther = "others,"
        }
        if ($updateTypeUtility -eq "True"){
            $DCUUtility = "utility,"
        }
        $updateTypeString="$DCUBIOS$DCUFirmware$DCUDriver$DCUApplication$DCUOther$DCUUtility"
        #Trim Last ,
        $updateTypeString = $updateTypeString.TrimEnd(',')
        [string]$updateTypeVar = "-updateType=$updateTypeString"
        $ArgList = "/configure $updateTypeVar -outputlog=`"$LogPath\DCU-CLI-$($DateTimeStamp)-Configure-updateType.log`""
        Write-Host $ArgList
        $DCUCOnfig = Start-Process -FilePath "$DCUPath\dcu-cli.exe" -ArgumentList $ArgList -NoNewWindow -PassThru -Wait
        if ($DCUConfig.ExitCode -ne 0){
            $ExitInfo = Get-DCUExitInfo -DCUExit $DCUConfig.ExitCode
            Write-Host "Exit: $($DCUConfig.ExitCode)"
            Write-Host "Description: $($ExitInfo.Description)"
            Write-Host "Resolution: $($ExitInfo.Resolution)"
        }
    }
    
    
    
    Write-Host "=============================================================================="
}

