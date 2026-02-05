function Import-DriverPack {
    param (
    [parameter(Mandatory=$true)]
    [string]$MakeAlias,
    [parameter(Mandatory=$true)]
    [string]$ModelAlias,
    [parameter(Mandatory=$true)]
    [string]$InputSourceFolder, #Downloaded Extracted Driver Pack Source Folder
    [string]$DeployRModulePath ='C:\Program Files\2Pint Software\DeployR\Client\PSModules\DeployR.Utility'
    )
    
    if (-not $InputSourceFolder) {
        Write-Error "InputSourceFolder is a required parameter. Exiting."
        Write-Host "Please provide a local InputSourceFolder path where the driver pack is already extracted." -ForegroundColor Yellow
        return
    }
    
    #Ensure Source Folder exists
    if (-not (Test-Path $InputSourceFolder)) {
        Write-Error "Source Folder $InputSourceFolder does not exist. Exiting."
        return
    }
    Import-Module $DeployRModulePath


    Write-Host "  Source Path: $InputSourceFolder"
    if (Get-DeployRContentItem | Where-Object {$_.Name -eq "Driver Pack - $MakeAlias - $ModelAlias"}){
        Write-Host "  Driver Pack Content Item already exists for $MakeAlias - $ModelAlias" -ForegroundColor Yellow
    }
    else {
        Write-Host "  Driver Pack Content Item does not exist for $MakeAlias - $ModelAlias. Creating new one."
        #Download the Driver Pack
        if ($InputSourceFolder -and (Test-Path $InputSourceFolder)) {
            Write-Host "  Using provided Input Source Folder: $InputSourceFolder"
        }
        
        #Create DeployR Content Item for the Driver Pack
        
        $NewCI = New-DeployRContentItem -Name "Driver Pack - $MakeAlias - $ModelAlias" -Type Folder -Purpose DriverPack -Description "Generated for $MakeAlias - $ModelAlias"
        $ContentId = $NewCI.id
        $NewVersion = New-DeployRContentItemVersion -ContentItemId $ContentId -Description "Source: $InputSourceFolder" -DriverManufacturer $MakeAlias -DriverModel $ModelAlias -SourceFolder "$InputSourceFolder"
        $ContentVersion = $NewVersion.versionNo
        #Upload the extracted driver pack to the DeployR Content Item
        write-Host "  Uploading extracted Driver Pack to DeployR Content Item"
        try {
            $ciVersion = update-DeployRContentItemContent -ContentId $ContentId -ContentVersion $ContentVersion -SourceFolder "$InputSourceFolder"
            write-Host "  Successfully uploaded Driver Pack content to DeployR!  Content Item Info:" -ForegroundColor Green
            write-Host "    CI driverManufacturer:   $($ciVersion.driverManufacturer)" -ForegroundColor DarkGray
            write-Host "    CI driverModel:          $($ciVersion.driverModel)" -ForegroundColor DarkGray
            write-Host "    CI ID:                   $($ciVersion.contentItemId), Version: $($ciVersion.versionNo)" -ForegroundColor DarkGray
            write-Host "    CI path:                 $($ciVersion.relativePath)" -ForegroundColor DarkGray
            write-Host "    CI Status:               $($ciVersion.status)" -ForegroundColor DarkGray
            write-Host "    CI Size:                 $([math]::round($ciVersion.contentSize / 1MB, 2)) MB" -ForegroundColor DarkGray
        }
        catch {
            Write-Error "  Failed to upload Driver Pack content to DeployR Content Item for $MakeAlias - $ModelAlias. Error: $_"
        }
    }
}