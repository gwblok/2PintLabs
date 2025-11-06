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
    [string]$DefaultValue = ""
    )
    
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    
    # Create the form
    $form = New-Object System.Windows.Forms.Form
    $form.Text = $Title
    $form.Size = New-Object System.Drawing.Size(400, 180)
    $form.StartPosition = 'CenterScreen'
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.TopMost = $true
    
    # Create the label
    $label = New-Object System.Windows.Forms.Label
    $label.Location = New-Object System.Drawing.Point(10, 20)
    $label.Size = New-Object System.Drawing.Size(370, 40)
    $label.Text = $Message
    $form.Controls.Add($label)
    
    # Create the text box
    $textBox = New-Object System.Windows.Forms.TextBox
    $textBox.Location = New-Object System.Drawing.Point(10, 70)
    $textBox.Size = New-Object System.Drawing.Size(360, 20)
    $textBox.Text = $DefaultValue
    $form.Controls.Add($textBox)
    
    # Create OK button
    $okButton = New-Object System.Windows.Forms.Button
    $okButton.Location = New-Object System.Drawing.Point(210, 105)
    $okButton.Size = New-Object System.Drawing.Size(75, 25)
    $okButton.Text = 'OK'
    $okButton.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $form.AcceptButton = $okButton
    $form.Controls.Add($okButton)
    
    # Create Cancel button
    $cancelButton = New-Object System.Windows.Forms.Button
    $cancelButton.Location = New-Object System.Drawing.Point(295, 105)
    $cancelButton.Size = New-Object System.Drawing.Size(75, 25)
    $cancelButton.Text = 'Cancel'
    $cancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $form.CancelButton = $cancelButton
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

# Example usage:
<#
$question = "What is your favorite color?"
$answer = Show-InputPopup -Message $question -Title "Survey Question"

if ($answer) {
Write-Host "You answered: $answer" -ForegroundColor Green
}
else {
Write-Host "User cancelled." -ForegroundColor Yellow
}

# Another example with default value
$version = Show-InputPopup -Message "Enter the application version:" -Title "Version Input" -DefaultValue "1.0.0"
if ($version) {
Write-Host "Version entered: $version"
}
#>


$UserInput = Show-InputPopup -Message "Please enter your input:" -Title "User Input"

#Pull Vars from TS:
try {
    Import-Module DeployR.Utility -ErrorAction SilentlyContinue
}
catch {}
if (Get-Module -name "DeployR.Utility"){
    ${TSEnv:UserInput} = $UserInput
    Write-Output "Set TSEnv UserInput to $UserInput"
}
else{
    Write-Output "Running outside of DeployR, not setting TSEnv variables."
    Write-Output "UserInput: $UserInput"
}