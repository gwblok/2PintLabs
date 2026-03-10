$iPXEExtraFilePath = "X:\Windows\System32\iPXEExtraFile.bin"
if (Test-Path $iPXEExtraFilePath) {
    Write-Host "Gathering information from iPXE file $iPXEExtraFilePath" -ForegroundColor Cyan
    Import-Module DeployR.Utility
    $AllBootInfo = Import-csv $iPXEExtraFilePath
    if ($AllBootInfo) {
        Write-Host "Successfully imported iPXE information:" -ForegroundColor Green
        $AllBootInfo | Select-Object * -ExcludeProperty s1 | Format-List
        ${TSEnv:WantedLang} = $AllBootInfo.language
        #language
        if ($AllBootInfo.language -and $AllBootInfo.language.Trim() -ne "") {
            $LanguageCode = $AllBootInfo.language
            #Set Language Code to lower-case
            $LanguageCode = $LanguageCode.ToLower()
            Write-Host "Setting LANGUAGECODE to $LanguageCode" -ForegroundColor Cyan
            ${TSEnv:LANGUAGECODE} = $LanguageCode
        }
        else {
            Write-Host "Language information is missing or empty in the iPXE file." -ForegroundColor Yellow
        }
        #Computer Name
        if ($AllBootInfo.computerName -and $AllBootInfo.computerName.Trim() -ne "") {
            Write-Host "Setting Computer Name to $($AllBootInfo.computerName)" -ForegroundColor Cyan
            ${TSEnv:COMPUTERNAME} = $AllBootInfo.computerName
        }
        else {
            Write-Host "Computer Name information is missing or empty in the iPXE file." -ForegroundColor Yellow
        }
        #S1
        if ($AllBootInfo.s1 -and $AllBootInfo.s1.Trim() -ne "") {
            Write-Host "Setting S1 Passcode to (something secret)" -ForegroundColor Cyan
            ${TSEnv:S1PASSCODE} = $AllBootInfo.s1
        }
        else {
            Write-Host "S1 Passcode information is missing or empty in the iPXE file." -ForegroundColor Yellow
        }
        #Domain
        if ($AllBootInfo.domain -and $AllBootInfo.domain.Trim() -ne "") {
            Write-Host "Setting Domain to $($AllBootInfo.domain)" -ForegroundColor Cyan
            ${TSEnv:DOMAIN} = $AllBootInfo.domain
        }
        else {
            Write-Host "Domain information is missing or empty in the iPXE file." -ForegroundColor Yellow
        }
        #Group Name
        if ($AllBootInfo.groupName -and $AllBootInfo.groupName.Trim() -ne "") {
            Write-Host "Setting Group Name to $($AllBootInfo.groupName)" -ForegroundColor Cyan
            ${TSEnv:GroupName} = $AllBootInfo.groupName
        }
        else {
            Write-Host "Group Name information is missing or empty in the iPXE file." -ForegroundColor Yellow
        }
    }
    else {
        Write-Host "Failed to import iPXE information from $iPXEExtraFilePath." -ForegroundColor Red
    }
    
    
}
else {
    Write-Host "iPXE file $iPXEExtraFilePath not found." -ForegroundColor Red
    #If Nothing Set, Set Lang to it-IT as default for testing
    ${TSEnv:LANGUAGECODE} = "it-it"
    ${TSEnv:DOMAIN} = "DOMAIN"
    ${TSEnv:GroupName} = "DOMAIN - IT"
}
