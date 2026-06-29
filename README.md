# App Volumes – Custom vCenter Role

PowerShell/PowerCLI automation that creates the custom vCenter Server role for the
**Omnissa App Volumes Manager** service account. The role uses the full privilege
set from the *App Volumes Administration Guide* GUI table (46 privilege IDs),
including three privileges missing from the PowerCLI doc.

## Quick start (one-liner)

```powershell
irm https://raw.githubusercontent.com/tomcek42/AppVolumes-vCenter-Role/main/Invoke-AppVolumesRole.ps1 | iex
```

`Invoke-AppVolumesRole.ps1` is self-contained: it prompts for any missing values
(vCenter server, role name, options) and stores `config.json` plus the
**encrypted** credential file next to the script — or, when run via `irm | iex`,
in the current working directory. Later runs reuse them.

> `| iex` cannot pass parameters. To use parameters, run the file directly
> (`.\Invoke-AppVolumesRole.ps1 -Server ...`) or via a script block:
> ```powershell
> & ([scriptblock]::Create((irm https://raw.githubusercontent.com/tomcek42/AppVolumes-vCenter-Role/main/Invoke-AppVolumesRole.ps1))) -Server vcenter.example.local -RoleName AppVolumes
> ```

## Requirements

- Windows PowerShell 5.1 or PowerShell 7+
- VMware/Omnissa PowerCLI: `Install-Module -Name VMware.PowerCLI -Scope CurrentUser`
- A vCenter account allowed to create roles (e.g. Administrator)

## Files

| File | Purpose |
|------|---------|
| `Invoke-AppVolumesRole.ps1` | Self-contained script for the `irm` one-liner (interactive). |
| `New-AppVolumesRole.ps1` | File-based variant driven by `config.json`. |
| `Save-AppVolumesCredential.ps1` | Stores the vCenter credentials encrypted. |
| `config.json` | Configuration for the file-based variant. |
| `permissions.txt` | Reference list of the GUI privileges. |

## Configuration (`config.json`)

```json
{
    "vCenter": {
        "Server": "vcenter.example.local",
        "Username": "svc-appvolumes@vsphere.local",
        "CredentialPath": "vcenter-credential.xml",
        "IgnoreCertificateErrors": false
    },
    "Role": {
        "Name": "AppVolumes",
        "Description": "Custom role for the Omnissa App Volumes Manager service account",
        "IncludeCryptographicOperations": false,
        "Overwrite": false
    }
}
```

| Key | Meaning |
|-----|---------|
| `vCenter.Server` | vCenter hostname/FQDN. |
| `vCenter.Username` | Account used to sign in. |
| `vCenter.CredentialPath` | Path to the encrypted credential file (relative paths resolve to the script directory). |
| `vCenter.IgnoreCertificateErrors` | `true` sets the session certificate action to *Ignore* (e.g. self-signed certs). |
| `Role.Name` | Name of the role to create. |
| `Role.Description` | Role description. |
| `Role.IncludeCryptographicOperations` | `true` adds the `Cryptographer.*` privileges. Only needed when VM storage uses encryption policies. |
| `Role.Overwrite` | `true` updates an existing role instead of failing. |

## Credentials

No plaintext passwords are stored. Credentials are encrypted with the Windows
Data Protection API (DPAPI) via `Export-Clixml`.

> The credential file can only be decrypted by the **same Windows user** on the
> **same machine** that created it. For scheduled/automated runs, create and run
> under the same account and host.

```powershell
# File-based variant: pre-create the credential file (optional)
.\Save-AppVolumesCredential.ps1

# Create the role
.\New-AppVolumesRole.ps1
# or with a custom config path:
.\New-AppVolumesRole.ps1 -ConfigPath "D:\Deploy\config.json"
```

## Privileges

Base set (always): **44** privileges — the full GUI table plus the system
privileges `System.Anonymous`, `System.View`, `System.Read` (not shown in the GUI
but required for PowerCLI).

Optional with `IncludeCryptographicOperations = true`: adds `Cryptographer.Access`
and `Cryptographer.AddDisk` (**+2 = 46**).

Three privileges are present in the GUI table but missing from the PowerCLI doc;
they are included here:

- `Cryptographer.AddDisk`
- `VirtualMachine.Config.AdvancedConfig`
- `VirtualMachine.Config.QueryUnownedFiles`
