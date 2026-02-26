<#
.SYNOPSIS
    Generares a new computer name based on a fixed prefix and the BIOS serial number, then renames the local machine accordingly with desired prefix. 

.DESCRIPTION
    - Uses `Get-CimInstance` to read the BIOS serial (safer than the deprecated Get-WmiObject).
    - Preserves the last 4 characters of long serials and fits the result into a configurable total length.
    - Validates/sanitizes the generated name to avoid invalid characters and common placeholder serials.

.NOTES
    - Requires administrative privileges to rename the computer.
    - NetBIOS/hostname hard upper limit is 15 characters; this script enforces that.
    - Set your prefix in line 27: $Prefix = 'DEVICE-PREFIX'

.EXAMPLE
    # Dry-run (no changes)
    .\Rename-FromSerial.ps1 -WhatIf

    # Rename locally and prompt for restart
    .\Rename-FromSerial.ps1

    # Rename domain-joined machine with supplied domain credential and force immediate restart
    .\Rename-FromSerial.ps1 -DomainCredential (Get-Credential) -ForceRestart
#>

param(
    [string]$Prefix = 'MALO-V2',
    [int]$MaxTotalLength = 15,
    [switch]$WhatIf,
    [switch]$ForceRestart,
    [pscredential]$DomainCredential,
    [switch]$AllowPlaceholderSerial  # set to allow OEM placeholder values (not recommended)
)

# --- Helpers --------------------------------------------------------------
function Get-BiosSerialSafe {
    try {
    $serial = (Get-CimInstance -ClassName Win32_BIOS -ErrorAction Stop).SerialNumber -as [string]
    } catch {
        Write-Verbose 'Failed to read BIOS serial via CIM.'
        return $null
    }

    if ([string]::IsNullOrWhiteSpace($serial)) { return $null }
    return $serial
}

function Test-PlaceholderSerial {
    param($s)
    if (-not $s) { return $true }
    $placeholders = @(
        'To be filled by O.E.M.','System Serial Number','1234567890','None','0','@#$%'
    )
    return $placeholders -contains $s -or $s -match '^[0-9]{1,4}$'
}

function New-SerialComponent {
    param(
        [string]$Serial,
        [int]$MaxSerialLen
    )
    $serial = ($Serial -replace '[^A-Za-z0-9\-]', '')
    if ($serial.Length -le $MaxSerialLen) { return $serial }

    # always preserve last 4 characters when possible
    $last4 = $serial.Substring($serial.Length - 4)
    $firstPartLen = $MaxSerialLen - 4
    if ($firstPartLen -gt 0) {
        return $serial.Substring(0, $firstPartLen) + $last4
    }
    return $last4
}

function Test-ComputerName {
    param($name, $maxTotal)
    if ($name.Length -gt $maxTotal) { throw "Generated name exceeds maximum length of $maxTotal." }
    if ($name -notmatch '^[A-Za-z0-9][A-Za-z0-9-]{0,14}$') {
        throw "Name '$name' contains invalid characters or format. Use only letters, digits and hyphen; do not begin with a hyphen."
    }
    return $true
}

function Test-NameInDns {
    param($name)
    try {
        Resolve-DnsName -Name $name -ErrorAction Stop | Out-Null
        return $true
    } catch {
        return $false
    }
}

# --- Main -----------------------------------------------------------------
# Basic validations
if ($MaxTotalLength -gt 15 -or $MaxTotalLength -lt 1) { throw 'MaxTotalLength must be between 1 and 15 (NetBIOS/hostname limit).' }

$biosSerial = Get-BiosSerialSafe
if (-not $biosSerial) {
    if (-not $AllowPlaceholderSerial) { throw 'BIOS serial not found or empty. Use -AllowPlaceholderSerial to override (not recommended).' }
    Write-Warning 'BIOS serial is empty; falling back to computer name suffix.'
    $biosSerial = $env:COMPUTERNAME
}

if (Test-PlaceholderSerial $biosSerial -and -not $AllowPlaceholderSerial) {
    throw "BIOS serial appears to be a placeholder value ('$biosSerial'); aborting. Use -AllowPlaceholderSerial to override."
}

$maxSerialLen = $MaxTotalLength - $Prefix.Length
if ($maxSerialLen -lt 1) { throw 'Prefix is too long for the configured MaxTotalLength.' }

$serialComponent = New-SerialComponent -Serial $biosSerial -MaxSerialLen $maxSerialLen
$newName = "$Prefix$serialComponent"

# Validate generated name
try {
    Test-ComputerName -name $newName -maxTotal $MaxTotalLength
} catch {
    throw "Generated computer name is invalid: $_"
}

$currentName = $env:COMPUTERNAME

Write-Output "Current name: $currentName"
Write-Output "Proposed name: $newName"

# DNS collision check (best-effort)
if (Test-NameInDns -name $newName) {
    Write-Warning "A DNS record for '$newName' already exists. This may indicate a naming collision on the network." 
}

if ($currentName -ieq $newName) {
    Write-Output "Computer name is already correct: $currentName"
    return 0
}

if ($WhatIf) {
    Write-Output "WhatIf: would rename '$currentName' -> '$newName' (no changes made)."
    return 0
}

# Prepare parameters for Rename-Computer
$renameParams = @{ NewName = $newName; Force = $true; ErrorAction = 'Stop' }
if ($DomainCredential) { $renameParams.DomainCredential = $DomainCredential }

# Perform rename
try {
    Rename-Computer @renameParams
    Write-Output "Successfully requested rename: $currentName -> $newName"
    return 0
} catch {
    Write-Error "Failed to rename computer: $_"
    return 1
}