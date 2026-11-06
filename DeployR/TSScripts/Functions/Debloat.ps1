Import-Module DeployR.Utility
try {
    $PATH = "$(${TSEnv:OSDTARGETSYSTEMDRIVE})\"
    $LogFolder = ${TSEnv:_DEPLOYRLOGPATH}
}
catch {
    $LogFolder = "$env:Temp"
    $Path = $null
}

function Invoke-Debloat {
    [CmdletBinding()]
    param (
    [Parameter(Mandatory = $false)]
    [string]$LogPath = "$LogFolder\Debloat.log"
    )
    
    <#
    This is a custom variant of Andrew's Script used for my own needs:
    https://github.com/andrew-s-taylor/public/blob/main/De-Bloat/RemoveBloat.ps1
    
    I've modified the log location and removed several parts that didn't make sense for my OSDCloud deployments
    I plan to run this during Setup Complete.
    
    
    Orginial Contents below:
    -------------------------
    
.SYNOPSIS
    .Removes bloat from a fresh Windows build
.DESCRIPTION
    .Removes AppX Packages
    .Disables Cortana
    .Removes McAfee
    .Removes HP Bloat
    .Removes Dell Bloat
    .Removes Lenovo Bloat
    .Windows 10 and Windows 11 Compatible
    .Removes any unwanted installed applications
    .Removes unwanted services and tasks
    .Removes Edge Surf Game
    
.INPUTS
.OUTPUTS
    C:\ProgramData\Debloat\Debloat.log
.NOTES
    Version:        4.1.2
    Author:         Andrew Taylor
    Twitter:        @AndrewTaylor_2
    WWW:            andrewstaylor.com
    Creation Date:  08/03/2022
    Purpose/Change: Initial script development
    Change: 12/08/2022 - Added additional HP applications
    Change 23/09/2022 - Added Clipchamp (new in W11 22H2)
    Change 28/10/2022 - Fixed issue with Dell apps
    Change 23/11/2022 - Added Teams Machine wide to exceptions
    Change 27/11/2022 - Added Dell apps
    Change 07/12/2022 - Whitelisted Dell Audio and Firmware
    Change 19/12/2022 - Added Windows 11 start menu support
    Change 20/12/2022 - Removed Gaming Menu from Settings
    Change 18/01/2023 - Fixed Scheduled task error and cleared up $null posistioning
    Change 22/01/2023 - Re-enabled Telemetry for Endpoint Analytics
    Change 30/01/2023 - Added Microsoft Family to removal list
    Change 31/01/2023 - Fixed Dell loop
    Change 08/02/2023 - Fixed HP apps (thanks to http://gerryhampsoncm.blogspot.com/2023/02/remove-pre-installed-hp-software-during.html?m=1)
    Change 08/02/2023 - Removed reg keys for Teams Chat
    Change 14/02/2023 - Added HP Sure Apps
    Change 07/03/2023 - Enabled Location tracking (with commenting to disable)
    Change 08/03/2023 - Teams chat fix
    Change 10/03/2023 - Dell array fix
    Change 19/04/2023 - Added loop through all users for HKCU keys for post-OOBE deployments
    Change 29/04/2023 - Removes News Feed
    Change 26/05/2023 - Added Set-ACL
    Change 26/05/2023 - Added multi-language support for Set-ACL commands
    Change 30/05/2023 - Logic to check if gamepresencewriter exists before running Set-ACL to stop errors on re-run
    Change 25/07/2023 - Added Lenovo apps (Thanks to Simon Lilly and Philip Jorgensen)
    Change 31/07/2023 - Added LenovoAssist
    Change 21/09/2023 - Remove Windows backup for Win10
    Change 28/09/2023 - Enabled Diagnostic Tracking for Endpoint Analytics
    Change 02/10/2023 - Lenovo Fix
    Change 06/10/2023 - Teams chat fix
    Change 09/10/2023 - Dell Command Update change
    Change 11/10/2023 - Grab all uninstall strings and use native uninstaller instead of uninstall-package
    Change 14/10/2023 - Updated HP Audio package name
    Change 31/10/2023 - Added PowerAutomateDesktop and update Microsoft.Todos
    Change 01/11/2023 - Added fix for Windows backup removing Shell Components
    Change 06/11/2023 - Removes Windows CoPilot
    Change 07/11/2023 - HKU fix
    Change 13/11/2023 - Added CoPilot removal to .Default Users
    Change 14/11/2023 - Added logic to stop errors on HP machines without HP docs installed
    Change 14/11/2023 - Added logic to stop errors on Lenovo machines without some installers
    Change 15/11/2023 - Code Signed for additional security
    Change 02/12/2023 - Added extra logic before app uninstall to check if a user has logged in
    Change 04/01/2024 - Added Dropbox and DevHome to AppX removal
    Change 05/01/2024 - Added MSTSC to whitelist
    N/A
    #>
    
    ############################################################################################################
    #                                         Initial Setup                                                    #
    #                                                                                                          #
    ############################################################################################################
    
    ##Elevate if needed
    
    If (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]'Administrator')) {
        Write-Host "You didn't run this script as an Administrator. This script will self elevate to run as an Administrator and continue."
        Start-Sleep 1
        Write-Host "                                               3"
        Start-Sleep 1
        Write-Host "                                               2"
        Start-Sleep 1
        Write-Host "                                               1"
        Start-Sleep 1
        Start-Process powershell.exe -ArgumentList ("-NoProfile -ExecutionPolicy Bypass -File `"{0}`"" -f $PSCommandPath) -Verb RunAs
        Exit
    }
    
    #no errors throughout
    $ErrorActionPreference = 'silentlycontinue'
    
    
    
    Start-Transcript -Path $LogPath
    

    
    ############################################################################################################
    #                                        Remove AppX Packages                                              #
    #                                                                                                          #
    ############################################################################################################
    <# DISABLED  SEEMS DANGEROUS
    #Removes AppxPackages
    $WhitelistedApps = 'Microsoft.WindowsNotepad|Microsoft.CompanyPortal|Microsoft.ScreenSketch|Microsoft.Paint3D|Microsoft.WindowsCalculator|Microsoft.WindowsStore|Microsoft.Windows.Photos|CanonicalGroupLimited.UbuntuonWindows|`
|Microsoft.MicrosoftStickyNotes|Microsoft.MSPaint|Microsoft.WindowsCamera|.NET|Framework|`
Microsoft.HEIFImageExtension|Microsoft.ScreenSketch|Microsoft.StorePurchaseApp|Microsoft.VP9VideoExtensions|Microsoft.WebMediaExtensions|Microsoft.WebpImageExtension|Microsoft.DesktopAppInstaller|WindSynthBerry|MIDIBerry|Slack'
    #NonRemovable Apps that where getting attempted and the system would reject the uninstall, speeds up debloat and prevents 'initalizing' overlay when removing apps
    $NonRemovable = '1527c705-839a-4832-9118-54d4Bd6a0c89|c5e2524a-ea46-4f67-841f-6a9465d9d515|E2A4F912-2574-4A75-9BB0-0D023378592B|F46D4000-FD22-4DB4-AC8E-4E1DDDE828FE|InputApp|Microsoft.AAD.BrokerPlugin|Microsoft.AccountsControl|`
Microsoft.BioEnrollment|Microsoft.CredDialogHost|Microsoft.ECApp|Microsoft.LockApp|Microsoft.MicrosoftEdgeDevToolsClient|Microsoft.MicrosoftEdge|Microsoft.PPIProjection|Microsoft.Win32WebViewHost|Microsoft.Windows.Apprep.ChxApp|`
Microsoft.Windows.AssignedAccessLockApp|Microsoft.Windows.CapturePicker|Microsoft.Windows.CloudExperienceHost|Microsoft.Windows.ContentDeliveryManager|Microsoft.Windows.Cortana|Microsoft.Windows.NarratorQuickStart|`
Microsoft.Windows.ParentalControls|Microsoft.Windows.PeopleExperienceHost|Microsoft.Windows.PinningConfirmationDialog|Microsoft.Windows.SecHealthUI|Microsoft.Windows.SecureAssessmentBrowser|Microsoft.Windows.ShellExperienceHost|`
Microsoft.Windows.XGpuEjectDialog|Microsoft.XboxGameCallableUI|Windows.CBSPreview|windows.immersivecontrolpanel|Windows.PrintDialog|Microsoft.XboxGameCallableUI|Microsoft.VCLibs.140.00|Microsoft.Services.Store.Engagement|Microsoft.UI.Xaml.2.0|*Nvidia*'
    Get-AppxPackage -AllUsers | Where-Object {$_.Name -NotMatch $WhitelistedApps -and $_.Name -NotMatch $NonRemovable} | Remove-AppxPackage
    Get-AppxPackage -allusers | Where-Object {$_.Name -NotMatch $WhitelistedApps -and $_.Name -NotMatch $NonRemovable} | Remove-AppxPackage
    Get-AppxProvisionedPackage -Online | Where-Object {$_.PackageName -NotMatch $WhitelistedApps -and $_.PackageName -NotMatch $NonRemovable} | Remove-AppxProvisionedPackage -Online
    
    #>

    ##Remove specific AppX Packages
    $AppXPackages2Remove = @(
    
    #Unnecessary Windows 10/11 AppX Apps
    "Microsoft.549981C3F5F10"
    "Microsoft.BingNews"
    "Microsoft.Messaging"
    "Microsoft.Microsoft3DViewer"
    "Microsoft.MicrosoftOfficeHub"
    "Microsoft.NetworkSpeedTest"
    "Microsoft.MixedReality.Portal"
    "Microsoft.News"
    "Microsoft.Office.Lens"
    "Microsoft.Office.OneNote"
    "Microsoft.Office.Sway"
    "Microsoft.OneConnect"
    "Microsoft.People"
    "Microsoft.Print3D"
    "Microsoft.SkypeApp"
    "Microsoft.Office.Todo.List"
    "microsoft.windowscommunicationsapps"
    "Microsoft.WindowsMaps"
    "Microsoft.Xbox.TCUI"
    "Microsoft.XboxApp"
    "Microsoft.XboxGameOverlay"
    "Microsoft.XboxIdentityProvider"
    "Microsoft.XboxSpeechToTextOverlay"
    "MicrosoftTeams"
    "Microsoft.YourPhone"
    "Microsoft.XboxGamingOverlay_5.721.10202.0_neutral_~_8wekyb3d8bbwe"
    "Microsoft.GamingApp"
    "Microsoft.Todos"
    "Microsoft.PowerAutomateDesktop"
    "SpotifyAB.SpotifyMusic"
    "Disney.37853FC22B2CE"
    "*EclipseManager*"
    "*ActiproSoftwareLLC*"
    "*AdobeSystemsIncorporated.AdobePhotoshopExpress*"
    "*Duolingo-LearnLanguagesforFree*"
    "*PandoraMediaInc*"
    "*CandyCrush*"
    "*BubbleWitch3Saga*"
    "*Wunderlist*"
    "*Flipboard*"
    "*Twitter*"
    "*Facebook*"
    "*Spotify*"
    "*Minecraft*"
    "*Royal Revolt*"
    "*Sway*"
    "*Speed Test*"
    "*Dolby*"
    "*Office*"
    "*Disney*"
    "clipchamp.clipchamp"
    "*gaming*"
    "MicrosoftCorporationII.MicrosoftFamily"
    "C27EB4BA.DropboxOEM"
    "*DevHome*"
    #Optional: Typically not removed but you can if you need to for some reason
    #"*Microsoft.Advertising.Xaml_10.1712.5.0_x64__8wekyb3d8bbwe*"
    #"*Microsoft.Advertising.Xaml_10.1712.5.0_x86__8wekyb3d8bbwe*"
    #"*Microsoft.BingWeather*"
    #"*Microsoft.MSPaint*"
    #"*Microsoft.MicrosoftStickyNotes*"
    #"*Microsoft.Windows.Photos*"
    #"*Microsoft.WindowsCalculator*"
    #"*Microsoft.WindowsStore*"
    
    )
    foreach ($AppX in $AppXPackages2Remove) {
        
        Get-AppxPackage -allusers -Name $AppX| Remove-AppxPackage -AllUsers
        Get-AppxProvisionedPackage -Online | Where-Object DisplayName -like $AppX | Remove-AppxProvisionedPackage -Online
        Write-Host "Trying to remove $AppX."
    }
    
    ############################################################################################################
    #                                        Remove Registry Keys                                              #
    #                                                                                                          #
    ############################################################################################################
    
    
    #Disables Windows Feedback Experience
    Write-Host "Disabling Windows Feedback Experience program"
    $Advertising = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo"
    If (!(Test-Path $Advertising)) {
        New-Item $Advertising
    }
    If (Test-Path $Advertising) {
        Set-ItemProperty $Advertising Enabled -Value 0 
    }
    
    #Disables Web Search in Start Menu
    Write-Host "Disabling Bing Search in Start Menu"
    $WebSearch = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search"
    If (!(Test-Path $WebSearch)) {
        New-Item $WebSearch
    }
    Set-ItemProperty $WebSearch DisableWebSearch -Value 1 
    ##Loop through all user SIDs in the registry and disable Bing Search
    foreach ($sid in $UserSIDs) {
        $WebSearch = "Registry::HKU\$sid\SOFTWARE\Microsoft\Windows\CurrentVersion\Search"
        If (!(Test-Path $WebSearch)) {
            New-Item $WebSearch
        }
        Set-ItemProperty $WebSearch BingSearchEnabled -Value 0
    }
    
    Set-ItemProperty "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search" BingSearchEnabled -Value 0 
    
    
    
    #Disables Wi-fi Sense
    Write-Host "Disabling Wi-Fi Sense"
    $WifiSense1 = "HKLM:\SOFTWARE\Microsoft\PolicyManager\default\WiFi\AllowWiFiHotSpotReporting"
    $WifiSense2 = "HKLM:\SOFTWARE\Microsoft\PolicyManager\default\WiFi\AllowAutoConnectToWiFiSenseHotspots"
    $WifiSense3 = "HKLM:\SOFTWARE\Microsoft\WcmSvc\wifinetworkmanager\config"
    If (!(Test-Path $WifiSense1)) {
        New-Item $WifiSense1
    }
    Set-ItemProperty $WifiSense1  Value -Value 0 
    If (!(Test-Path $WifiSense2)) {
        New-Item $WifiSense2
    }
    Set-ItemProperty $WifiSense2  Value -Value 0 
    Set-ItemProperty $WifiSense3  AutoConnectAllowedOEM -Value 0 
    
    
    ############################################################################################################
    #                                        Remove Scheduled Tasks                                            #
    #                                                                                                          #
    ############################################################################################################
    
    #Disables scheduled tasks that are considered unnecessary 
    Write-Host "Disabling scheduled tasks"
    $task1 = Get-ScheduledTask -TaskName XblGameSaveTaskLogon -ErrorAction SilentlyContinue
    if ($null -ne $task1) {
        Get-ScheduledTask  XblGameSaveTaskLogon | Disable-ScheduledTask -ErrorAction SilentlyContinue
    }
    $task2 = Get-ScheduledTask -TaskName XblGameSaveTask -ErrorAction SilentlyContinue
    if ($null -ne $task2) {
        Get-ScheduledTask  XblGameSaveTask | Disable-ScheduledTask -ErrorAction SilentlyContinue
    }
    $task3 = Get-ScheduledTask -TaskName Consolidator -ErrorAction SilentlyContinue
    if ($null -ne $task3) {
        Get-ScheduledTask  Consolidator | Disable-ScheduledTask -ErrorAction SilentlyContinue
    }
    $task4 = Get-ScheduledTask -TaskName UsbCeip -ErrorAction SilentlyContinue
    if ($null -ne $task4) {
        Get-ScheduledTask  UsbCeip | Disable-ScheduledTask -ErrorAction SilentlyContinue
    }
    $task5 = Get-ScheduledTask -TaskName DmClient -ErrorAction SilentlyContinue
    if ($null -ne $task5) {
        Get-ScheduledTask  DmClient | Disable-ScheduledTask -ErrorAction SilentlyContinue
    }
    $task6 = Get-ScheduledTask -TaskName DmClientOnScenarioDownload -ErrorAction SilentlyContinue
    if ($null -ne $task6) {
        Get-ScheduledTask  DmClientOnScenarioDownload | Disable-ScheduledTask -ErrorAction SilentlyContinue
    }
    
    

    ############################################################################################################
    #                                        Windows 11 Specific                                               #
    #                                                                                                          #
    ############################################################################################################
    #Windows 11 Customisations
    write-host "Removing Windows 11 Customisations"
    #Remove XBox Game Bar
    
    Get-AppxPackage -allusers Microsoft.XboxGamingOverlay | Remove-AppxPackage
    write-host "Removed Xbox Gaming Overlay"
    Get-AppxPackage -allusers Microsoft.XboxGameCallableUI | Remove-AppxPackage
    write-host "Removed Xbox Game Callable UI"
    
    #Remove Cortana
    Get-AppxPackage -allusers Microsoft.549981C3F5F10 | Remove-AppxPackage
    write-host "Removed Cortana"
    
    #Remove GetStarted
    Get-AppxPackage -allusers *getstarted* | Remove-AppxPackage
    write-host "Removed Get Started"
    
    #Remove Parental Controls
    Get-AppxPackage -allusers Microsoft.Windows.ParentalControls | Remove-AppxPackage 
    write-host "Removed Parental Controls"
    
    
    
    ############################################################################################################
    #                                              Remove Xbox Gaming                                          #
    #                                                                                                          #
    ############################################################################################################
    
    New-ItemProperty -Path "HKLM:\System\CurrentControlSet\Services\xbgm" -Name "Start" -PropertyType DWORD -Value 4 -Force
    Set-Service -Name XblAuthManager -StartupType Disabled
    Set-Service -Name XblGameSave -StartupType Disabled
    Set-Service -Name XboxGipSvc -StartupType Disabled
    Set-Service -Name XboxNetApiSvc -StartupType Disabled
    $task = Get-ScheduledTask -TaskName "Microsoft\XblGameSave\XblGameSaveTask" -ErrorAction SilentlyContinue
    if ($null -ne $task) {
        Set-ScheduledTask -TaskPath $task.TaskPath -Enabled $false
    }
    

    # MOVE TO WINPE
    <#
    ##Check if GamePresenceWriter.exe exists
    if (Test-Path "$env:WinDir\System32\GameBarPresenceWriter.exe") {
        write-host "GamePresenceWriter.exe exists"
        C:\Windows\Temp\SetACL.exe -on  "$env:WinDir\System32\GameBarPresenceWriter.exe" -ot file -actn setowner -ownr "n:$everyone"
        C:\Windows\Temp\SetACL.exe -on  "$env:WinDir\System32\GameBarPresenceWriter.exe" -ot file -actn ace -ace "n:$everyone;p:full"
        
        #Take-Ownership -Path "$env:WinDir\System32\GameBarPresenceWriter.exe"
        $NewAcl = Get-Acl -Path "$env:WinDir\System32\GameBarPresenceWriter.exe"
        # Set properties
        $identity = "$builtin\Administrators"
        $fileSystemRights = "FullControl"
        $type = "Allow"
        # Create new rule
        $fileSystemAccessRuleArgumentList = $identity, $fileSystemRights, $type
        $fileSystemAccessRule = New-Object -TypeName System.Security.AccessControl.FileSystemAccessRule -ArgumentList $fileSystemAccessRuleArgumentList
        # Apply new rule
        $NewAcl.SetAccessRule($fileSystemAccessRule)
        Set-Acl -Path "$env:WinDir\System32\GameBarPresenceWriter.exe" -AclObject $NewAcl
        Stop-Process -Name "GameBarPresenceWriter.exe" -Force
        Remove-Item "$env:WinDir\System32\GameBarPresenceWriter.exe" -Force -Confirm:$false
        
    }
    else {
        write-host "GamePresenceWriter.exe does not exist"
    }
    #>
    New-ItemProperty -Path "HKLM:\Software\Policies\Microsoft\Windows\GameDVR" -Name "AllowgameDVR" -PropertyType DWORD -Value 0 -Force
    New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" -Name "SettingsPageVisibility" -PropertyType String -Value "hide:gaming-gamebar;gaming-gamedvr;gaming-broadcasting;gaming-gamemode;gaming-xboxnetworking" -Force

    
    
    write-host "Completed"
    
    Stop-Transcript
}
