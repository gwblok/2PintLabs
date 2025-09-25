#Pull Vars from TS:
try {
    Import-Module DeployR.Utility
}
catch {}



# Get the provided variables
if (Get-Module -name "DeployR.Utility"){
    $CRMinMemory = ${TSEnv:CRMinMemory}
    $CRMinFreeStorage = ${TSEnv:CRMinFreeStorage}
    $CROSType = ${TSEnv:CROSType}
    $CRMinOSVer = ${TSEnv:CRMinOSVer}
    $CRTPM2 = ${TSEnv:CRTPM2}
    $CRMinWin11 = ${TSEnv:CRMinWin11}
    $HostValueOSType = if (${TSEnv:IsServerOS} -eq "true") { "Server" } else { "Client" }
    $DebugLogging = ${TSEnv:CRDebugLogging}
}
else{
    $CRMinMemory = "4"
    $CRMinFreeStorage = "20"
    $CROSType = "Client"
    $CRMinOSVer = "19045"
    $CRTPM2 = "true"
    $CRMinWin11 = "true"
    $HostValueOSType = if ((Get-CimInstance -ClassName Win32_OperatingSystem).ProductType -eq 1) { "Client" } else { "Server" }
    $DebugLogging = "true"
}
if ($env:SystemDrive -eq "X:"){
    $IsWinPE = $true
    Write-Host "Running in WinPE environment, Several Checks do not apply"
}
else {$IsWinPE = $false}
$DebugLogging = $true

#Report Step Variables
Write-Host "================================================================"
Write-Host "Reporting Step Variables"
if ($IsWinPE){
    Write-Host "CRMinFreeStorage | Does not apply in WinPE" = $CRMinFreeStorage
    Write-Host "CROSType         | Does not apply in WinPE" = $CROSType
    Write-Host "CRMinOSVer       | Does not apply in WinPE" = $CRMinOSVer
}
else{
    Write-Host "CRMinFreeStorage = $CRMinFreeStorage"
    Write-Host "CROSType =         $CROSType"
    Write-Host "CRMinOSVer =       $CRMinOSVer"

}
Write-Host "CRMinMemory =      $CRMinMemory"
Write-Host "CRTPM2 =           $CRTPM2"
Write-Host "CRMinWin11 =       $CRMinWin11"
Write-Host "================================================================"


write-host "Gathering System Information"
#Get Host Values That aren't in TS Vars
#Free Space in GB
$HostValueFreeStorage = [math]::Round((Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='C:'" | Select-Object -ExpandProperty FreeSpace) / 1GB, 2)
#Current OS Build
$HostValueCurrentBuild = (Get-CimInstance -ClassName Win32_OperatingSystem | Select-Object -ExpandProperty Version).split(".") | Select-Object -Last 1
#Host Value Memory
$HostValueMemory = [math]::Round((Get-CimInstance -ClassName Win32_ComputerSystem | Select-Object -ExpandProperty TotalPhysicalMemory) / 1GB, 2)

#TPM 2
$TPMRAW = (Get-CimInstance -Namespace "ROOT\cimv2\Security\MicrosoftTpm" -ClassName Win32_TPM).SpecVersion
if ($null -ne $TPMRAW) {
    if ($TPMRAW -like "2.*") {
        $HostValueTPM2 = $true
    }
    else {
        $HostValueTPM2 = $false
    }
}
else {
    $HostValueTPM2 = $false
}

#region functions
function Get-Win11Readiness {
    [CmdletBinding()]
    param (
        [switch]$DebugLogging = $true
    )


    <#
    Modified for OSD by @gwblok
    
    
    
    Changes
    2022.01.28
    - Changed Get-TPM to using Get-CimInstance -Namespace "ROOT\cimv2\Security\MicrosoftTpm" -ClassName Win32_TPM
    2022.07.01 
    - Modified for OSDCloud
    
    #>
    
    #=============================================================================================================================
    #
    #
    # Script Name:     HardwareReadiness.ps1
    # Description:     Verifies the hardware compliance. Return code 0 for success. 
    #                  In case of failure, returns non zero error code along with error message.
    
    # This script is not supported under any Microsoft standard support program or service and is distributed under the MIT license
    
    # Copyright (C) 2021 Microsoft Corporation
    
    # Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation
    # files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy,
    # modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software
    # is furnished to do so, subject to the following conditions:
    
    # The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
    
    # THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE
    # WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
    # COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
    # ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
    
    #=============================================================================================================================
    
    $CurrentVersion = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    if ($CurrentVersion.EditionID -match "WindowsPE"){$InWinPE = $true}
    
    $exitCode = 0
    
    [int]$MinOSDiskSizeGB = 64
    [int]$MinMemoryGB = 4
    [Uint32]$MinClockSpeedMHz = 1000
    [Uint32]$MinLogicalCores = 2
    [Uint16]$RequiredAddressWidth = 64
    
    $PASS_STRING = "PASS"
    $FAIL_STRING = "FAIL"
    $FAILED_TO_RUN_STRING = "FAILED TO RUN"
    $UNDETERMINED_CAPS_STRING = "UNDETERMINED"
    $UNDETERMINED_STRING = "Undetermined"
    $CAPABLE_STRING = "Capable"
    $NOT_CAPABLE_STRING = "Not capable"
    $CAPABLE_CAPS_STRING = "CAPABLE"
    $NOT_CAPABLE_CAPS_STRING = "NOT CAPABLE"
    $STORAGE_STRING = "Storage"
    $OS_DISK_SIZE_STRING = "OSDiskSize"
    $MEMORY_STRING = "Memory"
    $SYSTEM_MEMORY_STRING = "System_Memory"
    $GB_UNIT_STRING = "GB"
    $TPM_STRING = "TPM"
    $TPM_VERSION_STRING = "TPMVersion"
    $PROCESSOR_STRING = "Processor"
    $SECUREBOOT_STRING = "SecureBoot"
    $I7_7820HQ_CPU_STRING = "i7-7820hq CPU"
    
    # 0=name of check, 1=attribute checked, 2=value, 3=PASS/FAIL/UNDETERMINED
    $logFormat = '{0}: {1}={2}. {3}; '
    
    # 0=name of check, 1=attribute checked, 2=value, 3=unit of the value, 4=PASS/FAIL/UNDETERMINED
    $logFormatWithUnit = '{0}: {1}={2}{3}. {4}; '
    
    # 0=name of check.
    $logFormatReturnReason = '{0}, '
    
    # 0=exception.
    $logFormatException = '{0}; '
    
    # 0=name of check, 1= attribute checked and its value, 2=PASS/FAIL/UNDETERMINED
    $logFormatWithBlob = '{0}: {1}. {2}; '
    
    # return returnCode is -1 when an exception is thrown. 1 if the value does not meet requirements. 0 if successful. -2 default, script didn't run.
    $outObject = @{ returnCode = -2; returnResult = $FAILED_TO_RUN_STRING; returnReason = ""; logging = "" }
    
    # NOT CAPABLE(1) state takes precedence over UNDETERMINED(-1) state
    function Private:UpdateReturnCode {
        param(
        [Parameter(Mandatory = $true)]
        [ValidateRange(-2, 1)]
        [int] $ReturnCode
        )
        
        Switch ($ReturnCode) {
            
            0 {
                if ($outObject.returnCode -eq -2) {
                    $outObject.returnCode = $ReturnCode
                }
            }
            1 {
                $outObject.returnCode = $ReturnCode
            }
            -1 {
                if ($outObject.returnCode -ne 1) {
                    $outObject.returnCode = $ReturnCode
                }
            }
        }
    }
    
    $Source = @"
using Microsoft.Win32;
using System;
using System.Runtime.InteropServices;
    
    public class CpuFamilyResult
    {
        public bool IsValid { get; set; }
        public string Message { get; set; }
    }
    
    public class CpuFamily
    {
        [StructLayout(LayoutKind.Sequential)]
        public struct SYSTEM_INFO
        {
            public ushort ProcessorArchitecture;
            ushort Reserved;
            public uint PageSize;
            public IntPtr MinimumApplicationAddress;
            public IntPtr MaximumApplicationAddress;
            public IntPtr ActiveProcessorMask;
            public uint NumberOfProcessors;
            public uint ProcessorType;
            public uint AllocationGranularity;
            public ushort ProcessorLevel;
            public ushort ProcessorRevision;
        }
    
        [DllImport("kernel32.dll")]
        internal static extern void GetNativeSystemInfo(ref SYSTEM_INFO lpSystemInfo);
    
        public enum ProcessorFeature : uint
        {
            ARM_SUPPORTED_INSTRUCTIONS = 34
        }
    
        [DllImport("kernel32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        static extern bool IsProcessorFeaturePresent(ProcessorFeature processorFeature);
    
        private const ushort PROCESSOR_ARCHITECTURE_X86 = 0;
        private const ushort PROCESSOR_ARCHITECTURE_ARM64 = 12;
        private const ushort PROCESSOR_ARCHITECTURE_X64 = 9;
    
        private const string INTEL_MANUFACTURER = "GenuineIntel";
        private const string AMD_MANUFACTURER = "AuthenticAMD";
        private const string QUALCOMM_MANUFACTURER = "Qualcomm Technologies Inc";
    
        public static CpuFamilyResult Validate(string manufacturer, ushort processorArchitecture)
        {
            CpuFamilyResult cpuFamilyResult = new CpuFamilyResult();
    
            if (string.IsNullOrWhiteSpace(manufacturer))
            {
                cpuFamilyResult.IsValid = false;
                cpuFamilyResult.Message = "Manufacturer is null or empty";
                return cpuFamilyResult;
            }
    
            string registryPath = "HKEY_LOCAL_MACHINE\\Hardware\\Description\\System\\CentralProcessor\\0";
            SYSTEM_INFO sysInfo = new SYSTEM_INFO();
            GetNativeSystemInfo(ref sysInfo);
    
            switch (processorArchitecture)
            {
                case PROCESSOR_ARCHITECTURE_ARM64:
    
                    if (manufacturer.Equals(QUALCOMM_MANUFACTURER, StringComparison.OrdinalIgnoreCase))
                    {
                        bool isArmv81Supported = IsProcessorFeaturePresent(ProcessorFeature.ARM_SUPPORTED_INSTRUCTIONS);
    
                        if (!isArmv81Supported)
                        {
                            string registryName = "CP 4030";
                            long registryValue = (long)Registry.GetValue(registryPath, registryName, -1);
                            long atomicResult = (registryValue >> 20) & 0xF;
    
                            if (atomicResult >= 2)
                            {
                                isArmv81Supported = true;
                            }
                        }
    
                        cpuFamilyResult.IsValid = isArmv81Supported;
                        cpuFamilyResult.Message = isArmv81Supported ? "" : "Processor does not implement ARM v8.1 atomic instruction";
                    }
                    else
                    {
                        cpuFamilyResult.IsValid = false;
                        cpuFamilyResult.Message = "The processor isn't currently supported for Windows 11";
                    }
    
                    break;
    
                case PROCESSOR_ARCHITECTURE_X64:
                case PROCESSOR_ARCHITECTURE_X86:
    
                    int cpuFamily = sysInfo.ProcessorLevel;
                    int cpuModel = (sysInfo.ProcessorRevision >> 8) & 0xFF;
                    int cpuStepping = sysInfo.ProcessorRevision & 0xFF;
    
                    if (manufacturer.Equals(INTEL_MANUFACTURER, StringComparison.OrdinalIgnoreCase))
                    {
                        try
                        {
                            cpuFamilyResult.IsValid = true;
                            cpuFamilyResult.Message = "";
    
                            if (cpuFamily >= 6 && cpuModel <= 95 && !(cpuFamily == 6 && cpuModel == 85))
                            {
                                cpuFamilyResult.IsValid = false;
                                cpuFamilyResult.Message = "";
                            }
                            else if (cpuFamily == 6 && (cpuModel == 142 || cpuModel == 158) && cpuStepping == 9)
                            {
                                string registryName = "Platform Specific Field 1";
                                int registryValue = (int)Registry.GetValue(registryPath, registryName, -1);
    
                                if ((cpuModel == 142 && registryValue != 16) || (cpuModel == 158 && registryValue != 8))
                                {
                                    cpuFamilyResult.IsValid = false;
                                }
                                cpuFamilyResult.Message = "PlatformId " + registryValue;
                            }
                        }
                        catch (Exception ex)
                        {
                            cpuFamilyResult.IsValid = false;
                            cpuFamilyResult.Message = "Exception:" + ex.GetType().Name;
                        }
                    }
                    else if (manufacturer.Equals(AMD_MANUFACTURER, StringComparison.OrdinalIgnoreCase))
                    {
                        cpuFamilyResult.IsValid = true;
                        cpuFamilyResult.Message = "";
    
                        if (cpuFamily < 23 || (cpuFamily == 23 && (cpuModel == 1 || cpuModel == 17)))
                        {
                            cpuFamilyResult.IsValid = false;
                        }
                    }
                    else
                    {
                        cpuFamilyResult.IsValid = false;
                        cpuFamilyResult.Message = "Unsupported Manufacturer: " + manufacturer + ", Architecture: " + processorArchitecture + ", CPUFamily: " + sysInfo.ProcessorLevel + ", ProcessorRevision: " + sysInfo.ProcessorRevision;
                    }
    
                    break;
    
                default:
                    cpuFamilyResult.IsValid = false;
                    cpuFamilyResult.Message = "Unsupported CPU category. Manufacturer: " + manufacturer + ", Architecture: " + processorArchitecture + ", CPUFamily: " + sysInfo.ProcessorLevel + ", ProcessorRevision: " + sysInfo.ProcessorRevision;
                    break;
            }
            return cpuFamilyResult;
        }
    }
"@
    
    #region Storage
    Write-Host "Getting OS Drive Size"
    try {
        
        if ($InWinPE){
            $osDrive = Get-Disk -Number 0
            $osDriveSize = $osDrive | Select-Object @{Name = "SizeGB"; Expression = { $_.Size / 1GB -as [int] } } 
        }
        else {
            $osDrive = Get-CimInstance -ClassName Win32_OperatingSystem | Select-Object -Property SystemDrive
            $osDriveSize = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='$($osDrive.SystemDrive)'" | Select-Object @{Name = "SizeGB"; Expression = { $_.Size / 1GB -as [int] } } 
        }
        
        if ($null -eq $osDriveSize) {
            UpdateReturnCode -ReturnCode 1
            $outObject.returnReason += $logFormatReturnReason -f $STORAGE_STRING
            $outObject.logging += $logFormatWithBlob -f $STORAGE_STRING, "Storage is null", $FAIL_STRING
            $exitCode = 1
            $HR_Storage = $FAIL_STRING
            if ($DebugLogging) {Write-Host "OS Drive Size is null"}
        }
        elseif ($osDriveSize.SizeGB -lt $MinOSDiskSizeGB) {
            UpdateReturnCode -ReturnCode 1
            $outObject.returnReason += $logFormatReturnReason -f $STORAGE_STRING
            $outObject.logging += $logFormatWithUnit -f $STORAGE_STRING, $OS_DISK_SIZE_STRING, ($osDriveSize.SizeGB), $GB_UNIT_STRING, $FAIL_STRING
            $exitCode = 1
            $HR_Storage = $FAIL_STRING
            if ($DebugLogging) {Write-Host "OS Drive Size is less than $MinOSDiskSizeGB GB"}
        }
        else {
            $outObject.logging += $logFormatWithUnit -f $STORAGE_STRING, $OS_DISK_SIZE_STRING, ($osDriveSize.SizeGB), $GB_UNIT_STRING, $PASS_STRING
            UpdateReturnCode -ReturnCode 0
            $HR_Storage = $PASS_STRING
            if ($DebugLogging) {Write-Host "OS Drive Size is valid: $($osDriveSize.SizeGB) GB"}
        }
    }
    catch {
        UpdateReturnCode -ReturnCode -1
        $outObject.logging += $logFormat -f $STORAGE_STRING, $OS_DISK_SIZE_STRING, $UNDETERMINED_STRING, $UNDETERMINED_CAPS_STRING
        $outObject.logging += $logFormatException -f "$($_.Exception.GetType().Name) $($_.Exception.Message)"
        $exitCode = 1
        $HR_Storage = $FAIL_STRING
        if ($DebugLogging) {Write-Host "Exception getting OS Drive Size: $($_.Exception.Message)"}
    }
    #endregion

    #region Memory (bytes)
    if ($DebugLogging) {Write-Host "Getting Memory Details"}
    try {
        $memory = Get-CimInstance Win32_PhysicalMemory | Measure-Object -Property Capacity -Sum | Select-Object @{Name = "SizeGB"; Expression = { $_.Sum / 1GB -as [int] } }
        
        if ($null -eq $memory) {
            UpdateReturnCode -ReturnCode 1
            $outObject.returnReason += $logFormatReturnReason -f $MEMORY_STRING
            $outObject.logging += $logFormatWithBlob -f $MEMORY_STRING, "Memory is null", $FAIL_STRING
            $exitCode = 1
            $HR_Memory = $FAIL_STRING
            if ($DebugLogging) {Write-Host "Memory is null"}
        }
        elseif ($memory.SizeGB -lt $MinMemoryGB) {
            UpdateReturnCode -ReturnCode 1
            $outObject.returnReason += $logFormatReturnReason -f $MEMORY_STRING
            $outObject.logging += $logFormatWithUnit -f $MEMORY_STRING, $SYSTEM_MEMORY_STRING, ($memory.SizeGB), $GB_UNIT_STRING, $FAIL_STRING
            $exitCode = 1
            $HR_Memory = $FAIL_STRING
            if ($DebugLogging) {Write-Host "Memory is less than $MinMemoryGB GB"}
        }
        else {
            $outObject.logging += $logFormatWithUnit -f $MEMORY_STRING, $SYSTEM_MEMORY_STRING, ($memory.SizeGB), $GB_UNIT_STRING, $PASS_STRING
            UpdateReturnCode -ReturnCode 0
            $HR_Memory = $PASS_STRING
            if ($DebugLogging) {Write-Host "Memory is valid: $($memory.SizeGB) GB"}
        }
    }
    catch {
        UpdateReturnCode -ReturnCode -1
        $outObject.logging += $logFormat -f $MEMORY_STRING, $SYSTEM_MEMORY_STRING, $UNDETERMINED_STRING, $UNDETERMINED_CAPS_STRING
        $outObject.logging += $logFormatException -f "$($_.Exception.GetType().Name) $($_.Exception.Message)"
        $exitCode = 1
        $HR_Memory = $FAIL_STRING
        if ($DebugLogging) {Write-Host "Exception getting Memory: $($_.Exception.Message)"}
    }
    #endregion

    #region TPM
    if ($DebugLogging) {Write-Host "Getting TPM Status"}
    try {
        if ($InWinPE){
            $tpm = Get-CimInstance -Namespace "ROOT\cimv2\Security\MicrosoftTpm" -ClassName Win32_TPM 
        }
        else {
            $tpm = Get-Tpm
        }
        
        #$tpm = Get-Tpm
        
        if ($null -eq $tpm) {
            UpdateReturnCode -ReturnCode 1
            $outObject.returnReason += $logFormatReturnReason -f $TPM_STRING
            $outObject.logging += $logFormatWithBlob -f $TPM_STRING, "TPM is null", $FAIL_STRING
            $exitCode = 1
            $HR_TPM = $FAIL_STRING
            if ($DebugLogging) {Write-Host "TPM is null"}
        }
        elseif ($tpm.IsOwned_InitialValue -or $tpm.TpmPresent) {
            $tpmVersion = Get-CimInstance -ClassName Win32_Tpm -Namespace root\CIMV2\Security\MicrosoftTpm | Select-Object -Property SpecVersion
            
            if ($null -eq $tpmVersion.SpecVersion) {
                UpdateReturnCode -ReturnCode 1
                $outObject.returnReason += $logFormatReturnReason -f $TPM_STRING
                $outObject.logging += $logFormat -f $TPM_STRING, $TPM_VERSION_STRING, "null", $FAIL_STRING
                $exitCode = 1
                $HR_TPM = $FAIL_STRING
                if ($DebugLogging) {Write-Host "TPM Version is null"}
            }
            
            $majorVersion = $tpmVersion.SpecVersion.Split(",")[0] -as [int]
            if ($majorVersion -lt 2) {
                UpdateReturnCode -ReturnCode 1
                $outObject.returnReason += $logFormatReturnReason -f $TPM_STRING
                $outObject.logging += $logFormat -f $TPM_STRING, $TPM_VERSION_STRING, ($tpmVersion.SpecVersion), $FAIL_STRING
                $exitCode = 1
                $HR_TPM = $FAIL_STRING
                if ($DebugLogging) {Write-Host "TPM Version is less than 2: $($tpmVersion.SpecVersion)"}
            }
            else {
                $outObject.logging += $logFormat -f $TPM_STRING, $TPM_VERSION_STRING, ($tpmVersion.SpecVersion), $PASS_STRING
                UpdateReturnCode -ReturnCode 0
                $HR_TPM = $PASS_STRING
                if ($DebugLogging) {Write-Host "TPM Version is valid: $($tpmVersion.SpecVersion)"}
            }
        }
        else {
            if ($tpm.GetType().Name -eq "String") {
                UpdateReturnCode -ReturnCode -1
                $outObject.logging += $logFormat -f $TPM_STRING, $TPM_VERSION_STRING, $UNDETERMINED_STRING, $UNDETERMINED_CAPS_STRING
                $outObject.logging += $logFormatException -f $tpm
                if ($DebugLogging) {Write-Host "TPM is undetermined"}
            }
            else {
                UpdateReturnCode -ReturnCode  1
                $outObject.returnReason += $logFormatReturnReason -f $TPM_STRING
                if ($InWinPE){
                    $outObject.logging += $logFormat -f $TPM_STRING, $TPM_VERSION_STRING, "NA", $FAIL_STRING
                }
                else {                
                    $outObject.logging += $logFormat -f $TPM_STRING, $TPM_VERSION_STRING, ($tpm.TpmPresent), $FAIL_STRING
                }
                $HR_TPM = $FAIL_STRING
                if ($DebugLogging) {Write-Host "TPM is failed"}
            }
            $exitCode = 1
            $HR_TPM = $FAIL_STRING
            if ($DebugLogging) {Write-Host "TPM is not owned or not present"}
        }
    }
    catch {
        UpdateReturnCode -ReturnCode -1
        $outObject.logging += $logFormat -f $TPM_STRING, $TPM_VERSION_STRING, $UNDETERMINED_STRING, $UNDETERMINED_CAPS_STRING
        $outObject.logging += $logFormatException -f "$($_.Exception.GetType().Name) $($_.Exception.Message)"
        $exitCode = 1
        $HR_TPM = $FAIL_STRING
        if ($DebugLogging) {Write-Host "Exception getting TPM: $($_.Exception.Message)"}
    }
    #endregion

    #region CPU Details
    if ($DebugLogging) {Write-Host "Getting CPU Details"}
    #try {
        $cpuDetails = Get-CimInstance -ClassName Win32_Processor
        #$cpuDetails = @(Get-CimInstance -ClassName Win32_Processor)[0]
        if ($null -eq $cpuDetails) {
            UpdateReturnCode -ReturnCode 1
            $exitCode = 1
            $outObject.returnReason += $logFormatReturnReason -f $PROCESSOR_STRING
            $outObject.logging += $logFormatWithBlob -f $PROCESSOR_STRING, "CpuDetails is null", $FAIL_STRING
            $HR_CPU = $FAIL_STRING
            if ($DebugLogging) {Write-Host "CpuDetails is null"}
        }
        else {
            $processorCheckFailed = $false
            
            # AddressWidth
            if ($null -eq $cpuDetails.AddressWidth -or $cpuDetails.AddressWidth -ne $RequiredAddressWidth) {
                UpdateReturnCode -ReturnCode 1
                $processorCheckFailed = $true
                $exitCode = 1
                $HR_CPU = $FAIL_STRING
                if ($DebugLogging) {Write-Host "CpuDetails.AddressWidth is null or not equal to $RequiredAddressWidth"}
            }
            
            # ClockSpeed is in MHz
            if ($null -eq $cpuDetails.MaxClockSpeed -or $cpuDetails.MaxClockSpeed -le $MinClockSpeedMHz) {
                UpdateReturnCode -ReturnCode 1;
                $processorCheckFailed = $true
                $exitCode = 1
                $HR_CPU = $FAIL_STRING
                if ($DebugLogging) {Write-Host "CpuDetails.MaxClockSpeed is null or less than $MinClockSpeedMHz"}
            }
            
            # Number of Logical Cores
            if ($null -eq $cpuDetails.NumberOfLogicalProcessors -or $cpuDetails.NumberOfLogicalProcessors -lt $MinLogicalCores) {
                UpdateReturnCode -ReturnCode 1
                $processorCheckFailed = $true
                $exitCode = 1
                $HR_CPU = $FAIL_STRING
            }
            
            # CPU Family
            Add-Type -TypeDefinition $Source
            $cpuFamilyResult = [CpuFamily]::Validate([String]$cpuDetails.Manufacturer, [uint16]$cpuDetails.Architecture)
            
            $cpuDetailsLog = "{AddressWidth=$($cpuDetails.AddressWidth); MaxClockSpeed=$($cpuDetails.MaxClockSpeed); NumberOfLogicalCores=$($cpuDetails.NumberOfLogicalProcessors); Manufacturer=$($cpuDetails.Manufacturer); Caption=$($cpuDetails.Caption); $($cpuFamilyResult.Message)}"
            
            if (!$cpuFamilyResult.IsValid) {
                UpdateReturnCode -ReturnCode 1
                $processorCheckFailed = $true
                $exitCode = 1
                $HR_CPU = $FAIL_STRING
                if ($DebugLogging) {Write-Host "CpuFamily is not valid: $($cpuFamilyResult.Message)"}
            }
            
            if ($processorCheckFailed) {
                $outObject.returnReason += $logFormatReturnReason -f $PROCESSOR_STRING
                $outObject.logging += $logFormatWithBlob -f $PROCESSOR_STRING, ($cpuDetailsLog), $FAIL_STRING
                $HR_CPU = $FAIL_STRING
                if ($DebugLogging) {Write-Host "Processor check failed"}
            }
            else {
                $outObject.logging += $logFormatWithBlob -f $PROCESSOR_STRING, ($cpuDetailsLog), $PASS_STRING
                UpdateReturnCode -ReturnCode 0
                $HR_CPU = $PASS_STRING
                if ($DebugLogging) {Write-Host "Processor check passed"}
            }
        }
    #}
    <#catch {
        UpdateReturnCode -ReturnCode -1
        $outObject.logging += $logFormat -f $PROCESSOR_STRING, $PROCESSOR_STRING, $UNDETERMINED_STRING, $UNDETERMINED_CAPS_STRING
        $outObject.logging += $logFormatException -f "$($_.Exception.GetType().Name) $($_.Exception.Message)"
        $exitCode = 1
        $HR_CPU = $FAIL_STRING
        if ($DebugLogging) {Write-Host "Exception getting CpuDetails: $($_.Exception.Message)"}
    }#>
    #endregion

    #region SecureBoot
    if ($DebugLogging) {Write-Host "Getting Secure Boot Status"}
    try {
        $isSecureBootEnabled = Confirm-SecureBootUEFI
        $outObject.logging += $logFormatWithBlob -f $SECUREBOOT_STRING, $CAPABLE_STRING, $PASS_STRING
        UpdateReturnCode -ReturnCode 0
        $HR_SecureBoot = $PASS_STRING
        if ($DebugLogging) {Write-Host "Secure Boot is enabled"}
    }
    catch [System.PlatformNotSupportedException] {
        # PlatformNotSupportedException "Cmdlet not supported on this platform." - SecureBoot is not supported or is non-UEFI computer.
        UpdateReturnCode -ReturnCode 1
        $outObject.returnReason += $logFormatReturnReason -f $SECUREBOOT_STRING
        $outObject.logging += $logFormatWithBlob -f $SECUREBOOT_STRING, $NOT_CAPABLE_STRING, $FAIL_STRING
        $exitCode = 1
        $HR_SecureBoot = $FAIL_STRING
        if ($DebugLogging) {Write-Host "Secure Boot is not capable"}
    }
    catch [System.UnauthorizedAccessException] {
        UpdateReturnCode -ReturnCode -1
        $outObject.logging += $logFormatWithBlob -f $SECUREBOOT_STRING, $UNDETERMINED_STRING, $UNDETERMINED_CAPS_STRING
        $outObject.logging += $logFormatException -f "$($_.Exception.GetType().Name) $($_.Exception.Message)"
        $exitCode = 1
        $HR_SecureBoot = $FAIL_STRING
        if ($DebugLogging) {Write-Host "Secure Boot is not owned or not present"}
    }
    catch {
        UpdateReturnCode -ReturnCode -1
        $outObject.logging += $logFormatWithBlob -f $SECUREBOOT_STRING, $UNDETERMINED_STRING, $UNDETERMINED_CAPS_STRING
        $outObject.logging += $logFormatException -f "$($_.Exception.GetType().Name) $($_.Exception.Message)"
        $exitCode = 1
        $HR_SecureBoot = $FAIL_STRING
        if ($DebugLogging) {Write-Host "Exception getting Secure Boot: $($_.Exception.Message)"}
    }
    #endregion
    #region i7-7820hq CPU
    try {
        $supportedDevices = @('surface studio 2', 'precision 5520')
        $systemInfo = @(Get-CimInstance -ClassName Win32_ComputerSystem)[0]

        if ($null -ne $cpuDetails) {
            if ($cpuDetails.Name -match 'i7-7820hq cpu @ 2.90ghz'){
                $modelOrSKUCheckLog = $systemInfo.Model.Trim()
                if ($supportedDevices -contains $modelOrSKUCheckLog){
                    $outObject.logging += $logFormatWithBlob -f $I7_7820HQ_CPU_STRING, $modelOrSKUCheckLog, $PASS_STRING
                    $outObject.returnCode = 0
                    $exitCode = 0
                }
            }
        }
    }
    catch {
        if ($outObject.returnCode -ne 0){
            UpdateReturnCode -ReturnCode -1
            $outObject.logging += $logFormatWithBlob -f $I7_7820HQ_CPU_STRING, $UNDETERMINED_STRING, $UNDETERMINED_CAPS_STRING
            $outObject.logging += $logFormatException -f "$($_.Exception.GetType().Name) $($_.Exception.Message)"
            $exitCode = 1
        }
    }
    #endregion
    Switch ($outObject.returnCode) {
        
        0 { $outObject.returnResult = $CAPABLE_CAPS_STRING }
        1 { $outObject.returnResult = $NOT_CAPABLE_CAPS_STRING }
        -1 { $outObject.returnResult = $UNDETERMINED_CAPS_STRING }
        -2 { $outObject.returnResult = $FAILED_TO_RUN_STRING }
    }
    
    $Global:Readiness = $null
    $Global:Readiness = [ordered]@{
        Return = $null
        Reason = $null
        SecureBoot = $null
        CPU = $null
        TPM = $null
        Memory = $null
        Storage = $null
    }
    
    
    #Write-Output "HR_ReturnResult = $($outObject.returnResult)"
    $Global:Readiness.Return = $outObject.returnResult
    if ($outObject.returnReason)
    {
        if ($outObject.returnResult -eq $NOT_CAPABLE_CAPS_STRING){
            $Reason = $outObject.returnReason
            $Reason = $Reason.Substring(0,$Reason.Length-2)
        }
        else {$Reason = $outObject.returnReason}
        #Write-Output "HR_ReturnReason = $($outObject.returnReason)"
        $Global:Readiness.Reason = $Reason 
    }
    #Write-Output "HR_SecureBoot = $HR_SecureBoot"
    $Global:Readiness.SecureBoot = $HR_SecureBoot
    #Write-Output "HR_CPU = $HR_CPU"
    $Global:Readiness.CPU = $HR_CPU
    #Write-Output "HR_TPM = $HR_TPM"
    $Global:Readiness.TPM = $HR_TPM
    #Write-Output "HR_Memory = $HR_Memory"
    $Global:Readiness.Memory = $HR_Memory
    #Write-Output "HR_Storage = $HR_Storage"
    $Global:Readiness.Storage= $HR_Storage
    $outObject | ConvertTo-Json -Depth 10 | Out-File -FilePath $env:TEMP\Win11Readiness.json -Force
    return $Global:Readiness
    
    
    
    
}

#endregion




#Get the Win11 data
if ($DebugLogging){
    Write-Host "Getting Windows 11 Readiness Data - Debug Logging Enabled"
    $Win11Readiness = Get-Win11Readiness -DebugLogging
}
else {
    $Win11Readiness = Get-Win11Readiness
}

# Start the Compares
Write-host "Starting Requirement Checks"
$Compliant = $true

#Check for Items that only Pertain to starting in Full OS (WinPE = False)
if ($IsWinPE -eq $false){
    #Check for Required Minimum OS Version
    if ($null -ne $CRMinOSVer -and $CRMinOSVer -ne ""){
        #If Set, compare to Current OS Build and ensure Current OS Build is higher
        Write-Host ""
        Write-Host "Checking Minimum OS Version"
        if ($HostValueCurrentBuild -lt $CRMinOSVer) {
            $Compliant = $false
            Write-Host "✗ Compliance Failed: Minimum OS Version | Required: $CRMinOSVer | Current: $HostValueCurrentBuild" -ForegroundColor Red
        }
        else {
            Write-Host "✓ Compliant: Minimum OS Version | $HostValueCurrentBuild" -ForegroundColor Green
        }
    }
    #Check for Required Free Storage
    if ($null -ne $CRMinFreeStorage -and $CRMinFreeStorage -ne ""){
        #If Set, compare to Current Free Storage and ensure Current Free Storage is higher
        Write-Host ""
        Write-Host "Checking Minimum Free Storage"
        if ($HostValueFreeStorage -lt $CRMinFreeStorage) {
            $Compliant = $false
            Write-Host "✗ Compliance Failed: Minimum Free Storage | Required: $CRMinFreeStorage GB | Current: $HostValueFreeStorage GB" -ForegroundColor Red
        }
        else {
            Write-Host "✓ Compliant: Minimum Free Storage | $HostValueFreeStorage GB" -ForegroundColor Green
        }
    }
    #Check for Required OS Type
    if ($null -ne $CROSType -and $CROSType -ne ""){
        #If Set, compare to Current OS Type and ensure they match
        Write-Host ""
        Write-Host "Checking OS Type (Client of Server OS)"
        if ($HostValueOSType -ne $CROSType) {
            $Compliant = $false
            Write-Host "✗ Compliance Failed: OS Type | Required: $CROSType | Current: $HostValueOSType" -ForegroundColor Red
        }
        else {
            Write-Host "✓ Compliant: OS Type | $HostValueOSType" -ForegroundColor Green
        }
    }
}

#Now rest of these will run either way, either WinPE or Full OS

#Check if $CRMinMemory is set
if ($null -ne $CRMinMemory -and $CRMinMemory -ne ""){
    #If Set, compare to Current Memory and ensure Current Memory is higher
    #Round up to nearest whole number GB, typically video or graphics memory will steal a bit, making the value a bit lower than actual
    $HostValueMemoryCeiling = [math]::ceiling($HostValueMemory)
    Write-Host ""
    Write-Host "Checking Minimum Memory"
    if ($DebugLogging) {write-host "Rounding up to nearest whole number GB: $HostValueMemoryCeiling | Actual: $HostValueMemory"}

    if ($HostValueMemoryCeiling -lt $CRMinMemory) {
        $Compliant = $false
        Write-Host "✗ Compliance Failed: Minimum Memory | Required: $CRMinMemory GB | Current: $HostValueMemory GB" -ForegroundColor Red
    }
    else {
        Write-Host "✓ Compliant: Minimum Memory | $HostValueMemoryCeiling GB" -ForegroundColor Green
    }
} 
if ($CRTPM2 -eq "true"){
    #If Set to true, ensure TPM 2.0 is present
    Write-Host ""
    Write-Host "Checking for TPM 2.0"
    if ($CRTPM2 -eq "true" -and $HostValueTPM2 -ne $true) {
        $Compliant = $false
        Write-Host "✗ Compliance Failed: TPM 2.0" -ForegroundColor Red
    }
    else {
        Write-Host "✓ Compliant: TPM 2.0" -ForegroundColor Green
    }
}
if ($CRMinWin11 -eq "true"){
    #If Set to true, ensure Windows 11 is present
    Write-Host ""
    Write-Host "Checking for Windows 11 Compatibility"
    if ($Win11Readiness.SecureBoot){
            if (($Win11Readiness.SecureBoot) -eq 'PASS') {
                Write-Host "✓ SecureBoot: Pass" -ForegroundColor Green
            }
            else {
                Write-Host "✗ SecureBoot: Fail" -ForegroundColor Red
            }
        }
        if ($Win11Readiness.TPM){
            if (($Win11Readiness.TPM) -eq 'PASS') {
                Write-Host "✓ TPM: Pass" -ForegroundColor Green
            }
            else {
                Write-Host "✗ TPM: Fail" -ForegroundColor Red
            }
        }
        if ($Win11Readiness.CPU){
            if (($Win11Readiness.CPU) -eq 'PASS') {
                Write-Host "✓ CPU: Pass" -ForegroundColor Green
            }
            else {
                Write-Host "✗ CPU: Fail" -ForegroundColor Red
            }
        }
        if ($Win11Readiness.Memory){
            if (($Win11Readiness.Memory) -eq 'PASS') {
                Write-Host "✓ Memory: Pass" -ForegroundColor Green
            }
            else {
                Write-Host "✗ Memory: Fail" -ForegroundColor Red
            }
        }
        if ($Win11Readiness.Storage){
            if (($Win11Readiness.Storage) -eq 'PASS') {
                Write-Host "✓ Storage: Pass" -ForegroundColor Green
            }
            else {
                Write-Host "✗ Storage: Fail" -ForegroundColor Red
            }
        }
    if ($CRMinWin11 -eq "true" -and $($Win11Readiness.Return) -ne 'CAPABLE') {
        $Compliant = $false
        Write-Host "✗ Compliance Failed: Windows 11" -ForegroundColor Red
        if ($Win11Readiness.Reason){
            Write-Host "Reason: $($Win11Readiness.Reason)" -ForegroundColor Yellow
        }
        
    }
    else {
        Write-Host "✓ Compliant: Windows 11" -ForegroundColor Green
    }
}
if ($Compliant -eq $true) {
    Write-Host "All Requirements Met, Continuing Task Sequence" -ForegroundColor Green
    ${TSEnv:ReadinessCheck} = "Passed"
    exit 0
}
else {
    Write-Host "One or More Requirements Not Met, Failing Task Sequence" -ForegroundColor Red
    ${TSEnv:ReadinessCheck} = "Failed"
    exit 1
}