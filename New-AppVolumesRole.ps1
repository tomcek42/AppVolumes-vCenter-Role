<#
.SYNOPSIS
    Creates the custom vCenter Server role for Omnissa App Volumes.

.DESCRIPTION
    Reads all connection and role parameters from a config.json and creates a
    vCenter role via PowerCLI with the privileges required by the App Volumes
    Manager service account.

    The privilege list matches the full GUI table from the Omnissa App Volumes
    Administration Guide (Create a Custom vCenter Server Role) and additionally
    includes the three privileges missing from the PowerCLI doc
    (Cryptographer.AddDisk, VirtualMachine.Config.AdvancedConfig,
    VirtualMachine.Config.QueryUnownedFiles).

    The Cryptographer.* privileges (Direct Access / Add Disk) are only added when
    Role.IncludeCryptographicOperations is set to true in config.json. They are
    only needed when VM storage uses encryption policies.

.PARAMETER ConfigPath
    Path to config.json. Default: config.json in the script directory.

.EXAMPLE
    .\New-AppVolumesRole.ps1
    .\New-AppVolumesRole.ps1 -ConfigPath "D:\Deploy\config.json"

.NOTES
    Requirement: VMware/Omnissa PowerCLI is installed.
        Install-Module -Name VMware.PowerCLI -Scope CurrentUser
#>

[CmdletBinding()]
param(
    [string]$ConfigPath = (Join-Path -Path $PSScriptRoot -ChildPath 'config.json')
)

$ErrorActionPreference = 'Stop'

# --- Privileges per Omnissa App Volumes Administration Guide -------------------
# Base set (always): full GUI table + system privileges for PowerCLI.
$BasePrivilegeIds = @(
    # System privileges (not shown in the GUI, required for PowerCLI)
    'System.Anonymous'
    'System.View'
    'System.Read'
    # Global
    'Global.CancelTask'
    # Folder
    'Folder.Create'
    'Folder.Delete'
    # Datastore
    'Datastore.Browse'
    'Datastore.DeleteFile'
    'Datastore.FileManagement'
    'Datastore.AllocateSpace'
    'Datastore.UpdateVirtualMachineFiles'
    # Host > Local operations
    'Host.Local.CreateVM'
    'Host.Local.ReconfigVM'
    'Host.Local.DeleteVM'
    # Virtual machine > Edit Inventory
    'VirtualMachine.Inventory.Create'
    'VirtualMachine.Inventory.CreateFromExisting'
    'VirtualMachine.Inventory.Register'
    'VirtualMachine.Inventory.Delete'
    'VirtualMachine.Inventory.Unregister'
    'VirtualMachine.Inventory.Move'
    # Virtual machine > Interaction
    'VirtualMachine.Interact.PowerOn'
    'VirtualMachine.Interact.PowerOff'
    'VirtualMachine.Interact.Suspend'
    # Virtual machine > Change Configuration
    'VirtualMachine.Config.AddExistingDisk'
    'VirtualMachine.Config.AddNewDisk'
    'VirtualMachine.Config.RemoveDisk'
    'VirtualMachine.Config.AddRemoveDevice'
    'VirtualMachine.Config.Settings'
    'VirtualMachine.Config.Resource'
    'VirtualMachine.Config.AdvancedConfig'        # Missing from PowerCLI doc, added from GUI
    'VirtualMachine.Config.QueryUnownedFiles'     # Missing from PowerCLI doc, added from GUI
    # Virtual machine > Provisioning
    'VirtualMachine.Provisioning.Customize'
    'VirtualMachine.Provisioning.Clone'
    'VirtualMachine.Provisioning.PromoteDisks'
    'VirtualMachine.Provisioning.CreateTemplateFromVM'
    'VirtualMachine.Provisioning.DeployTemplate'
    'VirtualMachine.Provisioning.CloneTemplate'
    'VirtualMachine.Provisioning.MarkAsTemplate'
    'VirtualMachine.Provisioning.MarkAsVM'
    'VirtualMachine.Provisioning.ReadCustSpecs'
    'VirtualMachine.Provisioning.ModifyCustSpecs'
    # Resource
    'Resource.AssignVMToPool'
    # Tasks
    'Task.Create'
    # Sessions
    'Sessions.TerminateSession'
)

# Cryptographic Operations (optional, only for encrypted storage)
$CryptographicPrivilegeIds = @(
    'Cryptographer.Access'      # Direct Access
    'Cryptographer.AddDisk'     # Add Disk (missing from PowerCLI doc, added from GUI)
)

# --- Read configuration -------------------------------------------------------
if (-not (Test-Path -LiteralPath $ConfigPath)) {
    throw "Configuration file not found: $ConfigPath"
}

try {
    $config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
}
catch {
    throw "config.json could not be parsed as JSON: $($_.Exception.Message)"
}

# Validate required fields
if ([string]::IsNullOrWhiteSpace($config.vCenter.Server)) { throw 'config.json: vCenter.Server is missing.' }
if ([string]::IsNullOrWhiteSpace($config.vCenter.Username)) { throw 'config.json: vCenter.Username is missing.' }
if ([string]::IsNullOrWhiteSpace($config.Role.Name)) { throw 'config.json: Role.Name is missing.' }

$viServer        = $config.vCenter.Server
$roleName        = $config.Role.Name
$roleDescription = $config.Role.Description
$includeCrypto   = [bool]$config.Role.IncludeCryptographicOperations
$overwrite       = [bool]$config.Role.Overwrite
$ignoreCert      = [bool]$config.vCenter.IgnoreCertificateErrors

# Resolve the path to the encrypted credential file (relative to the script)
$credentialPath = $config.vCenter.CredentialPath
if ([string]::IsNullOrWhiteSpace($credentialPath)) {
    $credentialPath = 'vcenter-credential.xml'
}
if (-not [System.IO.Path]::IsPathRooted($credentialPath)) {
    $credentialPath = Join-Path -Path $PSScriptRoot -ChildPath $credentialPath
}

# --- Load PowerCLI ------------------------------------------------------------
if (-not (Get-Module -ListAvailable -Name 'VMware.VimAutomation.Core')) {
    throw 'PowerCLI (VMware.VimAutomation.Core) is not installed. Run "Install-Module VMware.PowerCLI" first.'
}
Import-Module 'VMware.VimAutomation.Core' -ErrorAction Stop

# Certificate behavior per config.json (session scope only)
$certAction = if ($ignoreCert) { 'Ignore' } else { 'Fail' }
Set-PowerCLIConfiguration -InvalidCertificateAction $certAction -Scope Session -Confirm:$false | Out-Null

# --- Build credentials --------------------------------------------------------
# Load the encrypted credential file (DPAPI). If it does not exist yet, the data
# is prompted securely and stored for future runs.
if (Test-Path -LiteralPath $credentialPath) {
    try {
        $credential = Import-Clixml -LiteralPath $credentialPath
    }
    catch {
        throw "Credential file '$credentialPath' could not be decrypted. It is bound to the Windows user and machine that created it. Please recreate it with Save-AppVolumesCredential.ps1. Details: $($_.Exception.Message)"
    }
    if (-not ($credential -is [System.Management.Automation.PSCredential])) {
        throw "File '$credentialPath' does not contain valid credentials. Please recreate it with Save-AppVolumesCredential.ps1."
    }
    Write-Host "Loaded encrypted credentials ($($credential.UserName))." -ForegroundColor Cyan
}
else {
    Write-Host "No credential file found at '$credentialPath' - creating it via Save-AppVolumesCredential.ps1." -ForegroundColor Yellow

    $saveScript = Join-Path -Path $PSScriptRoot -ChildPath 'Save-AppVolumesCredential.ps1'
    if (-not (Test-Path -LiteralPath $saveScript)) {
        throw "Helper script not found: $saveScript"
    }

    # Call Save-AppVolumesCredential.ps1 so creation and format stay in one place.
    & $saveScript -ConfigPath $ConfigPath -CredentialPath $credentialPath

    if (-not (Test-Path -LiteralPath $credentialPath)) {
        throw "Credential file was not created: $credentialPath"
    }
    $credential = Import-Clixml -LiteralPath $credentialPath
    if (-not ($credential -is [System.Management.Automation.PSCredential])) {
        throw "File '$credentialPath' does not contain valid credentials."
    }
    Write-Host "Loaded encrypted credentials ($($credential.UserName))." -ForegroundColor Cyan
}

# --- Build privilege list -----------------------------------------------------
$privilegeIds = [System.Collections.Generic.List[string]]::new()
$BasePrivilegeIds | ForEach-Object { $privilegeIds.Add($_) }
if ($includeCrypto) {
    $CryptographicPrivilegeIds | ForEach-Object { $privilegeIds.Add($_) }
    Write-Host "Including Cryptographic Operations ($($CryptographicPrivilegeIds.Count) privileges)." -ForegroundColor Cyan
}
else {
    Write-Host "Not including Cryptographic Operations (Role.IncludeCryptographicOperations = false)." -ForegroundColor Cyan
}

# --- Connect and create the role ----------------------------------------------
$connection = $null
try {
    Write-Host "Connecting to vCenter '$viServer' ..." -ForegroundColor Cyan
    $connection = Connect-VIServer -Server $viServer -Credential $credential -ErrorAction Stop

    # Retrieve privilege objects from the server and verify completeness
    $privileges = Get-VIPrivilege -Server $connection -Id $privilegeIds -ErrorAction Stop
    $resolvedIds = $privileges | Select-Object -ExpandProperty Id
    $missing = $privilegeIds | Where-Object { $resolvedIds -notcontains $_ }
    if ($missing) {
        throw "The following privilege IDs were not found on vCenter: $($missing -join ', ')"
    }
    Write-Host "Resolved all $($privilegeIds.Count) privileges on vCenter." -ForegroundColor Green

    # Handle existing role
    $existingRole = Get-VIRole -Server $connection -Name $roleName -ErrorAction SilentlyContinue
    if ($existingRole) {
        if (-not $overwrite) {
            throw "Role '$roleName' already exists. Set Role.Overwrite to true in config.json to update it."
        }
        Write-Host "Role '$roleName' already exists - updating privileges (Overwrite = true)." -ForegroundColor Yellow
        Set-VIRole -Role $existingRole -AddPrivilege $privileges -Server $connection -ErrorAction Stop | Out-Null
        $resultRole = Get-VIRole -Server $connection -Name $roleName
    }
    else {
        Write-Host "Creating new role '$roleName' ..." -ForegroundColor Cyan
        $resultRole = New-VIRole -Name $roleName -Privilege $privileges -Server $connection -ErrorAction Stop
    }

    # Set the optional description (only if supported by the API/version)
    if (-not [string]::IsNullOrWhiteSpace($roleDescription)) {
        try {
            Set-VIRole -Role $resultRole -Description $roleDescription -Server $connection -ErrorAction Stop | Out-Null
        }
        catch {
            Write-Host "Note: could not set description ($($_.Exception.Message))." -ForegroundColor DarkYellow
        }
    }

    $finalRole = Get-VIRole -Server $connection -Name $roleName
    Write-Host ""
    Write-Host "Done. Role '$($finalRole.Name)' has $($finalRole.PrivilegeList.Count) privileges." -ForegroundColor Green
}
finally {
    if ($connection) {
        Disconnect-VIServer -Server $connection -Confirm:$false -ErrorAction SilentlyContinue
        Write-Host "Disconnected from '$viServer'." -ForegroundColor DarkGray
    }
}
