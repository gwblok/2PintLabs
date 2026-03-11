#Requires -Version 5
#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    [Parameter()] [string] $DownloadLocation = ""
)

Write-Host "#########################################################"
Write-Host "Download.ps1"
Write-Host "#########################################################"
Write-Host " "

# Versions
$DotNetVersion = "8.0.20"
$PwshVersion = "7.4.12"

# Download using BITS
Function Download {
    [CmdletBinding()]
    param (
        [String] $Uri, 
        [string] $OutFile,
        [string] $OldFile = ""
    )

    # See if we can copy forward the old file
    if (($oldFile -ne "") -and (Test-Path $OldFile)) {
        Write-Host "Copying old file from $OldFile to $OutFile"
        Copy-Item $OldFile $OutFile -Force
    } else {
        # Download the file
        Write-Host "Downloading from $Uri to $OutFile"
        Invoke-WebRequest -Uri $Uri -OutFile $OutFile
        # Start-BitsTransfer -Source $Uri -Destination $OutFile -Dynamic -Priority Foreground
        Write-Host "Transfer completed"
    }
}

# If a download location was specified, we'll put all the needed files into it.  Otherwise, we should be running on the 
# DeployR server so that we can download everything to it.
if ($DownloadLocation -eq "")
{
    # If DeployR.Utility is already loaded, assume we are on the server.  Otherwise, figure out where to load it.
    if (-not (Get-Module -Name "DeployR.Utility")) {
        $InstallDir = Resolve-Path "$PSScriptRoot\..\.."
        Write-Host -Message "DeployR is installed at $InstalLDir"
        if (-not (Test-Path "$InstallDir\Client\PSModules\DeployR.Utility"))
        {
            throw "Either specify a -DownloadLocation parameter or run this script on the DeployR server"
        }
        Import-Module "$InstallDir\Client\PSModules\DeployR.Utility" -Force
    }
    # Calculate the paths
    $ContentLocation = Get-DeployRSetting "ContentLocation"
    $DownloadLocation = "$ContentLocation\Downloads"
    $TempLocation = "$ContentLocation\Downloads.temp"
} else {
    $TempLocation = $DownloadLocation
}

# Create the folders 
if (Test-Path $TempLocation) {
    Remove-Item $TempLocation -Recurse -Force | Out-Null
}
MkDir "$DownloadLocation" -Force | Out-Null
MkDir "$TempLocation" -Force | Out-Null

#################
# Download .NET 8
#################
Write-Host -Message "==== Downloading .NET 8"

# First we need the files for inclusion in Windows PE
Download -Uri "https://builds.dotnet.microsoft.com/dotnet/Runtime/$DotNetVersion/dotnet-runtime-$DotNetVersion-win-x64.zip" -OutFile "$TempLocation\dotnet-runtime-$DotNetVersion-win-x64.zip" -OldFile "$DownloadLocation\dotnet-runtime-$DotNetVersion-win-x64.zip"
Download -Uri "https://builds.dotnet.microsoft.com/dotnet/Runtime/$DotNetVersion/dotnet-runtime-$DotNetVersion-win-arm64.zip" -OutFile "$TempLocation\dotnet-runtime-$DotNetVersion-win-arm64.zip" -OldFile "$DownloadLocation\dotnet-runtime-$DotNetVersion-win-arm64.zip"
Download -Uri "https://builds.dotnet.microsoft.com/dotnet/aspnetcore/Runtime/$DotNetVersion/aspnetcore-runtime-$DotNetVersion-win-x64.zip" -OutFile "$TempLocation\aspnetcore-runtime-$DotNetVersion-win-x64.zip" -OldFile "$DownloadLocation\aspnetcore-runtime-$DotNetVersion-win-x64.zip"
Download -Uri "https://builds.dotnet.microsoft.com/dotnet/aspnetcore/Runtime/$DotNetVersion/aspnetcore-runtime-$DotNetVersion-win-arm64.zip" -OutFile "$TempLocation\aspnetcore-runtime-$DotNetVersion-win-arm64.zip" -OldFile "$DownloadLocation\aspnetcore-runtime-$DotNetVersion-win-arm64.zip"
Download -Uri "https://builds.dotnet.microsoft.com/dotnet/WindowsDesktop/$DotNetVersion/windowsdesktop-runtime-$DotNetVersion-win-x64.zip" -OutFile "$TempLocation\windowsdesktop-runtime-$DotNetVersion-win-x64.zip" -OldFile "$DownloadLocation\windowsdesktop-runtime-$DotNetVersion-win-x64.zip"
Download -Uri "https://builds.dotnet.microsoft.com/dotnet/WindowsDesktop/$DotNetVersion/windowsdesktop-runtime-$DotNetVersion-win-arm64.zip" -OutFile "$TempLocation\windowsdesktop-runtime-$DotNetVersion-win-arm64.zip" -OldFile "$DownloadLocation\windowsdesktop-runtime-$DotNetVersion-win-arm64.zip"

# And Linux boot images
Download -Uri "https://builds.dotnet.microsoft.com/dotnet/Runtime/$DotNetVersion/dotnet-runtime-$DotNetVersion-linux-x64.tar.gz" -OutFile "$TempLocation\dotnet-runtime-$DotNetVersion-linux-x64.tar.gz" -OldFile "$DownloadLocation\dotnet-runtime-$DotNetVersion-linux-x64.tar.gz"
Download -Uri "https://builds.dotnet.microsoft.com/dotnet/Runtime/$DotNetVersion/dotnet-runtime-$DotNetVersion-linux-arm64.tar.gz" -OutFile "$TempLocation\dotnet-runtime-$DotNetVersion-linux-arm64.tar.gz" -OldFile "$DownloadLocation\dotnet-runtime-$DotNetVersion-linux-arm64.tar.gz"
Download -Uri "https://builds.dotnet.microsoft.com/dotnet/aspnetcore/Runtime/$DotNetVersion/aspnetcore-runtime-$DotNetVersion-linux-x64.tar.gz" -OutFile "$TempLocation\aspnetcore-runtime-$DotNetVersion-linux-x64.tar.gz" -OldFile "$DownloadLocation\aspnetcore-runtime-$DotNetVersion-linux-x64.tar.gz"
Download -Uri "https://builds.dotnet.microsoft.com/dotnet/aspnetcore/Runtime/$DotNetVersion/aspnetcore-runtime-$DotNetVersion-linux-arm64.tar.gz" -OutFile "$TempLocation\aspnetcore-runtime-$DotNetVersion-linux-arm64.tar.gz" -OldFile "$DownloadLocation\aspnetcore-runtime-$DotNetVersion-linux-arm64.tar.gz"

# Then we need the installers 
$sources = @(
    "https://builds.dotnet.microsoft.com/dotnet/aspnetcore/Runtime/$DotNetVersion/aspnetcore-runtime-$DotNetVersion-win-x64.exe",
    "https://builds.dotnet.microsoft.com/dotnet/aspnetcore/Runtime/$DotNetVersion/aspnetcore-runtime-$DotNetVersion-win-arm64.exe",
    "https://builds.dotnet.microsoft.com/dotnet/Runtime/$DotNetVersion/dotnet-runtime-$DotNetVersion-win-x64.exe",
    "https://builds.dotnet.microsoft.com/dotnet/Runtime/$DotNetVersion/dotnet-runtime-$DotNetVersion-win-arm64.exe",
    "https://builds.dotnet.microsoft.com/dotnet/WindowsDesktop/$DotNetVersion/windowsdesktop-runtime-$DotNetVersion-win-x64.exe",
    "https://builds.dotnet.microsoft.com/dotnet/WindowsDesktop/$DotNetVersion/windowsdesktop-runtime-$DotNetVersion-win-arm64.exe"
)
$dest = "$TempLocation\WindowsInstallers"
$oldDest = "$DownloadLocation\WindowsInstallers"
if (-not (Test-Path $dest))
{
    MkDir $dest -Force | Out-Null
}
$sources | ForEach-Object {
    $fileName = Split-Path $_ -Leaf
    Download -Uri $_ -OutFile "$dest\$fileName" -OldFile "$oldDest\$fileName"
}

#######################
# Download PowerShell 7
#######################
Write-Host -Message "==== Downloading PowerShell 7"

# Extractable zip files for boot images
Download -Uri "https://github.com/PowerShell/PowerShell/releases/download/v$PwshVersion/PowerShell-$PwshVersion-win-x64.zip" -OutFile "$TempLocation\PowerShell-$PwshVersion-win-x64.zip" -OldFile "$DownloadLocation\PowerShell-$PwshVersion-win-x64.zip"
Download -Uri "https://github.com/PowerShell/PowerShell/releases/download/v$PwshVersion/PowerShell-$PwshVersion-win-arm64.zip" -OutFile "$TempLocation\PowerShell-$PwshVersion-win-arm64.zip" -OldFile "$DownloadLocation\PowerShell-$PwshVersion-win-arm64.zip"

# Installers for the full OS
Download -Uri "https://github.com/PowerShell/PowerShell/releases/download/v$PwshVersion/PowerShell-$PwshVersion-win-x64.msi" -OutFile "$dest\PowerShell-$PwshVersion-win-x64.msi" -OldFile "$oldDest\PowerShell-$PwshVersion-win-x64.msi"
Download -Uri "https://github.com/PowerShell/PowerShell/releases/download/v$PwshVersion/PowerShell-$PwshVersion-win-arm64.msi" -OutFile "$dest\PowerShell-$PwshVersion-win-arm64.msi" -OldFile "$oldDest\PowerShell-$PwshVersion-win-arm64.msi"

# And for Linux
Download -Uri "https://github.com/PowerShell/PowerShell/releases/download/v$PwshVersion/powershell-$PwshVersion-linux-x64.tar.gz" -OutFile "$TempLocation\powerShell-$PwshVersion-linux-x64.tar.gz" -OldFile "$DownloadLocation\powerShell-$PwshVersion-linux-x64.tar.gz"
Download -Uri "https://github.com/PowerShell/PowerShell/releases/download/v$PwshVersion/powershell-$PwshVersion-linux-arm64.tar.gz" -OutFile "$TempLocation\powerShell-$PwshVersion-linux-arm64.tar.gz" -OldFile "$DownloadLocation\powerShell-$PwshVersion-linux-arm64.tar.gz"

#######################
# Download WU manifests
#######################
Write-Host -Message "==== Downloading WU/MCT manifests"

# TODO: Move this to a cloud service so we only have to download the result
$sources = @(
    "https://download.microsoft.com/download/8e0c23e7-ddc2-45c4-b7e1-85a808b408ee/Products-Win11-24H2-6B.cab", #Windows 11 24H2
    "https://download.microsoft.com/download/6/2/b/62b47bc5-1b28-4bfa-9422-e7a098d326d4/products_win11_20231208.cab", #Windows 11 23H2 (duplicates above)
    "https://download.microsoft.com/download/b/1/9/b19bd7fd-78c4-4f88-8c40-3e52aee143c2/products_win11_20230510.cab.cab", #Windows 11 22H2
    "https://download.microsoft.com/download/1/b/4/1b4e06e2-767a-4c9a-9899-230fe94ba530/products_Win11_20211115.cab", #Windows 11 21H2
    # "https://go.microsoft.com/fwlink/?LinkId=2156292", #Latest Windows 11 (24H2)
    "https://go.microsoft.com/fwlink/?LinkId=841361" #Latest Windows 10
    )
$dest = "$TempLocation\WUManifests"
$oldDest = "$DownloadLocation\WUManifests"
if (-not (Test-Path $dest))
{
    MkDir $dest -Force | Out-Null
}
$sources | ForEach-Object {
    $fileName = Split-Path $_ -Leaf
    if ($fileName.StartsWith("?LinkId=")) {
        $fileName = "linkid_$($fileName.Substring(8)).cab"
    }
    Download -Uri $_ -OutFile "$dest\$fileName" -OldFile "$oldDest\$fileName"
}

##########
# All done
##########

# Write out the current date
$DownloadInfo = @{ LastDownloaded = Get-Date ; DotNetVersion = $DotNetVersion ; PowerShellVersion = $PwshVersion }
$DownloadInfo | ConvertTo-Json | Out-File "$TempLocation\DownloadInfo.json"

# Swap the locations if they are different
if ($TempLocation -ne $DownloadLocation) {
    $OldLocation = "$DownloadLocation.old"
    if (Test-Path $OldLocation)
    {
        Remove-Item $OldLocation -Recurse -Force
    }
    Move-Item $DownloadLocation $OldLocation -Force
    Move-Item $TempLocation $DownloadLocation -Force
    Write-Host "Content downloaded to $DownloadLocation"
} else {
    Write-Host "On a DeployR server running in Disconnected mode, copy the content from $DownloadLocation to <ContentLocation>\Downloads\"
}

# SIG # Begin signature block
# MIIvCwYJKoZIhvcNAQcCoIIu/DCCLvgCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCCW9RMe4tbR0grJ
# UP+07/2dzON4BXsaXQrQ+Xd+fRyqqKCCE5owggWQMIIDeKADAgECAhAFmxtXno4h
# MuI5B72nd3VcMA0GCSqGSIb3DQEBDAUAMGIxCzAJBgNVBAYTAlVTMRUwEwYDVQQK
# EwxEaWdpQ2VydCBJbmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xITAfBgNV
# BAMTGERpZ2lDZXJ0IFRydXN0ZWQgUm9vdCBHNDAeFw0xMzA4MDExMjAwMDBaFw0z
# ODAxMTUxMjAwMDBaMGIxCzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2VydCBJ
# bmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xITAfBgNVBAMTGERpZ2lDZXJ0
# IFRydXN0ZWQgUm9vdCBHNDCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIB
# AL/mkHNo3rvkXUo8MCIwaTPswqclLskhPfKK2FnC4SmnPVirdprNrnsbhA3EMB/z
# G6Q4FutWxpdtHauyefLKEdLkX9YFPFIPUh/GnhWlfr6fqVcWWVVyr2iTcMKyunWZ
# anMylNEQRBAu34LzB4TmdDttceItDBvuINXJIB1jKS3O7F5OyJP4IWGbNOsFxl7s
# Wxq868nPzaw0QF+xembud8hIqGZXV59UWI4MK7dPpzDZVu7Ke13jrclPXuU15zHL
# 2pNe3I6PgNq2kZhAkHnDeMe2scS1ahg4AxCN2NQ3pC4FfYj1gj4QkXCrVYJBMtfb
# BHMqbpEBfCFM1LyuGwN1XXhm2ToxRJozQL8I11pJpMLmqaBn3aQnvKFPObURWBf3
# JFxGj2T3wWmIdph2PVldQnaHiZdpekjw4KISG2aadMreSx7nDmOu5tTvkpI6nj3c
# AORFJYm2mkQZK37AlLTSYW3rM9nF30sEAMx9HJXDj/chsrIRt7t/8tWMcCxBYKqx
# YxhElRp2Yn72gLD76GSmM9GJB+G9t+ZDpBi4pncB4Q+UDCEdslQpJYls5Q5SUUd0
# viastkF13nqsX40/ybzTQRESW+UQUOsxxcpyFiIJ33xMdT9j7CFfxCBRa2+xq4aL
# T8LWRV+dIPyhHsXAj6KxfgommfXkaS+YHS312amyHeUbAgMBAAGjQjBAMA8GA1Ud
# EwEB/wQFMAMBAf8wDgYDVR0PAQH/BAQDAgGGMB0GA1UdDgQWBBTs1+OC0nFdZEzf
# Lmc/57qYrhwPTzANBgkqhkiG9w0BAQwFAAOCAgEAu2HZfalsvhfEkRvDoaIAjeNk
# aA9Wz3eucPn9mkqZucl4XAwMX+TmFClWCzZJXURj4K2clhhmGyMNPXnpbWvWVPjS
# PMFDQK4dUPVS/JA7u5iZaWvHwaeoaKQn3J35J64whbn2Z006Po9ZOSJTROvIXQPK
# 7VB6fWIhCoDIc2bRoAVgX+iltKevqPdtNZx8WorWojiZ83iL9E3SIAveBO6Mm0eB
# cg3AFDLvMFkuruBx8lbkapdvklBtlo1oepqyNhR6BvIkuQkRUNcIsbiJeoQjYUIp
# 5aPNoiBB19GcZNnqJqGLFNdMGbJQQXE9P01wI4YMStyB0swylIQNCAmXHE/A7msg
# dDDS4Dk0EIUhFQEI6FUy3nFJ2SgXUE3mvk3RdazQyvtBuEOlqtPDBURPLDab4vri
# RbgjU2wGb2dVf0a1TD9uKFp5JtKkqGKX0h7i7UqLvBv9R0oN32dmfrJbQdA75PQ7
# 9ARj6e/CVABRoIoqyc54zNXqhwQYs86vSYiv85KZtrPmYQ/ShQDnUBrkG5WdGaG5
# nLGbsQAe79APT0JsyQq87kP6OnGlyE0mpTX9iV28hWIdMtKgK1TtmlfB2/oQzxm3
# i0objwG2J5VT6LaJbVu8aNQj6ItRolb58KaAoNYes7wPD1N1KarqE3fk3oyBIa0H
# EEcRrYc9B9F1vM/zZn4wggawMIIEmKADAgECAhAIrUCyYNKcTJ9ezam9k67ZMA0G
# CSqGSIb3DQEBDAUAMGIxCzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2VydCBJ
# bmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xITAfBgNVBAMTGERpZ2lDZXJ0
# IFRydXN0ZWQgUm9vdCBHNDAeFw0yMTA0MjkwMDAwMDBaFw0zNjA0MjgyMzU5NTla
# MGkxCzAJBgNVBAYTAlVTMRcwFQYDVQQKEw5EaWdpQ2VydCwgSW5jLjFBMD8GA1UE
# AxM4RGlnaUNlcnQgVHJ1c3RlZCBHNCBDb2RlIFNpZ25pbmcgUlNBNDA5NiBTSEEz
# ODQgMjAyMSBDQTEwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQDVtC9C
# 0CiteLdd1TlZG7GIQvUzjOs9gZdwxbvEhSYwn6SOaNhc9es0JAfhS0/TeEP0F9ce
# 2vnS1WcaUk8OoVf8iJnBkcyBAz5NcCRks43iCH00fUyAVxJrQ5qZ8sU7H/Lvy0da
# E6ZMswEgJfMQ04uy+wjwiuCdCcBlp/qYgEk1hz1RGeiQIXhFLqGfLOEYwhrMxe6T
# SXBCMo/7xuoc82VokaJNTIIRSFJo3hC9FFdd6BgTZcV/sk+FLEikVoQ11vkunKoA
# FdE3/hoGlMJ8yOobMubKwvSnowMOdKWvObarYBLj6Na59zHh3K3kGKDYwSNHR7Oh
# D26jq22YBoMbt2pnLdK9RBqSEIGPsDsJ18ebMlrC/2pgVItJwZPt4bRc4G/rJvmM
# 1bL5OBDm6s6R9b7T+2+TYTRcvJNFKIM2KmYoX7BzzosmJQayg9Rc9hUZTO1i4F4z
# 8ujo7AqnsAMrkbI2eb73rQgedaZlzLvjSFDzd5Ea/ttQokbIYViY9XwCFjyDKK05
# huzUtw1T0PhH5nUwjewwk3YUpltLXXRhTT8SkXbev1jLchApQfDVxW0mdmgRQRNY
# mtwmKwH0iU1Z23jPgUo+QEdfyYFQc4UQIyFZYIpkVMHMIRroOBl8ZhzNeDhFMJlP
# /2NPTLuqDQhTQXxYPUez+rbsjDIJAsxsPAxWEQIDAQABo4IBWTCCAVUwEgYDVR0T
# AQH/BAgwBgEB/wIBADAdBgNVHQ4EFgQUaDfg67Y7+F8Rhvv+YXsIiGX0TkIwHwYD
# VR0jBBgwFoAU7NfjgtJxXWRM3y5nP+e6mK4cD08wDgYDVR0PAQH/BAQDAgGGMBMG
# A1UdJQQMMAoGCCsGAQUFBwMDMHcGCCsGAQUFBwEBBGswaTAkBggrBgEFBQcwAYYY
# aHR0cDovL29jc3AuZGlnaWNlcnQuY29tMEEGCCsGAQUFBzAChjVodHRwOi8vY2Fj
# ZXJ0cy5kaWdpY2VydC5jb20vRGlnaUNlcnRUcnVzdGVkUm9vdEc0LmNydDBDBgNV
# HR8EPDA6MDigNqA0hjJodHRwOi8vY3JsMy5kaWdpY2VydC5jb20vRGlnaUNlcnRU
# cnVzdGVkUm9vdEc0LmNybDAcBgNVHSAEFTATMAcGBWeBDAEDMAgGBmeBDAEEATAN
# BgkqhkiG9w0BAQwFAAOCAgEAOiNEPY0Idu6PvDqZ01bgAhql+Eg08yy25nRm95Ry
# sQDKr2wwJxMSnpBEn0v9nqN8JtU3vDpdSG2V1T9J9Ce7FoFFUP2cvbaF4HZ+N3HL
# IvdaqpDP9ZNq4+sg0dVQeYiaiorBtr2hSBh+3NiAGhEZGM1hmYFW9snjdufE5Btf
# Q/g+lP92OT2e1JnPSt0o618moZVYSNUa/tcnP/2Q0XaG3RywYFzzDaju4ImhvTnh
# OE7abrs2nfvlIVNaw8rpavGiPttDuDPITzgUkpn13c5UbdldAhQfQDN8A+KVssIh
# dXNSy0bYxDQcoqVLjc1vdjcshT8azibpGL6QB7BDf5WIIIJw8MzK7/0pNVwfiThV
# 9zeKiwmhywvpMRr/LhlcOXHhvpynCgbWJme3kuZOX956rEnPLqR0kq3bPKSchh/j
# wVYbKyP/j7XqiHtwa+aguv06P0WmxOgWkVKLQcBIhEuWTatEQOON8BUozu3xGFYH
# Ki8QxAwIZDwzj64ojDzLj4gLDb879M4ee47vtevLt/B3E+bnKD+sEq6lLyJsQfmC
# XBVmzGwOysWGw/YmMwwHS6DTBwJqakAwSEs0qFEgu60bhQjiWQ1tygVQK+pKHJ6l
# /aCnHwZ05/LWUpD9r4VIIflXO7ScA+2GRfS0YW6/aOImYIbqyK+p/pQd52MbOoZW
# eE4wggdOMIIFNqADAgECAhAN71g6LHT9/A9aiuXA2FCaMA0GCSqGSIb3DQEBCwUA
# MGkxCzAJBgNVBAYTAlVTMRcwFQYDVQQKEw5EaWdpQ2VydCwgSW5jLjFBMD8GA1UE
# AxM4RGlnaUNlcnQgVHJ1c3RlZCBHNCBDb2RlIFNpZ25pbmcgUlNBNDA5NiBTSEEz
# ODQgMjAyMSBDQTEwHhcNMjUwMzEzMDAwMDAwWhcNMjgwMzE0MjM1OTU5WjBWMQsw
# CQYDVQQGEwJTRTEPMA0GA1UEBwwGSG92w6VzMRowGAYDVQQKExEyUGludCBTb2Z0
# d2FyZSBBQjEaMBgGA1UEAxMRMlBpbnQgU29mdHdhcmUgQUIwggIiMA0GCSqGSIb3
# DQEBAQUAA4ICDwAwggIKAoICAQC10zuqpoxAwME7Dyqaqzl38pplYh/iqqodmehw
# cL61MlFBNzfz2AL3UAOuwqkqjJhlos48CrHZ5R9yJbmLpghkssYof2ot3z2hnHTB
# kMyskNP4ayjvhFI2a9MbueEi5zI0wXFd2Sn0aEmfI0J2RnWkYwvdbd8lYwO/0gws
# TOYyblYRoKUwJ2mBrKfSe/dxsWUc1mzVjrHOUkhkHsI2ICkBBfOrP8G3gPTi8vAE
# 89q4GpNekAcXeWXffN4iio1oxjGXF9yAa+pugiLqPQDd1AU1twLWFqWg9peXKaa/
# 7IMUZUfyzEPXl7GQAyT7SSgzf6OIl7/LKnecg6uM8dAfDHKlLYIvoyy+Alh00Zc5
# 7uuXW2ZBdpXsU5eCpW/d0DbnnQGp23dvWS+Eoq5HwdNVcfpMoaAaDfgnRLtyrHIS
# jaicOy2lpydH/mS348nEvplTmgP4CAOoPER31icv5jUtxbX4jyAQuddv4uwLKuDg
# N6UNSlRTO1E8bsNG6CrisB3xtEa97A0bVQjrPdZxxOdr3N49S96CI1rnjOfOjscI
# eATLtYuf7/o/2U5aXPwfvCdY/dNJ9zsvmZ48P+tdVAAxlupDCIKmX98obZl8NJsG
# 1U0WFoENvKyZ4gTx3O4DImFdCgpRhZpDvQkR1xxfBbgxcW7E3fItPUKv5vRbE8ld
# VMMnDQIDAQABo4ICAzCCAf8wHwYDVR0jBBgwFoAUaDfg67Y7+F8Rhvv+YXsIiGX0
# TkIwHQYDVR0OBBYEFLqTMurQaa9F0Tyodk6Rtg7KS0hFMD4GA1UdIAQ3MDUwMwYG
# Z4EMAQQBMCkwJwYIKwYBBQUHAgEWG2h0dHA6Ly93d3cuZGlnaWNlcnQuY29tL0NQ
# UzAOBgNVHQ8BAf8EBAMCB4AwEwYDVR0lBAwwCgYIKwYBBQUHAwMwgbUGA1UdHwSB
# rTCBqjBToFGgT4ZNaHR0cDovL2NybDMuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0VHJ1
# c3RlZEc0Q29kZVNpZ25pbmdSU0E0MDk2U0hBMzg0MjAyMUNBMS5jcmwwU6BRoE+G
# TWh0dHA6Ly9jcmw0LmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydFRydXN0ZWRHNENvZGVT
# aWduaW5nUlNBNDA5NlNIQTM4NDIwMjFDQTEuY3JsMIGUBggrBgEFBQcBAQSBhzCB
# hDAkBggrBgEFBQcwAYYYaHR0cDovL29jc3AuZGlnaWNlcnQuY29tMFwGCCsGAQUF
# BzAChlBodHRwOi8vY2FjZXJ0cy5kaWdpY2VydC5jb20vRGlnaUNlcnRUcnVzdGVk
# RzRDb2RlU2lnbmluZ1JTQTQwOTZTSEEzODQyMDIxQ0ExLmNydDAJBgNVHRMEAjAA
# MA0GCSqGSIb3DQEBCwUAA4ICAQAvVkmDb8Wg/Z/s1TfdlF0GEwuJ1iA62uTvnLbc
# L8RgLCYKue+BrJFIaJXVT3EoUNh9TB2uAaKxqU0JsL1p1JfKM6f7n1Zf/f7GiLkf
# 0LJ/z0EJAVk1ZvDb1TLOyZQb6lqPCbE7ZTijVHNZ6WmnbB/vAECrRzx2ojag9RjQ
# gsQ+lY93xOLjNU85eshmu/cI8kUsfDzonIp9sXjbCJLnVljD0X+Oo8utY3z0Kjgb
# oGAIXu3wX8/UEUkDLFgbrM6pdeXeB+B8Dc9eKYaekVvI/PeKqcUGQW9rTDnEowN6
# E6Pmld1zZ5U3Ous31/27NGM+mdPESxL4/P32w7cPfQGKtcDn1/e3ThvBbi2YQSWp
# xeS/CHde1j0JkhpXPRALphKsPG5+XZixUqlTkR4ruSPsS/CHFMKycZr1BUxjzu5z
# OMZEo7cUIY7EX9YPMian4qTkaKp6wLOh/jq3jNdmfrHGkT14XTaNVKqgqirP6+5g
# 2rCrEpYO0bW2bZ/rKegiE4D0uRYfg700BIg97LVkEvqUtZskaCEV31FQGhh4tBg5
# ATt1vSdwz5y8kwJVM3ImVeagBoIy4buE+j4gUBkHUsfTJ9aVVHUbqexr7WrhFRB4
# P0P+qd5ZsniXjqpZR17ROIwd1iSy68EPG5YQ4SuExebmUS2BwWqW9vFuRWC+6Bd6
# Pl9vvDGCGscwghrDAgEBMH0waTELMAkGA1UEBhMCVVMxFzAVBgNVBAoTDkRpZ2lD
# ZXJ0LCBJbmMuMUEwPwYDVQQDEzhEaWdpQ2VydCBUcnVzdGVkIEc0IENvZGUgU2ln
# bmluZyBSU0E0MDk2IFNIQTM4NCAyMDIxIENBMQIQDe9YOix0/fwPWorlwNhQmjAN
# BglghkgBZQMEAgEFAKCBojAZBgkqhkiG9w0BCQMxDAYKKwYBBAGCNwIBBDAcBgor
# BgEEAYI3AgELMQ4wDAYKKwYBBAGCNwIBFTAvBgkqhkiG9w0BCQQxIgQgA/kW08Tq
# 29uFjeVObEqLiOsCz6WH/SGt6SsSfJRudT4wNgYKKwYBBAGCNwIBDDEoMCagAoAA
# oSCAHmh0dHBzOi8vd3d3LjJwaW50c29mdHdhcmUuY29tIDANBgkqhkiG9w0BAQEF
# AASCAgCrP9B52ogQFBgtY3/04IFoYJkG74Vm10TyamjI1o5tUuz27OAZITmF1KWv
# F1ngVAEARPMVLaxzHJTziaNRZHJgfevpqqSlTxelc4HtsrYb0g4kjhXcKPMUdBBr
# IyxavCfu9ChHOimXsv/toZToe5E0fCpo5QLqYwiad1ARzwkoQW3XWRdkRgQQidcQ
# 3GKYjr6T1Q3IEf3ATnY9FKPNuRndY4jzN4YnH1t7t0pdwErf0eBcOZyKEzIeguem
# zbWBJHrc+L/dXAXK/+663d+TPMxKfbHZttoxq3asNV96jJgqd2jvrm2gaLkVfh+u
# 3USgOh5MLddWXPW1142kKp8qOuro2HfyV5xCuAa3JGFrOMIoHYg32Kv8UKKTa18+
# wtpjhlg+hfaqEHTjUwoUCsFrwVvhf99BN3m85XE3KZTv5PzJd7JqXRCYVKJT538s
# tef/Po6BTbyC4KwwsoV+5BrtRl5Ec//57c3XiMKU9x5pDjEjHzCob1AntDFfWKRe
# DAmvXGIs390Jt3ISKL0sNFeqWKiXvVsUql6uZLndSElLOkF+K1cLv3hRe3Z5gbVL
# wgCEDO7mgDifIM75fKckG4jqRpSJVAcZUJZmC4GwVYyT5YTZx9cPc/seCIJ4IW0u
# cZCQQwanOFPgVYmaDMPW/WsCRLdd4XeMuHYtgYkjsrzmbNLmSqGCF3YwghdyBgor
# BgEEAYI3AwMBMYIXYjCCF14GCSqGSIb3DQEHAqCCF08wghdLAgEDMQ8wDQYJYIZI
# AWUDBAIBBQAwdwYLKoZIhvcNAQkQAQSgaARmMGQCAQEGCWCGSAGG/WwHATAxMA0G
# CWCGSAFlAwQCAQUABCBEQ0l8nqgs8s3lKgl+5HWR94B9GoQ0eoHSNjQws8TRSwIQ
# URCASQdLgkuCx98gmD/inRgPMjAyNTA5MTYwMTA2NTdaoIITOjCCBu0wggTVoAMC
# AQICEAqA7xhLjfEFgtHEdqeVdGgwDQYJKoZIhvcNAQELBQAwaTELMAkGA1UEBhMC
# VVMxFzAVBgNVBAoTDkRpZ2lDZXJ0LCBJbmMuMUEwPwYDVQQDEzhEaWdpQ2VydCBU
# cnVzdGVkIEc0IFRpbWVTdGFtcGluZyBSU0E0MDk2IFNIQTI1NiAyMDI1IENBMTAe
# Fw0yNTA2MDQwMDAwMDBaFw0zNjA5MDMyMzU5NTlaMGMxCzAJBgNVBAYTAlVTMRcw
# FQYDVQQKEw5EaWdpQ2VydCwgSW5jLjE7MDkGA1UEAxMyRGlnaUNlcnQgU0hBMjU2
# IFJTQTQwOTYgVGltZXN0YW1wIFJlc3BvbmRlciAyMDI1IDEwggIiMA0GCSqGSIb3
# DQEBAQUAA4ICDwAwggIKAoICAQDQRqwtEsae0OquYFazK1e6b1H/hnAKAd/KN8wZ
# QjBjMqiZ3xTWcfsLwOvRxUwXcGx8AUjni6bz52fGTfr6PHRNv6T7zsf1Y/E3IU8k
# gNkeECqVQ+3bzWYesFtkepErvUSbf+EIYLkrLKd6qJnuzK8Vcn0DvbDMemQFoxQ2
# Dsw4vEjoT1FpS54dNApZfKY61HAldytxNM89PZXUP/5wWWURK+IfxiOg8W9lKMqz
# dIo7VA1R0V3Zp3DjjANwqAf4lEkTlCDQ0/fKJLKLkzGBTpx6EYevvOi7XOc4zyh1
# uSqgr6UnbksIcFJqLbkIXIPbcNmA98Oskkkrvt6lPAw/p4oDSRZreiwB7x9ykrjS
# 6GS3NR39iTTFS+ENTqW8m6THuOmHHjQNC3zbJ6nJ6SXiLSvw4Smz8U07hqF+8CTX
# aETkVWz0dVVZw7knh1WZXOLHgDvundrAtuvz0D3T+dYaNcwafsVCGZKUhQPL1naF
# KBy1p6llN3QgshRta6Eq4B40h5avMcpi54wm0i2ePZD5pPIssoszQyF4//3DoK2O
# 65Uck5Wggn8O2klETsJ7u8xEehGifgJYi+6I03UuT1j7FnrqVrOzaQoVJOeeStPe
# ldYRNMmSF3voIgMFtNGh86w3ISHNm0IaadCKCkUe2LnwJKa8TIlwCUNVwppwn4D3
# /Pt5pwIDAQABo4IBlTCCAZEwDAYDVR0TAQH/BAIwADAdBgNVHQ4EFgQU5Dv88jHt
# /f3X85FxYxlQQ89hjOgwHwYDVR0jBBgwFoAU729TSunkBnx6yuKQVvYv1Ensy04w
# DgYDVR0PAQH/BAQDAgeAMBYGA1UdJQEB/wQMMAoGCCsGAQUFBwMIMIGVBggrBgEF
# BQcBAQSBiDCBhTAkBggrBgEFBQcwAYYYaHR0cDovL29jc3AuZGlnaWNlcnQuY29t
# MF0GCCsGAQUFBzAChlFodHRwOi8vY2FjZXJ0cy5kaWdpY2VydC5jb20vRGlnaUNl
# cnRUcnVzdGVkRzRUaW1lU3RhbXBpbmdSU0E0MDk2U0hBMjU2MjAyNUNBMS5jcnQw
# XwYDVR0fBFgwVjBUoFKgUIZOaHR0cDovL2NybDMuZGlnaWNlcnQuY29tL0RpZ2lD
# ZXJ0VHJ1c3RlZEc0VGltZVN0YW1waW5nUlNBNDA5NlNIQTI1NjIwMjVDQTEuY3Js
# MCAGA1UdIAQZMBcwCAYGZ4EMAQQCMAsGCWCGSAGG/WwHATANBgkqhkiG9w0BAQsF
# AAOCAgEAZSqt8RwnBLmuYEHs0QhEnmNAciH45PYiT9s1i6UKtW+FERp8FgXRGQ/Y
# AavXzWjZhY+hIfP2JkQ38U+wtJPBVBajYfrbIYG+Dui4I4PCvHpQuPqFgqp1PzC/
# ZRX4pvP/ciZmUnthfAEP1HShTrY+2DE5qjzvZs7JIIgt0GCFD9ktx0LxxtRQ7vll
# KluHWiKk6FxRPyUPxAAYH2Vy1lNM4kzekd8oEARzFAWgeW3az2xejEWLNN4eKGxD
# J8WDl/FQUSntbjZ80FU3i54tpx5F/0Kr15zW/mJAxZMVBrTE2oi0fcI8VMbtoRAm
# aaslNXdCG1+lqvP4FbrQ6IwSBXkZagHLhFU9HCrG/syTRLLhAezu/3Lr00GrJzPQ
# FnCEH1Y58678IgmfORBPC1JKkYaEt2OdDh4GmO0/5cHelAK2/gTlQJINqDr6Jfwy
# YHXSd+V08X1JUPvB4ILfJdmL+66Gp3CSBXG6IwXMZUXBhtCyIaehr0XkBoDIGMUG
# 1dUtwq1qmcwbdUfcSYCn+OwncVUXf53VJUNOaMWMts0VlRYxe5nK+At+DI96HAlX
# HAL5SlfYxJ7La54i71McVWRP66bW+yERNpbJCjyCYG2j+bdpxo/1Cy4uPcU3AWVP
# Grbn5PhDBf3Froguzzhk++ami+r3Qrx5bIbY3TVzgiFI7Gq3zWcwgga0MIIEnKAD
# AgECAhANx6xXBf8hmS5AQyIMOkmGMA0GCSqGSIb3DQEBCwUAMGIxCzAJBgNVBAYT
# AlVTMRUwEwYDVQQKEwxEaWdpQ2VydCBJbmMxGTAXBgNVBAsTEHd3dy5kaWdpY2Vy
# dC5jb20xITAfBgNVBAMTGERpZ2lDZXJ0IFRydXN0ZWQgUm9vdCBHNDAeFw0yNTA1
# MDcwMDAwMDBaFw0zODAxMTQyMzU5NTlaMGkxCzAJBgNVBAYTAlVTMRcwFQYDVQQK
# Ew5EaWdpQ2VydCwgSW5jLjFBMD8GA1UEAxM4RGlnaUNlcnQgVHJ1c3RlZCBHNCBU
# aW1lU3RhbXBpbmcgUlNBNDA5NiBTSEEyNTYgMjAyNSBDQTEwggIiMA0GCSqGSIb3
# DQEBAQUAA4ICDwAwggIKAoICAQC0eDHTCphBcr48RsAcrHXbo0ZodLRRF51NrY0N
# lLWZloMsVO1DahGPNRcybEKq+RuwOnPhof6pvF4uGjwjqNjfEvUi6wuim5bap+0l
# gloM2zX4kftn5B1IpYzTqpyFQ/4Bt0mAxAHeHYNnQxqXmRinvuNgxVBdJkf77S2u
# PoCj7GH8BLuxBG5AvftBdsOECS1UkxBvMgEdgkFiDNYiOTx4OtiFcMSkqTtF2hfQ
# z3zQSku2Ws3IfDReb6e3mmdglTcaarps0wjUjsZvkgFkriK9tUKJm/s80FiocSk1
# VYLZlDwFt+cVFBURJg6zMUjZa/zbCclF83bRVFLeGkuAhHiGPMvSGmhgaTzVyhYn
# 4p0+8y9oHRaQT/aofEnS5xLrfxnGpTXiUOeSLsJygoLPp66bkDX1ZlAeSpQl92QO
# MeRxykvq6gbylsXQskBBBnGy3tW/AMOMCZIVNSaz7BX8VtYGqLt9MmeOreGPRdtB
# x3yGOP+rx3rKWDEJlIqLXvJWnY0v5ydPpOjL6s36czwzsucuoKs7Yk/ehb//Wx+5
# kMqIMRvUBDx6z1ev+7psNOdgJMoiwOrUG2ZdSoQbU2rMkpLiQ6bGRinZbI4OLu9B
# MIFm1UUl9VnePs6BaaeEWvjJSjNm2qA+sdFUeEY0qVjPKOWug/G6X5uAiynM7Bu2
# ayBjUwIDAQABo4IBXTCCAVkwEgYDVR0TAQH/BAgwBgEB/wIBADAdBgNVHQ4EFgQU
# 729TSunkBnx6yuKQVvYv1Ensy04wHwYDVR0jBBgwFoAU7NfjgtJxXWRM3y5nP+e6
# mK4cD08wDgYDVR0PAQH/BAQDAgGGMBMGA1UdJQQMMAoGCCsGAQUFBwMIMHcGCCsG
# AQUFBwEBBGswaTAkBggrBgEFBQcwAYYYaHR0cDovL29jc3AuZGlnaWNlcnQuY29t
# MEEGCCsGAQUFBzAChjVodHRwOi8vY2FjZXJ0cy5kaWdpY2VydC5jb20vRGlnaUNl
# cnRUcnVzdGVkUm9vdEc0LmNydDBDBgNVHR8EPDA6MDigNqA0hjJodHRwOi8vY3Js
# My5kaWdpY2VydC5jb20vRGlnaUNlcnRUcnVzdGVkUm9vdEc0LmNybDAgBgNVHSAE
# GTAXMAgGBmeBDAEEAjALBglghkgBhv1sBwEwDQYJKoZIhvcNAQELBQADggIBABfO
# +xaAHP4HPRF2cTC9vgvItTSmf83Qh8WIGjB/T8ObXAZz8OjuhUxjaaFdleMM0lBr
# yPTQM2qEJPe36zwbSI/mS83afsl3YTj+IQhQE7jU/kXjjytJgnn0hvrV6hqWGd3r
# LAUt6vJy9lMDPjTLxLgXf9r5nWMQwr8Myb9rEVKChHyfpzee5kH0F8HABBgr0Udq
# irZ7bowe9Vj2AIMD8liyrukZ2iA/wdG2th9y1IsA0QF8dTXqvcnTmpfeQh35k5zO
# CPmSNq1UH410ANVko43+Cdmu4y81hjajV/gxdEkMx1NKU4uHQcKfZxAvBAKqMVuq
# te69M9J6A47OvgRaPs+2ykgcGV00TYr2Lr3ty9qIijanrUR3anzEwlvzZiiyfTPj
# LbnFRsjsYg39OlV8cipDoq7+qNNjqFzeGxcytL5TTLL4ZaoBdqbhOhZ3ZRDUphPv
# SRmMThi0vw9vODRzW6AxnJll38F0cuJG7uEBYTptMSbhdhGQDpOXgpIUsWTjd6xp
# R6oaQf/DJbg3s6KCLPAlZ66RzIg9sC+NJpud/v4+7RWsWCiKi9EOLLHfMR2ZyJ/+
# xhCx9yHbxtl5TPau1j/1MIDpMPx0LckTetiSuEtQvLsNz3Qbp7wGWqbIiOWCnb5W
# qxL3/BAPvIXKUjPSxyZsq8WhbaM2tszWkPZPubdcMIIFjTCCBHWgAwIBAgIQDpsY
# jvnQLefv21DiCEAYWjANBgkqhkiG9w0BAQwFADBlMQswCQYDVQQGEwJVUzEVMBMG
# A1UEChMMRGlnaUNlcnQgSW5jMRkwFwYDVQQLExB3d3cuZGlnaWNlcnQuY29tMSQw
# IgYDVQQDExtEaWdpQ2VydCBBc3N1cmVkIElEIFJvb3QgQ0EwHhcNMjIwODAxMDAw
# MDAwWhcNMzExMTA5MjM1OTU5WjBiMQswCQYDVQQGEwJVUzEVMBMGA1UEChMMRGln
# aUNlcnQgSW5jMRkwFwYDVQQLExB3d3cuZGlnaWNlcnQuY29tMSEwHwYDVQQDExhE
# aWdpQ2VydCBUcnVzdGVkIFJvb3QgRzQwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAw
# ggIKAoICAQC/5pBzaN675F1KPDAiMGkz7MKnJS7JIT3yithZwuEppz1Yq3aaza57
# G4QNxDAf8xukOBbrVsaXbR2rsnnyyhHS5F/WBTxSD1Ifxp4VpX6+n6lXFllVcq9o
# k3DCsrp1mWpzMpTREEQQLt+C8weE5nQ7bXHiLQwb7iDVySAdYyktzuxeTsiT+CFh
# mzTrBcZe7FsavOvJz82sNEBfsXpm7nfISKhmV1efVFiODCu3T6cw2Vbuyntd463J
# T17lNecxy9qTXtyOj4DatpGYQJB5w3jHtrHEtWoYOAMQjdjUN6QuBX2I9YI+EJFw
# q1WCQTLX2wRzKm6RAXwhTNS8rhsDdV14Ztk6MUSaM0C/CNdaSaTC5qmgZ92kJ7yh
# Tzm1EVgX9yRcRo9k98FpiHaYdj1ZXUJ2h4mXaXpI8OCiEhtmmnTK3kse5w5jrubU
# 75KSOp493ADkRSWJtppEGSt+wJS00mFt6zPZxd9LBADMfRyVw4/3IbKyEbe7f/LV
# jHAsQWCqsWMYRJUadmJ+9oCw++hkpjPRiQfhvbfmQ6QYuKZ3AeEPlAwhHbJUKSWJ
# bOUOUlFHdL4mrLZBdd56rF+NP8m800ERElvlEFDrMcXKchYiCd98THU/Y+whX8Qg
# UWtvsauGi0/C1kVfnSD8oR7FwI+isX4KJpn15GkvmB0t9dmpsh3lGwIDAQABo4IB
# OjCCATYwDwYDVR0TAQH/BAUwAwEB/zAdBgNVHQ4EFgQU7NfjgtJxXWRM3y5nP+e6
# mK4cD08wHwYDVR0jBBgwFoAUReuir/SSy4IxLVGLp6chnfNtyA8wDgYDVR0PAQH/
# BAQDAgGGMHkGCCsGAQUFBwEBBG0wazAkBggrBgEFBQcwAYYYaHR0cDovL29jc3Au
# ZGlnaWNlcnQuY29tMEMGCCsGAQUFBzAChjdodHRwOi8vY2FjZXJ0cy5kaWdpY2Vy
# dC5jb20vRGlnaUNlcnRBc3N1cmVkSURSb290Q0EuY3J0MEUGA1UdHwQ+MDwwOqA4
# oDaGNGh0dHA6Ly9jcmwzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydEFzc3VyZWRJRFJv
# b3RDQS5jcmwwEQYDVR0gBAowCDAGBgRVHSAAMA0GCSqGSIb3DQEBDAUAA4IBAQBw
# oL9DXFXnOF+go3QbPbYW1/e/Vwe9mqyhhyzshV6pGrsi+IcaaVQi7aSId229GhT0
# E0p6Ly23OO/0/4C5+KH38nLeJLxSA8hO0Cre+i1Wz/n096wwepqLsl7Uz9FDRJtD
# IeuWcqFItJnLnU+nBgMTdydE1Od/6Fmo8L8vC6bp8jQ87PcDx4eo0kxAGTVGamlU
# sLihVo7spNU96LHc/RzY9HdaXFSMb++hUD38dglohJ9vytsgjTVgHAIDyyCwrFig
# DkBjxZgiwbJZ9VVrzyerbHbObyMt9H5xaiNrIv8SuFQtJ37YOtnwtoeW/VvRXKwY
# w02fc7cBqZ9Xql4o4rmUMYIDfDCCA3gCAQEwfTBpMQswCQYDVQQGEwJVUzEXMBUG
# A1UEChMORGlnaUNlcnQsIEluYy4xQTA/BgNVBAMTOERpZ2lDZXJ0IFRydXN0ZWQg
# RzQgVGltZVN0YW1waW5nIFJTQTQwOTYgU0hBMjU2IDIwMjUgQ0ExAhAKgO8YS43x
# BYLRxHanlXRoMA0GCWCGSAFlAwQCAQUAoIHRMBoGCSqGSIb3DQEJAzENBgsqhkiG
# 9w0BCRABBDAcBgkqhkiG9w0BCQUxDxcNMjUwOTE2MDEwNjU3WjArBgsqhkiG9w0B
# CRACDDEcMBowGDAWBBTdYjCshgotMGvaOLFoeVIwB/tBfjAvBgkqhkiG9w0BCQQx
# IgQgbYYeCo8HLMa4njNofHjMTARKnLba/dFW97eJnQe8PDEwNwYLKoZIhvcNAQkQ
# Ai8xKDAmMCQwIgQgSqA/oizXXITFXJOPgo5na5yuyrM/420mmqM08UYRCjMwDQYJ
# KoZIhvcNAQEBBQAEggIAt5CRV8/ThPcyQexXtX3yk/NAaoZzkNEjLxJccW9eUy80
# XAye5ZwfyX6yHaJKpGdI7PXVPqL2Qjc4nI7hs2acF6+KzEeniF797jncfxX9Gc3k
# Oe4oZrKN2xK4xkGPwB9ZPOa1pidyTliNZ399c7FJVyuwRr6OSRX+Lo3gW5bAyPli
# Mrpz5Gwus7/AVdhZ1mbDT9oDt/osvOklzR4r6kBJel1pHZko81+mIgKXKF26fsU1
# FXuILZxHzBVFsVe0AyOSo/MJhCuh9Ogk49SJIvNJQBc6iDePnvnZHT6UzMJ9J97a
# z4Eu223UE5Ne3oLW0Ka1FsBnABnN46RfEdHIRP4dNiyyb68xJ/pPJ1njrZRiFCSC
# FaSHlFnYsfa1d4pRpMMyKaY/HWoRmFJJ2vCjB9UlGtuQo71MOT+9MAfp8DYxEA0z
# QujmjOyiGBnYF7fIxeZzMgekMxqjc096spqVL+Yw7e1bnptLBABm5cSr3Dk4i2OA
# Wrg7eEdjn4oYmT03mIyg8BWan35A9B9yKV79+ckICRFpFD1IsMYG5QQ1puTGe/U0
# FOivmYe0NaXSe7TuQ8WVcDjRZ9f30KESv4KVzk2W+74DdsNFmOWX4ZyCQPNRleIr
# 1X8XLNAMWMMNszMF5LchbQKrAPCTIm0EdXedqFeOCXFprIqI6j6sAQhduIuZUSY=
# SIG # End signature block
