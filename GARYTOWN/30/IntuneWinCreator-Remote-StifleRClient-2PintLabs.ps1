#Gary Blok



#Build App Intune Installer
$IntuneAppRootPath = "C:\2Pint\IntuneWin\AppUtil"

#Path to App Folder you want to Convert
$SourceAppPathRoot = "C:\2Pint\IntuneWin\input"

#++++++++++++++++++++++++++
#!!!Change These!!!
$SourceAppPath = "$SourceAppPathRoot\Extracted"
#$LatestSourceAppPath = Get-ChildItem -Path $SourceAppPath | Where-Object {$_.Attributes -eq "Directory"} | sort-object -Property LastWriteTime -Descending | Select-Object -First 1
#$SourceAppPath = ($LatestSourceAppPath).FullName
#++++++++++++++++++++++++++

$JSONContent = Invoke-RestMethod -Uri "https://raw.githubusercontent.com/gwblok/2PintLabs/refs/heads/main/GARYTOWN/StifleR-ClientApp.json"
$settingsConfigURL = 'https://raw.githubusercontent.com/gwblok/2PintLabs/refs/heads/main/GARYTOWN/30/dr2pintlabs.2psImport'
$CMD = @"
msiexec /i StifleR-ClientApp-x64.msi AUTOSTART=1 OPTIONS="settings.2psImport" /quiet /l*v "C:\Windows\Temp\StifleRClientInstall.log"
"@
$StifleR30 = $JSONContent | Where-Object {$_.Version -like "3.0*"} | Select-Object -First 1
$StifleR30URL = $StifleR30.URL
$OutputAppPath = $SourceAppPath.Replace("Agent","AgentIntune")
$IntuneUtilFolderPath = "$IntuneAppRootPath\Microsoft-Win32-Content-Prep-Tool"
$IntuneUtilPath = "$IntuneUtilFolderPath\IntuneWinAppUtil.exe"
$IntuneUtilURL = "https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool/raw/master/IntuneWinAppUtil.exe"
#https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool/blob/master/IntuneWinAppUtil.exe




#Test Folder Structure and Build if needed
if (!(Test-Path -Path $SourceAppPath)){
    New-item -Path $SourceAppPath -ItemType Directory -Force | Out-Null
    Write-Host "Created $SourceAppPath" -ForegroundColor Green
    Write-Host "Place your SOURCE HERE!!!" -ForegroundColor Red
}
else {
    Write-Host "Using Source: $SourceAppPath" -ForegroundColor Green
}

if (!(Test-Path -Path $OutputAppPath)){
    New-item -Path $OutputAppPath -ItemType Directory -Force | Out-Null
    Write-Host "Created $OutputAppPath" -ForegroundColor Green
}
else {
    Write-Host "Using Output: $OutputAppPath" -ForegroundColor Green
}

if (!(Test-Path -Path $IntuneUtilFolderPath)){
    New-item -Path $IntuneUtilFolderPath -ItemType Directory -Force | Out-Null
    Write-Host "Created $IntuneUtilFolderPath" -ForegroundColor Green
}
else {
    Write-Host "Using IntuneUtilFolder: $IntuneUtilFolderPath" -ForegroundColor Green
}
if (!(Test-Path -Path $IntuneUtilPath)){
    Invoke-WebRequest -UseBasicParsing -Uri $IntuneUtilURL -OutFile $IntuneUtilPath
    Write-Host "Downloaded IntuneWinAppUtil.exe to $IntuneUtilPath" -ForegroundColor Green
}
else{
    Write-Host "Using IntuneWinAppUtil: $IntuneUtilPath" -ForegroundColor Green
}

#Do Stuff
Write-Host "Downloading StifleR 3.0 from $StifleR30URL" -ForegroundColor Green
Invoke-WebRequest -Uri $StifleR30URL -OutFile "$SourceAppPathRoot\StifleR-ClientApp.zip"
#Download settings.2psImport
Invoke-WebRequest -Uri $settingsConfigURL -OutFile "$SourceAppPath\settings.2psImport"
#Create the CMD file for install
$CMDPath = "$SourceAppPath\Install.cmd"
$CMD | Out-File -FilePath $CMDPath -Encoding ASCII
#Extract ZIP
Expand-Archive -Path "$SourceAppPathRoot\StifleR-ClientApp.zip" -DestinationPath $SourceAppPath -Force

#Get Latest MSI
$MSI = Get-ChildItem -Path $SourceAppPath -Filter *.msi
if ($MSI) {
    $WindowsInstaller = New-Object -ComObject WindowsInstaller.Installer
    $Database = $WindowsInstaller.OpenDatabase($MSI.FullName, 0)
    $View = $Database.OpenView("SELECT Value FROM Property WHERE Property = 'ProductCode'")
    $View.Execute()
    $Record = $View.Fetch()
    if ($Record) {
        $ProductCode = $Record.StringData(1)
        Write-Output "Product Code: $ProductCode"
    } else {
        Write-Output "Product Code not found."
    }
    $View.Close()
    [System.Runtime.Interopservices.Marshal]::ReleaseComObject($WindowsInstaller) | Out-Null
} else {
    Write-Output "No MSI file found."
}

$App = get-item -Path $SourceAppPath
$SetupCMD = Get-ChildItem -Path $App.FullName -Filter *.cmd
if (!($SetupCMD)){
    $SetupEXE = Get-ChildItem -Path $App.FullName -Filter *.exe
    if (!($SetupEXE)){$SetupEXE = Get-ChildItem -Path $App.FullName -Filter *.msi}
}
else {
    $SetupEXE = $SetupCMD
}
$SetupFolder = $App.FullName
#$CreateIntuneApp = Start-Process -FilePath $IntuneUtilPath -ArgumentList "-c $SetupFolder -s $SetupEXEPath -o $OutPutPath -q" -Wait -PassThru
Write-Host "Starting Intune Package Creation" -ForegroundColor Green
write-Host "& $IntuneUtilPath -c $SetupFolder -s $($SetupEXE.FullName) -o $OutputAppPath -q"
& $IntuneUtilPath -c $SetupFolder -s $SetupEXE.FullName -o $OutputAppPath -q

Write-Host "Finished App for Intune: $OutputAppPath" -ForegroundColor Green
if ($MSI){Write-Output "Product Code: $ProductCode"}