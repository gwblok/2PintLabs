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