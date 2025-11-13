<#
This Script will set the Computer Name based on Asset Tag and Serial Number
If Asset Tag is missing, it will prompt the user to enter it via a popup
It will also set the Asset Tag in BIOS via CCTK

Requires that you have CCTK.exe available in the content location when run in DeployR Task Sequence
Create a Content Item with the CCTK.exe and reference it in the Task Sequence

PowerShell Step -> Paste in this Script
- Attach a Content Item that contains CCTK.exe (the full contents of the c:\program files (x86)\Dell\Command Configure\x86-64 folder)



#>


#Set this to your BIOS Password or Delete if you have none.  Feel free to make this more secure, however you want to do that.  This is NOT best practice to have passwords in scripts.
$BIOSPassword = 'P@ssw0rd'

#Get Serial & Asset Tag from CIM
$varSerialNumber = (Get-CimInstance -ClassName Win32_BIOS).SerialNumber.Trim()
$varAssetTag = (Get-CimInstance -ClassName Win32_SystemEnclosure).SMBIOSAssetTag

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

#Grab Content Location for Import of Module
try {
    Import-Module DeployR.Utility
}
catch {}
if (Get-Module -name "DeployR.Utility" -ErrorAction SilentlyContinue){
    $ContentLocation = ${TSEnv:CONTENT-CONTENT}
    Write-Host "Running in TS, getting content location from TSEnv: $ContentLocation"
    $CCTKPath = "$ContentLocation\CCTK.exe"
    if (Test-Path -Path $CCTKPath){
        Write-Host "CCTK found at $CCTKPath"
    }
    else{
        Write-Host "CCTK NOT found at expected location: $CCTKPath"
    }
}
else{
    $ContentLocation = Split-Path -Path $MyInvocation.MyCommand.Definition -Parent
    Write-Host "Running outside of TS, setting content location to script folder: $ContentLocation"
}



# Build a proposed ComputerName when both Serial and AssetTag exist
# Format: AssetTag-SerialPart (ensure NetBIOS <= 15 chars)
if ($varSerialNumber -and $varAssetTag) {
    Write-Host "Serial Number: $varSerialNumber"
    Write-Host "Asset Tag: $varAssetTag"
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
    
    $msg = "Missing Asset Tag Information. Please enter a Asset Tag manually. (Note, max length is 5 characters)."
    $varAssetTag = Show-InputPopup -Message $msg -Title "Computer Asset Tag" -MaxInputLength 5
    $ComputerName = Build-ComputerName -Serial $varSerialNumber -AssetTag $varAssetTag
    
    #Set the Asset Tag in BIOS via CCTK
    Write-Host "Setting Asset Tag in BIOS to: $varAssetTag"
    if ($BIOSPassword){
        Start-Process -FilePath $CCTKPath -ArgumentList "--Asset=$($varAssetTag) --ValSetupPwd=$($BIOSPassword)" -Wait -NoNewWindow -RedirectStandardOutput "$env:TEMP\CCTK_AssetTag_Set.log"
    }
    else{
        Start-Process -FilePath $CCTKPath -ArgumentList "--Asset=$($varAssetTag)" -Wait -NoNewWindow -RedirectStandardOutput "$env:TEMP\CCTK_AssetTag_Set.log"
    }
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