<#
Requires that you delegate the 'Write Description' permission on computer objects in Active Directory to allow the computer (SELF) to update its own description.

Step-by-Step Delegation InstructionsOpen Active Directory Users and Computers (dsa.msc) on a domain controller or machine with RSAT.
Enable View > Advanced Features (required to see the Security tab properly).
Right-click the OU (or domain root if computers are scattered) containing your computer objects → Delegate Control...
Click Next → Add → Type SELF → Check Names (it should resolve) → OK → Next.
Select Create a custom task to delegate → Next.
Select Only the following objects in the folder → Check Computer objects → Also check Create selected objects in this folder and Delete selected objects in this folder (required for the wizard to proceed, even if not needed) → Next.
Check Property-specific → Scroll down and check Write description (under Permissions) → Next → Finish.

Once you do that, you can add this into the Task Sequence to have computers update their own description based on Make/Model/SystemSKU information during deployment.


#>


#Grab Local Computer Information
$LocalInfo = @{}
$LocalInfo['Make'] = (Get-CimInstance -ClassName Win32_ComputerSystem).Manufacturer.Trim()	
$LocalInfo['IsVM'] = "False"
Switch -Wildcard ($LocalInfo['Make']) {
    "*Microsoft*" {
        $LocalInfo['MakeAlias'] = "Microsoft"
        $LocalInfo['ModelAlias'] = (Get-CimInstance -ClassName Win32_ComputerSystem | Select-Object -ExpandProperty Model).Trim()
        $LocalInfo['SystemAlias'] = Get-CimInstance -ClassName MS_SystemInformation -Namespace root\wmi | Select-Object -ExpandProperty SystemSKU
        # Logic for Hyper-V Testing
        If ($LocalInfo['ModelAlias'] -eq "Virtual Machine") {
            $LocalInfo['SystemAlias'] = Get-CimInstance -ClassName MS_SystemInformation -Namespace root\wmi | Select-Object -ExpandProperty SystemVersion
            $LocalInfo['IsVM'] = "True"
        }
    }
    "*HP*" {
        $LocalInfo['MakeAlias'] = "HP"
        $LocalInfo['ModelAlias'] = (Get-CimInstance -ClassName Win32_ComputerSystem | Select-Object -ExpandProperty Model).Trim()
        $LocalInfo['SystemAlias'] = (Get-CimInstance -ClassName MS_SystemInformation -NameSpace root\wmi).BaseBoardProduct.Trim()
    }
    "*VMWare*" {
        $LocalInfo['MakeAlias'] = "VMWare"
        # $LocalInfo['ModelAlias'] = (Get-CimInstance -ClassName Win32_ComputerSystem | Select-Object -ExpandProperty Model).Trim() # Default, sets alias to same as model
        # $LocalInfo['ModelAlias'] = ((Get-CimInstance -ClassName Win32_ComputerSystem | Select-Object -ExpandProperty Model).Trim()).replace(",","_") # Remove the "," and replace with "_"
        $LocalInfo['ModelAlias'] = ((Get-CimInstance -ClassName Win32_ComputerSystem | Select-Object -ExpandProperty Model).Trim()).replace(" ","_").replace(",","_") # Remove the "," and replace with "_", Remove the " " and replace with "_"
        
        $LocalInfo['SystemAlias'] = Get-CimInstance -ClassName MS_SystemInformation -Namespace root\wmi | Select-Object -ExpandProperty SystemSKU
        $LocalInfo['IsVM'] = "True"
    }
    "*QEMU*" {
        $LocalInfo['MakeAlias'] = "QEMU"
        $LocalInfo['ModelAlias'] = (Get-CimInstance -ClassName Win32_ComputerSystem | Select-Object -ExpandProperty Model).Trim()
        $LocalInfo['SystemAlias'] = Get-CimInstance -ClassName MS_SystemInformation -Namespace root\wmi | Select-Object -ExpandProperty SystemSKU
        $LocalInfo['IsVM'] = "True"
    }
    "*Innotek*" {
        $LocalInfo['MakeAlias'] = "Innotek"
        $LocalInfo['ModelAlias'] = (Get-CimInstance -ClassName Win32_ComputerSystem | Select-Object -ExpandProperty Model).Trim()
        $LocalInfo['SystemAlias'] = Get-CimInstance -ClassName MS_SystemInformation -Namespace root\wmi | Select-Object -ExpandProperty SystemSKU
        $LocalInfo['IsVM'] = "True"
    }
    "*Hewlett-Packard*" {
        $LocalInfo['MakeAlias'] = "HP"
        $LocalInfo['ModelAlias'] = (Get-CimInstance -ClassName Win32_ComputerSystem | Select-Object -ExpandProperty Model).Trim()
        $LocalInfo['SystemAlias'] = (Get-CimInstance -ClassName MS_SystemInformation -NameSpace root\wmi).BaseBoardProduct.Trim()
    }
    "*Dell*" {
        $LocalInfo['MakeAlias'] = "Dell"
        $LocalInfo['ModelAlias'] = (Get-CimInstance -ClassName Win32_ComputerSystem | Select-Object -ExpandProperty Model).Trim()
        $LocalInfo['SystemAlias'] = (Get-CimInstance -ClassName MS_SystemInformation -NameSpace root\wmi ).SystemSku.Trim()
    }
    "*Lenovo*" {
        $LocalInfo['MakeAlias'] = "Lenovo"
        $LocalInfo['ModelAlias'] = (Get-CimInstance -ClassName Win32_ComputerSystemProduct | Select-Object -ExpandProperty Version).Trim()
        $LocalInfo['SystemAlias'] = ((Get-CimInstance -ClassName Win32_ComputerSystem | Select-Object -ExpandProperty Model).SubString(0, 4)).Trim()
    }
    "*Intel(R) Client Systems*" {
        $LocalInfo['MakeAlias'] = "Intel(R) Client Systems"
        $LocalInfo['ModelAlias'] = (Get-CimInstance -ClassName Win32_ComputerSystemProduct | Select-Object -ExpandProperty Version).Trim()
        $LocalInfo['SystemAlias'] = ((Get-CimInstance -ClassName Win32_ComputerSystem | Select-Object -ExpandProperty Model).Trim())
        $LocalInfo['SystemAlias'] = $LocalInfo['SystemAlias'].SubString(0, $LocalInfo['SystemAlias'].IndexOf("i")).Trim()
    }
    "*Panasonic*" {
        $LocalInfo['MakeAlias'] = "Panasonic Corporation"
        $LocalInfo['ModelAlias'] = (Get-CimInstance -ClassName Win32_ComputerSystem | Select-Object -ExpandProperty Model).Trim()
        $LocalInfo['SystemAlias'] = (Get-CimInstance -ClassName MS_SystemInformation -NameSpace root\wmi ).BaseBoardProduct.Trim()
    }
    "*Viglen*" {
        $LocalInfo['MakeAlias'] = "Viglen"
        $LocalInfo['ModelAlias'] = (Get-CimInstance -ClassName Win32_ComputerSystem | Select-Object -ExpandProperty Model).Trim()
        $LocalInfo['SystemAlias'] = (Get-CimInstance -ClassName Win32_BaseBoard | Select-Object -ExpandProperty SKU).Trim()
    }
    "*AZW*" {
        $LocalInfo['MakeAlias'] = "AZW"
        $LocalInfo['ModelAlias'] = (Get-CimInstance -ClassName Win32_ComputerSystem | Select-Object -ExpandProperty Model).Trim()
        $LocalInfo['SystemAlias'] = (Get-CimInstance -ClassName MS_SystemInformation -NameSpace root\wmi ).BaseBoardProduct.Trim()
    }
    "*Fujitsu*" {
        $LocalInfo['MakeAlias'] = "Fujitsu"
        $LocalInfo['ModelAlias'] = (Get-CimInstance -ClassName Win32_ComputerSystem | Select-Object -ExpandProperty Model).Trim()
        $LocalInfo['SystemAlias'] = (Get-CimInstance -ClassName Win32_BaseBoard | Select-Object -ExpandProperty SKU).Trim()
    }
    Default {
        $LocalInfo['MakeAlias'] = "NA"
        $LocalInfo['ModelAlias'] = "NA"
        $LocalInfo['SystemAlias'] = "NA"
    }
    # Closing for switch block
}
$MakeAlias = $LocalInfo['MakeAlias']
$ModelAlias = $LocalInfo['ModelAlias']
$SystemAlias = $LocalInfo['SystemAlias']

#Create New Description
$NewDescription = "$MakeAlias $ModelAlias | System: $SystemAlias"

#Get Domain Name
$RootDSE = [ADSI]"LDAP://RootDSE"
$DomainDN = $RootDSE.defaultNamingContext

#Build COnnector
$Searcher = New-Object System.DirectoryServices.DirectorySearcher
$Searcher.SearchRoot = [ADSI]"LDAP://$DomainDN"
$Searcher.Filter = "(&(objectCategory=Computer)(cn=$env:COMPUTERNAME))"
$ComputerObj = [ADSI]$Searcher.FindOne().Path

#Set Description
$ComputerObj.Put("description", $NewDescription)
$ComputerObj.SetInfo()


Write-Host "Set Description to: $NewDescription"