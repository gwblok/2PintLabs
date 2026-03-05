<#
.SYNOPSIS
Functions to enumerate Microsoft Deployment Toolkit (MDT) Deployment Share Applications and extract metadata.

.DESCRIPTION
Get-MDTApplications connects to a local MDT deployment share folder (path) and enumerates application definition folders under the "Applications" directory.
It loads application XML files it finds and maps common MDT properties to a PowerShell custom object for easy reporting.

The function is resilient: it searches each application folder for any XML files and looks for common nodes (Name, ShortName, Version, Publisher, CommandLine, WorkingDirectory, UninstallKey, Reboot, Language). If a node isn't present it leaves the property blank.


# Enumerate apps from a local deployment share folder
Get-MDTApplications -DeploymentSharePath 'E:\psd' | Format-Table -AutoSize

# Save the applications to CSV
Get-MDTApplications -DeploymentSharePath 'E:\psd' | Export-Csv apps.csv -NoTypeInformation
#>

function Get-MDTDeploymentShare {
    [CmdletBinding()]
    param(
    [Parameter(Mandatory=$true, Position=0)]
    [ValidateNotNullOrEmpty()]
    [string] $Path
    )
    
    if (-not (Test-Path -LiteralPath $Path)) {
        Throw "Deployment share path '$Path' does not exist."
    }
    
    $full = (Get-Item -LiteralPath $Path).FullName
    
    $appsFolder  = Join-Path -Path $full -ChildPath 'Applications'
    $controlFile = Join-Path -Path $full -ChildPath 'Control\Applications.xml'
    
    if (-not (Test-Path -LiteralPath $appsFolder)) {
        Throw "Path '$full' does not look like an MDT deployment share (missing 'Applications' folder)."
    }
    if (-not (Test-Path -LiteralPath $controlFile)) {
        Throw "Path '$full' does not look like an MDT deployment share (missing 'Control\Applications.xml')."
    }
    
    return @{
        Path                = $full
        ApplicationsPath    = $appsFolder
        ApplicationsXmlPath = $controlFile
    }
}

function Get-PSInstallCommand {
    <#
    .SYNOPSIS
    Parses an install.ps1 file and reconstructs the Start-Process command line string.
    
    .DESCRIPTION
    Uses the PowerShell AST to locate the last non-Robocopy HashtableAst that has a FilePath
    key (and optionally an ArgumentList key), mirroring the Start-Process splatting pattern
    used in PSD-style install scripts. Returns the reconstructed command line string, or $null
    if no suitable hashtable is found (e.g. file-staging-only scripts).
    
    .PARAMETER Path
    Full path to the install.ps1 file to parse.
    #>
    [CmdletBinding()]
    param(
    [Parameter(Mandatory=$true)]
    [string] $Path
    )
    
    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Verbose "install.ps1 not found at: $Path"
        return $null
    }
    
    try {
        $scriptContent = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
        $ast = [System.Management.Automation.Language.Parser]::ParseInput(
        $scriptContent, [ref]$null, [ref]$null
        )
    }
    catch {
        Write-Verbose "Failed to parse '$Path': $_"
        return $null
    }
    
    # Find all HashtableAst nodes that have at least a FilePath key
    $spHashtables = $ast.FindAll({
        param($node)
        if (-not ($node -is [System.Management.Automation.Language.HashtableAst])) { return $false }
        $keys = $node.KeyValuePairs | ForEach-Object { $_.Item1.Value }
        $keys -contains 'FilePath'
    }, $true)
    
    if (-not $spHashtables) {
        Write-Verbose "No Start-Process hashtable found in '$Path'"
        return $null
    }
    
    # Skip Robocopy hashtables. Among the remaining candidates, prefer the LAST one
    # with a quoted FilePath (prerequisites run before the main install, so the last
    # quoted-FilePath hashtable is typically the main installer).
    # Fall back to the last candidate of any kind if none have a quoted FilePath.
    $candidates = $spHashtables | Where-Object {
        $fpPair = $_.KeyValuePairs | Where-Object { $_.Item1.Value -eq 'FilePath' } | Select-Object -First 1
        $fpText = $fpPair.Item2.Extent.Text
        $fpText -notmatch '(?i)Robocopy'
    }
    
    # Prefer last candidate whose FilePath is a quoted string literal (not a bare variable)
    $installHt = $candidates | Where-Object {
        $fpPair = $_.KeyValuePairs | Where-Object { $_.Item1.Value -eq 'FilePath' } | Select-Object -First 1
        $fpText = $fpPair.Item2.Extent.Text.Trim()
        $fpText -match '^[''"]' -or $fpText -match '^[($].*[''"]'
    } | Select-Object -Last 1
    
    # If none had a quoted FilePath, take the last candidate of any kind
    if (-not $installHt) { $installHt = $candidates | Select-Object -Last 1 }
    
    if (-not $installHt) {
        Write-Verbose "Only Robocopy hashtables found in '$Path' (file-staging script, no install)"
        return $null
    }
    
    # -----------------------------------------------------------------------
    # Helper: extract a clean executable name from a FilePath expression raw text.
    # Strategy: collect all quoted tokens, pick the last one that looks like a
    # filename (contains a dot or ends in .exe/.msi/.bat etc).
    #   "msiexec.exe"                              -> msiexec.exe
    #   ($PSScriptRoot, "setup.exe" -join '\')     -> setup.exe
    #   $var, 'Install.exe' -join '\'              -> Install.exe
    #   'C:\Windows\System32\PNPUtil.exe'          -> PNPUtil.exe
    #   $var, "Files", "prereq", "boot.exe" -join  -> boot.exe
    # -----------------------------------------------------------------------
    function Get-FilePathValue ($rawText) {
        if ([string]::IsNullOrWhiteSpace($rawText)) { return $null }
        $text = $rawText.Trim()
        # Collect all quoted tokens (double or single quoted)
        $allMatches = [regex]::Matches($text, '"([^"]+)"|''([^'']+)''')
        # Pick the last token that looks like a filename (has a dot, or contains a path separator)
        $fileToken = $null
        for ($i = $allMatches.Count - 1; $i -ge 0; $i--) {
            $m = $allMatches[$i]
            $tok = if ($m.Groups[1].Success) { $m.Groups[1].Value } else { $m.Groups[2].Value }
            # A filename has a dot in it (extension) and is not just a separator
            if ($tok -match '\.' -and $tok -notmatch '^\\+$') {
                $fileToken = $tok
                break
            }
        }
        if ($fileToken) {
            # Return just the filename portion (strip any path prefix)
            return [System.IO.Path]::GetFileName($fileToken)
        }
        # No quoted filename found: strip $vars and backslashes, return bare identifier
        $text = $text -replace '\$\w[\w.]*', '' -replace '\\', '' -replace '\s+', ''
        return $text.Trim()
    }
    
    # -----------------------------------------------------------------------
    # Helper: clean a single argument string token.
    # Each element of ArgumentList is an extent text string. We want to keep
    # the static flag/switch parts and replace dynamic $(...) path subexpressions
    # with just the quoted filename inside them.
    #   "/qn"                                      -> /qn
    #   "/I `"$($var, "file.msi" -join '\'))`""   -> /I "file.msi"
    #   "/I `"$PSScriptRoot\file.msi`""            -> /I "file.msi"
    #   "SITE_TOKEN=abc123"                        -> SITE_TOKEN=abc123
    # -----------------------------------------------------------------------
    # Helper: clean a single argument element to a plain string.
    # Works on the expression object directly for best accuracy.
    # -----------------------------------------------------------------------
    function Format-ArgElement ($elemExpr) {
        if ($null -eq $elemExpr) { return $null }
        
        if ($elemExpr -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
            # Plain 'single' or "double" quoted string — .Value strips the quotes
            return $elemExpr.Value
        }
        
        # ExpandableStringExpressionAst: "/I `"$(...))`"" etc.
        # Strategy: work on the extent text, surgically remove dynamic portions.
        $s = $elemExpr.Extent.Text
        
        # Strip the outer string delimiter (first and last character, which is the quote char)
        if ($s.Length -ge 2) { $s = $s.Substring(1, $s.Length - 2) }
        
        # Replace escaped-quote sequences (`") with real quotes
        $s = $s -replace '`"', '"'
        
        # Replace $(...) subexpressions — scan for balanced parens
        $result = [System.Text.StringBuilder]::new()
        $i = 0
        while ($i -lt $s.Length) {
            if ($i + 1 -lt $s.Length -and $s[$i] -eq '$' -and $s[$i+1] -eq '(') {
                # Find the matching closing paren (balanced)
                $depth = 0; $j = $i + 1
                while ($j -lt $s.Length) {
                    if ($s[$j] -eq '(') { $depth++ }
                    elseif ($s[$j] -eq ')') { $depth--; if ($depth -eq 0) { break } }
                    $j++
                }
                # $s[$i..$j] is the full $(...) expression
                $inner = $s.Substring($i + 2, $j - $i - 2)  # strip $( and )
                # Extract the last filename-like quoted token inside
                $qms = [regex]::Matches($inner, '"([^"]+)"|''([^'']+)''')
                $fn = $null
                for ($k = $qms.Count - 1; $k -ge 0; $k--) {
                    $tok = if ($qms[$k].Groups[1].Success) { $qms[$k].Groups[1].Value } else { $qms[$k].Groups[2].Value }
                    if ($tok -match '\.' -and $tok -notmatch '^\\+$') { $fn = [System.IO.Path]::GetFileName($tok); break }
                }
                if ($fn) { [void]$result.Append($fn) }
                $i = $j + 1
            }
            elseif ($s[$i] -eq '$') {
                # Simple $variable — skip to end of variable name
                $j = $i + 1
                while ($j -lt $s.Length -and ($s[$j] -match '[\w.]')) { $j++ }
                # Skip a trailing backslash that's part of the path prefix
                if ($j -lt $s.Length -and $s[$j] -eq '\') { $j++ }
                $i = $j
            }
            else {
                [void]$result.Append($s[$i])
                $i++
            }
        }
        $clean = $result.ToString().Trim()
        # Remove stray leading/trailing backslashes and trim
        $clean = $clean -replace '^\\+', '' -replace '\\+$', ''
        return $clean.Trim()
    }
    
    # ---- Extract FilePath ----
    $fpPair = $installHt.KeyValuePairs | Where-Object { $_.Item1.Value -eq 'FilePath' } | Select-Object -First 1
    $fpRaw  = $fpPair.Item2.Extent.Text
    $filePath = Get-FilePathValue $fpRaw
    Write-Verbose "FilePath raw: $fpRaw  => $filePath"
    
    # ---- Extract ArgumentList (optional) ----
    $alPair = $installHt.KeyValuePairs | Where-Object { $_.Item1.Value -eq 'ArgumentList' } | Select-Object -First 1
    
    # ---- Early edge-case check: bail before arg parsing if key values are unresolvable ----
    $fpRawTrim = $fpRaw.Trim()
    $isEdgeCaseFilePath = [string]::IsNullOrWhiteSpace($filePath) -or
    ($fpRawTrim -match '^\$\w' -and $fpRawTrim -notmatch '[''"]') -or
    ($filePath -match '\$\w')   # filename itself still contains a variable
    $isEdgeCaseArgList  = $alPair -and
    ($alPair.Item2.PipelineElements[0].Expression -is
    [System.Management.Automation.Language.VariableExpressionAst])
    if ($isEdgeCaseFilePath -or $isEdgeCaseArgList) {
        Write-Verbose "Edge case detected in '$Path' (FilePath or ArgumentList is a runtime variable)"
        return 'Edge Case, see install.ps1'
    }
    
    $argTokens = @()
    
    if ($alPair) {
        $alExpr = $alPair.Item2.PipelineElements[0].Expression
        
        if ($alExpr -is [System.Management.Automation.Language.ArrayExpressionAst]) {
            # @( "arg1", "arg2", ... ) — each statement is one element
            foreach ($stmt in $alExpr.SubExpression.Statements) {
                $elemExpr = $null
                if ($stmt.PipelineElements) {
                    $pe = $stmt.PipelineElements[0]
                    if ($pe.PSObject.Properties['Expression']) { $elemExpr = $pe.Expression }
                }
                if ($null -eq $elemExpr) { continue }
                
                $cleaned = Format-ArgElement $elemExpr
                if ($cleaned) { $argTokens += $cleaned }
            }
        }
        elseif ($alExpr -is [System.Management.Automation.Language.VariableExpressionAst]) {
            # ArgumentList = $ArgumentList  — variable reference, skip (can't resolve statically)
            Write-Verbose "ArgumentList is a variable reference in '$Path', skipping arg extraction"
        }
        else {
            # Single string argument
            $cleaned = Format-ArgElement $alExpr
            if ($cleaned) { $argTokens += $cleaned }
        }
    }
    
    if (-not $filePath -and -not $argTokens) { return $null }
    
    $cmdLine = if ($argTokens) { "$filePath $($argTokens -join ' ')" } else { $filePath }
    $cmdLine  = $cmdLine.Trim()
    
    # If the assembled command line still contains unresolved $variables, flag as edge case
    if ($cmdLine -match '\$\w') {
        Write-Verbose "Edge case: assembled command line still contains runtime variables in '$Path'"
        return 'Edge Case, see install.ps1'
    }
    
    return $cmdLine
}

function Get-MDTApplications {
    <#
    .SYNOPSIS
    Enumerate Applications from an MDT Deployment Share and return their metadata.
    
    .DESCRIPTION
    Reads Control\Applications.xml (the single source of truth in an MDT/PSD share) and
    returns one PSObject per <application> node with all relevant fields.
    
    .PARAMETER DeploymentSharePath
    Path to the MDT Deployment Share root (the folder that contains Control\ and Applications\).
    
    .PARAMETER EnabledOnly
    When specified, only returns applications where enable="True" (default: all).
    
    .OUTPUTS PSObject
    Objects with properties:
    GUID, Name, ShortName, Version, Publisher, Language,
    MDTCommandLine, PSCommandLine, WorkingDirectory, UninstallKey, Reboot, HelpText,
    Source, ApplicationFolder, Enabled, Hidden,
    CreatedTime, CreatedBy, LastModifiedTime, LastModifiedBy, Dependency
    
    .EXAMPLE
    Get-MDTApplications -DeploymentSharePath 'E:\AmplifonPSD\psd' | Format-Table Name,Publisher,Version,CommandLine -AutoSize
    
    .EXAMPLE
    Get-MDTApplications 'E:\AmplifonPSD\psd' | Export-Csv C:\Temp\MDTApps.csv -NoTypeInformation
    #>
    [CmdletBinding()]
    param(
    [Parameter(Mandatory=$true, Position=0)]
    [string] $DeploymentSharePath,
    
    [Parameter()]
    [switch] $EnabledOnly
    )
    
    $share   = Get-MDTDeploymentShare -Path $DeploymentSharePath
    $xmlPath = $share.ApplicationsXmlPath
    $sharePath = $share.Path
    
    Write-Verbose "Reading applications from: $xmlPath"
    
    try {
        [xml]$doc = Get-Content -LiteralPath $xmlPath -Raw -ErrorAction Stop
    }
    catch {
        Throw "Failed to read '$xmlPath': $_"
    }
    
    $nodes = $doc.SelectNodes('//application')
    if ($null -eq $nodes -or $nodes.Count -eq 0) {
        Write-Warning "No <application> nodes found in '$xmlPath'."
        return
    }
    
    Write-Verbose "Found $($nodes.Count) application node(s)."
    
    $results = foreach ($app in $nodes) {
        
        $enabled = $app.GetAttribute('enable')
        $hidden  = $app.GetAttribute('hide')
        
        if ($EnabledOnly -and $enabled -ne 'True') { continue }
        
        # Resolve the absolute ApplicationFolder path from the Source element
        $source = if ($app.Source) { $app.Source.Trim() } else { '' }
        # Source values use .\Applications\... relative to the share root
        $appFolder = if ($source -ne '') {
            $resolved = $source -replace '^\.\\', ''   # strip leading .\
            Join-Path -Path $sharePath -ChildPath $resolved
        } else { '' }
        
        # Parse install.ps1 in the application folder for the PS-native command line
        $installPs1 = if ($appFolder -ne '') { Join-Path -Path $appFolder -ChildPath 'install.ps1' } else { '' }
        $psCommandLine = Get-PSInstallCommand -Path $installPs1
        
        [PSCustomObject]@{
            GUID             = $app.GetAttribute('guid')
            Name             = $app.Name
            ShortName        = $app.ShortName
            Version          = $app.Version
            Publisher        = $app.Publisher
            Language         = $app.Language
            MDTCommandLine   = $app.CommandLine
            PSCommandLine    = $psCommandLine
            WorkingDirectory = $app.WorkingDirectory
            UninstallKey     = $app.UninstallKey
            Reboot           = $app.Reboot
            HelpText         = $app.HelpText
            Source           = $source
            ApplicationFolder= $appFolder
            Enabled          = $enabled
            Hidden           = $hidden
            CreatedTime      = $app.CreatedTime
            CreatedBy        = $app.CreatedBy
            LastModifiedTime = $app.LastModifiedTime
            LastModifiedBy   = $app.LastModifiedBy
            Dependency       = $app.Dependency
        }
    }
    
    return $results
}

Function New-DeployRApp {
    Param (
    [string]$AppName,
    [string]$AppSourceFolder,
    [string]$AppDescription = "No Description Provided",
    [string]$AppVerDescription = "No Version Description Provided",
    [string]$InstallationCommandLine = ""
    )
    
    $NewDRCI = New-DeployRContentItem -Type Folder -Name $AppName -Description $AppDescription -Purpose Application
    New-DeployRContentItemVersion -ContentItemId $NewDRCI.id -SourceFolder $AppSourceFolder -InstallationCommandLine $InstallationCommandLine -Description $AppVerDescription
}


$MDTApps = Get-MDTApplications -DeploymentSharePath 'E:\psd' -EnabledOnly
#$MDTAppsTest = $MDTApps | Where-Object {$_.Name -match ".Net"}
$AllDeployRApps = Get-DeployRApplication
$existingApp = $null
foreach ($app in $MDTApps){
    #Test if App already exists in DeployR
    $DoesNotExist = $true
    try {
        
        $existingApp = $AllDeployRApps | Where-Object { $_.Name -eq $app.Name }
        if ($existingApp) {
            Write-Host "App '$($app.Name)' already exists in DeployR. Skipping creation." -ForegroundColor Yellow
            $DoesNotExist = $false
            continue
        }
    }
    catch {
        Write-Host "App '$($app.Name)' does not exist in DeployR. Proceeding with creation." -ForegroundColor Green
    }
    
    if ($DoesNotExist) {
        
        $AppPath = $app.ApplicationFolder
        $InstallPS1Path = Join-Path -Path $AppPath -ChildPath 'install.ps1'
        $AppWIM = Get-ChildItem -Path $AppPath -Filter *.wim
        #MountWIM to Temp Location
        $MountPath = "C:\Temp\WIMMount"
        if (!(Test-Path -LiteralPath $MountPath)) {
            New-Item -ItemType Directory -Path $MountPath | Out-Null
        }
        Mount-WindowsImage -ImagePath $AppWIM.FullName -Index 1 -Path $MountPath
        #Copy the install.ps1 file to the temp mount location
        if (Test-Path -LiteralPath $InstallPS1Path) {
            Write-Host " Copying install.ps1 for app '$($app.Name)' to mount path: $MountPath" -ForegroundColor DarkGray
            Copy-Item -Path $InstallPS1Path -Destination $MountPath -Force | Out-Null
        } else {
            Write-Verbose "install.ps1 not found for app '$($app.Name)' at expected path: $InstallPS1Path"
        }
        $MDTCmdLine = $app.MDTCommandLine

        Write-Host " Creating DeployR app for '$($app.Name)' with source folder: $MountPath" -ForegroundColor Cyan
        #Create DeployR App with extracted command line and source folder
        New-DeployRApp -AppName $app.Name -AppSourceFolder $MountPath -AppDescription "Imported from MDT" -InstallationCommandLine $MDTCmdLine -AppVerDescription "Version: $($app.Version); Publisher: $($app.Publisher)"
        
        Write-Host " Successfully created DeployR app for '$($app.Name)'. Cleaning up mount." -ForegroundColor Green
        #Dismount WIM
        Dismount-WindowsImage -Path $MountPath -Discard
        Start-Sleep -Seconds 1
        
        #Cleanup temp mount directory
        Remove-Item -Path $MountPath -Force
        Start-Sleep -Seconds 1
    }
    
}