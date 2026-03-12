$StifleRConfigPath = "C:\Program Files\2Pint Software\StifleR Server\StifleR.Service.exe.config"
if (Test-Path -Path $StifleRConfigPath) {
    [xml]$configXml = Get-Content -Path $StifleRConfigPath

    # Add <gcServer enabled="true" /> to <runtime> if not already present
    $runtimeNode = $configXml.configuration.runtime
    if ($runtimeNode) {
        $gcServerNode = $runtimeNode.SelectSingleNode("gcServer")
        if ($gcServerNode) {
            $gcServerNode.SetAttribute("enabled", "true")
            Write-Host "gcServer element already exists in runtime, updated enabled to true." -ForegroundColor Yellow
        }
        else {
            $newElement = $configXml.CreateElement("gcServer")
            $newElement.SetAttribute("enabled", "true")
            $runtimeNode.PrependChild($newElement) | Out-Null
            Write-Host "Added <gcServer enabled=""true"" /> to runtime section." -ForegroundColor Green
        }
        $configXml.Save($StifleRConfigPath)
        Write-Host "Configuration saved to $StifleRConfigPath" -ForegroundColor Green
    }
    else {
        Write-Host "runtime node not found in StifleR configuration." -ForegroundColor Red
    }
}
else {
    Write-Host "StifleR configuration file not found at $StifleRConfigPath" -ForegroundColor Red
}