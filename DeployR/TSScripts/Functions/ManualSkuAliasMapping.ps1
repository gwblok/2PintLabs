<#
Manual SKU -> ModelAlias mapping

Purpose:
 - Provide a small manual lookup that maps Lenovo SKU/type codes (for example: 21LB) to a normalized ModelAlias
   such as "L13G5". Use this from Task Sequence scripts to set a single ModelAlias value based on the SKU.

Data source:
 - The mapping is authored manually below based on the data you provided. Expand or edit the $ModelMap array
   if you need to add more SKU -> alias mappings.
#>

Set-StrictMode -Version Latest

# Build static model mapping (alias, family, generation, models, types, architecture)
$Global:ModelMap = @()

function Add-ModelMapEntry {
	param(
		[Parameter(Mandatory=$true)][string]$Alias,
		[Parameter(Mandatory=$true)][string]$Family,
		[Parameter(Mandatory=$true)][string]$Generation,
		[Parameter(Mandatory=$true)][string[]]$Models,
		[Parameter(Mandatory=$true)][string[]]$Types,
		[string]$Architecture = '64-bit'
	)

	$entry = [PSCustomObject]@{
		Alias = $Alias
		Family = $Family
		Generation = $Generation
		Models = @($Models)
		Types = @($Types)
		Architecture = $Architecture
	}
	$Global:ModelMap += $entry
}

# --- Populate the mapping table from your provided data ---
Add-ModelMapEntry -Alias 'L13G2' -Family 'L13' -Generation '2' -Models @('L13 Gen 2','L13 Yoga Gen 2') -Types @('20VH','20VJ','20VK','20VL','21AB','21AC','21AD','21AE')
Add-ModelMapEntry -Alias 'L13G3' -Family 'L13' -Generation '3' -Models @('L13 Gen 3','L13 Yoga Gen 3') -Types @('21B3','21B4','21B5','21B6','21B9','21BA','21BB','21BC')
Add-ModelMapEntry -Alias 'L13G4' -Family 'L13' -Generation '4' -Models @('L13 Gen 4','L13 Yoga Gen 4') -Types @('21FG','21FH','21FJ','21FK')
Add-ModelMapEntry -Alias 'L13G5' -Family 'L13' -Generation '5' -Models @('L13 Gen 5','L13 2-in-1 Gen 5') -Types @('21LB','21LC','21LM','21LN')

Add-ModelMapEntry -Alias 'L14G1' -Family 'L14' -Generation '1' -Models @('L14 Gen 1') -Types @('20U1','20U2','20U5','20U6')
Add-ModelMapEntry -Alias 'L15G1' -Family 'L15' -Generation '1' -Models @('L15 Gen 1') -Types @('20U3','20U4','20U7','20U8')

Add-ModelMapEntry -Alias 'L14G2' -Family 'L14' -Generation '2' -Models @('L14 Gen 2') -Types @('20X1','20X2','20X5','20X6')
Add-ModelMapEntry -Alias 'L15G2' -Family 'L15' -Generation '2' -Models @('L15 Gen 2') -Types @('20X3','20X4','20X7','20X8')

Add-ModelMapEntry -Alias 'L14G3' -Family 'L14' -Generation '3' -Models @('L14 Gen 3') -Types @('21C1','21C2','21C5','21C6')
Add-ModelMapEntry -Alias 'L15G3' -Family 'L15' -Generation '3' -Models @('L15 Gen 3') -Types @('21C3','21C4','21C7','21C8')

Add-ModelMapEntry -Alias 'L14G4' -Family 'L14' -Generation '4' -Models @('L14 Gen 4') -Types @('21H1','21H2','21H5','21H6')
Add-ModelMapEntry -Alias 'L15G4' -Family 'L15' -Generation '4' -Models @('L15 Gen 4') -Types @('21H3','21H4','21H7','21H8')

Add-ModelMapEntry -Alias 'L14G5' -Family 'L14' -Generation '5' -Models @('L14 Gen 5') -Types @('21L1','21L2','21L5','21L6')
Add-ModelMapEntry -Alias 'L16G1' -Family 'L16' -Generation '1' -Models @('L16 Gen 1') -Types @('21L3','21L4','21L7','21L8')

# Public helper: return full mapping
function Get-ModelMap {
	return $ModelMap
}

# Public helper: return full model info object for a SKU (or $null if not found)
function Get-ModelInfoForSku {
	param(
		[Parameter(Mandatory=$true)][string]$Sku
	)
	if (-not $Sku) { return $null }
	$k = $Sku.ToString().Trim().ToUpper()
	foreach ($m in $ModelMap) {
		# Compare each type case-insensitively
		foreach ($t in $m.Types) {
			if ($t.ToString().Trim().ToUpper() -eq $k) {
				return $m
			}
		}
	}
	return $null
}

# Public helper: return Alias for a SKU/type code (case-insensitive). Returns $null when not found.
function Get-ModelAliasForSku {
	param(
		[Parameter(Mandatory=$true)][string]$Sku
	)
	$info = Get-ModelInfoForSku -Sku $Sku
	if ($info) { return $info.Alias }
	return $null
}

# Example usage (uncomment to test interactively)
# Write-Host "Example: 21LB -> $(Get-ModelAliasForSku -Sku '21LB')"

# Now lets incorporate this into DeployR
try {
    Import-Module DeployR.Utility -ErrorAction SilentlyContinue
}
catch {}



# Get the provided variables
if (Get-Module -name "DeployR.Utility"){
    $SKUAlias = ${TSEnv:SKUAlias}
}
else{
	$computer = Get-CimInstance -Class "Win32_ComputerSystemProduct" -Namespace "root/cimv2"
	$SKUAlias = $computer.Name.Substring(0, 4)
}
if ($env:SystemDrive -eq "X:"){
}
else {
	Write-Host "This should be done in WinPE right before the Apply Drivers Step"
}

#$SKUAlias = '21H2' #Used for Manual test on Non-Lenovo

#ModelAlias Replacement
$ModelInfo = Get-ModelInfoForSku -Sku $SKUAlias
if ($ModelInfo){
	$UpdatedModelAlias = ($ModelInfo).Alias
	if (Get-Module -name "DeployR.Utility"){
		${TSEnv:ModelAlias} = $UpdatedModelAlias
		Write-Host "Updated TS Var ModelAlias to $UpdatedModelAlias"
	}
	else{
		Write-Host "Testing outside of DeployR"
		Write-Host "ModelAlias for SKU $SKUAlias is $UpdatedModelAlias"
	}
}
else{
	Write-Host "No ModelAlias mapping found for SKU $SKUAlias" -ForegroundColor Red
	write-host " More Details about Machine" -ForegroundColor DarkGray
	write-Host " Manufacturer: $((Get-CimInstance -Class Win32_ComputerSystem).Manufacturer)" -ForegroundColor DarkGray
	Write-Host " Model : $((Get-CimInstance -Class Win32_ComputerSystem).Model)" -ForegroundColor DarkGray
	Write-Host " Product Name : $((Get-CimInstance -Class Win32_ComputerSystemProduct).Version)" -ForegroundColor DarkGray
}
