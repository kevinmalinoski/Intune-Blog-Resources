# Script to uninstall specific HP security packages
# Optimized for Intune Win32 app deployment
Install-PackageProvider -Name NuGet -Force -Scope CurrentUser

# Define log file path for Intune
$logPath = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs\HP_Uninstall_Log.txt"

# Function to write to log file
function Write-Log {
    param (
        [string]$Message
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $Message" | Out-File -FilePath $logPath -Append
}

# Function to uninstall packages matching criteria
function Uninstall-HPPackages {
    param (
        [string]$PackageNamePattern,
        [version]$MinimumVersion = $null
    )
    
    try {
        Write-Log "Searching for packages matching pattern: $PackageNamePattern"
        
        $packages = Get-Package -AllVersions -ErrorAction Stop | 
            Where-Object { $_.Name -match $PackageNamePattern }
        
        if ($packages) {
            foreach ($package in $packages) {
                if ($MinimumVersion -and [version]$package.Version -lt $MinimumVersion) {
                    Write-Log "Skipping $($package.Name) version $($package.Version) - below minimum version $MinimumVersion"
                    continue
                }
                
                Write-Log "Uninstalling $($package.Name) version $($package.Version)"
                try {
                    $package | Uninstall-Package -ErrorAction Stop
                    Write-Log "Successfully uninstalled $($package.Name)"
                }
                catch {
                    Write-Log "Failed to uninstall $($package.Name): $_"
                }
            }
        }
        else {
            Write-Log "No packages found matching pattern: $PackageNamePattern"
        }
    }
    catch {
        Write-Log "Error processing packages for pattern $PackageNamePattern : $_"
    }
}

# Main execution
try {
    Write-Log "Starting HP security package uninstallation process"
    
    # Define packages and criteria
    $packagePatterns = @(
        @{ Name = "HP Client Security Manager"; MinVersion = "10.0.0" },
        @{ Name = "HP Wolf Security(?!.*Console)" },
        @{ Name = "HP Wolf Security.*Console" },
        @{ Name = "HP Security Update Service" }
    )
    
    # Process each package pattern
    foreach ($pattern in $packagePatterns) {
        if ($pattern.MinVersion) {
            Uninstall-HPPackages -PackageNamePattern $pattern.Name -MinimumVersion $pattern.MinVersion
        }
        else {
            Uninstall-HPPackages -PackageNamePattern $pattern.Name
        }
    }
    
    Write-Log "Uninstallation process completed"
    exit 0
}
catch {
    Write-Log "Fatal error in main execution: $_"
    exit 1
}
finally {
    Write-Log "Script execution finished"
}