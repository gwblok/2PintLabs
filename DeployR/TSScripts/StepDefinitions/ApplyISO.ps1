Write-Host "ApplyISO"

Import-Module DeployR.Utility

$continueMethod = ${TSEnv:ContinueMethod}


#$Server2025EvalURL = "https://go.microsoft.com/fwlink/?linkid=2293312&clcid=0x409&culture=en-us&country=us"
$Server2025EvalURL = "https://software-static.download.prss.microsoft.com/dbazure/888969d5-f34g-4e03-ac9d-1f9786c66749/26100.1742.240906-0331.ge_release_svc_refresh_SERVER_EVAL_x64FRE_en-us.iso"
# Download the specified file
Write-Host "Downloading from: $Server2025EvalURL"
$osWIM = Request-DeployRCustomContent -ContentName "OSISO" -ContentFriendlyName "Windows Server 2025 Standard Eval" -URL $Server2025EvalURL
$GetItemOutFile = Get-Item $osWIM
$ISOPath = $GetItemOutFile.FullName

# Mount the ISO and Get the Drive Letter
#$ISOPath = "C:\Users\GaryBlok\Downloads\26100.1742.240906-0331.ge_release_svc_refresh_SERVER_EVAL_x64FRE_en-us.iso"
$MountISO = Mount-DiskImage -ImagePath $ISOPath -PassThru -Access ReadOnly

# Get the volume object for the mounted ISO
$CDROM = $MountISO | Get-Volume

# Check if the current drive letter is not 'I' and change it if needed
if ($CDROM.DriveLetter -ne 'I') {
    # Change the drive letter to I:

	# Get the CD-ROM drive
	# Specify the current drive letter of the mounted ISO (replace 'D:' with the actual drive letter)
	$currentDriveLetter = 'D:'

	# Get the volume using Get-CimInstance
	$volume = Get-CimInstance -Query "SELECT * FROM Win32_Volume WHERE DriveLetter = '$currentDriveLetter'"

	# Check if the volume was found
	if ($null -eq $volume) {
		Write-Output "No volume found with drive letter $currentDriveLetter"
		exit
	}

	# Change the drive letter to 'I:'
	$volume | Set-CimInstance -Arguments @{DriveLetter = 'I:'}

	# Confirm the new drive letter
	$updatedVolume = Get-CimInstance -Query "SELECT * FROM Win32_Volume WHERE DriveLetter = 'I:'"
	if ($updatedVolume) {
		Write-Output "The volume is now mounted with drive letter: I:"
	} else {
		Write-Output "Failed to change the drive letter to I:"
	}
}

#Report the WIM info
$osWIM = "I:\sources\install.wim"
Get-WindowsImage -ImagePath $osWIM 

# Apply the image *Server Standard Desktop Experience* to S:\
Write-Host "Applying image to path S:\"
$null = Expand-WindowsImage -ImagePath $osWIM -Index 2 -ApplyPath "S:\"
$tsenv:OSDTargetSystemDrive = "S:"

# Get additional information about the image and put it into TS variables
$osImage = Get-WindowsImage -ImagePath $osWIM -Index 2
$tsenv:OSImageName = $osImage.ImageName
$tsenv:OSImageVersion = $osImage.Version
$tsenv:OSImageBuild = ([version]$osImage.Version).Build
$tsenv:OSImageUBR = ([version]$osImage.Version).Revision
$tsenv:OSImageEditionId = $osImage.EditionId
$tsenv:OSImageLanguages = $osImage.Languages
switch ($osImage.Architecture)
{
	5 { $tsenv:OSImageArchitecture = "x86" }
	9 { $tsenv:OSImageArchitecture = "x64" }
	12 { $tsenv:OSImageArchitecture = "arm64" }
}

# Override the method if the unattend.xml does not exist
if ($continueMethod -eq "0" -and ${TSEnv:Content-Unattend} -eq "") {
	Write-Host "No unattend.xml specified, will default to using SetupComplete.cmd"
	$continueMethod = "1"
}

$null = MkDir "S:\Windows\Panther\Unattend" -Force
switch ($continueMethod) {
	"0" {
		# Use provided unattend.xml

		# Copy the unattend.xml provided to the correct location
		$unattend = Join-Path -Path ${TSEnv:Content-Unattend} -ChildPath ${TSEnv:ContentFile-Unattend}
		Write-Host "Copying $unattend to S:\Windows\Panther\Unattend"
		Copy-Item $unattend "S:\Windows\Panther\Unattend\Unattend.xml"
	}
	"1" {
		# Use SetupComplete.cmd

		# Copy the template SetupComplete.cmd file to the correct location
		Write-Host "Copying template SetupComplete.cmd to S:\Windows\Setup\Scripts"
		$null = MkDir "S:\Windows\Setup\Scripts" -Force
		Copy-Item ".\SetupComplete.cmd" "S:\Windows\Setup\Scripts\SetupComplete.cmd"

		# Copy a default unattend.xml template
		Write-Host "Copying template Unattend_SetupComplete.xml to S:\Windows\Panther\Unattend"
		Copy-Item ".\Unattend_SetupComplete.xml" "S:\Windows\Panther\Unattend\Unattend.xml"
	}
	"2" {
		# Use specialize phase

		# Copy a default unattend.xml template
		Write-Host "Copying template Unattend_Specialize.xml to S:\Windows\Panther\Unattend"
		Copy-Item ".\Unattend_Specialize.xml" "S:\Windows\Panther\Unattend\Unattend.xml"
	}
	"3" {
		# Use AutoAdminLogon

		# Copy a default unattend.xml template
		Write-Host "Copying template Unattend_Autologon.xml to S:\Windows\Panther\Unattend"
		Copy-Item ".\Unattend_Autologon.xml" "S:\Windows\Panther\Unattend\Unattend.xml"
	}
	"4" {
		# No unattend

		# Nothing to do
		Write-Host "No unattend.xml will be used, OOBE will not be automated"
	}
	"5" {
		# Use Audit mode

		# Copy a default unattend.xml template
		Write-Host "Copying template Unattend_Audit.xml to S:\Windows\Panther\Unattend"
		Copy-Item ".\Unattend_Audit.xml" "S:\Windows\Panther\Unattend\Unattend.xml"
	}

}

# Process the Unattend to substitute in variables
if ($continueMethod -ne "4") {

	# Set some defaults
	$tsenv:ProcessorArchitecture = ($env:PROCESSOR_ARCHITECTURE).ToLower()
	$defaults = Get-Content ".\Defaults.json" | ConvertFrom-Json
	$defaults.PSObject.Properties | ForEach-Object {
		$current = (Get-Item -Path "tsenv:$($_.Name)").Value
		if ($current -eq "") {
			$adjusted = Resolve-DeployRVariables $_.Value
			Write-Host "Setting default value for : $($_.Name)"
			Set-Item -Path "tsenv:$($_.Name)" -Value $adjusted
		}
	}

	# Edit the unattend to substitute values (raw treats it as a single string instead of an array)
	$content = Get-Content -Path "S:\Windows\Panther\Unattend\Unattend.xml" -Raw
	Resolve-DeployRVariables $content | Out-File "S:\Windows\Panther\Unattend\Unattend.xml"
}

# Make the OS bootable
Write-Host "Running BCDBoot"
& bcdboot.exe S:\Windows /s W: /f uefi /c | Out-Host
# Workaround from PSD
bcdedit.exe | Out-Host
