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

$menu = @"
#!ipxe
#default section to set some key variable such as pictures etc.

#set debug true

#This calls the default param set named paramdata used in posts
$Paramdata

:start
menu iPXE Anywhere build menu
item --gap --          -------------------------------- Please choose an action           ------------------------  
item --key n deployr0 Boot to DeployR Menu
item --key n deployr1 Boot to DeployR TS 1
item --key m deployr2 Boot to DeployR TS 2
item --gap --          --------------------------------                Advanced           ------------------------
item reboot            Reboot the computer
item
item --key x exit      Exit and continue boot order
choose --timeout 30000 --default deployr0 selected || goto cancel
goto `${selected}

:deployr0
chain -ar `${wsurl}/script?scriptname=custom/deployr.ps1##params=paramdata || shell
goto start

:deployr1
chain -ar `${wsurl}/script?scriptname=custom/deployrTS1.ps1##params=paramdata || shell
goto start

:deployr2
chain -ar `${wsurl}/script?scriptname=custom/deployrTS2.ps1##params=paramdata || shell
goto start

:reboot
reboot

:exit
#This only works if the computer is set to always try PXE first and the drive is set as second. If drive is set to number one and using F12 to PXE-boot change this to "reboot" instead.
exit 1

"@

return $menu