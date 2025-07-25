# Enhanced McAfee Removal Script for Intune (Device Context)

# Define log file path
$LogFile = "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\McAfeeRemovalLog.txt"

# Function to write log messages
function Write-Log {
    param (
        [string]$Message
    )
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogMessage = "$Timestamp - $Message"
    Add-Content -Path $LogFile -Value $LogMessage
}

# Start logging
Write-Log "Starting McAfee removal script on $(Get-Date) on machine $(hostname)"

# Initialize success flag
$scriptSuccess = $true

# Get script directory
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition

# Path to McCleanup.exe
$program = Join-Path $scriptDir "McCleanup.exe"

# Check if McCleanup.exe exists
if (Test-Path $program) {
    try {
        # Arguments for McCleanup.exe
        $programArg = "-p StopServices,MFSY,PEF,MXD,CSP,Sustainability,MOCP,mc-fw-host,MFP,APPSTATS,Auth,EMproxy,FWdiver,HW,MAS,MAT,MBK,MCPR,McProxy,McSvcHost,VUL,MHN,MNA,MOBK,MPFP,MPFPCU,MPS,SHRED,MPSCU,MQC,MQCCU,MSAD,MSHR,MSK,MSKCU,MWL,NMC,RedirSvc,VS,REMEDIATION,WPS,MSC,YAP,TRUEKEY,LAM,PCB,Symlink,SafeConnect,MGS,WMIRemover,RESIDUE -v -s"
        
        # Run McCleanup.exe
        $process = Start-Process $program -ArgumentList $programArg -PassThru -Wait -NoNewWindow
        
        if ($process.ExitCode -ne 0) {
            Write-Log "McCleanup.exe failed with exit code $($process.ExitCode) - executing MCPR a second time"
            $process = Start-Process $program -ArgumentList $programArg -PassThru -Wait -NoNewWindow
            Write-Log "McCleanup.exe finished reattempt with exit code $($process.ExitCode)"
        } else {
            Write-Log "McCleanup.exe finished with exit code $($process.ExitCode)"
            $scriptSuccess = $false
        }
    } catch {
        Write-Log "Error running McCleanup.exe: $_"
        $scriptSuccess = $false
    }
} else {
    Write-Log "McCleanup.exe not found at $program"
    $scriptSuccess = $false
}

# Remove McAfee provisioned Store apps
$RemoveApp = 'Mcafee'
try {
    $provisioned = Get-AppxProvisionedPackage -Online | Where-Object {$_.PackageName -Match $RemoveApp}
    if ($provisioned) {
        $provisioned | Remove-AppxProvisionedPackage -Online
        Write-Log "Removed provisioned McAfee packages."
    } else {
        Write-Log "No provisioned McAfee packages found."
    }
} catch {
    Write-Log "Error removing provisioned McAfee packages: $_"
    $scriptSuccess = $false
}

# Remove McAfee Store apps installed for system account
try {
    $packages = Get-AppxPackage | Where-Object {$_.Name -Match $RemoveApp}
    if ($packages) {
        $packages | Remove-AppxPackage
        Write-Log "Removed McAfee apps for system account."
    } else {
        Write-Log "No McAfee apps found for system account."
    }
} catch {
    Write-Log "Error removing McAfee apps for system account: $_"
    $scriptSuccess = $false
}

# Finalize
if ($scriptSuccess) {
    Write-Log "Script completed successfully."
    exit 0
} else {
    Write-Log "Script completed with errors."
    exit 1
}