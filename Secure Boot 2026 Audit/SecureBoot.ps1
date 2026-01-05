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
    [string] $ExpectedIdentifier = 'Windows UEFI CA 2023'
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
        [System.Text.Encoding]::Unicode,
        [System.Text.Encoding]::BigEndianUnicode,
        [System.Text.Encoding]::ASCII
    )
    foreach ($enc in $encodings) {
        try {
            if ($enc.GetString($Bytes) -match [regex]::Escape($Text)) { return $true }
        } catch {}
    }
    return $false
}

# Secure Boot state
$SecureBootEnabled = $false
if (Get-Command Confirm-SecureBootUEFI -ErrorAction SilentlyContinue) {
    try { $SecureBootEnabled = Confirm-SecureBootUEFI } catch {}
}

# Check dbdefault and db
$dbDefaultBytes = Get-UEFIVariableBytes 'dbdefault'
$dbBytes       = Get-UEFIVariableBytes 'db'

$dbDefaultHasExpected = $dbDefaultBytes -and (Bytes-ContainsText $dbDefaultBytes $ExpectedIdentifier)
$dbHasExpected        = $dbBytes -and (Bytes-ContainsText $dbBytes $ExpectedIdentifier)

# Determine cert status
if (-not $dbDefaultHasExpected) {
    $certStatus = 'CERTS MISSING'
} elseif (-not $dbHasExpected) {
    $certStatus = 'CERTS INACTIVE'
} else {
    $certStatus = 'CERTS ACTIVE'
}

# Secure Boot wording
$sbStatus = if ($SecureBootEnabled) { 'Secure Boot Enabled' } else { 'Secure Boot Disabled' }

# Output: Cert Status + Secure Boot Status
Write-Output "$certStatus + $sbStatus"