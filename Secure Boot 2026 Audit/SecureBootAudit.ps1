<#
.SYNOPSIS
  Check Secure Boot state and whether 'Windows UEFI CA 2023' is present in dbdefault and db.

.DESCRIPTION
  - Verifies Secure Boot is enabled (uses Confirm-SecureBootUEFI if available).
  - Reads UEFI variables safely and searches for the certificate identifier.
  - Outputs one of: SECUREBOOT_DISABLED, MISSING, ACTIVE, INACTIVE (and returns exit codes).

#>

[CmdletBinding()]
param(
    [string] $ExpectedIdentifier = 'Windows UEFI CA 2023',
    [switch] $ReturnExitCode = $true  # default true for Intune friendliness
)

function Get-UEFIVariableBytes {
    param([string] $VarName)
    try {
        $entry = Get-SecureBootUEFI -Name $VarName -ErrorAction Stop
        if (-not $entry -or -not $entry.Bytes) { return $null }
        return $entry.Bytes
    } catch { return $null }
}

function Bytes-ContainsText {
    param([byte[]] $Bytes, [string] $Text)
    $encodings = @(
        [System.Text.Encoding]::UTF8,
        [System.Text.Encoding]::Unicode,            # UTF-16 LE
        [System.Text.Encoding]::BigEndianUnicode,   # UTF-16 BE
        [System.Text.Encoding]::ASCII
    )
    foreach ($enc in $encodings) {
        try {
            $decoded = $enc.GetString($Bytes)
            if ($decoded -and ($decoded -match [regex]::Escape($Text))) { return $true }
        } catch {}
    }
    return $false
}

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

# UEFI db checks
$dbDefaultBytes = Get-UEFIVariableBytes 'dbdefault'
$dbBytes        = Get-UEFIVariableBytes 'db'

$dbDefaultHasExpected = $dbDefaultBytes -and (Bytes-ContainsText $dbDefaultBytes $ExpectedIdentifier)
$dbHasExpected        = $dbBytes -and (Bytes-ContainsText $dbBytes $ExpectedIdentifier)

# Cert status
if (-not $dbDefaultHasExpected) {
    $certStatus = 'CERTS MISSING'
} elseif (-not $dbHasExpected) {
    $certStatus = 'CERTS INACTIVE'
} else {
    $certStatus = 'CERTS ACTIVE'
}

# Secure Boot wording
$sbStatus = if ($SecureBootStateKnown) {
    if ($SecureBootEnabled) { 'Secure Boot Enabled' } else { 'Secure Boot Disabled' }
} else {
    'Secure Boot Unknown'
}

# Compose single-line output
$line = "$certStatus + $sbStatus"

# Log: success only when Secure Boot Enabled AND Certs Active; else report issue
$success = ($certStatus -eq 'CERTS ACTIVE' -and $SecureBootEnabled -eq $true)

if ($success) {
    Write-Output $line
} else {
    Write-Error $line
}

# Exit code for Intune (0 = success/compliant; 1 = non-compliant)
if ($ReturnExitCode) {
    $global:LASTEXITCODE = if ($success) { 0 } else { 1 }
}

# If running as a detection script, also return the line so pipelines can parse it if needed
$line
