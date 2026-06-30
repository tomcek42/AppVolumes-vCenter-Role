<#
.SYNOPSIS
    Stores the vCenter credentials encrypted for New-AppVolumesRole.ps1.

.DESCRIPTION
    Prompts for username and password interactively and stores them encrypted via
    Export-Clixml. Encryption uses the Windows Data Protection API (DPAPI): the
    file can only be decrypted by the SAME Windows user on the SAME machine that
    created it.

    For automated/scheduled execution, run this script under exactly the account
    and host that will later run New-AppVolumesRole.ps1.

.PARAMETER ConfigPath
    Path to config.json. Default: config.json in the script directory.
    Username and target path (CredentialPath) are read from it.

.PARAMETER CredentialPath
    Optional direct target path for the credential file. Overrides the value from
    config.json.

.EXAMPLE
    .\Save-AppVolumesCredential.ps1
    .\Save-AppVolumesCredential.ps1 -CredentialPath "D:\Secure\vcenter.xml"
#>

[CmdletBinding()]
param(
    [string]$ConfigPath = (Join-Path -Path $PSScriptRoot -ChildPath 'config.json'),
    [string]$CredentialPath
)

$ErrorActionPreference = 'Stop'

# Read defaults from config.json if present
$defaultUser = $null
if (Test-Path -LiteralPath $ConfigPath) {
    try {
        $config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
        $defaultUser = $config.vCenter.Username
        if (-not $CredentialPath -and -not [string]::IsNullOrWhiteSpace($config.vCenter.CredentialPath)) {
            $CredentialPath = $config.vCenter.CredentialPath
        }
    }
    catch {
        Write-Host "Note: could not read config.json ($($_.Exception.Message))." -ForegroundColor DarkYellow
    }
}

if ([string]::IsNullOrWhiteSpace($CredentialPath)) {
    $CredentialPath = Join-Path -Path $PSScriptRoot -ChildPath 'vcenter-credential.xml'
}

# Resolve relative paths against the script directory
if (-not [System.IO.Path]::IsPathRooted($CredentialPath)) {
    $CredentialPath = Join-Path -Path $PSScriptRoot -ChildPath $CredentialPath
}

# Prompt for credentials (username prefilled from config.json when available)
if (-not [string]::IsNullOrWhiteSpace($defaultUser)) {
    $credential = Get-Credential -UserName $defaultUser -Message 'vCenter credentials for App Volumes'
}
else {
    $credential = Get-Credential -Message 'vCenter credentials for App Volumes'
}

# Store encrypted (DPAPI, bound to user + machine)
$credential | Export-Clixml -LiteralPath $CredentialPath -Force

Write-Host ""
Write-Host "Credentials stored encrypted:" -ForegroundColor Green
Write-Host "  $CredentialPath" -ForegroundColor Green
Write-Host "User: $($credential.UserName)" -ForegroundColor Gray
Write-Host ""
Write-Host "Note: the file is bound to this Windows user and machine." -ForegroundColor Yellow
Write-Host "Run New-AppVolumesRole.ps1 under the same account on the same host." -ForegroundColor Yellow
