Function Remove-DefaultWinApps {
    <#
    .SYNOPSIS
    Remove non-enterprise worthy apps
    
    .DESCRIPTION
    Given a list of apps, remove if found on local machine
    
    .LINK 
    http://www.vacuumbreather.com/index.php/blog/item/51-windows-10-1709-built-in-apps-what-to-keep
    
    .LINK 
    https://blogs.technet.microsoft.com/mniehaus/2015/11/11/removing-windows-10-in-box-apps-during-a-task-sequence/
    
    .LINK 
    https://blogs.technet.microsoft.com/mniehaus/2015/11/23/seeing-extra-apps-turn-them-off/
    
    
    Original Script by Keith Garner
    Modified by Gary Blok (@GWBLOK)
    
    22.02.23.01
    - Removed Parameters so it would work via Invoke-RestMethod
    - Added Logic to be able to run in WinPE to remove items offline & again online to clean up the rest... expect errors in logs.
    #>
    
    
    $results = @()
    $Capabilities = @(
    "App.Support.ContactSupport"
    "App.Support.QuickAssist"
    )
    $apps += @(
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
    "EclipseManager"
    "ActiproSoftwareLLC"
    "AdobeSystemsIncorporated.AdobePhotoshopExpress"
    "Duolingo-LearnLanguagesforFree"
    "PandoraMediaInc"
    "CandyCrush"
    "BubbleWitch3Saga"
    "Wunderlist"
    "Flipboard"
    "Twitter"
    "Facebook"
    "Spotify"
    "Minecraft"
    "Royal Revolt"
    "Sway"
    "Disney"
    "clipchamp.clipchamp"
    "gaming"
    "MicrosoftCorporationII.MicrosoftFamily"
    "C27EB4BA.DropboxOEM"
    "DevHome"
    "LinkedIn"
    )
    
    
    #region argument parsing and logging
    
    if ( -not ( get-module DISM ) ) { import-module DISM }
    
    Import-Module DeployR.Utility
    try {
    $PATH = "$(${TSEnv:OSDTARGETSYSTEMDRIVE})\"
    $LogFolder = ${TSEnv:_DEPLOYRLOGS}
    }
    catch {
        $LogFolder = "C:\Windows\Temp"
        $Path = $null
    }
    # Get the provided variables

    $LogPath = $LogFolder + "\RemoveApps.Log"
    Write-Output "LogPath: $LogPath"
    
    write-verbose "New DISM LogLevel [3]  LogPath: $LogPath"
    if ( $Path ) {
        $DISMArgs = @{ Path = $Path; LogLevel = [Microsoft.Dism.Commands.LogLevel]::WarningsInfo ;  LogPath = $LogPath }
    }
    elseif ( $env:SYSTEMDRIVE -eq "X:" ) {
        # RUnning offline in WinPE.
        
        $Path = get-volume | 
        Where-Object DRiveType -eq 'Fixed' | 
        Where-Object DriveLetter -ne 'x' | 
        Where-Object FileSystem -eq 'NTFS' | 
        Where-Object { test-path "$($_.DriveLetter):\Windows\System32" } | 
        ForEach-Object{ "$($_.DriveLetter):\" }
        
        $DISMArgs = @{ Path = $Path; LogLevel = [Microsoft.Dism.Commands.LogLevel]::WarningsInfo ;  LogPath = $LogPath }
    }
    else {
        $DISMArgs = @{ Online = $True; LogLevel = [Microsoft.Dism.Commands.LogLevel]::WarningsInfo ;  LogPath = $LogPath }
    }
    
    $DISMArgs | out-string -Width 120 | write-verbose
    
    #endregion
    
    #region Remove Provisioned Windows Apps
    
    write-verbose "Remove Provisioned Windows Apps"
    
    $results += Get-AppxProvisionedPackage  @DISMArgs | 
    Where-Object { $TestName = $_.DisplayName; $Apps | Where-Object { $TestName -match $_ } } | 
    Remove-AppxProvisionedPackage @DismArgs
    
    #endregion
    
    #region Remove Installed Windows Apps
    if ($InWinPE -ne "TRUE"){
        write-verbose "Remove Installed Windows Apps"
        
        $results += Get-AppxPackage | 
        Where-Object { $TestName = $_.Name; $Apps | Where-Object { $TestName -match $_ } } |
        Remove-AppxPackage
    }
    #endregion
    
    #region Remove Windows Capability
    
    write-verbose "Remove Windows Capability"
    
    $results += & dism.exe /online /get-capabilities /limitaccess | 
    Where-Object { $_ -match ".* (([^ \~]*)\~[^ ]*)$" } | 
    Where-Object { $Matches[2] -in $Capabilities } | 
    ForEach-Object { write-host "remove $Matches[1]" ; Remove-WindowsCapability @DISMArgs -Name $Matches[1] }
    
    #endregion
    
    #region Cleanup
    
    write-verbose "cleanup"
    
    if ( $true -in $results.restartneeded ) {
        
        $results | Out-string -Width 120 | write-verbose
        
        write-verbose "whoops, we need a reboot!"
        #exit 3010
        
    }
    
    #endregion
}

Write-Host -ForegroundColor Green "Starting Function Remove-DefaultWinApps"
try {
    Remove-DefaultWinApps
}
catch {
    Write-Host -ForegroundColor Red "Error in Remove-DefaultWinApps: $_"
}