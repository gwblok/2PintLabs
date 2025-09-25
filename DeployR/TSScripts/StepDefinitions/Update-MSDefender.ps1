# Adding Support for DeployR Task Sequence Variables
try {
    Import-Module DeployR.Utility
    Write-Host "DeployR.Utility module loaded successfully" -ForegroundColor Green
    
}
catch {
    Write-Warning "Failed to load DeployR.Utility module: $($_.Exception.Message)"
    Write-Warning "This script requires the DeployR Task Sequence environment"
}

#Get the Task Sequence Environment Variables
if (Get-Module -Name "DeployR.Utility") {
    $DefenderPlatform =       ${TSEnv:DefenderPlatform}
    $DefenderDefinitions =     ${TSEnv:DefenderDefinitions}
    
}

#Write out all Vars
Write-Host "==============================================================="
Write-Host "DefenderPlatform:           $DefenderPlatform" -ForegroundColor Cyan
Write-Host "DefenderDefinitions:        $DefenderDefinitions" -ForegroundColor Cyan
Write-Host "==============================================================="


function Test-WebConnection {
    [CmdletBinding()]
    param (
    [Parameter(Mandatory = $true)]
    [string]$Uri,
    [int]$TimeoutMs = 5000
    )
    
    # Ensure the URI has a protocol (default to https if none specified)
    if (-not $Uri.StartsWith('http://') -and -not $Uri.StartsWith('https://')) {
        $Uri = "https://$Uri"
    }
    
    try {
        # Use Invoke-WebRequest for a simpler and more reliable HTTP request
        $request = Invoke-WebRequest -Uri $Uri -TimeoutSec ($TimeoutMs / 1000) -UseBasicParsing -ErrorAction Stop
        if ($request.StatusCode -eq 200) {
            Write-Verbose "Successfully connected to $Uri. Status code: $($request.StatusCode)"
            return $true
        } else {
            Write-Verbose "Connected to $Uri but received unexpected status code: $($request.StatusCode)"
            return $false
        }
    }
    catch {
        Write-Verbose "Failed to connect to $Uri. Error: $($_.Exception.Message)"
        return $false
    }
}
function Test-WindowsUpdateEnvironment {
    [CmdletBinding()]
    param (
    [int]$TimeoutSeconds = 30
    )
    
    # Check if network is available (max $TimeoutSeconds)
    $networkReady = $false
    for ($i = 0; $i -lt $TimeoutSeconds; $i++) {
        if (Test-WebConnection -Uri 'www.microsoft.com') {
            $networkReady = $true
            break
        }
        Start-Sleep -Seconds 1
    }
    if (-not $networkReady) {
        Write-Warning "Network is not available after waiting. Skipping Windows Update."
        return $false
    }
    
    # Ensure Windows Update service is running (max $TimeoutSeconds)
    # This is important to avoid COMException 0x80240438 when calling Microsoft.Update.Session
    $serviceReady = $false
    for ($i = 0; $i -lt $TimeoutSeconds; $i++) {
        $service = Get-Service -Name wuauserv -ErrorAction SilentlyContinue
        if ($service) {
            if ($service.Status -eq 'Running') {
                $serviceReady = $true
                break
            }
            elseif ($service.Status -eq 'Stopped') {
                try {
                    Start-Service -Name wuauserv -ErrorAction Stop
                    Write-Output "Windows Update service was stopped. Attempting to start it..."
                } catch {
                    Write-Warning "Failed to start Windows Update service: $($_.Exception.Message)"
                }
            }
        }
        Start-Sleep -Seconds 1
    }
    
    if (-not $serviceReady) {
        Write-Warning "Windows Update service is not running. Skipping Windows Update."
        return $false
    }
    
    return $true
}

function Update-MSDefender {
    [CmdletBinding()]
    param (
    [string]$DefenderPlatform = "True",
    [string]$DefenderDefinitions = "True"
    )
    if (Test-WindowsUpdateEnvironment) {
        # Source Addresses - Defender for Windows 10, 8.1 ################################
        $sourceAVx64 = "http://go.microsoft.com/fwlink/?LinkID=121721&arch=x64"
        $sourcePlatformx64 = "https://go.microsoft.com/fwlink/?LinkID=870379&clcid=0x409&arch=x64"
        Write-Output "UPDATE Defender Package Script version $ScriptVer..."
        $Intermediate = "$env:TEMP\DefenderScratchSpace"
        if (!(Test-Path -Path "$Intermediate")) {
            $Null = New-Item -Path "$env:TEMP" -Name "DefenderScratchSpace" -ItemType Directory
        }
        
        if (!(Test-Path -Path "$Intermediate\x64")) {
            $Null = New-Item -Path "$Intermediate" -Name "x64" -ItemType Directory
        }
        Remove-Item -Path "$Intermediate\x64\*" -Force -EA SilentlyContinue
        $wc = New-Object System.Net.WebClient
        
        # x64 AV #########################################################################
        if ($DefenderDefinitions -eq "True") {
            Write-Output "Starting Defender Definitions Update"
            $Dest = "$Intermediate\x64\" + 'mpam-fe.exe'
            Write-Output "Starting MPAM-FE Download"
            $wc.DownloadFile($sourceAVx64, $Dest)
            if (Test-Path -Path $Dest) {
                $x = Get-Item -Path $Dest
                [version]$Version1a = $x.VersionInfo.ProductVersion #Downloaded
                [version]$Version1b = (Get-MpComputerStatus).AntivirusSignatureVersion #Currently Installed
                if ($Version1a -gt $Version1b) {
                    Write-Output "Starting MPAM-FE Install of $Version1b to $Version1a"
                    $MPAMInstall = Start-Process -FilePath $Dest -Wait -PassThru
                }
                else {
                    Write-Output "No Update Needed, Installed:$Version1b vs Downloaded: $Version1a"
                }
                Write-Output "Finished MPAM-FE Install"
            }
            else {
                Write-Output "Failed MPAM-FE Download"
            }
            Write-Output "Finished Defender Definitions Update"
        }
        else {
            Write-Output "Skipping Defender Definitions Update"
        }
        
        # x64 Update Platform ########################################################################
        if ($DefenderPlatform -eq "True") {
            Write-Output "Starting Defender Platform Update"
            Write-Output "Starting Update Platform Download"
            $Dest = "$Intermediate\x64\" + 'UpdatePlatform.exe'
            $wc.DownloadFile($sourcePlatformx64, $Dest)
            
            if (Test-Path -Path $Dest) {
                $x = Get-Item -Path $Dest
                [version]$Version2a = $x.VersionInfo.ProductVersion #Downloaded
                [version]$Version2b = (Get-MpComputerStatus).AMServiceVersion #Installed
                
                if ($Version2a -gt $Version2b) {
                    Write-Output "Starting Update Platform Install of $Version2b to $Version2a"
                    $UPInstall = Start-Process -FilePath $Dest -Wait -PassThru
                }
                else {
                    Write-Output "No Update Needed, Installed:$Version2b vs Downloaded: $Version2a"
                }
                Write-Output "Finished Update Platform Install"
            }
            else {
                Write-Output "Failed Update Platform Download"
            }
        }
    }
    else {
        Write-Output "No Internet Connection, Skipping Defender Updates"
    }
}
Update-MSDefender -DefenderPlatform $DefenderPlatform -DefenderDefinitions $DefenderDefinitions