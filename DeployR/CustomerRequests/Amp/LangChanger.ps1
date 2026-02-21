# Parameters
Param(
    [switch]$ApplyAfterReboot,
    [switch]$IsSecondRun,
    [int]$externalRun
)

function Get-RegionInfo($Name='*')
{
    $cultures = [System.Globalization.CultureInfo]::GetCultures('InstalledWin32Cultures')

	foreach($culture in $cultures)
	{
   		try{
       		$region = [System.Globalization.RegionInfo]$culture.Name

            if($region.Name -like $Name)
            {
                $region
            }
   		}
   		catch {}
     }
}

Import-Module DeployR.Utility

$WantedLang = ${TSEnv:WantedLang}

#Fetch OSDisk
$OSDriveLetter = "$($env:SystemDrive)"

$CABsDownloaded = Get-ChildItem -Path "C:\WINDOWS\TEMP\LangPacks" -Filter *.cab -Recurse

<#
if (!($ApplyAfterReboot)) {
    Write-Host "$($MyInvocation.MyCommand.Name): Searching for language package(s)"
}
#>

if (!($CABsDownloaded)){

    Write-Host "$($MyInvocation.MyCommand.Name): Searching for language package(s) for language $WantedLang"

    #Setup language pack path
    $WorkingDir = ${TSEnv:Content-Content}
    $BaseLanguagePath = "PSDResources\LanguagePacks"
    $SourceLanguagePackagePath = ($BaseLanguagePath + "\" + ("Win11") + "\" + ("23H2"))


    if((Test-PSDContent -content $BaseLanguagePath )){
        if (!($ApplyAfterReboot) -or !($CABsDownloaded)) {

            try {New-Item -Name "LangPacks" -Path "$($OSDriveLetter)\WINDOWS\TEMP\" -ItemType Directory} catch{}

            Write-Host "$($MyInvocation.MyCommand.Name): Found language pack under $SourceLanguagePackagePath "
            Write-Host "$($MyInvocation.MyCommand.Name): Lets download all language packs for $WantedLang from $SourceLanguagePackagePath "
    
            $MainLanguagePack = Test-PSDContent -content $BaseLanguagePath | where-object { $_.Name -match $WantedLang -and $_.Name -match "x64" -and ($_.Name -match "Language-Pack" )}
            $LanguagePackFileName = $MainLanguagePack.href | Split-Path -Leaf

            $AllOtherLanguageStuffs = Test-PSDContent -content $BaseLanguagePath | Where-Object { $_.Name -match $WantedLang -and ($_.Name -match "LanguageFeatures" -or $_.Name -match "MSPaint" -or $_.Name -match "Notepad" -or $_.Name -match "SnippingTool" -or $_.Name -match "WirelessDisplay" -or $_.Name -match "WordPad") }# | Select-Object Name

            if ($AllOtherLanguageStuffs) {try {New-Item -Name "OtherLanguageStuffs" -Path "$($OSDriveLetter)\WINDOWS\TEMP\LangPacks\" -ItemType Directory} catch{}}

            Show-PSDActionProgress -Message "Downloading main language pack for language: $($WantedLang)" -Step "1" -MaxStep "1"
            Write-Host "$($MyInvocation.MyCommand.Name): Downloading $LanguagePackFileName to Win TEMP "

            if ($env:SYSTEMDRIVE -eq "X:") {

                $MainLanguagePackDownloaded = Get-ChildItem -Path "$($OSDriveLetter)\WINDOWS\TEMP\LangPacks" -Filter $LanguagePackFileName -Recurse
                if (!($MainLanguagePackDownloaded)) {
                    Write-Host "$($MyInvocation.MyCommand.Name): Using WebClient to download $LanguagePackFileName "
                    $wc.DownloadFile($MainLanguagePack.href, "$($OSDriveLetter)\WINDOWS\TEMP\LangPacks\$LanguagePackFileName")

                }
            }
            else {
                $MainLanguagePackDownloaded = Get-ChildItem -Path "$($OSDriveLetter)\WINDOWS\TEMP\LangPacks" -Filter $LanguagePackFileName -Recurse
                if (!($MainLanguagePackDownloaded)) {
                    Write-Host "$($MyInvocation.MyCommand.Name): Using BITS to download $LanguagePackFileName "
                    $bitsJob = Start-BitsTransfer -Authentication Ntlm -Credential $global:psddsCredential -Source $MainLanguagePack.href -Destination "$($OSDriveLetter)\WINDOWS\TEMP\LangPacks\$LanguagePackFileName" -TransferType Download -DisplayName "PSD Transfer" -Priority High
                }
            }

            $Step = 0
            [UInt32]$Steps = $AllOtherLanguageStuffs.count

            Write-Host "$($MyInvocation.MyCommand.Name): Found a total of $Steps extra language packs "

            foreach ($OtherLanguageThing in $AllOtherLanguageStuffs) {
                $Step++

                Show-PSDActionProgress -Message "Downloading other language pack(s) for language: $($WantedLang)" -Step $Step -MaxStep $Steps
                $OtherLanguageThingFileName = $OtherLanguageThing.href | Split-Path -Leaf
                Write-Host "$($MyInvocation.MyCommand.Name): Downloading $OtherLanguageThingFileName to Win TEMP "

                if ($env:SYSTEMDRIVE -eq "X:") {
                    $OtherLanguageThingDownloaded = Get-ChildItem -Path "$($OSDriveLetter)\WINDOWS\TEMP\LangPacks" -Filter $OtherLanguageThingFileName -Recurse
                    if (!($OtherLanguageThingDownloaded)) {
                        Write-Host "$($MyInvocation.MyCommand.Name): Using WebClient to download $OtherLanguageThingFileName "
                        $wc.DownloadFile($OtherLanguageThing.href, "$($OSDriveLetter)\WINDOWS\TEMP\LangPacks\OtherLanguageStuffs\$OtherLanguageThingFileName")
                    }
                }
                else {

                    $OtherLanguageThingDownloaded = Get-ChildItem -Path "$($OSDriveLetter)\WINDOWS\TEMP\LangPacks" -Filter $OtherLanguageThingFileName -Recurse
                    if (!($OtherLanguageThingDownloaded)) {
                        Write-Host "$($MyInvocation.MyCommand.Name): Using BITS to download $OtherLanguageThingFileName "
                        $bitsJob = Start-BitsTransfer -Authentication Ntlm -Credential $global:psddsCredential -Source $OtherLanguageThing.href -Destination "$($OSDriveLetter)\WINDOWS\TEMP\LangPacks\OtherLanguageStuffs\$OtherLanguageThingFileName" -TransferType Download -DisplayName "PSD Transfer" -Priority High
                    }
                }
            }
        } #end if (!($ApplyAfterReboot) -or !($CABsDownloaded))
    } #end if((Test-PSDContent -content $BaseLanguagePath ))
    else {
        Write-Host "$($MyInvocation.MyCommand.Name): Couldn't access $BaseLanguagePath. Something up with the connection to the deploymentshare "
    }
} #end if (!($CABsDownloaded))
else {
    if (!($ApplyAfterReboot)) {
        Write-Host "$($MyInvocation.MyCommand.Name): Language files already downloaded. Proceeding to install them in full OS "
    }
}


if ($env:SYSTEMDRIVE -eq "X:") {
            
    if (!($LanguagePackFileName)) {
        $MainLanguagePack = Test-PSDContent -content $BaseLanguagePath | where-object { $_.Name -match $WantedLang -and $_.Name -match "x64" -and ($_.Name -match "Language-Pack" )}
        $LanguagePackFileName = $MainLanguagePack.href | Split-Path -Leaf
    }

    Write-Host "$($MyInvocation.MyCommand.Name): Installing $LanguagePackFileName to offline full OS "
    Add-WindowsPackage -Path "$($OSDriveLetter)\" -PackagePath "$($OSDriveLetter)\WINDOWS\TEMP\LangPacks\$LanguagePackFileName" -LogPath "$($OSDriveLetter)\WINDOWS\TEMP\LangPacks\$($LanguagePackFileName).log"
    #dism.exe /image:$($OSDriveLetter)\ /add-package /packagePath:"$($OSDriveLetter)\WINDOWS\TEMP\LangPacks\$LanguagePackFileName" /scratchdir:$($OSDriveLetter)\Windows\temp

    Show-PSDActionProgress -Message "Applying other language pack(s) for language: $($WantedLang)" -Step "1" -MaxStep "1"
    Write-Host "$($MyInvocation.MyCommand.Name): Installing all other lang packs to offline full OS "
    Add-WindowsPackage -Path "$($OSDriveLetter)\" -PackagePath "$($OSDriveLetter)\WINDOWS\TEMP\LangPacks\OtherLanguageStuffs" -IgnoreCheck -LogPath "$($OSDriveLetter)\WINDOWS\TEMP\LangPacks\OtherLanguageThings.log"
} #end if ($env:SYSTEMDRIVE -eq "X:")
else {
     
    $AllInstalledPacks = Get-WindowsPackage -Online 
    $MainPackAlreadyInstalled = $AllInstalledPacks | Where-Object { $_.PackageName -match $WantedLang -and $_.PackageName -match "LanguagePack-Package"}

    if (!($MainPackAlreadyInstalled)) {

        if (!($LanguagePackFileName)) {
            $MainLanguagePack = Test-PSDContent -content $BaseLanguagePath | where-object { $_.Name -match $WantedLang -and $_.Name -match "x64" -and ($_.Name -match "Language-Pack" )}
            $LanguagePackFileName = $MainLanguagePack.href | Split-Path -Leaf
        }

        Write-Host "$($MyInvocation.MyCommand.Name): Installing $LanguagePackFileName to online full OS "
        Add-WindowsPackage -Online -PackagePath "$($OSDriveLetter)\WINDOWS\TEMP\LangPacks\$LanguagePackFileName" -LogPath "$($OSDriveLetter)\WINDOWS\TEMP\LangPacks\$($LanguagePackFileName).log"
    }

    if (!($ApplyAfterReboot) -and !($MainPackAlreadyInstalled)) { 
        # Assuming all other language packs also got installed if main one was a success.
        Show-PSDActionProgress -Message "Applying other language pack(s) for language: $($WantedLang)" -Step "1" -MaxStep "1"
        Write-Host "$($MyInvocation.MyCommand.Name): Installing all other lang packs to online full OS "
        Add-WindowsPackage -Online -PackagePath "$($OSDriveLetter)\WINDOWS\TEMP\LangPacks\OtherLanguageStuffs" -IgnoreCheck -LogPath "$($OSDriveLetter)\WINDOWS\TEMP\LangPacks\OtherLanguageThings.log"
    }
}


if ($ApplyAfterReboot -and (-not $IsSecondRun)) {
    Write-Host "$($MyInvocation.MyCommand.Name): Languages installed, lets apply them to the OS. "
}
    
if ($env:SYSTEMDRIVE -ne "X:") {

    $attempt = if (-not $externalRun -or $externalRun -lt 1) {0} else { $externalRun }
    $maxAttempts = 3
    $langMismatch = $true

    $AllLangInfo = Get-RegionInfo -Name $WantedLang

    do {
        if ($attempt -is [int]) { $attempt++ }
        $langMismatch = $false

        Write-Host "$($MyInvocation.MyCommand.Name): Language configuration attempt #$attempt"

        Set-WinSystemLocale -SystemLocale $WantedLang
        Set-WinUILanguageOverride -Language $WantedLang
        Set-WinUserLanguageList -LanguageList $WantedLang -Force
        Set-Culture "$WantedLang"
        Set-SystemLanguage -Language $WantedLang
        Set-SystemPreferredUILanguage -Language $WantedLang -ErrorAction SilentlyContinue
        Set-WinHomeLocation -GeoId $AllLangInfo.GeoId

        Copy-UserInternationalSettingsToSystem -WelcomeScreen $True -NewUser $True

        # Launch a new PowerShell session to rerun this script
        if (-not $IsSecondRun) {
            Write-Host "$($MyInvocation.MyCommand.Name): Launching new session to verify changes..."
            $scriptPath = $MyInvocation.MyCommand.Path
            Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" -IsSecondRun -ApplyAfterReboot -externalRun $attempt" -WindowStyle Hidden -Wait
            break
        }

        $WantedBaseLang = $WantedLang.Split("-")[0].ToLowerInvariant()

        $values = @(
            @{ Name = "WinSystemLocale"; Value = (Get-WinSystemLocale).Name },
            @{ Name = "WinUILanguageOverride"; Value = (Get-WinUILanguageOverride).Name },
            @{ Name = "Culture"; Value = (Get-Culture).Name },
            @{ Name = "SystemLanguage"; Value = (Get-SystemLanguage) },
            @{ Name = "SystemPreferredUILanguage"; Value = (Get-SystemPreferredUILanguage) }
        )

        foreach ($item in $values) {
            $lang = $item.Value.ToString().ToLowerInvariant()
            if ($lang -ne $WantedLang -and $lang -ne $WantedBaseLang) {
                Write-Host "$($MyInvocation.MyCommand.Name): Setting [$($item.Name)] is [$lang] — expected [$WantedLang] or [$WantedBaseLang]."
                $langMismatch = $true
            }
        }

        $userLangs = Get-WinUserLanguageList
        if (-not ($userLangs.LanguageTag | Where-Object { $_.ToLowerInvariant().StartsWith($WantedBaseLang) })) {
            Write-Host "$($MyInvocation.MyCommand.Name): User language list still missing [$WantedLang] or [$WantedBaseLang]."
            $langMismatch = $true
        }

        if (-not $langMismatch) {
            Write-Host "$($MyInvocation.MyCommand.Name): All language settings now match $WantedLang. Great stuff!"
        }

    } while ($langMismatch -and $attempt -lt $maxAttempts)

    if ($langMismatch) {
        Write-Host "$($MyInvocation.MyCommand.Name): Language settings did not fully apply after $maxAttempts attempts. Falling back to try and download and install language pack from internet."
        Install-Language $WantedLang
        Set-SystemPreferredUILanguage $WantedLang
    }
} #end if ($env:SYSTEMDRIVE -ne "X:")
else {
    Write-Host "$($MyInvocation.MyCommand.Name): Language packages downloaded and installed to offline full OS. PE phase completed."
}

Save-PSDVariables | Out-Null

<#
Get-WinSystemLocale
Get-WinHomeLocation
Get-WinUILanguageOverride
Get-WinUserLanguageList
Get-Culture
Get-SystemPreferredUILanguage
Get-SystemLanguage
#>

