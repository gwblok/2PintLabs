param(
    $Machine, 
    $RequestStatusInfo, 
    $RequestNetworkInfo, 
    $Machineinformation, 
    $QueryParams, 
    $PostParams, 
    $Paramdata, 
    $DeployMachineKeyValues,
    $TargetMachineKeyValues,
    $DeployLocation,
    $DeployNetworkGroup,
    $DeployNetwork,
    $TargetLocation,
    $TargetNetworkGroup,
    $TargetNetwork
)


#Update the TSID: to the GUID for the TS you want to start automatically
$BootStrapContent = '{"Variables":{"DeployRHost":"https://server.company.com:7281","Anonymous":"true","Custom":"true","Debug":"true","TSID":"eb480b28-4b9e-46e9-ab87-7304922687aa"}}'
$BootStrapContent | out-file 'C:\ProgramData\2Pint Software\2PXE\Remoteinstall\Boot\BootStrapContent.json' -Encoding utf8 -Force

$2pxeserver = 'https://server.company.com:8050/2PXE/File/Boot/'
$deployrserver = 'https://server.company.com:7281/Content/Boot/'

$menu = @"
#!ipxe

# Uncomment below row if you want to disable branchcache peering. Will increase the download speed in environments with peering is disabled.
# set peerdist 0

set 2pxeserver $2pxeserver || shell
set deployrserver $deployrserver || shell
$paramdata
initrd --name wimboot `${2pxeserver}wimboot.x86_64.efi##params=paramdata wimboot || shell
$paramdata
initrd --name Bootstrap.json `${2pxeserver}BootStrapContent.json##params=paramdata Bootstrap.json || shell
initrd --name BCD `${deployrserver}BCD BCD || shell
initrd --name boot.wim `${deployrserver}winpe_amd64.wim boot.wim || shell
kernel wimboot gui || shell
boot || shell

"@


return $menu