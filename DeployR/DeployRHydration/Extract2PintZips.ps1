# Assumes you downloaded the items from the DeployRSuite link and placed in your Downloads folder in a folder named DeployRSuite
# Will extract all of the zip files to a new folder named Extracted, then move all of the installers to the Extracted folder and remove any empty folders and zip files

$sourceFolder = "$env:USERPROFILE\Downloads\DeployRSuite"
$targetFolder = "$env:USERPROFILE\Downloads\DeployRSuite\Extracted"

if (!(Test-Path -Path $sourceFolder)) {
    Write-Host "Source folder does not exist: $sourceFolder"
    exit
}
if (!(Test-Path -Path $targetFolder)) {
    New-Item -ItemType Directory -Path $targetFolder | Out-Null
}

#Unblock any Zip files in the source folder
Get-ChildItem -Path $sourceFolder -Filter *.zip | Unblock-File

#Extract each zip file to the target folder, creating a subfolder for each zip file based on its name
Get-ChildItem -Path $sourceFolder -Filter *.zip | ForEach-Object {
    $zipFile = $_.FullName
    $fileName = $_.Name
    $destination = Join-Path -Path $targetFolder -ChildPath $_.BaseName
    Expand-Archive -Path $zipFile -DestinationPath $destination -Force
    Write-Host "Extracted: $fileName to $destination" -ForegroundColor DarkGray
    #Confirm it Extracted Successfully by checking for the presence of the extracted folder
    if (Test-Path -Path $destination) {
        Write-Host "Successfully extracted: $fileName" -ForegroundColor Green
    } else {
        Write-Host "Failed to extract: $fileName" -ForegroundColor Red
    }
}

#Dig into the StifleR folder and extract all of the additional zip files found there to the target folder, creating subfolders for each zip file based on their names
$stifleRFolder = (Get-ChildItem -Path $targetFolder -Directory | Where-Object { $_.Name -like "StifleR*" } | Select-Object -First 1).FullName
if (Test-Path -Path $stifleRFolder) {
    Get-ChildItem -Path $stifleRFolder -Filter *.zip | ForEach-Object {
        $zipFile = $_.FullName
        $destination = Join-Path -Path $targetFolder -ChildPath $_.BaseName
        Expand-Archive -Path $zipFile -DestinationPath $destination -Force
        Write-Host "Extracted: $zipFile to $destination"
    }
} else {
    Write-Host "StifleR folder not found: $stifleRFolder"
}
#Dig into the extracted folders and move the contents to the target folder, then remove the now empty subfolders
Get-ChildItem -Path $targetFolder -Directory | ForEach-Object {
    $subFolder = $_.FullName
    Get-ChildItem -Path $subFolder -Recurse | Move-Item -Destination $targetFolder -Force
    Remove-Item -Path $subFolder -Recurse -Force
    Write-Host "Moved contents of: $subFolder to $targetFolder and removed $subFolder"
}
#Delete all .wixpdb files from the target folder
Get-ChildItem -Path $targetFolder -Filter *.wixpdb | Remove-Item

#Cleanup all empty folders from the target folder
Get-ChildItem -Path $targetFolder -Directory -Recurse | Where-Object { $_.GetFileSystemInfos().Count -eq 0 } | Remove-Item -Force

#Cleanup all .zip files from the target folder
Get-ChildItem -Path $targetFolder -Filter *.zip | Remove-Item -Force

#Move any installers from subfolders to the target folder and remove the now empty subfolders (MSI or EXE files)
Get-ChildItem -Path $targetFolder -Directory | ForEach-Object {
    $subFolder = $_.FullName
    Get-ChildItem -Path $subFolder -Filter *.exe -Recurse | Move-Item -Destination $targetFolder -Force
    Get-ChildItem -Path $subFolder -Filter *.msi -Recurse | Move-Item -Destination $targetFolder -Force
    Remove-Item -Path $subFolder -Recurse -Force
    Write-Host "Moved installers from: $subFolder to $targetFolder and removed $subFolder"
}