# NO SUPPORT | THIS IS PROVIDED "AS IS" WITHOUT WARRANTY OF ANY KIND
# THIS IS NOT SECURE


# Note: This script expects domain join credentials and domain information to be provided
# by the Task Sequence environment variables or set manually before calling Set-DomainJoin.
# Required Task Sequence variables (or set these values in your calling code):
#
# Set-DomainJoin.ps1
# ------------------
# Purpose:
#   Join the local computer to an Active Directory domain. This function is designed
#   to be used from Task Sequences and automation runbooks for 2Pint Software DeployR.
#
# Behavior / Features:
#   - Accepts credentials as a PSCredential (-Credential) or as Username + Password
#     where Password may be a SecureString or plain-text string (plain-text will be
#     converted to a SecureString automatically).
#   - The OU parameter is optional. If omitted, the domain's default computer container
#     will be used.
#   - Checks current domain membership and is idempotent when already joined to the
#     target domain.
#
# Task Sequence Integration (2Pint DeployR):
#   If running inside a Task Sequence and the optional `DeployR.Utility` module is
#   available, this script will read the following TSEnv variables by convention:
#     - ${TSEnv:DomainJoinUsername}  (username used to join, e.g. CM_DJ)
#     - ${TSEnv:DomainJoinPassword}  (SecureString or plain-text)
#     - ${TSEnv:DomainJoinDomain}    (DNS domain name, e.g. 2P.GARYTOWN.COM)
#     - ${TSEnv:DomainJoinOU}  (optional OU distinguishedName when using
#                                     Online Domain Join workflow)
#
#   If `DeployR.Utility` isn't present this script will rely on the calling scope to
#   set $UserName, $Password and $Domain variables before calling `Set-DomainJoin`.
#
# Security Notes:
#   - Plain-text passwords are supported for convenience in automation but will be
#     converted to SecureString prior to creating a PSCredential. Prefer passing a
#     PSCredential object or SecureString where possible.
#   - "Online Domain Join" workflows expose credentials to the network and may be
#     considered less secure; ensure you understand your environment's security
#     posture before using that mode.
#
# Examples:
#   # Using a PSCredential
#   $cred = Get-Credential
#   Set-DomainJoin -Credential $cred -Domain '2P.GARYTOWN.COM' -Restart
#
#   # Using username + plain-text password (converted internally)
#   Set-DomainJoin -Username '2P\\CM_DJ' -Password 'P@ssw0rd' -Domain '2P.GARYTOWN.COM'
#
#   # From Task Sequence (DeployR) - variables read from TSEnv when DeployR.Utility
#   # is available. The outer Task Sequence should set DomainJoinUsername, DomainJoinPassword
#   # and DomainJoinDomain prior to invoking this script.
#
# Designed For:
#   This function is part of the 2PintLabs DeployR toolset and was created to support
#   2Pint Software DeployR Task Sequence workflows. It is safe to call from automation
#   tasks and Task Sequences that follow the variable conventions above.

Write-Host "================================" -ForegroundColor Green
Write-Host "Starting Domain Join Script" -ForegroundColor Green
try {
    Import-Module DeployR.Utility -ErrorAction SilentlyContinue
}
catch {
    Write-Warning "DeployR.Utility module not found. Environment variables will be set in the standard environment."
}

if (Get-Module -name "DeployR.Utility"){
    write-Host "Using DeployR.Utility Module to get FQDN" -ForegroundColor Green
    $OU = ${TSEnv:DomainJoinOU}
    $UserName = ${TSEnv:DomainJoinUsername}
    $Password = ${TSEnv:DomainJoinPassword}
    $Domain = ${TSEnv:DomainJoinDomain}
    $Password = ConvertTo-SecureString -String $Password -AsPlainText -Force
}
else{
    Write-Host "Not IN TS"
    $OU = 'OU=Workstations,OU=2PintTown,DC=2P,DC=garytown,DC=com'
    $UserName = 'CM_DJ'
    $Domain = '2P.GARYTOWN.COM'
}


function Set-DomainJoin {
    <#
    .SYNOPSIS
    Join the local computer to an Active Directory domain.

    .PARAMETER Username
    Username (domain\user or user@domain) of an account with rights to join computers.

    .PARAMETER Password
    Use either -Credential (PSCredential) or -Password (SecureString or plain-text) together with -Username. If a plain-text password is provided it will be converted to a SecureString before creating the PSCredential.

    .PARAMETER OU
    (Optional) Distinguished Name of the OU to place the computer account in (e.g. "OU=Computers,DC=corp,DC=contoso,DC=com"). If omitted the default computer container will be used or the domain controller's default.

    .PARAMETER Domain
    DNS name of the domain to join. Defaults to current user DNS domain if available.

    .PARAMETER Restart
    Switch to restart the computer automatically after joining.
    #>

    [CmdletBinding(SupportsShouldProcess=$true, DefaultParameterSetName='Pass')]
    param(
    # When using a password: Username + Password (SecureString or plain-text string)
    # NOTE: Password is declared as [object] to allow callers to supply either a
    #       SecureString (preferred) or a plain-text string for automation scenarios.
    #       The script will convert plain-text strings to SecureString before
    #       constructing a PSCredential. A static analyzer may warn about string
    #       usage for passwords; this is intentional to preserve automation
    #       convenience while still converting to a secure form at runtime.
    [Parameter(Mandatory=$true, ParameterSetName='Pass')]
    [string]$Username,

    [Parameter(Mandatory=$true, ParameterSetName='Pass')]
    [AllowNull()]
    [object]$Password,

        # Alternatively, supply a PSCredential directly
        [Parameter(Mandatory=$true, ParameterSetName='Cred')]
        [System.Management.Automation.PSCredential]$Credential,

        [Parameter(Mandatory=$false)]
        [AllowNull()]
        [string]$OU = $null,

        [Parameter(Mandatory=$false)]
        [string]$Domain = $env:USERDNSDOMAIN,

        [Parameter(Mandatory=$false)]
        [switch]$Restart
    )

    try {
        if (-not $Domain) {
            throw "Domain not specified and USERDNSDOMAIN is empty. Provide -Domain."
        }

        # Normalize credentials into a PSCredential ($cred)
        if ($PSBoundParameters.ContainsKey('Credential')) {
            $cred = $Credential
        }
        else {
            if (-not $Password) {
                throw "Password is required when calling with -Username (provide a SecureString or plain-text string)."
            }

            # Convert plain-text to SecureString if necessary
            if ($Password -is [System.Security.SecureString]) {
                $securePassword = $Password
            }
            elseif ($Password -is [string]) {
                $securePassword = ConvertTo-SecureString -String $Password -AsPlainText -Force
            }
            else {
                throw "Unsupported Password type. Provide a SecureString or a plain-text string."
            }

            # Username must be present in this parameter set
            if (-not $Username) {
                throw "Username is required when providing a password."
            }
            $cred = New-Object System.Management.Automation.PSCredential ($Username, $securePassword)
        }

        # Check current domain membership
        $cs = Get-CimInstance -ClassName Win32_ComputerSystem
        if ($cs.PartOfDomain) {
            if ($cs.Domain -ieq $Domain) {
                Write-Output "This computer is already joined to domain '$Domain'."
                return @{ Joined = $true; Domain = $Domain; Message = "Already joined" }
            } else {
                throw "Computer is already joined to a different domain: $($cs.Domain). Leave domain first if you intend to join '$Domain'."
            }
        }

        # Validate OU string looks like a distinguishedName if provided
        $addParams = @{
            DomainName = $Domain
            Credential = $cred
            ErrorAction= 'Stop'
        }

        if ($OU) {
            if ($OU -notmatch '=') {
                throw "OU parameter does not appear to be a distinguished name. Example: 'OU=Computers,DC=contoso,DC=com'"
            }
            $addParams.OUPath = $OU
        }
        else {
            Write-Verbose "No OU specified; using default computer container for domain join."
        }

        $joinTarget = if ($addParams.ContainsKey('OUPath')) { "$Domain (OU: $($addParams.OUPath))" } else { $Domain }

        if ($PSCmdlet.ShouldProcess("LocalComputer","Join domain $joinTarget")) {
            Add-Computer @addParams
            Write-Output "Successfully joined computer to domain '$Domain'."

            if ($Restart.IsPresent) {
                Write-Output "Restarting computer to complete domain join..."
                Restart-Computer -Force
            }

            return @{ Joined = $true; Domain = $Domain; Message = "Joined" }
        } else {
            return @{ Joined = $false; Domain = $Domain; Message = "Operation cancelled by ShouldProcess" }
        }
    }
    catch {
        Write-Error "Domain join failed: $($_.Exception.Message)"
        return @{ Joined = $false; Domain = $Domain; Error = $_.Exception.Message }
    }
}

# Do the stuff
Write-Host "================================" -ForegroundColor Green
Write-Host "Starting Domain Join Script" -ForegroundColor Green
Write-Host "Joining Domain: $Domain" -ForegroundColor Green
write-host "Using account: $UserName" -ForegroundColor Green
write-host "Using OU: $OU" -ForegroundColor Green
Set-DomainJoin -Username $UserName -Password $Password -OU $OU -Domain $Domain