<#
.SYNOPSIS
    Sets up a Hyper-V lab environment with DeployR server and Client VMs.

.DESCRIPTION
    This script performs the following:
    1. Confirms Hyper-V is enabled
    2. Creates an External Network switch called "External" using the host's NIC
    3. Creates folder C:\HyperVLab
    4. Creates DeployR VM (4GB RAM, 120GB C:, 140GB D:, 4 vCPUs)
    5. Creates Client VM (4GB RAM, 120GB C:, 4 vCPUs)
    Both VMs use External network and boot from Network first.

.NOTES
    Author: Gary Blok
    Date: November 2, 2025
    Requires: Administrator privileges, Hyper-V feature installed
#>

#Requires -RunAsAdministrator

########## Set Vars ##############

$VMFolderDrive = "C"
$VMFolderPath = "$VMFolderDrive:\HyperVLab"

[CmdletBinding()]
param()

##################################
#region functions
##################################
# Function to enable Hyper-V
function Enable-HyperV {
    Write-Host "`n=== Enabling Hyper-V ===" -ForegroundColor Cyan
    
    # Detect OS type (Server or Client)
    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    $isServer = $os.ProductType -ne 1  # 1 = Workstation, 2 = Domain Controller, 3 = Server
    
    try {
        # Determine which Hyper-V feature to enable based on OS
        if ($isServer) {
            Write-Host "  Detected Server OS - Enabling Hyper-V..." -ForegroundColor Yellow
            $featureName = "Microsoft-Hyper-V"
            $mgmtFeatures = @("Microsoft-Hyper-V-Management-PowerShell", "Microsoft-Hyper-V-Management-Clients", "RSAT-Hyper-V-Tools-Feature")
        }
        else {
            Write-Host "  Detected Client OS - Enabling Hyper-V..." -ForegroundColor Yellow
            $featureName = "Microsoft-Hyper-V-All"
            $mgmtFeatures = @()
        }
        
        # Enable Hyper-V using Get-WindowsOptionalFeature (works on both Server and Client)
        $result = Enable-WindowsOptionalFeature -Online -FeatureName $featureName -All -NoRestart -ErrorAction Stop
        
        # Enable management tools if on Server
        if ($isServer -and $mgmtFeatures.Count -gt 0) {
            foreach ($mgmtFeature in $mgmtFeatures) {
                $mgmtCheck = Get-WindowsOptionalFeature -Online -FeatureName $mgmtFeature -ErrorAction SilentlyContinue
                if ($mgmtCheck -and $mgmtCheck.State -ne 'Enabled') {
                    Write-Host "  Enabling $mgmtFeature..." -ForegroundColor Gray
                    Enable-WindowsOptionalFeature -Online -FeatureName $mgmtFeature -All -NoRestart -ErrorAction SilentlyContinue | Out-Null
                }
            }
        }
        
        if ($result.RestartNeeded) {
            Write-Host "✓ Hyper-V feature enabled successfully" -ForegroundColor Green
            Write-Host "⚠ A restart is required to complete the installation" -ForegroundColor Yellow
            Write-Host "  Please restart the computer and run this script again." -ForegroundColor Yellow
            exit 3010
        }
        else {
            Write-Host "✓ Hyper-V feature enabled successfully" -ForegroundColor Green
            return $true
        }
    }
    catch {
        Write-Host "✗ Failed to enable Hyper-V: $_" -ForegroundColor Red
        throw
    }
}

# Function to check if Hyper-V is enabled
function Test-HyperVEnabled {
    Write-Host "`n=== Checking Hyper-V Status ===" -ForegroundColor Cyan
    
    # Detect OS type
    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    $isServer = $os.ProductType -ne 1
    
    # Determine which Hyper-V feature to check based on OS
    if ($isServer) {
        $featureName = "Microsoft-Hyper-V"
    }
    else {
        $featureName = "Microsoft-Hyper-V-All"
    }
    
    # Check using Get-WindowsOptionalFeature (works on both Server and Client)
    try {
        $hyperv = Get-WindowsOptionalFeature -Online -FeatureName $featureName -ErrorAction SilentlyContinue
        if ($hyperv -and $hyperv.State -eq 'Enabled') {
            # Hyper-V feature is enabled, but verify cmdlets are available (not pending reboot)
            $vmmsService = Get-Service -Name vmms -ErrorAction SilentlyContinue
            if (-not $vmmsService) {
                Write-Host "⚠ Hyper-V is enabled but requires a reboot to complete installation" -ForegroundColor Yellow
                Write-Host "  Please restart the computer and run this script again." -ForegroundColor Yellow
                exit 3010
            }
            
            # Double-check that Hyper-V cmdlets are available
            $hypervModule = Get-Module -Name Hyper-V -ListAvailable -ErrorAction SilentlyContinue
            if (-not $hypervModule) {
                Write-Host "⚠ Hyper-V is enabled but requires a reboot to complete installation" -ForegroundColor Yellow
                Write-Host "  Please restart the computer and run this script again." -ForegroundColor Yellow
                exit 3010
            }
            
            Write-Host "✓ Hyper-V is enabled" -ForegroundColor Green
            return $true
        }
    }
    catch {
        # Fallback: Check if Hyper-V service exists
        $hypervService = Get-Service -Name vmms -ErrorAction SilentlyContinue
        if ($hypervService) {
            Write-Host "✓ Hyper-V is enabled" -ForegroundColor Green
            return $true
        }
    }
    
    Write-Host "✗ Hyper-V is NOT enabled" -ForegroundColor Red
    return $false
}

# Function to create External virtual switch
function New-ExternalVirtualSwitch {
    param(
        [string]$SwitchName = "External"
    )
    
    Write-Host "`n=== Creating External Virtual Switch ===" -ForegroundColor Cyan
    
    # Check if switch already exists
    $existingSwitch = Get-VMSwitch -Name $SwitchName -ErrorAction SilentlyContinue
    if ($existingSwitch) {
        Write-Host "✓ Virtual switch '$SwitchName' already exists" -ForegroundColor Green
        return $existingSwitch
    }
    
    # Get available network adapters (exclude virtual adapters)
    $netAdapters = Get-NetAdapter | Where-Object { 
        $_.Status -eq 'Up' -and 
        $_.Virtual -eq $false -and
        $_.Name -notlike "*Bluetooth*" -and
        $_.Name -notlike "*Virtual*"
    } | Sort-Object -Property ifIndex
    
    if ($netAdapters.Count -eq 0) {
        Write-Host "✗ No suitable network adapters found" -ForegroundColor Red
        throw "No active physical network adapters available for External switch"
    }
    
    # Use the first available adapter
    $selectedAdapter = $netAdapters[0]
    Write-Host "  Using network adapter: $($selectedAdapter.Name) ($($selectedAdapter.InterfaceDescription))" -ForegroundColor Yellow
    
    try {
        $switch = New-VMSwitch -Name $SwitchName -NetAdapterName $selectedAdapter.Name -AllowManagementOS $true -ErrorAction Stop
        Write-Host "✓ Created External virtual switch '$SwitchName'" -ForegroundColor Green
        return $switch
    }
    catch {
        Write-Host "✗ Failed to create virtual switch: $_" -ForegroundColor Red
        throw
    }
}

# Function to create VM folder
function New-VMFolder {
    param(
        [string]$Path = "C:\HyperVLab"
    )
    
    Write-Host "`n=== Creating VM Folder ===" -ForegroundColor Cyan
    
    if (Test-Path $Path) {
        Write-Host "✓ Folder already exists: $Path" -ForegroundColor Green
    }
    else {
        try {
            New-Item -Path $Path -ItemType Directory -Force -ErrorAction Stop | Out-Null
            Write-Host "✓ Created folder: $Path" -ForegroundColor Green
        }
        catch {
            Write-Host "✗ Failed to create folder: $_" -ForegroundColor Red
            throw
        }
    }
    
    return $Path
}

# Function to create a VM
function New-LabVM {
    param(
        [string]$VMName,
        [string]$VMPath,
        [int64]$MemoryStartupBytes,
        [int]$ProcessorCount,
        [string]$SwitchName,
        [hashtable[]]$VirtualHardDisks  # Array of @{Path='...'; SizeBytes=...}
    )
    
    Write-Host "`n=== Creating VM: $VMName ===" -ForegroundColor Cyan
    
    # Check if VM already exists
    $existingVM = Get-VM -Name $VMName -ErrorAction SilentlyContinue
    if ($existingVM) {
        Write-Host "✓ VM '$VMName' already exists - skipping creation" -ForegroundColor Yellow
        Write-Host "  RAM: $([math]::Round($existingVM.MemoryStartup/1GB))GB" -ForegroundColor Gray
        Write-Host "  Processors: $($existingVM.ProcessorCount)" -ForegroundColor Gray
        Write-Host "  State: $($existingVM.State)" -ForegroundColor Gray
        return $existingVM
    }
    
    # Create VM path
    $vmFolder = Join-Path -Path $VMPath -ChildPath $VMName
    if (-not (Test-Path $vmFolder)) {
        New-Item -Path $vmFolder -ItemType Directory -Force | Out-Null
    }
    
    try {
        # Create the VM
        Write-Host "  Creating VM..." -ForegroundColor Gray
        $vm = New-VM -Name $VMName `
            -Path $VMPath `
            -MemoryStartupBytes $MemoryStartupBytes `
            -Generation 2 `
            -SwitchName $SwitchName `
            -ErrorAction Stop
        
        # Set processor count
        Set-VMProcessor -VMName $VMName -Count $ProcessorCount
        
        # Enable dynamic memory (optional - can be disabled if you prefer static)
        Set-VMMemory -VMName $VMName -DynamicMemoryEnabled $false
        
        # Create and attach virtual hard disks
        foreach ($vhd in $VirtualHardDisks) {
            $vhdPath = $vhd.Path
            $vhdSize = $vhd.SizeBytes
            $driveLetter = if ($vhdPath -match '([A-Z])\.vhdx') { $matches[1] } else { "Disk" }
            
            Write-Host "  Creating virtual hard disk ($driveLetter): $([math]::Round($vhdSize/1GB))GB" -ForegroundColor Gray
            
            # Check if VHD already exists (safety check)
            if (Test-Path $vhdPath) {
                Write-Host "  ⚠ VHD already exists: $vhdPath - skipping creation" -ForegroundColor Yellow
            }
            else {
                # Create VHD
                New-VHD -Path $vhdPath -SizeBytes $vhdSize -Dynamic -ErrorAction Stop | Out-Null
            }
            
            # Attach VHD to VM (only if not already attached)
            $existingDisk = Get-VMHardDiskDrive -VMName $VMName | Where-Object { $_.Path -eq $vhdPath }
            if (-not $existingDisk) {
                Add-VMHardDiskDrive -VMName $VMName -Path $vhdPath -ErrorAction Stop
            }
        }
        
        # Get all SCSI controllers and hard drives
        $hardDrives = Get-VMHardDiskDrive -VMName $VMName
        
        # Set boot order: Network adapter first, then hard drives
        $networkAdapter = Get-VMNetworkAdapter -VMName $VMName
        $bootOrder = @()
        $bootOrder += $networkAdapter
        $bootOrder += $hardDrives
        
        Set-VMFirmware -VMName $VMName -BootOrder $bootOrder -ErrorAction Stop
        
        # Disable secure boot
        Set-VMFirmware -VMName $VMName -EnableSecureBoot Off -ErrorAction Stop
        
        # Set display resolution to 1280x720
        try {
            Set-VMVideo -VMName $VMName -HorizontalResolution 1280 -VerticalResolution 720 -ResolutionType Single -ErrorAction Stop
        }
        catch {
            Write-Host "  ⚠ Could not set video resolution (VM may need to be stopped): $_" -ForegroundColor Yellow
        }
        
        Write-Host "✓ VM '$VMName' created successfully" -ForegroundColor Green
        Write-Host "  RAM: $([math]::Round($MemoryStartupBytes/1GB))GB" -ForegroundColor Gray
        Write-Host "  Processors: $ProcessorCount" -ForegroundColor Gray
        Write-Host "  Network: $SwitchName" -ForegroundColor Gray
        Write-Host "  Boot Order: Network, Hard Drives" -ForegroundColor Gray
        
        return $vm
    }
    catch {
        Write-Host "✗ Failed to create VM '$VMName': $_" -ForegroundColor Red
        throw
    }
}
##################################
#endregion functions
##################################
# Main Script Execution
try {
    Write-Host "`n================================================" -ForegroundColor Cyan
    Write-Host "  Hyper-V Lab Setup Script" -ForegroundColor Cyan
    Write-Host "================================================" -ForegroundColor Cyan
    
    # Step 1: Confirm Hyper-V is enabled
    if (-not (Test-HyperVEnabled)) {
        Write-Host "`nAttempting to enable Hyper-V..." -ForegroundColor Yellow
        $enableResult = Enable-HyperV
        
        if (-not $enableResult) {
            throw "Hyper-V installation requires a restart. Please restart the computer and run this script again."
        }
        
        # Verify Hyper-V is now enabled
        if (-not (Test-HyperVEnabled)) {
            throw "Failed to enable Hyper-V. Please check system requirements and try again."
        }
    }
    
    # Step 2: Create External virtual switch
    $switchName = "External"
    $vmSwitch = New-ExternalVirtualSwitch -SwitchName $switchName
    
    # Step 3: Create VM folder
    $vmPath = New-VMFolder -Path $VMFolderPath
    
    # Step 4: Create DeployR VM
    $deployRVhdFolder = Join-Path -Path $vmPath -ChildPath "DeployR\Virtual Hard Disks"
    if (-not (Test-Path $deployRVhdFolder)) {
        Write-Host "  Creating DeployR VHD folder..." -ForegroundColor Gray
        New-Item -Path $deployRVhdFolder -ItemType Directory -Force -ErrorAction Stop | Out-Null
    }
    
    $deployRDisks = @(
        @{
            Path = Join-Path -Path $deployRVhdFolder -ChildPath "C.vhdx"
            SizeBytes = 120GB
        },
        @{
            Path = Join-Path -Path $deployRVhdFolder -ChildPath "D.vhdx"
            SizeBytes = 140GB
        }
    )
    
    $deployRVM = New-LabVM -VMName "DeployR" `
        -VMPath $vmPath `
        -MemoryStartupBytes 4GB `
        -ProcessorCount 4 `
        -SwitchName $switchName `
        -VirtualHardDisks $deployRDisks
    
    # Check for ISO in C:\HyperVLab and attach to DeployR VM
    Write-Host "  Checking for ISO files in $($VMFolderDrive):\HyperVLab..." -ForegroundColor Gray
    $isoFiles = Get-ChildItem -Path "$($VMFolderDrive):\HyperVLab" -Filter "*.iso" -ErrorAction SilentlyContinue
    if ($isoFiles) {
        $isoFile = $isoFiles | Select-Object -First 1
        Write-Host "  Found ISO: $($isoFile.Name)" -ForegroundColor Yellow
        Write-Host "  Attaching ISO to DeployR VM..." -ForegroundColor Gray
        try {
            Add-VMDvdDrive -VMName "DeployR" -Path $isoFile.FullName
            Write-Host "✓ ISO attached successfully to DeployR VM" -ForegroundColor Green
        }
        catch {
            Write-Host "⚠ Failed to attach ISO: $_" -ForegroundColor Yellow
        }
    }
    else {
        Write-Host "  No ISO files found in $($VMFolderDrive):\HyperVLab" -ForegroundColor Gray
    }
    
    # Step 5: Create Client VM
    $clientVhdFolder = Join-Path -Path $vmPath -ChildPath "Client\Virtual Hard Disks"
    if (-not (Test-Path $clientVhdFolder)) {
        Write-Host "  Creating Client VHD folder..." -ForegroundColor Gray
        New-Item -Path $clientVhdFolder -ItemType Directory -Force -ErrorAction Stop | Out-Null
    }
    
    $clientDisks = @(
        @{
            Path = Join-Path -Path $clientVhdFolder -ChildPath "C.vhdx"
            SizeBytes = 120GB
        }
    )
    
    $clientVM = New-LabVM -VMName "Client" `
        -VMPath $vmPath `
        -MemoryStartupBytes 4GB `
        -ProcessorCount 4 `
        -SwitchName $switchName `
        -VirtualHardDisks $clientDisks
    
    # Summary
    Write-Host "`n================================================" -ForegroundColor Cyan
    Write-Host "  Setup Complete!" -ForegroundColor Green
    Write-Host "================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Virtual Switch:" -ForegroundColor Cyan
    Write-Host "  Name: $switchName (External)" -ForegroundColor Gray
    Write-Host ""
    Write-Host "VMs Created:" -ForegroundColor Cyan
    Write-Host "  1. DeployR" -ForegroundColor Gray
    Write-Host "     - 4GB RAM, 4 vCPUs" -ForegroundColor Gray
    Write-Host "     - 120GB C: drive, 140GB D: drive" -ForegroundColor Gray
    Write-Host "     - Network boot enabled" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  2. Client" -ForegroundColor Gray
    Write-Host "     - 4GB RAM, 4 vCPUs" -ForegroundColor Gray
    Write-Host "     - 120GB C: drive" -ForegroundColor Gray
    Write-Host "     - Network boot enabled" -ForegroundColor Gray
    Write-Host ""
    Write-Host "VM Path: $vmPath" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Next Steps:" -ForegroundColor Yellow
    Write-Host "  1. Attach ISO images to the VMs" -ForegroundColor Gray
    Write-Host "  2. Start the VMs: Start-VM -Name DeployR, Client" -ForegroundColor Gray
    Write-Host "  3. Connect to VMs: vmconnect localhost DeployR" -ForegroundColor Gray
    Write-Host ""
}
catch {
    Write-Host "`n✗ Script failed: $_" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Red
    exit 1
}
