Import-Module DeployR.Utility




# Regenerate the Boot Image to ensure it includes the latest drivers and configurations
$bootImageId = '00000003-0000-0000-0000-000000000001' #x64 Boot Image
Invoke-DeployRRestMethod -RelativeUri "/v1/BootImage/$bootImageId/Generate?regenerate=true" -Method POST


# Update Boot Image properties if needed
$bootImageId = "00000003-0000-0000-0000-000000000001"

$body = @{
    id                       = $bootImageId
    name                     = "Windows PE x64"
    description              = "Default Windows PE x64 boot image"
    architecture             = "X64"          # ← THIS WAS WRONG BEFORE
    platform                 = "Windows"
    driversContentItem       = "bb2a9aa4-a8e7-471f-ac67-c59fff54a8c8:1"
    stifleRClientContentItem = $null
    winREContentItem         = $null
    extraFilesContentItem    = $null
    certificateContentItem   = "4958a345-8fbf-4172-a54e-35652dabd6c4:1"   # OK if you really want it
    relativePath             = $null        # you probably don’t want to override this manually
} | ConvertTo-Json -Depth 10

Invoke-DeployRRestMethod `
    -RelativeUri "/v1/BootImage/$bootImageId" `
    -Method PUT `
    -Body $body `
    -ContentType "application/json"