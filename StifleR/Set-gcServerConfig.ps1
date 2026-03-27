#Update this Path to match your StifleR Server config file location
$StifleRConfigPath = "C:\Program Files\2Pint Software\StifleR Server\StifleR.Service.exe.config"
Write-Host ""
Write-Host "Setting gcServer enabled=true in StifleR configuration..." -ForegroundColor Cyan
Write-Host "Testing for StifleR configuration file at $StifleRConfigPath" -ForegroundColor Cyan
if (Test-Path -Path $StifleRConfigPath) {
    [xml]$configXml = Get-Content -Path $StifleRConfigPath

    # Add <gcServer enabled="true" /> to <runtime> if not already present
    $runtimeNode = $configXml.configuration.runtime
    if ($runtimeNode) {
        $gcServerNode = $runtimeNode.SelectSingleNode("gcServer")
        if ($gcServerNode) {
            if ($gcServerNode.GetAttribute("enabled") -ne "true") {
                $gcServerNode.SetAttribute("enabled", "true")
                Write-Host "gcServer element already exists in runtime, updated enabled to true." -ForegroundColor Yellow
                Write-Host "Configuration is saved at $StifleRConfigPath" -ForegroundColor Green
            }
            else {
                Write-Host "gcServer element already exists in runtime with enabled=true." -ForegroundColor Magenta
                
            }
        }
        else {
            $newElement = $configXml.CreateElement("gcServer")
            $newElement.SetAttribute("enabled", "true")
            $runtimeNode.PrependChild($newElement) | Out-Null
            Write-Host "Added <gcServer enabled=""true"" /> to runtime section." -ForegroundColor Green
            Write-Host "Configuration is saved at $StifleRConfigPath" -ForegroundColor Green
        }
        $configXml.Save($StifleRConfigPath)
        
    }
    else {
        Write-Host "runtime node not found in StifleR configuration." -ForegroundColor Red
    }
    Write-Host""
    Write-Host "Reporting the 4 lines of the runtime section as currently set:" -ForegroundColor DarkCyan
    # Grab again and display the updated configuration
    [xml]$configXml = Get-Content -Path $StifleRConfigPath
    $gcServerNode = $configXml.configuration.runtime.SelectSingleNode("gcServer")
    #write out the first 4 lines of the runtime section to confirm the change
    $runtimeSection = $configXml.configuration.runtime.OuterXml
        # Insert newlines between adjacent tags so the XML is readable when split
        $formattedRuntime = $runtimeSection -replace '>\s*<', ">`n<"
    $runtimeLines = $formattedRuntime -split "`n" | Select-Object -First 4
    $runtimeLines | ForEach-Object { Write-Host $_ -ForegroundColor Green }
    

}
else {
    Write-Host "StifleR configuration file not found at $StifleRConfigPath" -ForegroundColor Red
}

