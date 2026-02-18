Write-Host "Install multiple apps"

Import-Module DeployR.Utility


Function Install-App {
    Write-Host "Install app"


    Import-Module DeployR.Utility

    # Get the metadta from the environment
    Write-Host "Getting application information"
    $contentItem = ConvertFrom-Json ${TSEnv:ContentMetadata-Application}
    $contentItemVersion = ConvertFrom-Json ${TSEnv:ContentVersionMetadata-Application}
    if (($null -eq $contentItemVersion.installationSuccessCodes) -or ($contentItemVersion.installationSuccessCodes -eq "")) {
        $returnCodes = "0 3010"
    } else {
        $returnCodes = $contentItemVersion.installationSuccessCodes
    }

    # Log information
    Write-Host "Installing application: $($contentItem.name)"
    Write-Host "Command line: $($contentItemVersion.installationCommandLine)"
    Write-Host "Working directory: $($contentItemVersion.installationWorkingDirectory)"
    Write-Host "Success codes: $returnCodes"

    # Figure out the working directory
    $workingDir = ${TSEnv:Content-Application}
    if ($contentItemVersion.installationWorkingDirectory) {
        # Drive letter in it?  Then it's not a relative path.  (UNC paths won't work, so we'll ignore those.)
        if ($contentItemVersion.installationWorkingDirectory -like "*:*")
        {
            $workingDir = $contentItemVersion.installationWorkingDirectory 
        } else {
            $workingDir = Join-Path $workingDir $contentItemVersion.installationWorkingDirectory 
        }
    }

    # Do we have a .intunewin file as content?  If so, we need to decrypt and extract it
    if (${TSEnv:ContentFile-Application} -like "*.intunewin") {

        # Decrypt
        $originalFile = "$workingDir\${TSEnv:ContentFile-Application}"
        Write-Host "Decrypting $originalFile"
        & "$PSScriptRoot\IntuneWinAppUtilDecoder.exe" "$originalFile" /s

        # Extract
        $newFile = $originalFile.Replace(".intunewin", ".decoded.zip")
        Write-Host "Extracting from $newFile"
        $workingDir = "${TSEnv:DeployRContent}\$($contentItem.Id).expanded"
        MkDir $workingDir -Force | Out-Null
        Expand-Archive -Path $newFile -DestinationPath $workingDir

        # Clean up decoded file
        Remove-Item $newFile -Force | Out-Null
    }
    Write-Host "Using working directory: $workingDir"
    $tsenv:WorkingDir = $workingDir

    # Execute the command line, waiting for it to finish
    Write-Host "Starting command..."
    #$process = Start-Process -FilePath "$env:COMSPEC" -ArgumentList "/c $($contentItemVersion.installationCommandLine)" -WorkingDirectory $workingDir -Wait -Passthru
    $downloader = (Get-Host).PrivateData
    # TODO: Provide a way to change the showWindow parameter, false means hide
    $replaceCommand = Resolve-DeployRVariables -Value $contentItemVersion.installationCommandLine
    $rc = $downloader.Run($replaceCommand, $workingDir, $false)
    Write-Host "Command completed, rc = $rc"
    $tsenv:WorkingDir = ""

    # Check the return codes
    $success = $false
    $returnCodes -Split " " | ForEach-Object {
        $testRc = [int]$_
        if ($rc -eq $testRc) {
            $success = $true
        }
    }
    if (-not $success) {
        throw "Application $($contentItem.name) install failed, rc = $rc"
        Write-Error ""
        return 2222
    }
    return 0

}



$continueOnAppError = ${TSEnv:ContinueOnAppError} -ieq "true"
$baseVariable = "Applications"

# First go through the REF_Applications referenced content items

$appList = ${TSEnvList:ContentVersionMetadata-REF_Applications}
if (($appList -ne $null) -and ($appList.Count -gt 0)) {
    Write-Host "Number of applications to install from REF_Applications : $($appList.Count)"
    $current = 0
    $appList | ForEach-Object {

        $current++
        $appVersion = $_ | ConvertFrom-Json
        $seq = '{0:D3}' -f $current
        $app = (Get-Item "tsenv:CONTENTMETADATA-REF_APPLICATIONS$seq").Value | ConvertFrom-Json

        # Report progress
        Write-Host "****** Processing app: $($app.Name)"
        $percent = [int]($current * 100.0 / $appList.Count)
        Write-Progress -Activity "MultiApp" -Status "Installing application: $($app.Name)" -PercentComplete $percent

        # Download the application
        $loc = Request-DeployRContent -ContentName "Application" -ContentItemId $appVersion.ContentItemId -ContentItemVersion $appVersion.VersionNo

        # Call InstallApp.ps1 to do the actual installation
        try {
            Install-App
        } catch {
            Write-Host "Error installing $($app.Name): $_"
            if (-not $continueOnAppError) {
                throw "Fatal error installing $($app.Name), terminating: $_"
            }		
        }
    }
}


# Process any dynamic list of applications

if ($baseVariable -eq "") {
	Write-Host "No dynamic app list base variable specified, exiting."
	exit 0
}

#MADE CHANGE HERE.. added .value
$appList = (Get-Item "tsenvlist:$baseVariable").Value
if ($appList.Count -eq 0) {
	Write-Host "No applications found in $baseVariable list, exiting."
	exit 0
}

Write-Host "Number of applications to install from $baseVariable : $($appList.Count)"
$current = 0
$appList | ForEach-Object {

	$current++

	# Report progress
	Write-Host "****** Processing app: $_"
	$percent = [int]($current * 100.0 / $appList.Count)
	Write-Progress -Activity "MultiApp" -Status "Installing application: $_" -PercentComplete $percent

	# Split the ID into the guid and version
	$parts = $_.Split(":")

	# Download the application
	$loc = Request-DeployRContent -ContentName "Application" -ContentItemId $parts[0] -ContentItemVersion $parts[1]
	$app = (Get-Item "tsenv:CONTENTMETADATA-APPLICATION").Value | ConvertFrom-Json

	# Call InstallApp.ps1 to do the actual installation
	try {
		Install-App
	} catch {
		Write-Host "Error installing $($app.Name): $($app.Name)"
		if (-not $continueOnAppError) {
			throw "Fatal error installing $($app.Name), terminating: $_"
		}		
	}
}
