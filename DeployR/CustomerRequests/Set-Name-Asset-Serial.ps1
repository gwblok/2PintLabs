function Show-InputPopup {
    <#
    .SYNOPSIS
    Displays a simple popup dialog with a question and text input field.
    
    .DESCRIPTION
    Creates a Windows Forms popup that asks a question and returns the user's text input.
    
    .PARAMETER Message
    The question or message to display in the popup.
    
    .PARAMETER Title
    The title of the popup window. Defaults to "Input Required".
    
    .PARAMETER DefaultValue
    Optional default value to pre-populate in the text box.
    
    .EXAMPLE
    $userName = Show-InputPopup -Message "What is your name?"
    Write-Host "Hello, $userName!"
    
    .EXAMPLE
    $version = Show-InputPopup -Message "Enter the version number:" -Title "Version Input" -DefaultValue "1.0.0"
    #>
    [CmdletBinding()]
    param(
    [Parameter(Mandatory)]
    [string]$Message,
    
    [Parameter()]
    [string]$Title = "Input Required",
    
    [Parameter()]
    [string]$DefaultValue = "",
    
    [Parameter()]
    [int]
    $MaxInputLength = 15
    )
    
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    
    # Create the form (narrower and shorter to reduce empty space)
    $form = New-Object System.Windows.Forms.Form
    $form.Text = $Title
    $form.Size = New-Object System.Drawing.Size(420, 260)
    $form.StartPosition = 'CenterScreen'
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.TopMost = $true
    
    # Shared font for readability
    $font = New-Object System.Drawing.Font('Segoe UI',10)
    $form.Font = $font
    
    # Create a Label for the message with padding so text has equal buffer on both sides
    $messageLabel = New-Object System.Windows.Forms.Label
    $messageLabel.Location = New-Object System.Drawing.Point(15, 10)
    $messageLabel.Size = New-Object System.Drawing.Size(390, 100)
    $messageLabel.AutoSize = $false
    $messageLabel.Text = $Message
    $messageLabel.Font = $font
    $messageLabel.Padding = New-Object System.Windows.Forms.Padding(8)
    $messageLabel.TextAlign = 'TopLeft'
    $messageLabel.AutoEllipsis = $true
    $messageLabel.BackColor = $form.BackColor
    $messageLabel.TabStop = $false
    $form.Controls.Add($messageLabel)
    
    # Create the text box (shorter and centered below the message box)
    $textBox = New-Object System.Windows.Forms.TextBox
    $textBox.Size = New-Object System.Drawing.Size(300, 24)
    $textBox.Location = New-Object System.Drawing.Point(60, 110)
    # enforce max length and pre-populate with truncated default if supplied
    if ($DefaultValue) {
        $textBox.Text = $DefaultValue.Substring(0, [Math]::Min($DefaultValue.Length, $MaxInputLength))
    } else {
        $textBox.Text = $DefaultValue
    }
    $textBox.MaxLength = $MaxInputLength
    $form.Controls.Add($textBox)
    
    # Create OK button
    $okButton = New-Object System.Windows.Forms.Button
    # Place OK and Cancel next to each other, centered under the input
    $okButton.Location = New-Object System.Drawing.Point(114, 150)
    $okButton.Size = New-Object System.Drawing.Size(90, 30)
    $okButton.Text = 'OK'
    $okButton.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $form.AcceptButton = $okButton
    $okButton.Font = $font
    $form.Controls.Add($okButton)
    
    # Create Cancel button
    $cancelButton = New-Object System.Windows.Forms.Button
    # place Cancel next to OK (centered)
    $cancelButton.Location = New-Object System.Drawing.Point(216, 150)
    $cancelButton.Size = New-Object System.Drawing.Size(90, 30)
    $cancelButton.Text = 'Cancel'
    $cancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $form.CancelButton = $cancelButton
    $cancelButton.Font = $font
    $form.Controls.Add($cancelButton)
    
    # Set focus to text box
    $form.Add_Shown({ $textBox.Select() })
    
    # Show the form and return the result
    $result = $form.ShowDialog()
    
    if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
        return $textBox.Text
    }
    else {
        return $null
    }
}

function Build-ComputerName {
    <#
    .SYNOPSIS
    Builds a ComputerName from Asset Tag and Serial Number.
    
    .DESCRIPTION
    Retrieves the Asset Tag and Serial Number from CIM and constructs a ComputerName
    in the format AssetTag-SerialPart, ensuring it does not exceed 15 characters.
    
    .OUTPUTS
    String - The proposed ComputerName or null if insufficient data.
    #>
    [CmdletBinding()]
    param(
    [Parameter(Mandatory)]
    [string]$Serial,
    
    [Parameter()]
    [string]$AssetTag
    )
    
    #Gather Serial Numbers & Asset Tag from CIM
    $asset = $AssetTag.ToString().Trim()
    $serial = $Serial.ToString().Trim()
    $maxLen = 15
    $sep = '-'
    
    # Calculate how many serial characters can be used (rightmost characters)
    $maxSerialLen = $maxLen - ($asset.Length + $sep.Length)
    
    if ($maxSerialLen -gt 0) {
        if ($serial.Length -gt $maxSerialLen) {
            $serialPart = $serial.Substring($serial.Length - $maxSerialLen)
        } else {
            $serialPart = $serial
        }
        $ComputerName = "${asset}${sep}${serialPart}"
    } else {
        # Asset tag alone would exceed limit; truncate asset to fit
        if ($asset.Length -gt $maxLen) {
            $ComputerName = $asset.Substring(0, $maxLen)
        } else {
            $ComputerName = $asset
        }
    }
    return $ComputerName
}


#Get Serial & Asset Tag from CIM
$varSerialNumber = (Get-CimInstance -ClassName Win32_BIOS).SerialNumber.Trim()
$varAssetTag = (Get-CimInstance -ClassName Win32_SystemEnclosure).SMBIOSAssetTag
$BIOSPassword = 'P@ssw0rd'
# Build a proposed ComputerName when both Serial and AssetTag exist
# Format: AssetTag-SerialPart (ensure NetBIOS <= 15 chars)
if ($varSerialNumber -and $varAssetTag) {
    
    $ComputerName = Build-ComputerName -Serial $varSerialNumber -AssetTag $varAssetTag
    
} else {
    # Report which specific data elements are missing
    $missing = @()
    if (-not $varAssetTag -or $varAssetTag -eq '') { $missing += 'AssetTag' }
    if (-not $varSerialNumber -or $varSerialNumber -eq '') { $missing += 'SerialNumber' }
    if ($missing.Count -eq 0) {
        Write-Host "Insufficient data to build ComputerName (unknown missing data)"
        $missingList = 'unknown'
    } else {
        $missingList = $missing -join ', '
        Write-Host "Insufficient data to build ComputerName. Missing: $missingList"
    }
    
    $msg = "Unable to generate ComputerName due to missing Asset Tag Information. Please enter a Asset Tag manually. (Note, max length is 5 characters)."
    $varAssetTag = Show-InputPopup -Message $msg -Title "Computer Asset Tag" -MaxInputLength 5
    $ComputerName = Build-ComputerName -Serial $varSerialNumber -AssetTag $varAssetTag
    
    #region Set Asset Tag in BIOS if not set
    # Import Dell BIOS module
    $DellProviderInstalled = Get-InstalledModule -Name DellBIOSProvider -ErrorAction SilentlyContinue
    if (!($DellProviderInstalled)){
        Install-Module -Name DellBIOSProvider -Force -AcceptLicense -Repository PSGallery -SkipPublisherCheck
    }
    Import-Module DellBIOSProvider
    
    # Check for BIOS password
    $varBIOSPassword = (Get-Item -Path DellSmbios:\Security\IsAdminPasswordSet | Select-Object -expand CurrentValue)
    
    # Check for asset tag
    $varTestAssetTag = (Get-Item -Path DellSmbios:\SystemInformation\Asset | Select-Object -expand CurrentValue)
    
    # Grab computer name and pull asset tag info in preparation to have to set later on
    
    if ($varTestAssetTag -eq $null) {
        Write-Host "Asset Tag is null, proceeding to set from computer name"
    } else {
        Write-Host "Asset Tag is already set to $varTestAssetTag"
    }
    $newAsset=$varAssetTag
    
    
    # Read out variables
    write-host "Is Password Set: $varBIOSPassword"
    write-host "Asset Tag: $varTestAssetTag"
    write-host "New Asset: $newAsset"
    
    
    # Determine if BIOS password is set, if not set BIOS password
    If ($varBIOSPassword -eq "True") {Write-Host 'BIOS password set, moving on...'}
    elseif ($varBIOSPassword -eq "False") {Write-Host 'BIOS password not set, setting...' (Set-Item -Path DellSmbios:\Security\AdminPassword $BIOSPassword)}
    
    # Determine if Asset Tag is set, if not set the Asset Tag
    if ($varTestAssetTag) {Write-Host 'Asset Tag set, moving on...'}
    elseif (!$varTestAssetTag) {Write-Host 'Asset Tag not set, setting...' (Set-Item -path DellSmbios:\SystemInformation\Asset "$newAsset" -Password $BIOSPassword)}
    #endregion
}


if ($ComputerName){
    #Pull Vars from TS:
    try {
        Import-Module DeployR.Utility -ErrorAction SilentlyContinue
    }
    catch {}
    if (Get-Module -name "DeployR.Utility"){
        ${TSEnv:ComputerName} = $ComputerName
        Write-Output "Set TSEnv ComputerName to $ComputerName"
    }
    else{
        Write-Output "Running outside of DeployR, not setting TSEnv variables."
        Write-Output "ComputerName: $ComputerName"
    }
}