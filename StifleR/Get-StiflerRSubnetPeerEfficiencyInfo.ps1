<#
.SYNOPSIS
  Get-StiflerRSubnetPeerEfficiencyInfo.ps1

.DESCRIPTION
  Enumerate all Stifler Network Groups where

.NOTES
  Version:        1.0
  Author:         2Pint Software
  Creation Date:  2024-04-09
  Purpose/Change: Initial script development

#>
#region --------------------------------------------------[Script Parameters]------------------------------------------------------
$Date = $(get-date -f MMddyyyy_hhmm)
$DateForCSVTimeStamp = $(Get-Date -UFormat "%D %T")
$ExportPath = "D:\2Pint_Maintenance\Results\PeerNetworkInfo_$Date.csv"
if (-not (Test-Path -Path ($ExportPath | split-path))) {
    New-Item -Path ($ExportPath | split-path) -ItemType Directory
}

$NetworkGroups = Get-WmiObject -Namespace root\stifler -query "Select NetworksIds,Id from NetworkGroups where VPN = 'False'"

[System.Collections.ArrayList]$PeerNetworkInfo = @()
Foreach ($NG in $NetworkGroups) {

    $NetworkIds = @()
    $MaxClients = @()
    $BITSSourceHistory = @()
    $BITSPeerToPeerHistory = @()
    $DOSourceHistory = @()
    $DOPeerToPeerHistory = @()
    $DOCacheServerHistory = @()
    $BITSEfficiency = @()
    foreach ($NetID in $NG.NetworksIds) {
        $class = "Networks"
        $x = New-CimInstance -ClassName $class -Namespace root\stifler -Property @{ "Id" = $NetID } -Key Id -ClientOnly
        [System.Object]$Subnet = Get-CimInstance -CimInstance $x

        if ($Subnet.MaxClients -gt 1) {
            $BITSSourceHistory += $Subnet.BITSSourceHistory
            $BITSPeerToPeerHistory += $Subnet.BITSPeerToPeerHistory

            $DOSourceHistory += $Subnet.DOSourceHistory
            $DOPeerToPeerHistory += $subnet.DOPeerToPeerHistory
            $DOCacheServerHistory += $Subnet.DOCacheServerHistory

            $NetworkIds += $Subnet.NetworkId
            $MaxClients += [INT]$Subnet.MaxClients
        }
    }
    $MaxClients = $MaxClients | Measure-Object -Sum | Select-Object -ExpandProperty Sum

    If ($MaxClients -gt 1) {

        $BITSSourceHistory = $BITSSourceHistory | Measure-Object -Sum | Select-Object -ExpandProperty Sum
        $BITSPeerToPeerHistory = $BITSPeerToPeerHistory | Measure-Object -Sum | Select-Object -ExpandProperty Sum
        $BITSSourceHistoryInGB = $([math]::Round(($BITSSourceHistory / 1GB), 2))
        $BITSPeerToPeerHistoryInGB = $([math]::Round(($BITSPeerToPeerHistory / 1GB), 2))

        If ($BITSPeerToPeerHistory -eq 0) {
            $BITSEfficiency = 0
        }
        Else {
            $BITSEfficiency = $BITSPeerToPeerHistory / ($BITSSourceHistory + $BITSPeerToPeerHistory)
            $BITSEfficiency = $([math]::Round(($BITSEfficiency * 100), 2))
        
        }

        $DOSourceHistory = $DOSourceHistory | Measure-Object -Sum | Select-Object -ExpandProperty Sum
        $DOPeerToPeerHistory = $DOPeerToPeerHistory | Measure-Object -Sum | Select-Object -ExpandProperty Sum
        $DOCacheServerHistory = $DOCacheServerHistory | Measure-Object -Sum | Select-Object -ExpandProperty Sum
        $DOSourceHistoryInGB = $([math]::Round(($DOSourceHistory / 1GB), 2))
        $DOPeerToPeerHistoryInGB = $([math]::Round(($DOPeerToPeerHistory / 1GB), 2))
        $DOCacheServerHistoryInGB = $([math]::Round(($DOCacheServerHistory / 1GB), 2))
    
        If ($DOPeerToPeerHistory -eq 0) {
            $DOEfficiency = 0
        }
        Else {
            $DOEfficiency = ($DOPeerToPeerHistory + $DOCacheServerHistory) / ($DOSourceHistory + $DOPeerToPeerHistory + $DOCacheServerHistory)
            $DOEfficiency = $([math]::Round(($DOEfficiency * 100), 2))
        
        }

        $obj = [PSCustomObject]@{
            # Add values to arraylist
            NetWorkGroupID            = $NG.id
            NetworkIds                = $NetworkIds -join "|"
            DataCollectDate           = $DateForCSVTimeStamp
            MaxClients                = $MaxClients | Measure-Object -Sum | Select-Object -ExpandProperty Sum
            BITSSourceHistoryInGB     = $BITSSourceHistoryInGB 
            BITSPeerToPeerHistoryInGB = $BITSPeerToPeerHistoryInGB 
            BITSEfficiency            = $BITSEfficiency
            DOSourceHistoryInGB       = $DOSourceHistoryInGB
            DOPeerToPeerHistoryInGB   = $DOPeerToPeerHistoryInGB
            DOCacheServerHistoryInGB  = $DOCacheServerHistoryInGB
            DOEfficiency              = $DOEfficiency
        }
    
        # Add all the values
        $PeerNetworkInfo.Add($obj) | Out-Null

    }
}

$PeerNetworkInfo | Export-Csv -Path $ExportPath -NoTypeInformation

