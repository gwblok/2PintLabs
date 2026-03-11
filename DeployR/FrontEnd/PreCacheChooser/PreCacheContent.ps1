#THIS SCRIPT MUST BE RUN AFTER YOU RUN THE FRONTEND SCRIPT, it relies on the output of the form results from the frontend script to know what content to pre-cache. It will read the form results from a JSON file that the frontend script creates in the logs folder.

# THIS SCRIPT requires the "Run PowerShell Script" step and can be called by name or embedded.

#region Functions
Function Test-URLExists {
    param (
    [string]$URL
    )
    try {
        $request = [System.Net.WebRequest]::Create($URL)
        $request.Method = "HEAD"
        $response = $request.GetResponse()
        $response.Close()
        return $true
    }
    catch {
        return $false
    }
}
#endregion Functions

try {
    Import-Module DeployR.Utility -ErrorAction SilentlyContinue
    $Global:LogFolderPath = ${TSEnv:_DEPLOYRLOGS}
}
catch {
}

# Start up the logs paths for DeployR / ConfigMgr or Local Testing
if (!($Global:LogFolderPath)) {
    if ($env:SystemDrive -eq "X:") {
        if (!(Test-Path -Path "$env:SystemDrive\_2P")) {
            $Global:LogFolderPath = "$env:temp\Logs"
            Write-Output "System Drive is X:, and _2P folder not found. Log Path set to $Global:LogFolderPath"
        }
        else {
            $Global:LogFolderPath = "$env:SystemDrive\_2P\Logs"
            Write-Output "System Drive is X:, Log Path set to $Global:LogFolderPath"
        }
    }
    else {
        # Prefer user-writable temp folder to avoid permission issues when not elevated
        if ($env:TEMP) {
            $Global:LogFolderPath = Join-Path -Path $env:TEMP -ChildPath 'DeployRLogs'
            Write-Output "Using TEMP folder for logs: $Global:LogFolderPath"
        }
        elseif (Test-Path -Path 'C:\Windows\Temp') {
            $Global:LogFolderPath = 'C:\Windows\Temp\DeployRLogs'
            Write-Output "Using Windows Temp folder for logs: $Global:LogFolderPath"
        }
    }
}

#Import of FormResults from PreCacheChooser Form
$jsonPath = Join-Path -Path $Global:LogFolderPath -ChildPath "FrontendFormResults.json"
if (Test-Path -Path $jsonPath) {
    Write-Host "Loading form results from $jsonPath" -ForegroundColor Green
    $FormResults = Get-Content -Path $jsonPath | ConvertFrom-Json
}
else {
    Write-Host "Error: Form results file not found at $jsonPath" -ForegroundColor Red
    exit 1
}

#Start Pre-Caching of selected items based on $FormResults

#Boot Media First
#Region Boot Media Pre-Cache
if ($FormResults.PreCacheAllBootImages -eq $true){
    # Process a list of static files for Boot Images
    $BootImagefiles = @("boot.sdi",
    "winpe_amd64.wim",
    "winpe_arm64.wim",
    "x64/initrd.img",
    "x64/shimx64.efi",
    "x64/squashfs.img",
    "x64/vmlinuz"
    )
    $count = 0
    Foreach ($file in $BootImagefiles) {
        $count++
        $bootID = "BC$($count.ToString("D3"))"
        $sourceURI = "${TSEnv:DeployRHost}/Content/Boot/$file"
        if (-not (Test-URLExists -URL $sourceURI)) {
            Write-Host "Warning: Boot file not found at $sourceURI" -ForegroundColor Yellow
        }
        else{
            Write-Host "Caching boot file $file from $sourceURI" -ForegroundColor Green
            $destFile = Request-DeployRCustomContent -ContentName $bootID -ContentFriendlyName "Boot file: $file" -URL $sourceURI
        }
        
    }
}
#endregion Boot Media Pre-Cache

#Region Operating Systems Pre-Cache
if ($FormResults.SelectedOperatingSystems -and $FormResults.SelectedOperatingSystems.Count -gt 0) {
    foreach ($ContentItem in $FormResults.SelectedOperatingSystems) {
        Write-Host "Pre-caching operating system: $($ContentItem.Name) (ID: $($ContentItem.ContentItemId))" -ForegroundColor Green
        $destFile = Request-DeployRContent -ContentName $ContentItem.name -ContentItemId $ContentItem.ContentItemId -ContentItemVersion $ContentItem.versionNo -ErrorAction SilentlyContinue
    }
}
#endregion Operating Systems Pre-Cache

#Region Driver Packs Pre-Cache
if ($FormResults.SelectedDriverPacks -and $FormResults.SelectedDriverPacks.Count -gt 0) {
    foreach ($ContentItem in $FormResults.SelectedDriverPacks) {
        Write-Host "Pre-caching driver pack: $($ContentItem.Name) (ID: $($ContentItem.ContentItemId))" -ForegroundColor Green
        $destFile = Request-DeployRContent -ContentName $ContentItem.name -ContentItemId $ContentItem.ContentItemId -ContentItemVersion $ContentItem.versionNo -ErrorAction SilentlyContinue
    }
}
#endregion Driver Packs Pre-Cache

#Region Other Pre-Cache
if ($FormResults.SelectedOther -and $FormResults.SelectedOther.Count -gt 0){
    foreach ($ContentItem in $FormResults.SelectedOther) {
        Write-Host "Pre-caching item: $($ContentItem.Name) (ID: $($ContentItem.ContentItemId))" -ForegroundColor Green
        $destFile = Request-DeployRContent -ContentName $ContentItem.name -ContentItemId $ContentItem.ContentItemId -ContentItemVersion $ContentItem.versionNo -ErrorAction SilentlyContinue
    }
}
#endregion Other Pre-Cache

#Region Applications Pre-Cache
if ($FormResults.SelectedApplications -and $FormResults.SelectedApplications.Count -gt 0){
    foreach ($ContentItem in $FormResults.SelectedApplications) {
        Write-Host "Pre-caching application: $($ContentItem.Name) (ID: $($ContentItem.ContentItemId))" -ForegroundColor Green
        $destFile = Request-DeployRContent -ContentName $ContentItem.name -ContentItemId $ContentItem.ContentItemId -ContentItemVersion $ContentItem.versionNo -ErrorAction SilentlyContinue
    }
}
#endregion Applications Pre-Cache