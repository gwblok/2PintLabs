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
} else {
    Write-Host "Could not find a download link."
}
