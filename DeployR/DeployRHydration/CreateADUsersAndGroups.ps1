<#
.SYNOPSIS
    Creates Active Directory groups and users for 2PintLabs.local domain.

.DESCRIPTION
    This script creates a custom Organizational Unit (OU) structure with OU=2PintLabs
    at the root, containing sub-OUs for Workstations, Users, and Groups. It then creates
    security groups and user accounts in their respective OUs and adds users to their
    corresponding groups. This is typically run after promoting a server to a Domain Controller.

.NOTES
    Author: Gary Blok
    Date: November 5, 2025
    
    Requirements:
    - Active Directory Domain Services must be installed and configured
    - Script must be run on a Domain Controller
    - Administrative privileges required
    - ActiveDirectory PowerShell module
    
    OU Structure Created:
    - OU=2PintLabs,DC=2PintLabs,DC=local
      - OU=Workstations (for future computer objects)
      - OU=Users (user accounts placed here)
      - OU=Groups (security groups placed here)
#>


$CreateADObjects = @'

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$Domain = "2PintLabs.local",
    
    [Parameter(Mandatory=$false)]
    [string]$DefaultPassword = "P@ssw0rd"
)

start-transcript -Path "$env:TEMP\CreateADUsersAndGroups.log" -Force
# Set error action preference
$ErrorActionPreference = "Stop"

# Function to write colored output
function Write-ColorOutput {
    param(
        [string]$Message,
        [string]$Color = "White"
    )
    Write-Host $Message -ForegroundColor $Color
}

# Function to check if running on a Domain Controller
function Test-DomainController {
    try {
        $dc = Get-ADDomainController -Discover -ErrorAction SilentlyContinue
        return $true
    } catch {
        return $false
    }
}

# Main script execution
try {
    Write-ColorOutput "`n========================================" -Color Cyan
    Write-ColorOutput "AD Users and Groups Creation Script" -Color Cyan
    Write-ColorOutput "========================================`n" -Color Cyan
    
    # Import Active Directory module
    Write-ColorOutput "[Step 1/5] Importing Active Directory module..." -Color Cyan
    try {
        Import-Module ActiveDirectory -ErrorAction Stop
        Write-ColorOutput "  ✓ Module imported successfully" -Color Green
    } catch {
        Write-ColorOutput "  ✗ Failed to import ActiveDirectory module" -Color Red
        Write-ColorOutput "  Make sure this script is run on a Domain Controller" -Color Yellow
        exit 1
    }
    
    # Verify we're on a Domain Controller
    Write-ColorOutput "`n[Step 2/5] Verifying Domain Controller..." -Color Cyan
    if (-not (Test-DomainController)) {
        Write-ColorOutput "  ✗ This script must be run on a Domain Controller" -Color Red
        exit 1
    }
    Write-ColorOutput "  ✓ Running on Domain Controller" -Color Green
    
    # Get domain DN
    $domainDN = (Get-ADDomain).DistinguishedName
    Write-ColorOutput "  Domain DN: $domainDN" -Color Gray
    
    # Create OU structure
    Write-ColorOutput "`n[Step 3/5] Creating Organizational Unit Structure..." -Color Cyan
    
    # Create main 2PintLabs OU
    $mainOU = "OU=2PintLabs,$domainDN"
    try {
        $existingOU = Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$mainOU'" -ErrorAction SilentlyContinue
        if (-not $existingOU) {
            New-ADOrganizationalUnit -Name "2PintLabs" -Path $domainDN
            Write-ColorOutput "  ✓ Created OU: 2PintLabs" -Color Green
        } else {
            Write-ColorOutput "  ℹ OU already exists: 2PintLabs" -Color Yellow
        }
    } catch {
        Write-ColorOutput "  ✗ Failed to create main OU: 2PintLabs" -Color Red
        Write-ColorOutput "    Error: $($_.Exception.Message)" -Color Red
    }
    
    # Create sub-OUs
    $subOUs = @("Workstations", "Users", "Groups")
    foreach ($ouName in $subOUs) {
        $ouDN = "OU=$ouName,$mainOU"
        try {
            $existingOU = Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$ouDN'" -ErrorAction SilentlyContinue
            if (-not $existingOU) {
                New-ADOrganizationalUnit -Name $ouName -Path $mainOU
                Write-ColorOutput "  ✓ Created sub-OU: $ouName" -Color Green
            } else {
                Write-ColorOutput "  ℹ Sub-OU already exists: $ouName" -Color Yellow
            }
        } catch {
            Write-ColorOutput "  ✗ Failed to create sub-OU: $ouName" -Color Red
            Write-ColorOutput "    Error: $($_.Exception.Message)" -Color Red
        }
    }
    
    # Set OU paths for users and groups
    $usersOU = "OU=Users,$mainOU"
    $groupsOU = "OU=Groups,$mainOU"
    
    Write-ColorOutput "  OU structure created:" -Color Gray
    Write-ColorOutput "    Users will be created in: $usersOU" -Color Gray
    Write-ColorOutput "    Groups will be created in: $groupsOU" -Color Gray
    
    # Define groups to create
    Write-ColorOutput "`n[Step 4/5] Creating Security Groups..." -Color Cyan
    $groups = @(
        @{Name = "StifleR Admins"; Description = "Administrators for StifleR"},
        @{Name = "StifleR Users"; Description = "Standard users for StifleR"},
        @{Name = "StifleR Remote Tools Admins"; Description = "Administrators for StifleR Remote Tools"},
        @{Name = "StifleR Remote Tools Read Only"; Description = "Read-only users for StifleR Remote Tools"},
        @{Name = "Server Local Admins"; Description = "Local administrators for servers"},
        @{Name = "Workstation Local Admins"; Description = "Local administrators for workstations"}
    )
    
    $createdGroups = @()
    foreach ($group in $groups) {
        try {
            # Check if group already exists
            $existingGroup = Get-ADGroup -Filter "Name -eq '$($group.Name)'" -ErrorAction SilentlyContinue
            
            if ($existingGroup) {
                Write-ColorOutput "  ℹ Group already exists: $($group.Name)" -Color Yellow
                $createdGroups += $existingGroup
            } else {
                $newGroup = New-ADGroup -Name $group.Name `
                    -SamAccountName $group.Name `
                    -GroupCategory Security `
                    -GroupScope Global `
                    -Description $group.Description `
                    -Path $groupsOU `
                    -PassThru
                
                Write-ColorOutput "  ✓ Created group: $($group.Name)" -Color Green
                $createdGroups += $newGroup
            }
        } catch {
            Write-ColorOutput "  ✗ Failed to create group: $($group.Name)" -Color Red
            Write-ColorOutput "    Error: $($_.Exception.Message)" -Color Red
        }
    }
    
    # Define users to create
    Write-ColorOutput "`n[Step 5/5] Creating User Accounts..." -Color Cyan
    $users = @(
        @{FirstName = "Regular"; LastName = "User"; DisplayName = "Regular User"; SamAccountName = "RegularUser"; Groups = @("StifleR Users", "StifleR Remote Tools Read Only")},
        @{FirstName = "Unregular"; LastName = "User"; DisplayName = "Unregular User"; SamAccountName = "UnregularUser"; Groups = @("StifleR Users", "StifleR Remote Tools Read Only")},
        @{FirstName = "Irregular"; LastName = "User"; DisplayName = "Irregular User"; SamAccountName = "IrregularUser"; Groups = @("StifleR Users", "StifleR Remote Tools Read Only")},
        @{FirstName = "Nonregular"; LastName = "User"; DisplayName = "Nonregular User"; SamAccountName = "NonregularUser"; Groups = @("StifleR Users", "StifleR Remote Tools Read Only")},
        @{FirstName = "DO"; LastName = "Doris"; DisplayName = "DO Doris"; SamAccountName = "DODoris"; Groups = @("StifleR Remote Tools Admins", "StifleR Users")},
        @{FirstName = "PC"; LastName = "Pete"; DisplayName = "PC Pete"; SamAccountName = "PCPete"; Groups = @("StifleR Remote Tools Admins", "StifleR Users")},
        @{FirstName = "Server"; LastName = "Admin"; DisplayName = "Server Admin"; SamAccountName = "ServerAdmin"; Groups = @("Server Local Admins")},
        @{FirstName = "StifleR"; LastName = "Admin"; DisplayName = "StifleR Admin"; SamAccountName = "StifleRAdmin"; Groups = @("StifleR Admins")},
        @{FirstName = "StifleR"; LastName = "User"; DisplayName = "StifleR User"; SamAccountName = "StifleRUser"; Groups = @("StifleR Users")},
        @{FirstName = "StifleR"; LastName = "ToolsU"; DisplayName = "StifleR Tools User"; SamAccountName = "StifleRToolsU"; Groups = @("StifleR Remote Tools Read Only")},
        @{FirstName = "StifleR"; LastName = "ToolsA"; DisplayName = "StifleR Tools Admin"; SamAccountName = "StifleRToolsA"; Groups = @("StifleR Remote Tools Admins")},
        @{FirstName = "WS"; LastName = "Admin"; DisplayName = "Workstation Admin"; SamAccountName = "WSAdmin"; Groups = @("Workstation Local Admins")}
    )
    
    # Convert password to secure string
    $securePassword = ConvertTo-SecureString $DefaultPassword -AsPlainText -Force
    
    $createdUsers = @()
    foreach ($user in $users) {
        try {
            # Check if user already exists
            $existingUser = Get-ADUser -Filter "SamAccountName -eq '$($user.SamAccountName)'" -ErrorAction SilentlyContinue
            
            if ($existingUser) {
                Write-ColorOutput "  ℹ User already exists: $($user.DisplayName) ($($user.SamAccountName))" -Color Yellow
                $createdUsers += @{User = $existingUser; Groups = $user.Groups}
            } else {
                $newUser = New-ADUser -Name $user.DisplayName `
                    -GivenName $user.FirstName `
                    -Surname $user.LastName `
                    -DisplayName $user.DisplayName `
                    -SamAccountName $user.SamAccountName `
                    -UserPrincipalName "$($user.SamAccountName)@$Domain" `
                    -Path $usersOU `
                    -AccountPassword $securePassword `
                    -Enabled $true `
                    -ChangePasswordAtLogon $false `
                    -PasswordNeverExpires $true `
                    -PassThru
                
                Write-ColorOutput "  ✓ Created user: $($user.DisplayName) ($($user.SamAccountName))" -Color Green
                $createdUsers += @{User = $newUser; Groups = $user.Groups}
            }
        } catch {
            Write-ColorOutput "  ✗ Failed to create user: $($user.DisplayName)" -Color Red
            Write-ColorOutput "    Error: $($_.Exception.Message)" -Color Red
        }
    }
    
    # Add users to groups
    Write-ColorOutput "`n[Step 6/6] Adding Users to Groups..." -Color Cyan
    foreach ($userInfo in $createdUsers) {
        if ($userInfo.Groups.Count -eq 0) {
            continue
        }
        
        $userName = $userInfo.User.SamAccountName
        foreach ($groupName in $userInfo.Groups) {
            try {
                # Check if user is already a member
                $group = Get-ADGroup -Filter "Name -eq '$groupName'"
                $isMember = Get-ADGroupMember -Identity $group | Where-Object {$_.SamAccountName -eq $userName}
                
                if ($isMember) {
                    Write-ColorOutput "  ℹ User $userName already member of: $groupName" -Color Yellow
                } else {
                    Add-ADGroupMember -Identity $groupName -Members $userInfo.User
                    Write-ColorOutput "  ✓ Added $userName to group: $groupName" -Color Green
                }
            } catch {
                Write-ColorOutput "  ✗ Failed to add $userName to group: $groupName" -Color Red
                Write-ColorOutput "    Error: $($_.Exception.Message)" -Color Red
            }
        }
    }
    
    # Summary
    Write-ColorOutput "`n========================================" -Color Green
    Write-ColorOutput "AD Users and Groups Creation Complete!" -Color Green
    Write-ColorOutput "========================================" -Color Green
    
    Write-ColorOutput "`nOU Structure:" -Color Yellow
    Write-ColorOutput "  OU=2PintLabs,$domainDN" -Color White
    Write-ColorOutput "    ├─ OU=Workstations (for computer objects)" -Color White
    Write-ColorOutput "    ├─ OU=Users (user accounts)" -Color White
    Write-ColorOutput "    └─ OU=Groups (security groups)" -Color White
    
    Write-ColorOutput "`nSummary:" -Color Yellow
    Write-ColorOutput "  Groups Created: $($groups.Count)" -Color White
    Write-ColorOutput "  Users Created: $($users.Count)" -Color White
    Write-ColorOutput "  Default Password: $DefaultPassword" -Color White
    
    Write-ColorOutput "`nCreated Groups:" -Color Yellow
    foreach ($group in $groups) {
        Write-ColorOutput "  • $($group.Name)" -Color White
    }
    
    Write-ColorOutput "`nCreated Users:" -Color Yellow
    foreach ($user in $users) {
        $groupList = if ($user.Groups.Count -gt 0) { " → Member of: $($user.Groups -join ', ')" } else { "" }
        Write-ColorOutput "  • $($user.DisplayName) ($($user.SamAccountName))$groupList" -Color White
    }
    
    Write-ColorOutput "`nNOTE: All users have the password: $DefaultPassword" -Color Cyan
    Write-ColorOutput "      PasswordNeverExpires is set to TRUE" -Color Cyan
    Write-ColorOutput "      ChangePasswordAtLogon is set to FALSE" -Color Cyan
    
} catch {
    Write-ColorOutput "`nAn unexpected error occurred:" -Color Red
    Write-ColorOutput $_.Exception.Message -Color Red
    Write-ColorOutput "`nStack Trace:" -Color Red
    Write-ColorOutput $_.ScriptStackTrace -Color Red
    exit 1
}

stop-transcript

'@

$CreateADObjects | Out-File $env:TEMP\CreateADObjects.ps1 -Encoding UTF8 -Force
# Execute the generated form script
write-host "`nExecuting AD Users and Groups Creation Script..." -ForegroundColor Cyan
write-host "Command: pwsh.exe -NoProfile -ExecutionPolicy Bypass -File `"$env:TEMP\CreateADObjects.ps1`"" -ForegroundColor Gray
Start-Process pwsh.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$env:TEMP\CreateADObjects.ps1`"" -Wait -NoNewWindow -PassThru
if (Test-Path -path "$env:TEMP\CreateADUsersAndGroups.log"){
    write-host "Log file created at: $env:TEMP\CreateADUsersAndGroups.log" -ForegroundColor Gray
} else {
    write-host "Log file not found at: $env:TEMP\CreateADUsersAndGroups.log" -ForegroundColor Yellow
}
write-host "Completed calling script... check specific log for details"