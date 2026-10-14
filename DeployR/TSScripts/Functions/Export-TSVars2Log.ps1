<# 
This script exports selected TS variables and values to Export-TSVars2Log.log.

What it does is grab the VARS, then creates a header based on the TS Name and UUID, then creates a message body with all the other variables and values. 
Some internal or sensitive variables (such as progress and token variables) are excluded below; adjust the filter as needed.

I have the step definition script pasted below for reference, it is not needed, just was nice to know what was happening so I could do manual tests.

HOW TO USE:
Add this script as a PowerShell step where you want to capture the current TS variables.
Each run appends a timestamped snapshot to the DeployR logs folder (or TEMP if unavailable).

#>


#Get all TS Vars
$Vars = Get-ChildItem -path tsenv: 

$LogFolder = Join-Path $env:SystemDrive "_2P\Logs"
if (-not (Test-Path -Path $LogFolder)){
    $LogFolder = $env:TEMP
}

if (-not (Test-Path -LiteralPath $LogFolder -PathType Container)) {
    New-Item -Path $LogFolder -ItemType Directory -Force | Out-Null
}

#Grab the progress variable to get the TS Name and UUID for the header of the message, then remove it from the Vars list so it doesn't get sent to Teams.
$TSProgressJSON = ($Vars | Where-Object {$_.Name -eq '_DEPLOYRPROGRESS'}).value | ConvertFrom-Json
$TSName = $TSProgressJSON.Name
$TSUUID = $TSProgressJSON.UUID

#Select only the Vars to include in the log.
$subVars = $Vars | Where-Object { 
    $_.Name -notlike '_DEPLOYRPROGRESS*' -and
    $_.Name -notlike '_DEPLOYRTASKSEQUENCERUN*' -and
    $_.Name -notlike '_SEQUENCESTATE*' -and
    $_.Name -notlike 'DEPLOYRCLIENTPASSCODE*' -and
    $_.Name -notlike 'DEPLOYRCOMPLETEDSTEPS*' -and
    $_.Name -notlike 'DEPLOYRTOKEN*' -and
    $_.Name -notlike '_CI_*' -and
    $_.Name -notlike '_CIV_*' -and
    $_.Name -notlike 'SCRIPT*'
}

# Append a readable snapshot instead of creating another task-sequence variable.
$LogPath = Join-Path $LogFolder 'Export-TSVars2Log.log'
$LogLines = @(
    "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Task Sequence: $TSName | UUID: $TSUUID"
    ($subVars | ForEach-Object { '{0} = {1}' -f $_.Name, $_.Value })
    ''
)
Add-Content -LiteralPath $LogPath -Value $LogLines -Encoding UTF8
Write-Host "Task sequence variables written to $LogPath"