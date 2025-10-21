write-Host "Installing PanasonicCommandUpdate Module"
try {
    Install-Module -Name PanasonicCommandUpdate -Force -Verbose -Scope AllUsers
}
catch {
    <#Do this if a terminating exception happens#>
}

if (Get-Module -Name PanasonicCommandUpdate) {
    $ModulePath = (Get-Module -Name PanasonicCommandUpdate).ModuleBase | Split-Path
    Write-Host "PanasonicCommandUpdate Module installed successfully. Copying Files for PS 5." -ForegroundColor Green
    Copy-Item -Path "$ModulePath\*" -Destination "$env:ProgramFiles\WindowsPowerShell\Modules\PanasonicCommandUpdate" -Recurse -Force
} else {
    Write-Host "Failed to install PanasonicCommandUpdate Module." -ForegroundColor Red
    Exit 1
}

Write-Host "Launching Panasonic Update Tool to list Updates in PowerShell v5"
Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -command Show-PanasonicUpdate -AcceptLicense" -Wait -PassThru -NoNewWindow

Write-Host "Starting Update Process for Panasonic Drivers and BIOS in PowerShell v5"
Write-Host " Logging to $env:systemdrive\_2p\Logs\PanasonicUpdateOutput.txt"
write-Host '$Updates = Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -command Install-PanasonicUpdate -AcceptLicense -Force -Verbose" -PassThru -NoNewWindow -RedirectStandardOutput $Output'
$Output = "$env:systemdrive\_2p\Logs\PanasonicUpdateOutput.txt"
$Updates = Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -command Install-PanasonicUpdate -AcceptLicense -Force -Verbose" -PassThru -NoNewWindow -RedirectStandardOutput $Output

$SameLastLine = $null
do {  #Continous loop while PSUPDATE is running
    Start-Sleep -Milliseconds 300
    
    #Read in the DISM Logfile
    $Content = Get-Content -Path $Output -ReadCount 1
    $LastLine = $Content | Select-Object -Last 1
    if ($LastLine){
        if ($SameLastLine -ne $LastLine){ #Only continue if PSUPDATE log has changed
            $SameLastLine = $LastLine
            Write-Output $LastLine
            if ($LastLine -match "Downloading catalog"){
                #Write-Output $LastLine
                $PercentComplete = 1
                Write-Progress -Activity "Updates" -Status 'Downloading catalog...' -PercentComplete $PercentComplete
            }
            elseif ($LastLine -match "Parsing") {
                $PercentComplete = 3
                Write-Progress -Activity "Updates" -Status 'Parsing XML...' -PercentComplete $PercentComplete
            }
            elseif ($LastLine -match "Scanning updates") {
                $PercentComplete = 5
                Write-Progress -Activity "Updates" -Status 'Scanning updates...' -PercentComplete $PercentComplete
            }
            elseif ($LastLine -match "Download updates") {
                $PercentComplete = 10
                Write-Progress -Activity "Updates" -Status 'Download updates...' -PercentComplete $PercentComplete
            }
            elseif ($LastLine -match "Install updates") {
                $PercentComplete = 15
                Write-Progress -Activity "Updates" -Status 'Installing updates...' -PercentComplete $PercentComplete
            }
            elseif ($LastLine -match "RebootRequired") {
                $PercentComplete = 100
                Write-Progress -Activity "Updates" -Status 'Reboot Required' -PercentComplete $PercentComplete
                Start-Sleep -Seconds 3
                break
            }
            elseif ($LastLine -match "downloading :") {
                $ToRemove = "VERBOSE:     "
                $Message = $LastLine.Replace($ToRemove,"")
                # Try to extract a counter/total such as "2 / 3" or "2 of 3" and compute a percent
                $PercentComplete = 0
                if ($Message -match '(?:Installing\s+)?(\d+)\s*/\s*(\d+)') {
                    $counter = [int]$matches[1]
                    $total = [int]$matches[2]
                    if ($total -gt 0) { $PercentComplete = [math]::Round(($counter / $total) * 100) }
                }
                elseif ($Message -match '(?:Installing\s+)?(\d+)\s*of\s*(\d+)') {
                    $counter = [int]$matches[1]
                    $total = [int]$matches[2]
                    if ($total -gt 0) { $PercentComplete = [math]::Round(($counter / $total) * 100) }
                }
                Write-Progress -Activity "Downloading Updates" -Status $Message -PercentComplete $PercentComplete
            }
            elseif ($LastLine -match "installing :") {
                $ToRemove = "VERBOSE: "
                $Message = $LastLine.Replace($ToRemove,"")
                # Try to extract a counter/total such as "2 / 3" or "2 of 3" and compute a percent
                $PercentComplete = 0
                if ($Message -match '(?:Installing\s+)?(\d+)\s*/\s*(\d+)') {
                    $counter = [int]$matches[1]
                    $total = [int]$matches[2]
                    if ($total -gt 0) { $PercentComplete = [math]::Round(($counter / $total) * 100) }
                }
                elseif ($Message -match '(?:Installing\s+)?(\d+)\s*of\s*(\d+)') {
                    $counter = [int]$matches[1]
                    $total = [int]$matches[2]
                    if ($total -gt 0) { $PercentComplete = [math]::Round(($counter / $total) * 100) }
                }
                Write-Progress -Activity "Installing Updates" -Status $Message -PercentComplete $PercentComplete
            }
            else  {
                $PercentComplete = $PercentComplete #AKA, Use the last PercentComplete value available
                $Message = $null
                Write-Progress -Activity "Panasonic Update" -Status $Message -PercentComplete $PercentComplete
            }
        }
    }
    
}
until (!(Get-Process -Id $Updates.Id -ErrorAction SilentlyContinue))