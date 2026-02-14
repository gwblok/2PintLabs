#So far, just created Function, but will integrate into Task Sequence for Backup.

<#
.SYNOPSIS
    Performs backup and restore operations for Windows user profiles, including browser data for Chrome, Edge, and Firefox.

.DESCRIPTION
    This function migrates user profiles including their data and browser information.
    Based on the Windows User Migration script from: https://github.com/Xaoc-Industries/WindowsUserMigration

.PARAMETER Mode
    Specifies the operation mode: 'Copy' for backup or 'Paste' for restore

.PARAMETER SourceProfile
    (Copy mode) The user profile name to backup. If omitted, all non-built-in profiles will be backed up.
    (Paste mode) The profile name in the repository to restore from

.PARAMETER RepositoryPath
    The path where the profile backup is stored or will be stored

.PARAMETER DestinationProfile
    (Paste mode only) The destination profile name to restore the backup to

.PARAMETER Force
    If $true in Copy mode, overwrites existing backups. If $false (default), skips profiles that already have backups

.EXAMPLE
    Invoke-MigrateData -Mode 'Copy' -SourceProfile 'john.doe' -RepositoryPath 'C:\ProfileBackups'

.EXAMPLE
    Invoke-MigrateData -Mode 'Copy' -RepositoryPath 'C:\ProfileBackups'
    Backs up all non-built-in user profiles

.EXAMPLE
    Invoke-MigrateData -Mode 'Paste' -SourceProfile 'john.doe' -RepositoryPath 'C:\ProfileBackups' -DestinationProfile 'jane.smith'
#>
function Invoke-MigrateData {
    param(
        [Parameter(Mandatory=$true)]
        [ValidateSet('Copy', 'Paste')]
        [string]$Mode,

        [Parameter(Mandatory=$false)]
        [string]$SourceProfile,

        [Parameter(Mandatory=$true)]
        [string]$RepositoryPath,

        [Parameter(Mandatory=$false)]
        [string]$DestinationProfile,

        [Parameter(Mandatory=$false)]
        [bool]$Force = $false
    )

    # Get the system drive and current user principal
    $SystemDrive = (Get-CimInstance Win32_OperatingSystem).SystemDrive
    $CurrentUserPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())

    # Function to copy files from the source directory to the destination directory
    function CopyFiles {
        param([string]$Src, [string]$Folder)

        $DestinationPath = "$Dest\$Usr\$Folder"
        $LogDir = "$Dest\Logs\$Usr"
        $LogFile = "$LogDir\robocopy_log_$Folder.txt"

        # Check if the destination path exists, if not create it
        if (!(Test-Path -Path $DestinationPath)) {
            New-Item -Path $DestinationPath -ItemType Directory -Force | Out-Null
        }

        # Ensure robocopy log directory exists
        if (!(Test-Path -Path $LogDir)) {
            New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
        }

        # Execute robocopy
        Start-Process robocopy -ArgumentList "$Src $DestinationPath /MIR /LOG:$LogFile /NFL /NDL /NP /R:3 /W:5" -NoNewWindow -Wait
    }

    # Function to paste files from the repository to the destination user profile
    function PasteFiles {
        param([string]$Repo, [string]$Folder)

        $SourcePath = "$Repo\$Usr\$Folder"
        $DestinationPath = "$SystemDrive\Users\$DestProfile\$Folder"
        $LogDir = "$Repo\Logs\$Usr"
        $LogFile = "$LogDir\robocopy_log_$Folder.txt"

        # Ensure log directory exists
        if (!(Test-Path -Path $LogDir)) {
            New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
        }

        if ($Folder -eq "RootFolders") {
            # Copy each subfolder in RootFolders individually
            Get-ChildItem -Directory $SourcePath -ErrorAction SilentlyContinue | ForEach-Object {
                $SubFolder = $_.Name
                $SubSourcePath = "$SourcePath\$SubFolder"
                $SubDestinationPath = "$DestinationPath\$SubFolder"
                $SubLogFile = "$LogDir\robocopy_log_RootFolders_$SubFolder.txt"

                # Execute robocopy for each subfolder
                Start-Process robocopy -ArgumentList "$SubSourcePath $SubDestinationPath /E /LOG:$SubLogFile /NFL /NDL /NP /R:3 /W:5" -NoNewWindow -Wait
            }
        }
        else {
            # Execute robocopy for folder
            Start-Process robocopy -ArgumentList "$SourcePath $DestinationPath /E /LOG:$LogFile /NFL /NDL /NP /R:3 /W:5" -NoNewWindow -Wait
        }
    }

    # Function to take (backup) a user profile
    function TakeProfile {
        param([string]$Usr, [string]$Dest, [bool]$ForceOverwrite = $false)

        # Check if the script is running with administrative privileges
        if (!($CurrentUserPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))) {
            if (!($Usr -eq $Env:UserName)) {
                Write-Error "ERROR: No Administrator access. Can only copy other profiles when run as Administrator!"
                return $false
            }
        }

        # Get all folders in the user profile, excluding system folders
        $SystemFolders = @("AppData", "Application Data", "Cookies", "Local Settings", "NetHood", "PrintHood", "Recent", "SendTo", "Start Menu", "Templates", "NTUSER.DAT", "ntuser.dat.LOG1", "ntuser.dat.LOG2", "NTUSER.DAT{*", "ntuser.ini", "3D Objects", "Links", "Saved Games", "Searches")
        $AllUserFolders = @(Get-ChildItem "$SystemDrive\Users\$Usr\" -Directory -ErrorAction SilentlyContinue | Where-Object { 
            $_.Name -notin $SystemFolders -and 
            $_.Name -notmatch "^OneDrive" 
        } | Select-Object -ExpandProperty Name)
        
        # List of folders to copy from the user profile (includes all user-created folders)
        $FoldersToCopy = $AllUserFolders

        # Check if the destination path for the user profile already exists
        if (Test-Path -Path $Dest\$Usr) {
            if ($ForceOverwrite) {
                Write-Host "Overwriting existing profile backup..."
                Remove-Item $Dest\$Usr -Force -Recurse
            }
            else {
                Write-Host "Profile backup already exists, skipping: $Dest\$Usr"
                return $true
            }
        }
        else {
            New-Item $Dest\$Usr -ItemType Directory | Out-Null
        }

        # Copy home folder contents (files only, folders are handled below)
        Write-Host "Copying Home Folder Files"
        Get-ChildItem "$SystemDrive\Users\$Usr\" -File -ErrorAction SilentlyContinue | ForEach-Object {
            if (!(Test-Path $Dest\$Usr\RootFolders)) {
                New-Item $Dest\$Usr\RootFolders -ItemType Directory | Out-Null
            }
            Copy-Item "$SystemDrive\Users\$Usr\$_" -Destination "$Dest\$Usr\RootFolders\" -ErrorAction SilentlyContinue
        }

        # Copy all user folders (including standard and user-created folders)
        $FoldersToCopy | ForEach-Object {
            Write-Host "Copying $_ Folder"
            CopyFiles "$SystemDrive\Users\$Usr\$_" "$_"
        }

        # Terminate any running browser processes to ensure data integrity
        $CurrentProcesses = @((Get-CimInstance win32_process -computername $env:COMPUTERNAME -ErrorAction SilentlyContinue | Select-Object ProcessName).ProcessName)
        if ($CurrentProcesses.Contains("chrome.exe") -or $CurrentProcesses.Contains("msedge.exe") -or $CurrentProcesses.Contains("firefox.exe")) {
            Get-Process -Name chrome -ErrorAction SilentlyContinue | Stop-Process -Force
            Get-Process -Name msedge -ErrorAction SilentlyContinue | Stop-Process -Force
            Get-Process -Name firefox -ErrorAction SilentlyContinue | Stop-Process -Force
            Start-Sleep -Milliseconds 500
        }

        # Copy browser data
        if (Test-Path "$SystemDrive\Users\$Usr\AppData\Local\Google\Chrome\User Data\Default") {
            Write-Host "Copying Chrome Data"
            Copy-Item "$SystemDrive\Users\$Usr\AppData\Local\Google\Chrome\User Data\Default" -Destination $Dest\$Usr\ChromeData\Default -Recurse -ErrorAction SilentlyContinue
        }

        Write-Host "Copying Edge Data"
        Copy-Item "$SystemDrive\Users\$Usr\AppData\Local\Microsoft\Edge\User Data\Default" -Destination $Dest\$Usr\EdgeData\Default -Recurse -ErrorAction SilentlyContinue

        if (Test-Path "$SystemDrive\Users\$Usr\AppData\Roaming\Mozilla\Firefox\Profiles") {
            Write-Host "Copying Firefox Data"
            Copy-Item "$SystemDrive\Users\$Usr\AppData\Roaming\Mozilla\Firefox\Profiles" -Destination $Dest\$Usr\FirefoxData\Profiles -Recurse -ErrorAction SilentlyContinue
            Copy-Item "$SystemDrive\Users\$Usr\AppData\Roaming\Mozilla\Firefox\profiles.ini" -Destination $Dest\$Usr\FirefoxData\profiles.ini -ErrorAction SilentlyContinue
        }

        return $true
    }

    # Function to put (restore) a user profile
    function PutProfile {
        param([string]$Usr, [string]$Repo, [string]$DestProfile)

        # Check if the repository path exists
        if (!(Test-Path $Repo)) {
            Write-Error "Invalid Repository Path: $Repo"
            return $false
        }

        if (!(Test-Path $Repo\$Usr)) {
            Write-Error "User Profile Not Found in Repository: $Repo\$Usr"
            return $false
        }

        # Get all folders from the backup (dynamically discover what was backed up)
        $BackedUpFolders = @(Get-ChildItem "$Repo\$Usr" -Directory -ErrorAction SilentlyContinue | 
            Where-Object { $_.Name -ne "ChromeData" -and $_.Name -ne "EdgeData" -and $_.Name -ne "FirefoxData" } |
            Select-Object -ExpandProperty Name)
        
        # Build list of folders to paste, starting with RootFolders if it exists
        $FoldersToPaste = @()
        if ($BackedUpFolders -contains "RootFolders") {
            $FoldersToPaste += "RootFolders\*"
        }
        # Add all other folders from the backup
        $FoldersToPaste += $BackedUpFolders | Where-Object { $_ -ne "RootFolders" }

        Write-Host "Pasting Home Folder Files"
        Get-ChildItem "$Repo\$Usr\RootFolders" -File -ErrorAction SilentlyContinue | ForEach-Object {
            Copy-Item "$Repo\$Usr\RootFolders\$_" -Destination "$SystemDrive\Users\$DestProfile\" -ErrorAction SilentlyContinue
        }

        # Paste each folder back to the destination user profile
        $FoldersToPaste | ForEach-Object {
            if ([string]$_ -eq "RootFolders\*") {
                Write-Host "Pasting Home Folder Folders"
            }
            else {
                Write-Host "Pasting $_ Folder"
            }
            PasteFiles "$Repo" "$_"
        }

        # Terminate any running browser processes to ensure data integrity
        $CurrentProcesses = @((Get-CimInstance win32_process -computername $env:COMPUTERNAME -ErrorAction SilentlyContinue | Select-Object ProcessName).ProcessName)
        if ($CurrentProcesses.Contains("chrome.exe") -or $CurrentProcesses.Contains("msedge.exe") -or $CurrentProcesses.Contains("firefox.exe")) {
            Get-Process -Name chrome -ErrorAction SilentlyContinue | Stop-Process -Force
            Get-Process -Name msedge -ErrorAction SilentlyContinue | Stop-Process -Force
            Get-Process -Name firefox -ErrorAction SilentlyContinue | Stop-Process -Force
            Start-Sleep -Milliseconds 500
        }

        # Paste browser data
        if (Test-Path $Repo\$Usr\ChromeData\Default) {
            Write-Host "Pasting Chrome Data Folder"
            if (Test-Path "$SystemDrive\Users\$DestProfile\AppData\Local\Google\Chrome\User Data\Default") {
                Remove-Item "$SystemDrive\Users\$DestProfile\AppData\Local\Google\Chrome\User Data\Default" -Force -Recurse
            }
            Copy-Item $Repo\$Usr\ChromeData\Default "$SystemDrive\Users\$DestProfile\AppData\Local\Google\Chrome\User Data\Default" -Force -Recurse -ErrorAction SilentlyContinue
        }

        Write-Host "Pasting Edge Data Folder"
        if (Test-Path "$SystemDrive\Users\$DestProfile\AppData\Local\Microsoft\Edge\User Data\Default") {
            Remove-Item "$SystemDrive\Users\$DestProfile\AppData\Local\Microsoft\Edge\User Data\Default" -Force -Recurse
        }
        Copy-Item $Repo\$Usr\EdgeData\Default "$SystemDrive\Users\$DestProfile\AppData\Local\Microsoft\Edge\User Data\Default" -Force -Recurse -ErrorAction SilentlyContinue

        if (Test-Path $Repo\$Usr\FirefoxData\Profiles) {
            Write-Host "Pasting Firefox Data Folder"
            if (Test-Path "$SystemDrive\Users\$DestProfile\AppData\Roaming\Mozilla\Firefox\Profiles") {
                Remove-Item "$SystemDrive\Users\$DestProfile\AppData\Roaming\Mozilla\Firefox\Profiles" -Force -Recurse
                Remove-Item "$SystemDrive\Users\$DestProfile\AppData\Roaming\Mozilla\Firefox\profiles.ini" -Force
            }
            Copy-Item $Repo\$Usr\FirefoxData\Profiles "$SystemDrive\Users\$DestProfile\AppData\Roaming\Mozilla\Firefox\Profiles" -Force -Recurse -ErrorAction SilentlyContinue
            Copy-Item $Repo\$Usr\FirefoxData\profiles.ini "$SystemDrive\Users\$DestProfile\AppData\Roaming\Mozilla\Firefox\profiles.ini" -ErrorAction SilentlyContinue
        }

        return $true
    }

    # Rename parameters for internal use
    $Dest = $RepositoryPath

    # Define built-in profiles to exclude
    $BuiltInProfiles = @("Administrator", "Default", "DefaultAccount", "Guest", "Public", "WDAGUtilityAccount")

    # Validate mode and parameters
    switch ($Mode) {
        'Copy' {
            # Validate copy parameters
            if ([string]::IsNullOrWhiteSpace($RepositoryPath)) {
                Write-Error "RepositoryPath is required for Copy mode"
                return $false
            }

            # Create repository path if it doesn't exist
            if (!(Test-Path $RepositoryPath)) {
                New-Item -Path $RepositoryPath -ItemType Directory -Force | Out-Null
            }

            # Get all profiles and filter out built-in ones
            $AllProfiles = @(Get-ChildItem "$SystemDrive\Users" | Where-Object { $_.PSIsContainer } | Select-Object -ExpandProperty Name)
            $ProfilesToBackup = @($AllProfiles | Where-Object { $_ -notin $BuiltInProfiles })

            if ([string]::IsNullOrWhiteSpace($SourceProfile)) {
                # If no specific profile provided, backup all non-built-in profiles
                if ($ProfilesToBackup.Count -eq 0) {
                    Write-Error "No user profiles found to backup"
                    return $false
                }

                Write-Host "Backing up all non-built-in profiles: $($ProfilesToBackup -join ', ')"
                $allSuccess = $true

                foreach ($profile in $ProfilesToBackup) {
                    Write-Host "---"
                    Write-Host "Backing up profile: $profile"
                    $Usr = $profile
                    $result = TakeProfile $profile $RepositoryPath $Force
                    if (!$result) {
                        $allSuccess = $false
                        Write-Warning "Failed to backup profile: $profile"
                    }
                }

                if ($allSuccess) {
                    Write-Host "All profile backups completed successfully"
                }
                return $allSuccess
            }
            else {
                # Specific profile provided
                if (!($ProfilesToBackup.Contains($SourceProfile))) {
                    Write-Error "Source profile '$SourceProfile' not found or is a built-in profile"
                    return $false
                }

                # Perform the backup
                $Usr = $SourceProfile
                $result = TakeProfile $SourceProfile $RepositoryPath $Force
                if ($result) {
                    Write-Host "Profile backup completed successfully"
                }
                return $result
            }
        }

        'Paste' {
            # Validate paste parameters
            if ([string]::IsNullOrWhiteSpace($SourceProfile)) {
                Write-Error "SourceProfile is required for Paste mode"
                return $false
            }

            if ([string]::IsNullOrWhiteSpace($RepositoryPath)) {
                Write-Error "RepositoryPath is required for Paste mode"
                return $false
            }

            if ([string]::IsNullOrWhiteSpace($DestinationProfile)) {
                Write-Error "DestinationProfile is required for Paste mode"
                return $false
            }

            # Validate destination profile exists
            $ValidDestProfiles = @(Get-ChildItem "$SystemDrive\Users" | Where-Object { $_.PSIsContainer } | Select-Object -ExpandProperty Name)
            if (!($ValidDestProfiles.Contains($DestinationProfile))) {
                Write-Error "Destination profile '$DestinationProfile' not found in $SystemDrive\Users"
                return $false
            }

            # Perform the restore
            $result = PutProfile $SourceProfile $RepositoryPath $DestinationProfile
            if ($result) {
                Write-Host "Profile restore completed successfully"
            }
            return $result
        }

        default {
            Write-Error "Invalid Mode: $Mode. Use 'Copy' or 'Paste'"
            return $false
        }
    }
}
