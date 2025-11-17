# Dell - Setting BIOS Settings during Task Sequence

I'll provide some notes on how to set BIOS settings during a Task Sequence using DeployR.  These scripts and processes are not official and are used at your own risk.

> [!IMPORTANT]
> These examples are using clear text passwords as examples of how the processes work.  If you want to secure it, that's outside the scope of these examples.

## CCTK

One style for older devices, it just works on all devices, and there is good documentation around CCTK

##  Native WMI

Custom PowerShell functions to get and set BIOS settings which work in WinPE as well as the Full OS