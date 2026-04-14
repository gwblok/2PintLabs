function Invoke-CMTraceLog {
	[CmdletBinding()]
	Param (
	[Parameter(Mandatory=$false)]
	$Message,
	[Parameter(Mandatory=$false)]
	$ErrorMessage,
	[Parameter(Mandatory=$false)]
	$Component = "Script",
	[Parameter(Mandatory=$false)]
	[int]$Type,
	[Parameter(Mandatory=$true)]
	$LogFile = "$env:ProgramData\Logs\IForgotToName.log"
	)
	<#
	Type: 1 = Normal, 2 = Warning (yellow), 3 = Error (red)
	#>
	$Time = Get-Date -Format "HH:mm:ss.ffffff"
	$Date = Get-Date -Format "MM-dd-yyyy"
	if ($ErrorMessage -ne $null) {$Type = 3}
	if ($Component -eq $null) {$Component = " "}
	if ($Type -eq $null) {$Type = 1}
	$LogMessage = "<![LOG[$Message $ErrorMessage" + "]LOG]!><time=`"$Time`" date=`"$Date`" component=`"$Component`" context=`"`" type=`"$Type`" thread=`"`" file=`"`">"
	$LogMessage.Replace("`0","") | Out-File -Append -Encoding UTF8 -FilePath $LogFile
}

Function Out-LogVariables{
	[CmdletBinding()]
	Param (
		$LogPath = "D:\iPXELogging"
	)

	#We use StringBuilder for performance
	
	$CustomVarsValues = @{WindowsMenu= "Available" }
	$sb = [System.Text.StringBuilder]::new()
	
	function InifyObject-Parameter {
		param (
		$Header,
		$Object
		)
		
		[void]$sb.AppendLine('[' + $Header + ']')
		
		if($Object.PsObject.Properties["Keys"] -ne $null)
		{
			foreach ($key in $Object.Keys) 
			{ 
				[void]$sb.Append($key) 
				[void]$sb.Append('=')
				[void]$sb.AppendLine($($Object[$key]))
			}
			
			[void]$sb.AppendLine();
			return;
		}
		
		foreach($object_properties in $Object.PsObject.Properties)
		{
			if($object_properties.Value -like 'System.Data.Entity*') 
			{
				continue;
			}
			
			if($object_properties.Value -like 'iPXEAnywhere.Persistence.*') 
			{
				continue;
			}
			
			
			# Access the name of the property
			[void]$sb.Append($object_properties.Name) 
			#Write the .ini file =
			[void]$sb.Append('=')
			# Access the value of the property, note the AppendLine
			if($object_properties.TypeNameOfValue -like 'System.Collections.Generic.Dictionary*')
			{
				foreach ($key in $object_properties.Value.Keys) 
				{ 
					[void]$sb.Append($key) 
					[void]$sb.Append(':')
					[void]$sb.Append($($object_properties.Value[$key]))
					[void]$sb.Append(',')
				}
				
				continue;
			}
			[void]$sb.AppendLine($object_properties.Value)
		}
		
		[void]$sb.AppendLine();
	}
	InifyObject-Parameter -Header iPXEVariables -Object $PostParams
	
	InifyObject-Parameter -Header Machine -Object $Machine
	InifyObject-Parameter -Header RequestStatusInfo -Object $RequestStatusInfo
	InifyObject-Parameter -Header RequestNetworkInfo -Object $RequestNetworkInfo
	
	InifyObject-Parameter -Header DeployNetworkRequest -Object $RequestNetworkInfo.DeployNetwork
	InifyObject-Parameter -Header TargetNetworkRequest -Object $RequestNetworkInfo.TargetNetwork
	
	InifyObject-Parameter -Header Machineinformation -Object $Machineinformation
	InifyObject-Parameter -Header Model -Object $Machineinformation.Model
	
	InifyObject-Parameter -Header DeployLocation -Object $DeployLocation
	InifyObject-Parameter -Header TargetLocation -Object $TargetLocation
	InifyObject-Parameter -Header DeployNetworkGroup -Object $DeployNetworkGroup
	InifyObject-Parameter -Header TargetNetworkGroup -Object $TargetNetworkGroup
	InifyObject-Parameter -Header DeployNetwork -Object $DeployNetwork
	InifyObject-Parameter -Header TargetNetwork -Object $TargetNetwork
	
	InifyObject-Parameter -Header DeployMachineKeyValues -Object $DeployMachineKeyValues
	InifyObject-Parameter -Header TargetMachineKeyValues -Object $TargetMachineKeyValues
	
	#InifyObject-Parameter -Header CustomVars -Object $Paramdata
	
	
	#$sb.ToString() | out-file 'c:\temp\var.ini
	[string]$MAC = ($RequestStatusInfo.DeployMAC.ToString()).replace(":","")
	$sb.ToString() | out-file "$LogPath\var\var$($MAC).ini" -Force
}