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


enum NetworkGroupType
{
    Regular = 0
    WellConnected = 1
    VPN = 2
    DataCenter = 8
    BuildDepot = 16
}


enum NetworkGroupFlags
{
    LocalInternetBreakOut = 4
    DisableGreenLeader = 16
    RoamingLocation = 32
    DirectRoute = 64
    MeasureOverridesTemplate = 128
    CentralSwitching = 256
    DisableBranchCacheForiPXE = 512
}

[string]$ComponentMAC = ($RequestStatusInfo.DeployMAC.ToString()).replace(":","")
$scriptPath = "C:\Program Files\2Pint Software\iPXE AnywhereWS\Scripts"
$FunctionsFile = "$scriptPath\Functions\Functions.ps1" #Goes to the Function file (iPXEFunctions.ps1), where ever you placed it.
$LogPath = "D:\iPXELogging" #Update to where you want logs to go
$LogFile = "$LogPath\iPXEProcess.log"

$toolserver = "http://2pdp22.2p.garytown.com"
$2pxeserver = 'https://2pdp22.2p.garytown.com:8050/2PXE/File/Boot/'
$214deployrserver = 'https://214-DeployR.2p.garytown.com:7281/Content/Boot/'
$deployrserver = 'https://DeployR.2p.garytown.com:7281/Content/Boot/'

$bootstrap214 = '{"Variables":{"DeployRHost":"https://214-DeployR.2p.garytown.com:7281","Anonymous":"true","Custom":"true","Debug":"true","TSID":"eb480b28-4b9e-46e9-ab87-7304922687aa"}}'
$bootstrap214 | out-file 'C:\ProgramData\2Pint Software\2PXE\Remoteinstall\Boot\bootstrap214.json' -Encoding utf8 -Force

#Test for Debug Enabled Flag
if ((Test-Path -Path "$LogPath\EnableDebug.ini")-eq $true){
    $DebugEnabled = $true
    $MenuDebugEnable = @"
item
item --gap !!! Debug Logging Enabled !!!"
item
"@
}
else {
    $DebugEnabled = $false
}

if((Test-Path $FunctionsFile) -eq $false){
    throw [System.IO.FileNotFoundException] "Could not find: $FunctionsFile"
}
else{
    Invoke-Expression (Get-Content -Path $FunctionsFile -Raw)
}

if ($DebugEnabled){
    Invoke-CMTraceLog -Message "Main Menu | ----------------------------------------------------" -LogFile $LogFile -Component $ComponentMAC
    Invoke-CMTraceLog -Message "Main Menu | Launching Main iPXE Menu" -LogFile $LogFile -Component $ComponentMAC
    Invoke-CMTraceLog -Message "Main Menu | Debug Logging = $DebugEnabled" -LogFile $LogFile -Component $ComponentMAC
}

#Write Log (leverages the iPXEFunctions.ps1 functions)
[string]$ComponentMAC = ($RequestStatusInfo.DeployMAC.ToString()).replace(":","")
Out-LogVariables -LogPath $LogPath


$menu = @"
#!ipxe

#This calls the default param set named paramdata used in posts
$Paramdata

:start

menu Please choose an OS version for production deployment [2CM]
$MenuDebugEnable
item --gap Available DeployR Servers:
item
item DeployRALW DeployR.2p.garytown.com WebUI      (OnPrem)
item DeployRAL DeployR.2p.garytown.com       (OnPrem)
item DeployRML 214-DeployR.2p.garytown.com   (OnPrem)


item --gap CM Stuff
item --key a winclientavailable Windows Client (Available)
item --key b winclientrequirement Windows Client (Required) 
item
item
item --key p cm List other available task sequences
item
item --gap Other Boot Options
#item --key k w365kiosk W365 Kiosk
item
item --key x exit      Exit and continue boot order
item --key y edebug     Enable Debug and Reset Menu
item --key z ddebug     Disable Debug and Reset Menu

choose --default deployrls --timeout 30000 target && goto `${target} || goto exit

goto `${selected}

:winclientavailable
chain `${wsurl}/script?scriptname=configmgr/winclientavailable.ps1##params=paramdata || shell

:winclientrequirement
chain `${wsurl}/script?scriptname=configmgr/winclientrequirement.ps1##params=paramdata || shell

:ubuntu-live
# See http://manpages.ubuntu.com/manpages/precise/man7/casper.7.html for casper cmdline details
echo Booting Ubuntu Live for education
kernel http://2pdp22.2p.garytown.com/linux/casper/vmlinuz
initrd http://2pdp22.2p.garytown.com/linux/casper/initrd
imgargs vmlinuz root=/dev/ram0 ip=dhcp url=http://2pdp22.2p.garytown.com/linux/ubuntu-24.04.2-desktop-amd64.iso
boot || goto failed
goto start

:DeployRLinux
echo Booting DeployR Linux
set deployrserver $deployrserver || shell
kernel `${deployrserver}x64/vmlinuz \
    initrd=initrd.img \
    root=live:http://2pdp22.2p.garytown.com/DeployR/Linux/squashfs.img \
    nomodeset rhgb quiet || shell
initrd `${deployrserver}x64/initrd.img  || shell
shim `${deployrserver}x64/shimx64.efi || shell

initrd `${deployrserver}certs/deployr-root-ca.crt /etc/pki/ca-trust/source/anchors/deployr-root-ca.crt || shell
initrd `${deployrserver}certs/01-deployr-ca.sh /var/lib/dracut/hooks/pre-mount/01-deployr-ca.sh mode=755|| shell

boot || goto failed
goto start


:cm
chain `${wsurl}/script?scriptname=configmgr/cm.ps1##params=paramdata || shell

:w365kiosk
chain `${wsurl}/script?scriptname=custom/w365kiosk.ps1##params=paramdata || shell
goto start

:DeployRALW
#set peerdist 0
set toolroot $toolserver/DeployR/ || shell
set 2pxeserver $2pxeserver || shell
set deployrserver $deployrserver || shell
$paramdata
initrd --name wimboot `${2pxeserver}wimboot.x86_64.efi##params=paramdata wimboot || shell
$paramdata
initrd --name BCD `${deployrserver}BCD BCD || shell
initrd --name Bootstrap.json `${toolroot}Bootstrap-DeployR-WebUI.json || shell

initrd --name boot.wim `${deployrserver}winpe_amd64.wim boot.wim || shell
kernel wimboot gui || shell
boot || shell
goto start


:DeployRAL
#set peerdist 0
set toolroot $toolserver/DeployR/ || shell
set 2pxeserver $2pxeserver || shell
set deployrserver $deployrserver || shell
$paramdata
initrd --name wimboot `${2pxeserver}wimboot.x86_64.efi##params=paramdata wimboot || shell
$paramdata
initrd --name BCD `${deployrserver}BCD BCD || shell
initrd --name Bootstrap.json `${toolroot}Bootstrap-DeployR-NoWebUI.json || shell

initrd --name boot.wim `${deployrserver}winpe_amd64.wim boot.wim || shell
kernel wimboot gui || shell
boot || shell
goto start

:DeployRML
#set peerdist 0
set toolroot $toolserver/DeployR/ || shell
set 2pxeserver $2pxeserver || shell
set deployrserver $214deployrserver || shell
$paramdata
initrd --name wimboot `${2pxeserver}wimboot.x86_64.efi##params=paramdata wimboot || shell
initrd --name BCD `${deployrserver}BCD BCD || shell
#initrd --name Bootstrap.json `${toolroot}Bootstrap-214-DeployR-Default.json Bootstrap.json || shell
#initrd --name Bootstrap.json `${toolroot}Bootstrap-214-DeployR-Filter-Tag.json Bootstrap.json || shell
initrd --name boot.wim `${deployrserver}winpe_amd64.wim boot.wim || shell
kernel wimboot gui || shell
boot || shell
goto start

:DeployRCE
set peerdist 1
set toolroot $toolserver/DeployR/ || shell
set 2pxeserver $2pxeserver || shell
set deployrserver $azure3deployrserver || shell
$paramdata
initrd --name wimboot `${2pxeserver}wimboot.x86_64.efi##params=paramdata wimboot || shell
initrd --name BCD `${deployrserver}BCD BCD || shell
#initrd --name Bootstrap.json `${toolroot}Bootstrap-214-DeployR-Default.json Bootstrap.json || shell
initrd --name boot.wim `${deployrserver}winpe_amd64.wim boot.wim || shell
kernel wimboot gui || shell
boot || shell
goto start


:DeployRC
set peerdist 1
set toolroot $toolserver/DeployR/ || shell
initrd --name boot.sdi `${toolroot}boot.sdi boot.sdi || shell
initrd --name wimboot `${toolroot}wimboot.x86_64.efi wimboot || shell
initrd --name BCD `${toolroot}BCD BCD || shell
initrd --name Bootstrap.json `${toolroot}Bootstrap-214-DeployR-WBMFC-01688b23b256.json Bootstrap.json || shell
initrd --name boot.wim `${deployrserver}winpe_amd64.wim boot.wim || shell
#initrd --name boot.wim `${toolroot}winpe_amd64.wim boot.wim || shell

kernel wimboot gui || shell
boot || shell
goto start



:edebug
chain `${wsurl}/script?scriptname=Boot/enabledebug.ps1##params=paramdata || shell
goto start

:ddebug
chain `${wsurl}/script?scriptname=Boot/disabledebug.ps1##params=paramdata || shell
goto start

:reboot
reboot

:exit
exit 1

"@



return $menu