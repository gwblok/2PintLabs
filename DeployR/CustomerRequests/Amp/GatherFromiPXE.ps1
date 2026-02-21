$iPXEExtraFilePath = "X:\Windows\System32\iPXEExtraFile.bin"
if (Test-Path $iPXEExtraFilePath) {
    Write-Host "Gathering information from iPXE file $iPXEExtraFilePath" -ForegroundColor Cyan
    Import-Module DeployR.Utility
    $AllBootInfo = Import-csv $iPXEExtraFilePath
    $WantedLang = $AllBootInfo.Lang
    ${TSEnv:WantedLang} = $WantedLang
}
else {
    Write-Host "iPXE file $iPXEExtraFilePath not found." -ForegroundColor Red
    #If Nothing Set, Set Lang to sv-SE as default for testing
    ${TSEnv:WantedLang} = "sv-SE"
}
