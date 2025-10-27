#Connect to DeployR
try {
    Import-Module DeployR.Utility
}
catch {}
if (Get-Module -name "DeployR.Utility"){
    # Get the provided variables

    [String]$TargetSystemDrive = ${TSEnv:OSDTARGETSYSTEMDRIVE}
    [String]$LogPath = ${TSEnv:_DEPLOYRLOGS}
    [String]$MakeAlias = ${TSEnv:MakeAlias}
    [String]$Make = ${TSEnv:Make}
    [String]$ModelAlias = ${TSEnv:ModelAlias}
}
else {
    <#Do this if a terminating exception happens#>
    [String]$TargetSystemDrive = "C:"
    [String]$LogPath = "C:\Windows\Temp\"
    $Gather = iex (irm gather.garytown.com)
    [String]$MakeAlias = $Gather.MakeAlias
    [String]$Make = $Gather.Make
    [String]$ModelAlias = $Gather.ModelAlias
}


if ($ModelAlias -eq "Virtual Machine") {
    Write-Host "ModelAlias is Virtual Machine, exiting script."
    Exit 0
}

write-host "==================================================================="
write-host "Migrate WinPE Drivers for $MakeAlias $ModelAlias"

#region functions


function Migrate-WinPEDrivers {
    [CmdletBinding()]
    param(
    [string]$OfflineOSPath
    )
    
    $startTime = Get-Date
    $WindowsPath = $OfflineOSPath
    
    function timeDuration() {
        $totalSeconds = [int]$args[0]
        if ($totalSeconds -gt 0) { $time = New-TimeSpan -Seconds $totalSeconds }
        else { $time = New-TimeSpan -Seconds 600 }
        if ($time.Hours -gt 0) {
            if ($time.Hours -eq 1) { $output += "$($time.Hours) Hour" }
            else { $output += "$($time.Hours) Hours" }
        }
        if ($time.Minutes -gt 0) { 
            if ($time.Minutes -eq 1) { $output += " $($time.Minutes) Minute" } 
            else { $output += " $($time.Minutes) Minutes" }
        }
        if ($time.Seconds -gt 0) { 
            if ($time.Seconds -eq 1) { $output += " $($time.Seconds) Second" }
            else { $output += " $($time.Seconds) Seconds" }
        } 
        $output
    }
    
    Write-Host "Grabbing all the drivers..."
    $windrivers = Get-WindowsDriver -Online
    $runningDrivers = Get-CimInstance -ClassName win32_systemdriver | Where-Object State -eq 'Running'
    Write-Host "Found $($windrivers.Count) imported drivers and $($runningDrivers.Count) running drivers"
    
    $matchedDrivers = [System.Collections.Generic.List[PSCustomObject]]::new()
    Write-Host "Starting match driver process..."
    foreach ($run in $runningDrivers) {
        $runName = $run.Name                       # e.g. "iaStorVD"
        $runPath = $run.PathName                   # e.g. X:\Windows\System32\drivers\iaStorVD.sys
        $baseNoExt = [IO.Path]::GetFileNameWithoutExtension($runPath)
        
        # get the hash of the running .sys file
        $runHash = (Get-FileHash -Path $runPath -Algorithm SHA256).Hash
        
        # Find all packages for this driver base name
        $candidates = $windrivers | Where-Object {
            [IO.Path]::GetFileNameWithoutExtension($_.CatalogFile) -ieq $baseNoExt
        }
        $foundOne = $false
        foreach ($pkg in $candidates) {
            # Derive the driver‐store folder from the INF path
            $storeFolder = Split-Path -Path $pkg.OriginalFileName
            
            # Build the path to the .sys in that folder
            $candidateSys = Join-Path $storeFolder ("$baseNoExt.sys")
            if (-not (Test-Path $candidateSys)) {
                Write-Host "Skipping $($pkg.CatalogFile) - no SYS file at $candidateSys" -Severity 2
                continue
            }
            
            try {
                $candHash = (Get-FileHash -Path $candidateSys -Algorithm SHA256).Hash
            }
            catch {
                Write-Host "ERROR: Could not hash $candidateSys : $_" -Severity 3
                continue
            }
            
            
            if (Test-Path $candidateSys) {
                $candHash = (Get-FileHash -Path $candidateSys -Algorithm SHA256).Hash
                #We are doing a hash match as different versions of the same driver can be imported
                if ($candHash -eq $runHash) {
                    # WOW! (hubble reference)
                    $matchedDrivers.Add([PSCustomObject]@{
                        DriverName       = $runName
                        DriverPath       = $runPath
                        CatalogFile      = $pkg.CatalogFile
                        OriginalFileName = $pkg.OriginalFileName
                        ClassName        = $pkg.ClassName
                        ClassGuid        = $pkg.ClassGuid
                    })
                    Write-Host "Matched $runName -> $($pkg.CatalogFile) (store = $storeFolder)"
                    $foundOne = $true
                    break
                }
            }
        }
        # You can uncomment this line for extreme verbose messages, but typically not needed
        # if (-not $foundOne) {
        #     Write-Host "WARNING: No hash match found for $runName among $($candidates.Count) candidates" -Severity 2
        # }
    }
    if ($matchedDrivers.Count -eq 0) {
        Write-Host "ERROR: No matched drivers at all. Exiting script." -Severity 3
        exit 0
    }
    Write-Host "Completing matching imported and running drivers. Found $($matchedDrivers.count) matched drivers total."
    ${TSEnv:DriverMigrateCount} = $($matchedDrivers.count)
    # set up drivers folder
    $exportRoot = "$($env:SystemDrive)\ExportedDrivers"
    
    # create it if it doesn't already exist
    if (-not (Test-Path $exportRoot)) {
        Write-Host "Creating $exportRoot to export drivers"
        New-Item -Path $exportRoot -ItemType Directory | Out-Null
    }
    Write-Host "Starting export process for injection"
    foreach ($m in $matchedDrivers) {
        # OriginalFileName is the path to the .inf in its DriverStore folder
        $storeFolder = Split-Path -Path $m.OriginalFileName
        
        # pull just the leaf folder name (i.e. "iastorvd.inf_amd64_da06297c4b8e9167")
        $leafName = Split-Path -Path $storeFolder -Leaf
        $destFolder = Join-Path $exportRoot $leafName
        
        # copy the entire folder 
        Copy-Item -Path $storeFolder -Destination $destFolder -Recurse -Force
        Write-Host "Copied $storeFolder -> $destFolder"
    }
    
    Write-Host "Starting DISM injection: /Image:$WindowsPath /Add-Driver /Driver:$exportRoot /Recurse"
    $Output = "$env:systemdrive\_2p\Logs\DISMMigrateDriversOutput.txt"
    $DISM = Start-Process DISM.EXE -ArgumentList "/image:$($WindowsPath)\ /Add-Driver /driver:$exportRoot /recurse" -PassThru -NoNewWindow -RedirectStandardOutput $Output
    #& Dism /Image:$WindowsPath /Add-Driver /Driver:$exportRoot /Recurse
    $SameLastLine = $null
    do {  #Continous loop while DISM is running
        Start-Sleep -Milliseconds 300
        
        #Read in the DISM Logfile
        $Content = Get-Content -Path $Output -ReadCount 1
        $LastLine = $Content | Select-Object -Last 1
        if ($LastLine){
            if ($SameLastLine -ne $LastLine){ #Only continue if DISM log has changed
                $SameLastLine = $LastLine
                Write-Output $LastLine
                if ($LastLine -match "Searching for driver packages to install..."){
                    #Write-Output $LastLine
                    Write-Progress -Activity "Migrating Drivers" -Status $LastLine -PercentComplete 5
                }
                elseif ($LastLine -match "Installing"){
                    #Write-Output $LastLine
                    $Message = $Content | Where-Object {$_ -match "Installing"} | Select-Object -Last 1
                    if ($Message){
                        $ToRemove = $Message.Split(':') | Select-Object -Last 1
                        $Message = $Message.Replace(":$($ToRemove)","")
                        $Message = $Message.Replace($exportRoot,"")
                        $Total = (($Message.Split("-")[0]).Split("of") | Select-Object -Last 1).replace(" ","")
                        $Counter = ((($Message.Split("-")[0]).Split("of") | Select-Object -First 1).replace(" ","")).replace("Installing","")
                        if ($Counter -eq "0"){$Counter = 1}
                        $Total = $Total + 1 #So that when it gets to 3 of 3, it doesn't show 100% complete while it is still installing
                        $PercentComplete = [math]::Round(($Counter / $Total) * 100)
                        Write-Progress -Activity "Migrating Drivers" -Status $LastLine -PercentComplete $PercentComplete
                        
                    }
                }
                elseif ($LastLine -match "The operation completed successfully."){
                    Write-Progress -Activity "Migrating Drivers" -Status $LastLine -Completed
                }
                else{
                    Write-Progress -Activity "Migrating Drivers" -Status $LastLine -Completed
                }
            }
        }
        
    }
    until (!(Get-Process -Name DISM -ErrorAction SilentlyContinue))
    
    Write-Output "Dism Step Complete"
    Write-Output "See DISM log for more Details: $Output"
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: DISM exited with $LASTEXITCODE" -Severity 3
    }
    else {
        Write-Host "DISM injection completed successfully."
    }
    $endTime = Get-Date
    $ScriptDuration = timeDuration $((New-TimeSpan -Start $startTime -End $endTime).TotalSeconds)
    $ScriptDuration = $ScriptDuration.Trim()
    Write-Output "Total export process took: $ScriptDuration"
    
}
#endregion

#_______________________________________________________________________________________#
# Doing Stuff Now...

#Region migrate active drivers from WinPE into Full OS
Write-Host "Attempting to Migrate WInPE Drivers to Offline OS as fallback"
if ($env:SystemDrive -eq "X:"){
    Migrate-WinPEDrivers -OfflineOSPath "$($TargetSystemDrive)\"
} else {
    Write-Host "Not currently in WinPE, exiting script."
    Exit 0
}
#endregion
