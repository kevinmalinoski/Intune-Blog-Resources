<#
.SYNOPSIS
    Intune Win32 app detection rule for McAfee consumer products.

.DESCRIPTION
    Detection semantics: this rule detects McAfee ITSELF, not the removal tool.
    The app is assigned as an Uninstall, so Intune runs mcafeeremoval.ps1 and
    then re-evaluates this script. "Not detected" is what marks the uninstall
    successful.

        Any one of the tracked keys present -> McAfee is installed -> DETECTED
        All of the tracked keys absent      -> McAfee is gone      -> NOT DETECTED

    Both registry views are checked explicitly. The Intune Management Extension
    is a 32-bit process, so a detection script can be launched in the 32-bit
    PowerShell host, where "HKLM:\SOFTWARE\McAfee" is silently redirected to
    "HKLM:\SOFTWARE\Wow6432Node\McAfee". Reading through OpenBaseKey with an
    explicit RegistryView removes that ambiguity regardless of host bitness.

.OUTPUTS
    Detected     : writes one line to STDOUT and exits 0.
    Not detected : writes nothing to STDOUT and exits 1.

.NOTES
    Intune Win32 app configuration
    ------------------------------
      Detection rule    : Use a custom detection script
      Script file       : McAfeeDetectionScript.ps1
      Run as 32-bit     : No (either setting works, but 64-bit is preferred)
      Enforce signature : No
#>

#Requires -Version 5.1

[CmdletBinding()]
param()

# HKLM paths, relative to the hive root. Each is checked in every registry view.
# HKLM:\SOFTWARE\McAfee\WebAdvisor is a child of HKLM:\SOFTWARE\McAfee and so is
# redundant for the OR test, but it is listed deliberately: it is the key MCPR
# is worst at clearing, and naming it here keeps the log output honest about
# which product left residue behind.
$KeyPaths = @(
    'SOFTWARE\McAfee'
    'SOFTWARE\McAfee\WebAdvisor'
    'SOFTWARE\McAfee Safe Connect'
)

$Views = if ([Environment]::Is64BitOperatingSystem) {
    @([Microsoft.Win32.RegistryView]::Registry64, [Microsoft.Win32.RegistryView]::Registry32)
}
else {
    @([Microsoft.Win32.RegistryView]::Default)
}

function Test-HklmKey {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][Microsoft.Win32.RegistryView]$View
    )

    $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, $View)
    try {
        $key = $base.OpenSubKey($Path)
        if ($key) { $key.Dispose(); return $true }
        return $false
    }
    catch {
        # An unreadable key is still a key. Treat access errors as "present" so
        # a locked-down remnant cannot be mistaken for a clean device.
        return $true
    }
    finally {
        $base.Dispose()
    }
}

$found = [System.Collections.Generic.List[string]]::new()

foreach ($path in $KeyPaths) {
    foreach ($view in $Views) {
        if (Test-HklmKey -Path $path -View $view) {
            $found.Add("[$view] HKLM\$path")
        }
    }
}

if ($found.Count -gt 0) {
    # STDOUT + exit 0 is what Intune reads as "detected".
    Write-Output "McAfee detected: $($found -join '; ')"
    exit 0
}

# No STDOUT output. Intune reads this as "not detected", which is the success
# condition for the uninstall.
exit 1
