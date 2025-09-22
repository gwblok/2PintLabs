# Requires -Version 7.0
# Requires -RunAsAdministrator



#Region Declaration
$ModulePath = 'C:\Program Files\2Pint Software\DeployR\Client\PSModules\DeployR.Utility'

#Set-DeployRHost "http://localhost:7282"

#Import Content for Steps
$DownloadPath = "D:\DeployRGitHubImports" #Update this path to your desired download location for the source before it's imported.
$DownloadStepsPath = "$DownloadPath\CustomSteps"
$DownloadTSModulesPath = "$DownloadPath\TaskSequences"
#EndRegion


#Region Functions
Function Get-DeployRStepsFromGitHub {<#
.SYNOPSIS
    Downloads DeployR CustomSteps from GitHub repository and imports them into DeployR
    
.DESCRIPTION
    This script downloads the contents of the DeployR CustomSteps folder from the GitHub repository
    and prepares them for import into DeployR. It uses the GitHub API to enumerate folder contents
    and downloads each file to a local directory.
    
.PARAMETER DownloadPath
    Local path where the CustomSteps will be downloaded. Defaults to current directory + CustomSteps
    
.PARAMETER GitHubRepo
    GitHub repository in format "owner/repo". Defaults to "gwblok/2PintLabs"
    
.PARAMETER GitHubPath
    Path within the repository. Defaults to "DeployR/CustomSteps"
    
.EXAMPLE
    .\DeployR-ImportFromGithub.ps1
    Downloads CustomSteps to .\CustomSteps using default parameters
    
.EXAMPLE
    .\DeployR-ImportFromGithub.ps1 -DownloadPath "C:\Temp\CustomSteps"
    Downloads CustomSteps to specified path
    #>
    
    
    param(
    [string]$DownloadPath = "D:\DeployRGitHubImports",
    [string]$GitHubRepo = "gwblok/2PintLabs",
    [string]$GitHubPath = "DeployR/CustomSteps"
    )
    
    # GitHub URLs
    $GitHubBrowseUrl = "https://github.com/$GitHubRepo/tree/main/$GitHubPath"
    $GitHubApiUrl = "https://api.github.com/repos/$GitHubRepo/contents/$GitHubPath"
    $GitHubRawUrl = "https://raw.githubusercontent.com/$GitHubRepo/main"
    
    Write-Host "DeployR CustomSteps GitHub Importer" -ForegroundColor Green
    Write-Host "====================================" -ForegroundColor Green
    Write-Host "Repository: $GitHubBrowseUrl" -ForegroundColor Cyan
    #Write-Host "Download Path: $((Resolve-Path $DownloadPath -ErrorAction SilentlyContinue) ?? (Join-Path (Get-Location) $DownloadPath))" -ForegroundColor Cyan
    Write-Host ""
    
    # Create download directory if it doesn't exist
    if (Test-Path $DownloadPath) {
        Write-Host "Download directory already exists: $DownloadPath" -ForegroundColor Green
        #Delete And Recreate the Directory
        Remove-Item -Path $DownloadPath -Recurse -Force
        New-Item -ItemType Directory -Path $DownloadPath -Force | Out-Null
        Write-Host "Recreated download directory: $DownloadPath" -ForegroundColor Yellow
    }
    else {
        Write-Host "Creating download directory: $DownloadPath" -ForegroundColor Yellow
        New-Item -ItemType Directory -Path $DownloadPath -Force | Out-Null
    }
    
    # Function to download file from GitHub
    function Get-GitHubFile {
        param(
        [string]$FileUrl,
        [string]$LocalPath,
        [string]$RelativePath
        )
        
        try {
            Write-Host "Downloading: $RelativePath" -ForegroundColor White
            $webClient = New-Object System.Net.WebClient
            $webClient.DownloadFile($FileUrl, $LocalPath)
            Write-Host "  -> Downloaded to: $LocalPath" -ForegroundColor Gray
            return $true
        }
        catch {
            Write-Warning "Failed to download $RelativePath : $($_.Exception.Message)"
            return $false
        }
    }
    
    # Function to recursively download directory contents
    function Get-GitHubDirectory {
        param(
        [string]$ApiUrl,
        [string]$LocalBasePath,
        [string]$RelativeBasePath = ""
        )
        
        try {
            Write-Host "Fetching directory contents from: $ApiUrl" -ForegroundColor Cyan
            $response = Invoke-RestMethod -Uri $ApiUrl -ErrorAction Stop
            
            $downloadCount = 0
            $successCount = 0
            
            foreach ($item in $response) {
                $relativePath = if ($RelativeBasePath) { "$RelativeBasePath/$($item.name)" } else { $item.name }
                $localPath = Join-Path $LocalBasePath $relativePath
                
                if ($item.type -eq "file") {
                    # Download file
                    $downloadCount++
                    $fileUrl = "$GitHubRawUrl/$GitHubPath/$relativePath"
                    
                    # Create directory if needed
                    $localDir = Split-Path $localPath -Parent
                    if (!(Test-Path $localDir)) {
                        New-Item -ItemType Directory -Path $localDir -Force | Out-Null
                    }
                    
                    if (Get-GitHubFile -FileUrl $fileUrl -LocalPath $localPath -RelativePath $relativePath) {
                        $successCount++
                    }
                }
                elseif ($item.type -eq "dir") {
                    # Recursively download subdirectory
                    Write-Host "Entering directory: $relativePath" -ForegroundColor Yellow
                    $subApiUrl = $item.url
                    $subCounts = Get-GitHubDirectory -ApiUrl $subApiUrl -LocalBasePath $LocalBasePath -RelativeBasePath $relativePath
                    $downloadCount += $subCounts.Total
                    $successCount += $subCounts.Success
                }
            }
            
            return @{ Total = $downloadCount; Success = $successCount }
        }
        catch {
            Write-Error "Failed to fetch directory contents from $ApiUrl : $($_.Exception.Message)"
            return @{ Total = 0; Success = 0 }
        }
    }
    
    # Main execution
    Write-Host "Starting download from GitHub..." -ForegroundColor Green
    
    $results = Get-GitHubDirectory -ApiUrl $GitHubApiUrl -LocalBasePath $DownloadPath
    
    Write-Host ""
    Write-Host "Download Summary:" -ForegroundColor Green
    Write-Host "=================" -ForegroundColor Green
    Write-Host "Total files: $($results.Total)" -ForegroundColor White
    Write-Host "Successfully downloaded: $($results.Success)" -ForegroundColor Green
    Write-Host "Failed downloads: $($results.Total - $results.Success)" -ForegroundColor $(if ($results.Total - $results.Success -eq 0) { "Green" } else { "Red" })
    
    if ($results.Success -gt 0) {
        Write-Host ""
        Write-Host "CustomSteps have been downloaded to: $DownloadPath" -ForegroundColor Green
        Write-Host ""
        Write-Host "Next Steps for DeployR Import:" -ForegroundColor Yellow
        Write-Host "1. Open DeployR Management Console" -ForegroundColor White
        Write-Host "2. Navigate to Custom Steps" -ForegroundColor White
        Write-Host "3. Import the downloaded CustomSteps from: $DownloadPath" -ForegroundColor White
        Write-Host "4. Each subdirectory typically represents a separate custom step" -ForegroundColor White
        Write-Host ""
        
        # List downloaded items
        if (Test-Path $DownloadPath) {
            $items = Get-ChildItem $DownloadPath -Directory | Sort-Object Name
            if ($items.Count -gt 0) {
                Write-Host "Downloaded CustomSteps:" -ForegroundColor Cyan
                foreach ($item in $items) {
                    Write-Host "  - $($item.Name)" -ForegroundColor White
                }
            }
        }
    }
    else {
        Write-Warning "No files were successfully downloaded. Please check your internet connection and try again."
    }
    
    Write-Host ""
    Write-Host "Script completed." -ForegroundColor Green
    
}
#EndRegion Functions

#Region Execution
# Check PowerShell version
if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Error "This script requires PowerShell 7 or higher. Current version: $($PSVersionTable.PSVersion)"
    exit 1
}
# Check for Administrator role
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "This script must be run as Administrator."
    exit 1
}

if (Test-Path -Path $ModulePath) {
    Write-Host "Module found at: $ModulePath" -ForegroundColor Green
    Import-Module $ModulePath
} else {
    Write-Error "Module not found at: $ModulePath"
    exit 1
}

<# for Import Reference
dir c:\temp\ContentBackup -File | Import-DeployRContentItem 
dir c:\temp\StepDefinitionBackup -File | Import-DeployRStepDefinition 
dir c:\temp\TaskSequenceBackup -File | Import-DeployRTaskSequence
#>

#Download the Steps from GitHub

try {
    Get-DeployRStepsFromGitHub -DownloadPath $DownloadStepsPath
    Get-DeployRStepsFromGitHub -DownloadPath $DownloadTSModulesPath -GitHubPath "DeployR/CustomTaskSequenceModules"
}
catch {
    Write-Error "Failed to download steps from GitHub: $_"
    exit 0
}
#Get Steps info from the Download Path but Exclude the ReferencedContent folder 
if (Test-Path -Path "$DownloadStepsPath\ReferencedContent") {
    Get-ChildItem -Path "$DownloadStepsPath\ReferencedContent" -Directory  | ForEach-Object {
        $StepFolder = $_.FullName
        Write-Host "Importing Custom Step from: $StepFolder" -ForegroundColor Cyan
        Get-ChildItem -path $StepFolder -File | Where-Object {$_.Extension -eq ".json"} | ForEach-Object {
            $StepFile = $_.FullName           
            $StepJSON = Get-Content -Path $StepFile -Raw | ConvertFrom-Json
            write-host "Checking if step definition already exists: $StepFile" -ForegroundColor Yellow
            if (Get-DeployRContentItem -Id $StepJSON.id -ErrorAction SilentlyContinue) {
                Write-Host "Content item already exists: $($StepJSON.name) | $($StepJSON.id)" -ForegroundColor Yellow
                $SourcePath = Join-Path -Path $StepFolder -ChildPath (Get-ChildItem $StepFolder -Directory).Name
                $ContentVersions = Get-ChildItem -Path $SourcePath -Directory
                foreach ($version in $ContentVersions) {
                    Write-Host "Updating content item version: $($version.Name)" -ForegroundColor Cyan
                    Update-DeployRContentItemContent -ContentId $StepJSON.id -SourceFolder $version.FullName -ContentVersion $version.Name
                }
            } else {
                Write-Host "Importing step definition from file: $StepFile" -ForegroundColor Yellow
                Import-DeployRContentItem -SourceFile $StepFile
            }
        }
    }
}

#Import Steps
Get-ChildItem -Path $DownloadStepsPath -Directory | Where-Object {$_.Name -ne "ReferencedContent"} | ForEach-Object {
    $StepFolder = $_.FullName
    Write-Host "Importing Custom Step from: $StepFolder" -ForegroundColor Cyan
    Get-ChildItem -path $StepFolder -File | Where-Object {$_.Extension -eq ".json"} | ForEach-Object {
        $StepFile = $_.FullName
        $StepJSON = Get-Content -Path $StepFile -Raw | ConvertFrom-Json
        Write-Host "Importing step definition from file: $StepFile" -ForegroundColor Yellow
        Import-DeployRStepDefinition -SourceFile $StepFile -Force
    }
}

#Import Task Sequences
Get-ChildItem -Path $DownloadTSModulesPath -Directory | ForEach-Object {
    $TSFolder = $_.FullName
    Write-Host "Importing Task Sequence from: $TSFolder" -ForegroundColor Cyan
    Get-ChildItem -path $TSFolder -File | Where-Object {$_.Extension -eq ".json"} | ForEach-Object {
        $TSFile = $_.FullName
        $TSJSON = Get-Content -Path $TSFile -Raw | ConvertFrom-Json
        Write-Host "Importing task sequence from file: $TSFile" -ForegroundColor Yellow
        Import-DeployRTaskSequence -SourceFile $TSFile -Force
    }
}