<#
.SYNOPSIS
    Removes McAfee consumer products using McAfee's MCPR package. Built for
    deployment as an Intune Win32 app assigned as an Uninstall.

.DESCRIPTION
    Version 2.0 (2026). Iterates on the 2025 release, keeping the same core
    approach - drive McAfee's own MCPR engine from PowerShell - with clearer
    logging and several fixes that let a run finish in fewer passes.

    Order of operations:

        1. Stop and disable the McAfee services.
        2. Remove McAfee scheduled tasks.
        3. Run mccleanup.exe against the MCPR product list, up to three times.
        4. Uninstall WebAdvisor, if present.
        5. Uninstall Security Scan, if present.
        6. Remove McAfee Store (Appx) packages - provisioned, system, per-user.

    Removal completes across one or more Intune retry cycles with a reboot in
    between. MCPR cannot delete files that are open or driver-protected, so it
    stages them via PendingFileRenameOperations and Windows finishes the job on
    restart. A non-zero exit on the first attempt is normal and is what causes
    Intune to retry.

    IMPORTANT - MCPR BUILD
    ----------------------
    This must be packaged with a LEGACY build of mccleanup.exe.

    McAfee's 2024 and later builds call ValidateParentProcess on startup and
    refuse to run unless launched by McClnUI.exe, their interactive wizard.
    Launched from PowerShell they log "failed to validate parent module", exit
    immediately and remove nothing - silently, from the caller's point of view.

    The trade-off is real and worth understanding before deploying:

      Legacy engine - runs headless, but cannot process the newer WPS module.
                      It logs "Service Type ppl not supported" and rejects the
                      driver-unload steps as "Malformed INI", so McAfee Windows
                      Protection Suite is only partly removed.
      2024+ engine  - handles WPS correctly, but will not run unattended at all.

    The script logs the engine's FileVersion before running it, so a packaging
    mistake is visible in the first few lines of the log rather than after a
    fleet-wide rollout.

.PARAMETER MaxCleanupPasses
    Maximum mccleanup.exe passes per run. Default 3. The loop stops early on a
    zero exit code, so this is a ceiling rather than a fixed count.

.PARAMETER LogPath
    Log file. Defaults to the Intune Management Extension log folder so it is
    collected by Intune's "Collect diagnostics" action. Rolls at 5 MB.

.OUTPUTS
    0 - every step completed without error.
    1 - at least one step reported an error, commonly because MCPR still needs
        a reboot to finish. Intune retries on its next cycle.

.EXAMPLE
    powershell.exe -ExecutionPolicy Bypass -File .\mcafeeremoval.ps1

    The Intune uninstall command. Runs as SYSTEM with the defaults.

.EXAMPLE
    .\mcafeeremoval.ps1 -MaxCleanupPasses 1 -LogPath C:\Temp\mcafee.log

    Single pass to a local log, for manual testing.

.NOTES
    Intune Win32 app configuration
    ------------------------------
      Install command   : cmd.exe /c
      Uninstall command : powershell.exe -ExecutionPolicy Bypass -File .\mcafeeremoval.ps1
      Install behavior  : System
      Detection rule    : Registry key exists - HKEY_LOCAL_MACHINE\SOFTWARE\McAfee
      Assignment        : Uninstall

    Detection is deliberately the McAfee key itself, not the removal tool. The
    app is assigned as an Uninstall, so Intune runs this script and re-evaluates
    detection; "not detected" is what marks the uninstall successful.

    mccleanup.exe exit codes
    ------------------------
    McAfee publishes none of these. Established by lab testing:
      0 - success
      2 - reboot required to complete removal
      3 - leftover components remain

    Version 2.0
    -----------
    Changes from the 2025 release:

    Behaviour:
    * mccleanup.exe runs up to three times per invocation instead of once, with
      a five second pause between passes so terminated processes release their
      file handles. Exits the loop early on a zero exit code.
    * WMIRemover removed from the product list. McAfee references it in
      master.ini but the folder is absent from every MCPR build tested, so it
      fails on every run - and that single failure is enough to make MCPR report
      "Incomplete uninstallation" and return non-zero even when everything else
      succeeded.
    * McAfee scheduled tasks are removed before mccleanup runs. The TaskCache
      registry keys are owned by the Task Scheduler service and cannot be
      deleted directly, so MCPR's LAM module failed on them three times per run.
    * 13 real Windows service names added to $servicesToDisable, taken from
      McAfee's own StopServices\stopservices1.ini. The original list was almost
      entirely MCPR product codes, which Get-Service cannot resolve - only five
      of its 53 entries ever matched a real service. Purely additive.
    * Get-Unique replaced with Sort-Object -Unique. Get-Unique only collapses
      ADJACENT duplicates, so unsorted input left duplicates in place and the
      same package was processed more than once.

    Logging:
    * Fixed the service-loop brace placement. The catch block was empty and the
      "Service $svc not found" line sat outside it, so that message was written
      on EVERY iteration - including successful ones - and the real error text
      was discarded. Per-service results are now accurate.
    * Severity levels, a run header, per-step summaries, and a footer with
      elapsed time and exit code.
    * The log rolls at 5 MB. Repeated retries previously appended to one file
      until it was too large to open.
    * Service results are summarised - the inert product codes report on one
      line, while services that exist but fail to stop are logged individually.
    * mccleanup.exe's FileVersion and exit-code meaning are logged.
    * WebAdvisor and Security Scan uninstaller exit codes are captured rather
      than discarded.
    * Fixed "Securitu Scan" typo.

    Unchanged from 2025: the mccleanup argument string (apart from WMIRemover),
    the WebAdvisor and Security Scan paths, the Appx removal logic, and the
    exit-code contract.

    Credits
    -------
    Builds on earlier work by Tbone (tbone.se) and SMB to the Cloud
    (smbtothecloud.com).
#>

#Requires -Version 5.1

[CmdletBinding()]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidOverwritingBuiltInCmdlets', '',
    Justification = 'Targets Windows PowerShell 5.1, which has no Write-Log cmdlet. Name kept from v1 for continuity.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
    Justification = 'Write-Host is intentional. This runs as a deployment script, not a pipeline component, and the console output is wanted during manual testing.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingEmptyCatchBlock', '',
    Justification = 'The empty catch in Write-Log is deliberate. A failure to write the log file must never stop the removal.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWMICmdlet', '',
    Justification = 'Get-WmiObject retained verbatim from v1 to keep behaviour identical. Get-CimInstance is the modern equivalent if this is ever revisited.')]
param(
    # Number of times to run mccleanup.exe before accepting the result. The loop
    # exits early on a zero exit code, so this is a ceiling, not a fixed count.
    [ValidateRange(1, 5)]
    [int]$MaxCleanupPasses = 3,

    [string]$LogPath = 'C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\McAfeeRemovalLog.txt'
)

$ScriptVersion = '2.0'
$startTime     = Get-Date

#region ---------------------------------------------------------------- Logging

function Write-Log {
    param(
        [string]$Message = '',
        [string]$Level   = 'INFO'
    )

    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$Level] $Message"

    # Console, so a manual run shows progress.
    Write-Host $line

    # File. AppendAllText opens, appends and closes in one call, so the handle
    # is never held between writes. Never allowed to break the run - if the log
    # cannot be written the removal still proceeds.
    try {
        [System.IO.File]::AppendAllText($LogPath, $line + [Environment]::NewLine)
    }
    catch {
    }
}

function Get-McCleanupExitMeaning {
    param([int]$Code)

    # McAfee publishes nothing on mccleanup.exe exit codes. These were derived
    # from lab testing and are logged as a hint, not treated as authoritative.
    switch ($Code) {
        0       { 'Success.' }
        2       { 'Reboot required to complete removal.' }
        3       { 'Leftover components remain.' }
        default { 'Meaning unknown.' }
    }
}

#endregion

#region ------------------------------------------------------------- Inventory

# Services to stop and disable.
#
# SAFETY NOTE - read before editing this list:
# Get-Service -Name performs EXACT matching with no wildcards, which is the only
# reason 'MPS' below is safe: it is a prefix of MpsSvc (Windows Defender
# Firewall) and of MPSDRV. If this loop is ever changed to use -DisplayName, a
# wildcard, or -like, 'MPS' will start matching the Windows firewall service and
# disable it. Do not make that change without pruning this list first.
#
# All 53 original entries were checked against Windows and Intel service names:
# no exact collisions.

# Block 1 - carried over verbatim from v1.
#
# Most of these are MCPR *product codes* (MFSY, PEF, MXD, RESIDUE, ...) rather
# than Windows service names, so Get-Service will not resolve them and those
# iterations are inert. They are kept because they are harmless and because the
# same tokens appear in the mccleanup -p argument below. The entries that are
# real services are mccspsvc, McComponentHostService, McProxy, SafeConnectService
# and 'McAfee WebAdvisor'.
$servicesToDisable = @(
    'MFSY', 'PEF', 'MXD', 'CSP', 'Sustainability', 'MOCP', 'MFP', 'APPSTATS', 'Auth', 'EMproxy', 'FWdiver', 'HW', 'MAS'
    'MAT', 'MBK', 'MCPR', 'McProxy', 'mccspsvc', 'McSvcHost', 'VUL', 'MHN', 'MNA', 'MOBK', 'MPFP', 'MPFPCU', 'MPS', 'SHRED'
    'MPSCU', 'MQC', 'MQCCU', 'MSAD', 'MSHR', 'MSK', 'MSKCU', 'MWL', 'NMC', 'RedirSvc', 'VS', 'REMEDIATION', 'McComponentHostService'
    'WPS', 'McAfee WebAdvisor', 'MSC', 'YAP', 'TRUEKEY', 'LAM', 'PCB', 'Symlink', 'SafeConnect', 'SafeConnectService', 'MGS', 'WMIRemover', 'RESIDUE'

    # Block 2 - added in v2.
    #
    # Real Windows service names, taken from McAfee's own service list in
    # StopServices\stopservices1.ini inside this MCPR package. mccleanup.exe
    # stops these itself via the StopServices product, so this block is
    # redundant whenever mccleanup runs -- and is the only thing stopping them
    # when it does not.
    #
    # NOT in this list, deliberately: mc-fw-host (McAfee Framework Host).
    # On WPS it runs with LaunchProtected=3 (PPL, antimalware-light), so the
    # SCM refuses control requests from any unprotected caller - Stop-Service,
    # sc stop and sc config all return 5 ACCESS_DENIED even as SYSTEM. That is
    # by design and no PowerShell can defeat it.
    #
    # mc-fw-host is left to mccleanup.exe, which is passed the mc-fw-host token
    # in $programArg below. WPS\wps100.ini declares
    #     [stop_delete_wps_service] type=service servicetype=ppl name=mc-fw-host
    # and a 2024+ engine honours that by registering itself as a PPL service.
    #
    # Note that the LEGACY engine this script ships with does NOT implement that
    # operation - it logs "Service Type ppl not supported" and skips it. So on
    # WPS machines mc-fw-host survives the cleanup and is removed by the reboot
    # plus subsequent Intune retries rather than by MCPR itself. Adding it to
    # this list still would not help: PowerShell cannot stop a PPL service.
    #
    # mc-update and mc-wps-update are ordinary services and stop normally. They
    # exist only on WPS machines and log as not found elsewhere.
    'homenetsvc', 'mcbootdelaystartsvc', 'mcmpfsvc', 'mcpltsvc', 'mfeavsvc', 'mfecore'
    'mfefire', 'mfevtp', 'mmscom', 'ProtectedModuleHostService', 'mgshost'
    'mc-update', 'mc-wps-update'
)

# mccleanup product list - verbatim from v1.
# NOTE: WMIRemover was removed from this list. McAfee references it in
# master.ini but the folder is absent from every MCPR build tested, so mccleanup
# logs
#   ERROR Internal Error. Could not locate ini file "...\WMIRemover\WMIRemover.ini"
#   FAIL  Product WMIRemover was not successfully removed.
# on every single run. That one guaranteed failure is enough to make MCPR report
# "Incomplete uninstallation" and return a non-zero exit code even when
# everything else succeeded. Dropping it removes a permanent false failure.
$programArg = '-p StopServices,MFSY,PEF,MXD,CSP,Sustainability,MOCP,mc-fw-host,MFP,APPSTATS,Auth,EMproxy,FWdiver,HW,MAS,MAT,MBK,MCPR,McProxy,McSvcHost,VUL,MHN,MNA,MOBK,MPFP,MPFPCU,MPS,SHRED,MPSCU,MQC,MQCCU,MSAD,MSHR,MSK,MSKCU,MWL,NMC,RedirSvc,VS,REMEDIATION,WPS,MSC,YAP,TRUEKEY,LAM,PCB,Symlink,SafeConnect,MGS,RESIDUE -v -s'

$webadvisor = 'C:\Program Files\McAfee\Webadvisor\Uninstaller.exe'
$SecScan    = 'C:\Program Files (x86)\McAfee Security Scan\uninstall.exe'
$RemoveApp  = 'Mcafee'

#endregion

#region ----------------------------------------------------------------- Setup

$logFolder = Split-Path -Parent $LogPath
if ($logFolder -and -not (Test-Path -LiteralPath $logFolder)) {
    New-Item -Path $logFolder -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
}

# Roll the log once it passes 5 MB. Without this, repeated Intune retries append
# to the same file indefinitely until it is too large to open.
try {
    $existingLog = Get-Item -LiteralPath $LogPath -ErrorAction SilentlyContinue
    if ($existingLog -and $existingLog.Length -gt 5MB) {
        $archivePath = Join-Path $logFolder ('{0}.1{1}' -f
            [System.IO.Path]::GetFileNameWithoutExtension($LogPath),
            [System.IO.Path]::GetExtension($LogPath))
        Move-Item -LiteralPath $LogPath -Destination $archivePath -Force -ErrorAction SilentlyContinue
    }
}
catch {
}

$scriptDir = $PSScriptRoot
if (-not $scriptDir) { $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition }

$program = Join-Path $scriptDir 'McCleanup.exe'

$scriptSuccess = $true

Write-Log ('=' * 78)
Write-Log "McAfee Removal v$ScriptVersion starting on $env:COMPUTERNAME"
Write-Log "Account          : $([Security.Principal.WindowsIdentity]::GetCurrent().Name)"
Write-Log "PowerShell       : $($PSVersionTable.PSVersion) ($(if ([Environment]::Is64BitProcess) { '64-bit' } else { '32-bit' }))"
Write-Log "Script directory : $scriptDir"
Write-Log "Log file         : $LogPath"
Write-Log "MCPR passes      : up to $MaxCleanupPasses"

#endregion

#region ------------------------------------------------- Stop/disable services

Write-Log ""
Write-Log "--- Stopping and disabling McAfee services ---"

$svcStopped  = 0
$svcDisabled = 0
$svcNotFound = @()
$svcErrors   = @()

foreach ($svc in $servicesToDisable) {
    try {
        $service = Get-Service -Name $svc -ErrorAction Stop

        if ($service.Status -ne 'Stopped') {
            Stop-Service -Name $svc -Force -ErrorAction Stop
            Write-Log "Stopped service: $svc"
            $svcStopped++
        }
        else {
            Write-Log "Service already stopped: $svc"
        }

        Set-Service -Name $svc -StartupType Disabled -ErrorAction Stop
        Write-Log "Disabled service: $svc"
        $svcDisabled++
    }
    catch {
        $message = $_.Exception.Message

        # Most of this list is MCPR product codes rather than service names, so
        # "not found" is the normal result for ~60 of them. Collect those and
        # report them on one line instead of 60. A service that exists but could
        # not be stopped is a different matter and is logged individually.
        if ($message -match 'Cannot find any service') {
            $svcNotFound += $svc
        }
        else {
            Write-Log "Service $svc could not be stopped or disabled: $message" 'WARN'
            $svcErrors += $svc
        }
    }
}

Write-Log "Services: $svcStopped stopped, $svcDisabled disabled, $($svcNotFound.Count) not installed, $($svcErrors.Count) errored."
if ($svcNotFound.Count -gt 0) {
    Write-Log "Not installed on this device: $($svcNotFound -join ', ')"
}

#endregion

#region ------------------------------------------------------ Run McCleanup.exe

Write-Log ""
Write-Log "--- Removing McAfee scheduled tasks ---"

# MCPR's LAM module fails three times per run with:
#   FAIL Failed to remove HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\
#        CurrentVersion\Schedule\TaskCache\Tree\McAfee\
# TaskCache is owned by the Task Scheduler service and its keys cannot be
# deleted directly, even as SYSTEM - they have to go through the Task Scheduler
# API. MCPR does eventually do this, but only in RESIDUE, which runs last, long
# after LAM has already failed. Clearing the tasks here means LAM finds nothing
# left to delete and passes on the first attempt.
$tasksRemoved = 0

try {
    $mcTasks = @(Get-ScheduledTask -ErrorAction SilentlyContinue |
        Where-Object { $_.TaskPath -like '*\McAfee\*' -or $_.TaskName -like 'McAfee*' })

    foreach ($task in $mcTasks) {
        try {
            Unregister-ScheduledTask -TaskName $task.TaskName -TaskPath $task.TaskPath -Confirm:$false -ErrorAction Stop
            Write-Log "Removed scheduled task: $($task.TaskPath)$($task.TaskName)"
            $tasksRemoved++
        }
        catch {
            Write-Log "Could not remove scheduled task $($task.TaskPath)$($task.TaskName): $($_.Exception.Message)" 'WARN'
        }
    }
}
catch {
    Write-Log "Could not enumerate scheduled tasks: $($_.Exception.Message)" 'WARN'
}

# Remove the now-empty McAfee task folder. This mirrors RESIDUE's own call.
try {
    $null = & "$env:WINDIR\System32\schtasks.exe" /delete /tn "McAfee" /f 2>&1
}
catch {
}

Write-Log "Scheduled tasks removed: $tasksRemoved"

Write-Log ""
Write-Log "--- Running McCleanup.exe ---"

if (Test-Path -LiteralPath $program) {
    try {
        # Log the engine version. The 2024+ builds of mccleanup.exe validate
        # their parent process and refuse to run when launched directly from
        # PowerShell, so knowing which binary is packaged is the first thing to
        # check when a run does nothing.
        $mcprVersion = 'unknown'
        try {
            $mcprVersion = (Get-Item -LiteralPath $program -ErrorAction Stop).VersionInfo.FileVersion
        }
        catch {
        }

        Write-Log "Executable : $program"
        Write-Log "MCPR build : $mcprVersion"
        Write-Log "Arguments  : $programArg"

        # Run MCPR up to $MaxCleanupPasses times, stopping as soon as it
        # returns 0. Each pass clears a little more: services that were running
        # during pass 1 are gone by pass 2, which releases file handles and lets
        # pass 3 remove what was locked before. Only what is still locked after
        # the final pass gets deferred to the reboot.
        $cleanupExit = $null

        for ($pass = 1; $pass -le $MaxCleanupPasses; $pass++) {

            $passStart = Get-Date
            $process = Start-Process $program -ArgumentList $programArg -PassThru -Wait -NoNewWindow
            $passElapsed = (Get-Date) - $passStart
            $cleanupExit = $process.ExitCode

            Write-Log "McCleanup.exe pass $pass of $MaxCleanupPasses ran for $([int]$passElapsed.TotalSeconds) seconds, exit code $cleanupExit. $(Get-McCleanupExitMeaning $cleanupExit)"

            if ($cleanupExit -eq 0) {
                Write-Log "Clean exit on pass $pass. Remaining passes skipped."
                break
            }

            if ($pass -lt $MaxCleanupPasses) {
                # Brief pause so terminated processes release their file handles
                # before the next pass tries to delete those files.
                Start-Sleep -Seconds 5
                Write-Log "Non-zero exit - running MCPR again (pass $($pass + 1) of $MaxCleanupPasses)."
            }
        }

        if ($cleanupExit -eq 0) {
            Write-Log 'McCleanup.exe ran successfully.'
        }
        else {
            Write-Log "McCleanup.exe still returning $cleanupExit after $MaxCleanupPasses pass(es). Reporting failure so Intune retries after the reboot." 'WARN'
            $scriptSuccess = $false
        }
    }
    catch {
        Write-Log "Error running McCleanup.exe: $($_.Exception.Message)" 'ERROR'
        $scriptSuccess = $false
    }
}
else {
    Write-Log "McCleanup.exe not found at $program" 'ERROR'
    $scriptSuccess = $false
}

#endregion

#region --------------------------------------------------- Uninstall WebAdvisor

Write-Log ""
Write-Log "--- Removing WebAdvisor ---"

if (Test-Path -LiteralPath $webadvisor) {
    try {
        $proc = Start-Process -FilePath $webadvisor -ArgumentList '/s' -PassThru -Wait -NoNewWindow
        Write-Log "WebAdvisor uninstaller exit code: $($proc.ExitCode)"
        Write-Log 'WebAdvisor uninstalled successfully.'
    }
    catch {
        Write-Log "Error uninstalling WebAdvisor: $($_.Exception.Message)" 'ERROR'
        $scriptSuccess = $false
    }
}
else {
    Write-Log "WebAdvisor not found at $webadvisor"
}

#endregion

#region ------------------------------------------------ Uninstall Security Scan

Write-Log ""
Write-Log "--- Removing Security Scan ---"

if (Test-Path -LiteralPath $SecScan) {
    try {
        $proc = Start-Process -FilePath $SecScan -ArgumentList '/s /inner' -PassThru -Wait -NoNewWindow
        Write-Log "Security Scan uninstaller exit code: $($proc.ExitCode)"
        Write-Log 'Security Scan uninstalled successfully.'
    }
    catch {
        Write-Log "Error uninstalling Security Scan: $($_.Exception.Message)" 'ERROR'
        $scriptSuccess = $false
    }
}
else {
    Write-Log "Security Scan not found at $SecScan"
}

#endregion

#region ------------------------------------------- Remove provisioned packages

Write-Log ""
Write-Log "--- Removing provisioned McAfee packages ---"

try {
    $provisioned = @(Get-AppxProvisionedPackage -Online |
        Where-Object { $_.PackageName -match $RemoveApp })

    if ($provisioned) {
        foreach ($package in $provisioned) {
            Write-Log "Removing provisioned package: $($package.PackageName)"
        }
        $provisioned | Remove-AppxProvisionedPackage -Online | Out-Null
        Write-Log "Removed $($provisioned.Count) provisioned McAfee package(s)."
    }
    else {
        Write-Log 'No provisioned McAfee packages found.'
    }
}
catch {
    Write-Log "Error removing provisioned McAfee packages: $($_.Exception.Message)" 'ERROR'
    $scriptSuccess = $false
}

#endregion

#region -------------------------------------- Remove packages for this account

Write-Log ""
Write-Log "--- Removing McAfee packages for the current account ---"

try {
    $packages = @(Get-AppxPackage | Where-Object { $_.Name -match $RemoveApp })

    if ($packages) {
        foreach ($package in $packages) {
            Write-Log "Removing package: $($package.PackageFullName)"
        }
        $packages | Remove-AppxPackage
        Write-Log "Removed $($packages.Count) McAfee app(s) for the system account."
    }
    else {
        Write-Log 'No McAfee apps found for the system account.'
    }
}
catch {
    Write-Log "Error removing McAfee apps for system account: $($_.Exception.Message)" 'ERROR'
    $scriptSuccess = $false
}

#endregion

#region ------------------------------------------- Remove packages, all users

Write-Log ""
Write-Log "--- Removing McAfee packages for all user profiles ---"

try {
    # v1 used Get-Unique, which only collapses ADJACENT duplicates. On unsorted
    # input that leaves duplicates in place and the same package gets processed
    # repeatedly. Sort-Object -Unique is the correct cmdlet here.
    $packageFullNames = @(Get-AppxPackage -AllUsers |
        Where-Object { $_.Name -match $RemoveApp } |
        Select-Object -ExpandProperty PackageFullName |
        Sort-Object -Unique)

    $users = @(Get-WmiObject Win32_UserProfile |
        Where-Object { $_.Special -eq $false } |
        Select-Object -ExpandProperty SID)

    Write-Log "Found $($packageFullNames.Count) package(s) across $($users.Count) profile(s)."

    $removed = 0
    $failed  = 0

    foreach ($package in $packageFullNames) {
        foreach ($user in $users) {
            try {
                Remove-AppxPackage -Package $package -User $user -ErrorAction Stop
                Write-Log "Removed $package for SID $user"
                $removed++
            }
            catch {
                # Not treated as a script failure - matches v1. A package that
                # was never installed for a given profile is normal.
                Write-Log "Failed to remove $package for SID ${user}: $($_.Exception.Message)" 'WARN'
                $failed++
            }
        }
    }

    Write-Log "Per-user package removal: $removed removed, $failed skipped or failed."
}
catch {
    Write-Log "Error in removing McAfee apps for all users: $($_.Exception.Message)" 'ERROR'
    $scriptSuccess = $false
}

#endregion

#region ------------------------------------------------------------- Finalize

$elapsed = (Get-Date) - $startTime

Write-Log ''
if ($scriptSuccess) {
    Write-Log 'Script completed successfully.'
    $exitCode = 0
}
else {
    Write-Log 'Script completed with errors. Intune will retry on the next cycle.' 'WARN'
    $exitCode = 1
}

Write-Log "Total run time: $([int]$elapsed.TotalSeconds) seconds. Exiting with code $exitCode."
Write-Log ('=' * 78)

exit $exitCode

#endregion
