Function New-DeployRApp {
    Param (
        [string]$AppName,
        [string]$AppSourceFolder,
        [string]$AppDescription = "No Description Provided",
        [string]$InstallationCommandLine = ""
    )

    $NewDRCI = New-DeployRContentItem -Type Folder -Name $AppName -Description $AppDescription -Purpose Application
    New-DeployRContentItemVersion -ContentItemId $NewDRCI.id -SourceFolder $AppSourceFolder -InstallationCommandLine $InstallationCommandLine
}

Function Update-DeployRApp {
    Param (
        [string]$AppName,
        [string]$AppSourceFolder,
        [string]$AppDescription = "No Description Provided",
        [string]$InstallationCommandLine = ""
    )

    $DRCI = Get-DeployRContentItem -Purpose Application | Where-Object { $_.name -eq $AppName }
    if ($DRCI) {
        Write-Host "Updating application '$AppName' (ID: $($DRCI.id)) with new version from source folder '$AppSourceFolder'..." -ForegroundColor Green
        #New-DeployRContentItemVersion -ContentItemId $DRCI.id -SourceFolder $AppSourceFolder -InstallationCommandLine $InstallationCommandLine
    }
    else {
        Write-Error "Application '$AppName' not found. Cannot update non-existent application."
    }
}