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
