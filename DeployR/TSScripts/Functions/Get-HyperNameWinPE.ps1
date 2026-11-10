<#
.SYNOPSIS
Returns the Hyper-V host and virtual machine identity.

.DESCRIPTION
Defines Get-HyperNameWinPE. Requires Windows and Hyper-V guest registry
parameters populated by the Hyper-V integration services. These values may not
be available in WinPE. Reads the registry without making changes.

.EXAMPLE
. .\Get-HyperNameWinPE.ps1
Get-HyperNameWinPE

.NOTES
Author: Not specified
Created: 2026-11-09
Change History:
2026-11-09 - Initial version.
#>


function Get-HyperNameWinPE {
	<#
	.SYNOPSIS
	Gets the Hyper-V host name, VM name, and VM ID.

	.DESCRIPTION
	Reads HKLM:\SOFTWARE\Microsoft\Virtual Machine\Guest\Parameters and
	returns a PSCustomObject. Throws if the key or a required value is unavailable.

	.EXAMPLE
	Get-HyperNameWinPE
	#>
	[CmdletBinding()]
	param ()

	$RegistryPath = 'HKLM:\SOFTWARE\Microsoft\Virtual Machine\Guest\Parameters'
	$Parameters = Get-ItemProperty -LiteralPath $RegistryPath -ErrorAction Stop

	foreach ($ValueName in @('HostName', 'VirtualMachineName', 'VirtualMachineId')) {
		if ([string]::IsNullOrWhiteSpace($Parameters.$ValueName)) {
			throw "Hyper-V guest registry value '$ValueName' is missing or empty at '$RegistryPath'."
		}
	}

	[PSCustomObject]@{
		HostName = $Parameters.HostName
		VMName   = $Parameters.VirtualMachineName
		VMId     = $Parameters.VirtualMachineId
	}
}

try {
    Import-Module DeployR.Utility -ErrorAction SilentlyContinue
    $HyperVInfo = Get-HyperNameWinPE
    ${TSEnv:VMHostName} = $HyperVInfo.HostName
    ${TSEnv:VMName} = $HyperVInfo.VMName
    ${TSEnv:VMId} = $HyperVInfo.VMId
    if (${TSEnv:SetComputerName2VMName} -eq $true) {
        ${TSEnv:COMPUTERNAME} = $HyperVInfo.VMName
    }

}
catch {
    Write-Warning "Failed to import DeployR.Utility module or retrieve Hyper-V information: $_"
}