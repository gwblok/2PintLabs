# URL for SQL Server 2022 CUs
$url = "https://www.microsoft.com/en-us/download/details.aspx?id=105013"

# Download the page content
$response = Invoke-WebRequest -Uri $url -UseBasicParsing

# Find the first download link (usually the latest CU)
$downloadLink = $response.Links | Where-Object { $_.href -match "download\.microsoft\.com" } | Select-Object -First 1

# Extract CU version from the page title or description
$title = $response.ParsedHtml.title

Write-Host "Latest SQL Server 2022 CU info:"
Write-Host "Title: $title"
if ($downloadLink) {
    Write-Host "Download URL: $($downloadLink.href)"

    # Set download destination
    $dest = "$env:TEMP\SQL2022CU.exe"

    Write-Host "Downloading CU to $dest ..."
    Start-BitsTransfer -Source $downloadLink.href -Destination $dest

    # Show splash screen while installing
    $splash = Start-Process -FilePath powershell -ArgumentList "-NoProfile -WindowStyle Hidden -Command `"Add-Type -AssemblyName PresentationFramework;[System.Windows.MessageBox]::Show('Installing SQL 2022 CU...','SQL CU Installer')`"" -PassThru

    Write-Host "Starting silent install..."
    Start-Process -FilePath $dest -ArgumentList "/quiet /updateenabled=false /IAcceptSQLServerLicenseTerms" -Wait

    # Close splash screen
    if ($splash -and !$splash.HasExited) {
        $splash.CloseMainWindow() | Out-Null
        $splash | Stop-Process -Force
    }

    Write-Host "SQL Server 2022 CU installation complete."
} else {
    Write-Host "Could not find a download link."
}