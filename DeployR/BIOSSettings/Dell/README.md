# Dell - Setting BIOS Settings during Task Sequence

I'll provide some notes on how to set BIOS settings during a Task Sequence using DeployR.  These scripts and processes are not official and are used at your own risk.

> [!IMPORTANT]
> These examples are using clear text passwords as examples of how the processes work.  If you want to secure it, that's outside the scope of these examples.

## CCTK

One style for older devices, it just works on all devices, and there is good documentation around CCTK

##  Native WMI

Custom PowerShell functions to get and set BIOS settings which work in WinPE as well as the Full OS.

**Custom PowerShell Functions:**

- **Test-DellBIOSWMISupport** - Verifies if the device supports Dell BIOS WMI management (devices 2018+)
- **Test-DellBIOSPassword** - Checks if a BIOS Admin or System password is currently set
- **Get-DellBIOSSetting** - Retrieves BIOS settings from the device (all settings or specific setting)
- **Set-DellBIOSSetting** - Modifies BIOS settings with automatic password detection
- **Set-DellBIOSAdminPassword** - Simplified function to set, change, or remove BIOS Admin password

See the [Native WMI folder](NativeWMI/) for detailed documentation and examples.

## Resources

- [Intune Examples for Custom Compliance and Detection/Remediation with Dell Clients](https://github.com/svenriebedell/Intune/tree/main)
- [Dell Tools Update List on GitHub](https://github.com/mkaptano/tools/)

Those are my go-to resources for Dell devices.  You can find these nice Dell folks on X if you're there:
- [Sven Riebe](https://x.com/SvenRiebe) - Technical PreSales 
@Dell
- [Mesut Kaptanoğlu](https://x.com/mkaptano) - Product Manager @ Dell
- [Mathieu Ait Azzouzene](https://x.com/MatAitAzzouzene)
  