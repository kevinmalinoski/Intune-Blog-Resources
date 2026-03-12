<#
.SYNOPSIS
  Check Secure Boot state and whether 'Windows UEFI CA 2023' is present in dbdefault and db.

.DESCRIPTION
  - Verifies Secure Boot is enabled (uses Confirm-SecureBootUEFI if available).
  - Reads UEFI variables safely and searches for the certificate identifier.
  - Outputs one of: MISSING, ACTIVE, INACTIVE (and returns exit codes).

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\securebootcertcheck_new.ps1
#>

[CmdletBinding()]
param()

function Write-Log {
    param(
        [string] $Message,
        [switch] $Problem
    )
    if ($Problem) { Write-Error $Message } else { Write-Output $Message }
}

function Is-RunningElevated {
    try {
        $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        return $false
    }
}

function Get-UEFIVariableText {
    param(
        [Parameter(Mandatory=$true)][string] $VarName
    )
    try {
        $entry = Get-SecureBootUEFI $VarName -ErrorAction Stop
        if (-not $entry -or -not $entry.bytes) { return $null }
        # Prefer UTF8, fallback to ASCII
        try { return [System.Text.Encoding]::UTF8.GetString($entry.bytes) } catch { return [System.Text.Encoding]::ASCII.GetString($entry.bytes) }
    } catch {
        return $null
    }
}

# Warn if not elevated (Get-SecureBootUEFI usually requires elevation)
if (-not (Is-RunningElevated)) {
    Write-Warning "Script is not running elevated. Get-SecureBootUEFI may fail or return incomplete results."
}

# Determine Secure Boot status
# Secure Boot state
$SecureBootEnabled = $false
$SecureBootStateKnown = $false
if (Get-Command Confirm-SecureBootUEFI -ErrorAction SilentlyContinue) {
    try {
        $SecureBootEnabled = Confirm-SecureBootUEFI
        $SecureBootStateKnown = $true
    } catch {
        $SecureBootStateKnown = $false
    }
}

# Secure Boot wording
$sbStatus = if ($SecureBootStateKnown) {
    if ($SecureBootEnabled) { 'Secure Boot Enabled' } else { 'Secure Boot Disabled' }
} else {
    'Secure Boot Unknown'
}

$dbText = Get-UEFIVariableText -VarName 'db'
$expected = 'Windows UEFI CA 2023'
$dbDefaultText = Get-UEFIVariableText -VarName 'dbdefault'

if ($dbText -and $dbText -match [regex]::Escape($expected)) {
    Write-Output "CERTS ACTIVE - $sbStatus"
    exit 0
}elseif (-not $dbDefaultText -or ($dbDefaultText -notmatch [regex]::Escape($expected))) {
    Write-Output "CERTS MISSING - $sbStatus"
    exit 1
}else {
    Write-Output "CERTS INACTIVE - $sbStatus"
    exit 1
}