#Borrowed from https://github.com/hypercube33/SCCM/blob/master/Detect_Report_Remove_1909_G3%20Scrubbed.ps1
$Global:LogFolderPath = ${TSEnv:_DEPLOYRLOGS}
$Global:LogFilePath = "$($Global:LogFolderPath)\DeployRCustomLogging.log"
$Global:LogFileSize   = "40"

function Start-CMTraceLog {
    # Checks for path to log file and creates if it does not exist
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $indexoflastslash = $Path.lastindexof('\')
    $directory = $Path.substring(0, $indexoflastslash)

    if (!(test-path -path $directory)){
        New-Item -ItemType Directory -Path $directory
    }
    else{
        # Directory Exists, do nothing    
    }
}

function Write-CMTraceLog {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [Parameter(Mandatory = $false)]
        [string]$LogPath = $($Global:LogFilePath),
            
        [Parameter()]
        [ValidateSet(1, 2, 3)]
        [int]$LogLevel = 1,

        [Parameter()]
        [string]$Component,

        [Parameter()]
        [ValidateSet('Info','Warning','Error')]
        [string]$Type
    )
    Switch ($Type) {
        Info {$LogLevel = 1}
        Warning {$LogLevel = 2}
        Error {$LogLevel = 3}
    }
    # Get Date message was triggered
    $TimeGenerated = "$(Get-Date -Format HH:mm:ss).$((Get-Date).Millisecond)+000"
    $Line = '<![LOG[{0}]LOG]!><time="{1}" date="{2}" component="{3}" context="" type="{4}" thread="" file="">'
    $LineFormat = $Message, $TimeGenerated, (Get-Date -Format MM-dd-yyyy), $Component, $LogLevel
    $Line = $Line -f $LineFormat
    # Write new line in the log file
    Add-Content -Value $Line -Path $LogPath
    # Roll log file over at size threshold
    if ((Get-Item $Global:LogFilePath).Length / 1KB -gt $Global:LogFileSize) {
        $log = $Global:LogFilePath
        Remove-Item ($log.Replace(".log", ".lo_"))
        Rename-Item $Global:LogFilePath ($log.Replace(".log", ".lo_")) -Force
    }
} 

# Start up the logs
Start-CMTraceLog -Path $Global:LogFilePath

Write-CMTraceLog -Message "=====================================================" -Type "Info" -Component "Main"
Write-CMTraceLog -Message "Starting Script..." -Type "Info" -Component "Main"
Write-CMTraceLog -Message "=====================================================" -Type "Info" -Component "Main"