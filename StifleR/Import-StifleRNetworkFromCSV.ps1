<#
.SYNOPSIS
  Test

.DESCRIPTION
  <Brief description of script>

.PARAMETER <Parameter_Name>
  <Brief description of parameter input required. Repeat this attribute if required>

.INPUTS
  <Inputs if any, otherwise state None>

.OUTPUTS
  <Outputs if any, otherwise state None>

.NOTES
  Version:        1.0
  Author:         <Name>
  Creation Date:  <Date>
  Purpose/Change: Initial script development

.EXAMPLE
  <Example explanation goes here>
  
  <Example goes here. Repeat this attribute for more than one example>
#>
#Requires -RunAsAdministrator
#region --------------------------------------------------[Script Parameters]------------------------------------------------------
Param (
    [parameter(Mandatory = $false)]
    [string]$CSVPath = "C:\Users\me\Downloads\StifleRNetworks.csv",
    [parameter(Mandatory = $false)]
    [string]$CSVDelimiter = ",",
    [switch]$Force
)

#endregion
#region --------------------------------------------------[Initialisations]--------------------------------------------------------

#Set Error Action to Silently Continue
#$ErrorActionPreference = 'SilentlyContinue'

#Import Modules & Snap-ins
#endregion
#region ---------------------------------------------------[Declarations]----------------------------------------------------------

#Any Global Declarations go here
$maxlogfilesize = 5Mb
$Verbose = $PSCmdlet.MyInvocation.BoundParameters["Verbose"].IsPresent

#endregion
#region ---------------------------------------------------[Functions]------------------------------------------------------------

#region Logging: Functions used for Logging, do not edit!
Function Start-Log {
    [CmdletBinding()]
    param (
        [ValidateScript({ Split-Path $_ -Parent | Test-Path })]
        [string]$FilePath
    )

    try {
        if (!(Test-Path $FilePath)) {
            ## Create the log file
            New-Item $FilePath -Type File | Out-Null
        }
  
        ## Set the global variable to be used as the FilePath for all subsequent Write-Log
        ## calls in this session
        $global:ScriptLogFilePath = $FilePath
    }
    catch {
        Write-Error $_.Exception.Message
    }
}

Function Write-Log {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,
  
        [Parameter()]
        [ValidateSet(1, 2, 3)]
        [int]$LogLevel = 1
    )    
    $TimeGenerated = "$(Get-Date -Format HH:mm:ss).$((Get-Date).Millisecond)+000"
    $Line = '<![LOG[{0}]LOG]!><time="{1}" date="{2}" component="{3}" context="" type="{4}" thread="" file="">'
  
    if ($MyInvocation.ScriptName) {
        $LineFormat = $Message, $TimeGenerated, (Get-Date -Format MM-dd-yyyy), "$($MyInvocation.ScriptName | Split-Path -Leaf):$($MyInvocation.ScriptLineNumber)", $LogLevel
    }
    else {
        #if the script havn't been saved yet and does not have a name this will state unknown.
        $LineFormat = $Message, $TimeGenerated, (Get-Date -Format MM-dd-yyyy), "Unknown", $LogLevel
    }
    $Line = $Line -f $LineFormat

    If ($Verbose) {
        switch ($LogLevel) {
            2 { $TextColor = "Yellow" }
            3 { $TextColor = "Red" }
            Default { $TextColor = "Gray" }
        }
        Write-Host -nonewline -f $TextColor "$Message`r`n" 
    }

    #Make sure the logfile do not exceed the $maxlogfilesize
    if (Test-Path $ScriptLogFilePath) { 
        if ((Get-Item $ScriptLogFilePath).length -ge $maxlogfilesize) {
            If (Test-Path "$($ScriptLogFilePath.Substring(0,$ScriptLogFilePath.Length-1))_") {
                Remove-Item -path "$($ScriptLogFilePath.Substring(0,$ScriptLogFilePath.Length-1))_" -Force
            }
            Rename-Item -Path $ScriptLogFilePath -NewName "$($ScriptLogFilePath.Substring(0,$ScriptLogFilePath.Length-1))_" -Force
        }
    }

    Add-Content -Value $Line -Path $ScriptLogFilePath -Encoding UTF8

}
#endregion

# Add functions Here
function Compare-StifleRMethodParameters($WMIClass, $Method, $CALLINGParams) {

    $Class = Get-CimClass -Namespace root\StifleR -ClassName "$WMIClass"
    $Class_Params = $Class.CimClassMethods[$Method].Parameters

    ForEach ($entry in $Class_Params) {
        if ($verbose) { Write-Log -message "Processing $($entry.Name) of type: $($entry.CimType)" }
        if ($CALLINGParams.ContainsKey($entry.Name)) {
            if ($verbose) { Write-Log -message "Found valid parameter: $($entry.Name) of type: $($entry.CimType)" }
        
            $othertype = $CALLINGParams[$entry.Name].GetType()

            if ($othertype.Name -ne $entry.CimType) {
                Write-Log -Message "$($CALLINGParams[$entry.Name].GetType())  does not match  $($entry.CimType)" -LogLevel 3 -Verbose
                return 1
            }
            else {
                if ($verbose) { Write-Log -message "Input matches the parameter type!" }
            }
        }
        else {
            if ($verbose) { Write-Log -message $entry.Name }
            Write-Log -Message "Missing valid parameter $($entry.Name) on call to $Method on $WMIClass" -LogLevel 3 -Verbose
            return 1
        }
    }
    return 0
}


function Add-Location($LocationName, $LocationDescription) {
    $class = "Locations"
    $method = "AddLocation"
    if ($verbose) { Write-Log -message "Processing $method" }
    $params = @{ Name = $LocationName; Description = $LocationDescription };
    
    $result = Compare-StifleRMethodParameters $class $method $params
    
    if ($result -ne 0) {
        Write-Error "Failed to verify Parameters to $class"
        return 1
    }
    else {
        #Add out location
        if ($verbose) { Write-Log -message "Calling Invoke-CimMethod to $class $method" }
        $ret = Invoke-CimMethod -Namespace root\StifleR -ClassName $class -Name $method -Arguments $params
        
        $locationid = $ret.ReturnValue
        #Dont be this guy! This calls the enumerator for each call, if we have the ID, whe dont need to query!
        #$Location = Get-CimInstance -Namespace root\StifleR -Query "Select * from $class where id like '$locationid'"
        
        #This is MUCH faster, and does not slow down with larget lists. Key here is the -ClientOnly
        $x = New-CimInstance -ClassName $class -Namespace root\stifler -Property @{ "Id" = $locationid } -Key Id -ClientOnly
        $Location = Get-CimInstance -CimInstance $x

        return , $Location
    }
}


function Add-NetworkGroupToLocation([System.Object]$Location, $NetworkGroupName, $NetworkGroupDescription) {
    write-debug "incoming object is type ($Location.GetType())"

    write-debug "##########################"
    $method = "AddNetworkGroupToLocation"
    $class = "NetworkGroups"
    write-debug "Processing $method"
    $params = @{ Name = $NetworkGroupName ; Description = $NetworkGroupDescription }
    $result = Compare-StifleRMethodParameters $class $method $params
    if ($result -ne 0) {
        Write-Error "Failed to verify Parameters to $class"
        return 1
    }
    else {
    
        #Add location on the actual object in the location object just created using non static method
        write-debug "Calling Invoke-CimMethod on LocationInstance $Location.id"
        $ret = Invoke-CimMethod -InputObject $Location -MethodName $method -Arguments $params

        $netGrpId = $ret.ReturnValue
        #$netGrp = Get-CimInstance -Namespace root\StifleR -Query "Select * from $class where id like '$netGrpId'"
        
        $x = New-CimInstance -ClassName $class -Namespace root\stifler -Property @{ "Id" = $netGrpId } -Key Id -ClientOnly
        Start-Sleep -Seconds 1
        $netGrp = Get-CimInstance -CimInstance $x
		
        return $netGrp

        #You can also call the static methods to add on the class NetworkGroups
        #write-debug "Calling Invoke-CimMethod to $class $method"
        #$args = @{ Name = 'Name' ; Description = 'Description'; LocationId=<guid>}
        #$netGrp = Invoke-CimMethod -Namespace root\StifleR -ClassName $class -Name $method -Arguments $args
    }
}


function Add-NetworkToNetworkGroup([System.Object]$NetGrp, $NetworkId, $NetworkMask, $GatewayMAC) {
    
    write-debug "##########################"
    $class = "Networks"
    $method = "AddNetworkToNetworkGroup"
    write-debug "Processing $method"
    $params = @{ Network = $NetworkId ; NetworkMask = $NetworkMask; GatewayMAC = $GatewayMAC };
    $result = Compare-StifleRMethodParameters $class $method $params
    if ($result -ne 0) {
        Write-Error "Failed to verify Parameters to $class"
        return 1
    }
    else {
        #Add out location
        write-debug "Calling Invoke-CimMethod on newly create network group"
    

        #Add location on the actual object in the location object just created using non static method
        $ret = Invoke-CimMethod -InputObject $NetGrp -MethodName AddNetworkToNetworkGroup -Arguments $params

        $NetworkId = $ret.ReturnValue
        #$Network = Get-CimInstance -Namespace root\StifleR -Query "Select * from $class where id like '$NetworkId'"
        
        $x = New-CimInstance -ClassName $class -Namespace root\stifler -Property @{ "Id" = $NetworkId } -Key Id -ClientOnly
        $Network = Get-CimInstance -CimInstance $x
		
        return $Network
    }
}


#endregion
#-----------------------------------------------------------[Execution]------------------------------------------------------------
#Default logging to %temp%\scriptname.log, change if needed.
Start-Log -FilePath "$($env:TEMP)\$([io.path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)).log"
# Syntax is:
# Loglevel 1 is default and does not need to be specified
# Write-Log -Message "<message goes here>"
# Write-Log -Message "<message goes here>" -LogLevel 2

#Script Execution goes here



$networks = Import-Csv -Path $CSVPath -Encoding UTF8 -Delimiter $CSVDelimiter

#$networks |Select-Object -Property AvailableBw_Old -Unique |Sort-Object -Property AvailableBw_Old

$defaultTemplate = '00000000-0000-0000-0000-000000000012'

$createdLocations = @{}
$createdNetworkGroups = @{}
$createdNetworks = @{}

# $locations = $networks | Select-Object -Property SiteID, Country, City -Unique

$class = "Locations"
$currentLocations = Get-CimInstance -Namespace root\StifleR -Query "Select LocationName from $class" | Select-Object -Property LocationName, id | Sort-Object LocationName -unique 
#$class = "NetworkGroups"
#$currentNetworkGroups = (Get-CimInstance -Namespace root\StifleR -Query "Select Name from $class" | Select-Object -Property Name, Id) | Sort-Object Name -unique
$class = "Networks"
$currentNetworks = (Get-CimInstance -Namespace root\StifleR -Query "Select NetworkId,SubnetMask from $class" | Select-Object -Property NetworkId, SubnetMask) | ForEach-Object { "$($_.NetworkId),$($_.SubNetMask)" }  | Sort-Object -unique


foreach ($cLoc in $currentLocations) { $createdLocations.Add($cLoc.LocationName, $cLoc.id) }

# Start creating new locations.
foreach ($net in $networks) {

    If ($createdLocations["$($net.LOLocationName)"]) {
        Write-host "Location $($net.LOLocationName) already exists, not creating.."
       
        $class = "Locations"
        $x = New-CimInstance -ClassName $class -Namespace root\stifler -Property @{ "Id" = $($createdLocations["$($net.LOLocationName)"]) } -Key Id -ClientOnly
        [System.Object]$newlocation  = Get-CimInstance -CimInstance $x

        #[System.Object]$newlocation = Get-CimInstance -Namespace root\StifleR -Query "Select * from $class where id = `'$($createdLocations["$($net.LOTown)/$($net.LOAddress)"])`'"
    }
    else {
        [System.Object]$newlocation = Add-Location "$($net.LOLocationName)" $net.LODescription
        write-host "Created new location type is $($newlocation.GetType())"
        $createdLocations.Add("$($net.LOLocationName)", $newlocation.id)

        #Set a new value - Note: WMI is not updated until you pipe it to Set-CimInstance
        $newlocation.Address = $net.LOAddress
        $newlocation.Town = $net.LOTown
        $newlocation.Country = $net.LOCountry
        $newlocation.County = $net.LOCounty
        $newlocation.CountryCode = $net.LOCountryCode 
        #$newlocation.Description = $net.LODescription
        $newlocation.Region = $net.LORegion
        $newlocation.Latitude = $net.LOLatitude
        $newlocation.Longitude = $net.LOLongitude
        $newlocation.State = $net.LOState
        $newlocation.ZIP = $net.LOZIP
        $newlocation.Type = $net.LOType
        $newlocation.TimeZone = $net.TimeZone
        $newlocation.QueryString = $net.LOQueryString
        $newlocation.GooglePlaceId = $net.LOGooglePlaceId

        #Write the value changed back again
        $newlocation | Set-CimInstance 

    }
    
    if ($createdNetworkGroups["$($net.NGName)"]) {
        Write-host "NetworkGroups $($newlocation.NetworkGroups) already exists, not creating.."
        $class = "NetworkGroups"
        $x = New-CimInstance -ClassName $class -Namespace root\stifler -Property @{ "Id" = $($createdNetworkGroups["$($net.NGName)"]) } -Key Id -ClientOnly
        [System.Object]$newNetgrp   = Get-CimInstance -CimInstance $x
        #[System.Object]$newNetgrp = Get-CimInstance -Namespace root\StifleR -ClassName $class -Filter "id = '$($createdNetworkGroups["$($net.NGName)"])'"

        #$newNetgrp = Get-CimInstance -Namespace root\StifleR -Query "Select * from $class where id = '$($newlocation.NetworkGroups)'"
    }
    else {
        [System.Object]$newNetgrp = Add-NetworkGroupToLocation $newlocation "$($net.NGName)" $net.NGDescription
        Write-host "Creating NetworkGroups "$($newNetgrp.Name)/$($newNetgrp.Description)""
        $createdNetworkGroups.Add("$($newNetgrp.Name)", $newNetgrp.id)
       

        <#
        $template = $null

        if ($templateTableNew[$($net.AvailableBw_New)]) {
            $template = $templateTableNew[$($net.AvailableBw_New)]
        }
        elseif ($templateTableOld[$($net.AvailableBw_Old)]) {
            $template = $templateTableOld[$($net.AvailableBw_Old)]
        }
        else {
            $template = $defaultTemplate
        }
            
        $params = @{
            Description = 'Testing WMI Update'
        }
        $newNetgrp = Get-CimInstance -Namespace root\StifleR -ClassName 'NetworkGroups' | Where-Object {$_.id -eq "$($newNetgrp.id)"}
        Set-CimInstance -InputObject $newNetgrp -Property @{ Description = 'Testing WMI Update' } -Verbose
        Get-CimInstance -Namespace root\StifleR -ClassName 'NetworkGroups' | Where-Object {$_.id -eq "$($newNetgrp.id)"} | Set-CimInstance -Property $params -Verbose
        #>
        [string]$DOGroupId = ($newNetgrp.id).Trim()
        $params = @{
            DOGroupId = $DOGroupId
        }
        
        $newNetgrp | Set-CimInstance -Property $params -Verbose

        if([string]::IsNullOrEmpty($net.NGTemplate))
        {
            $params = @{
                BandwidthTuning = $net.NGBandwidthTuning
                #BeaconId = $net.NGBeaconId
                BranchCacheFlags = $net.NGBranchCacheFlags
                DODownloadMode = $net.NGDODownloadMode
                DOFlags = $net.NGDOFlags
                Flags = $net.NGFlags
                HighBandwidthThreshold = $net.NGHighBandwidthThreshold
                InternetBandwidth = $net.NGInternetBandwidth
                LEDBATTargetBandwidth = $net.NGLEDBATTargetBandwidth
                LowBandwidthThreshold = $net.NGLowBandwidthThreshold
                MaxBandwidthDownstream = $net.NGMaxBandwidthDownstream
                MaxBandwidthUpstream = $net.NGMaxBandwidthUpstream
                #Name = $net.
                NonRedLeaderBITSBandwidth = $net.NGNonRedLeaderBITSBandwidth
                NonRedLeaderDOBandwidth = $net.NGNonRedLeaderDOBandwidth
                PercentOfMaxDownstream = $net.NGPercentOfMaxDownstream
                ServerSecret = $net.NGServerSecret
                TargetBandwidth = $net.NGTargetBandwidth
                WellConnectedBITSBandwidth = $net.NGWellConnectedBITSBandwidth
                WellConnectedDOBandwidth = $net.NGWellConnectedDOBandwidth
            }
            $newNetgrp | Set-CimInstance -Property $params -Verbose
        }
        else {
        # Set template separatly
        $params = @{
            TemplateId = $net.NGTemplate
        }
        $ret = Invoke-CimMethod -InputObject $newNetgrp -MethodName SetTemplate -Arguments $params
        }

        $createdNetworkGroups.Add($newNetgrp.id, $newlocation.id)

    }

    if ($currentNetworks) {

        If ($currentNetworks -contains "$($net.NWNetworkID),$($net.NWSubnetMask)") {
            Write-host "The network $($net.NWNetworkID),$($net.NWSubnetMask) already exists, skipping!"  
        }
        else {
            [System.Object]$Network = Add-NetworkToNetworkGroup $newNetgrp $net.NWNetworkID $net.NWSubnetMask ""

            


            $createdNetworks.Add($Network.id, $newNetgrp.id)
       
        }
    }
    else {
        [System.Object]$Network = Add-NetworkToNetworkGroup $newNetgrp $net.NWNetworkID $net.NWSubnetMask ""
        $createdNetworks.Add($Network.id, $newNetgrp.id)
    }





}

# Workaround to fix templates not being properly set
$class = "NetworkGroupTemplates"
$allTemplates = Get-CimInstance -Namespace root\StifleR -Query "Select * from $class" 
foreach ($tmpl in $allTemplates) {
    $tmpl | Set-CimInstance
}

