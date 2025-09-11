# Define the registry key path
$regKeyPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\TargetVersionUpgradeExperienceIndicators"

# Check if the registry key exists
if (Test-Path $regKeyPath) {
    Write-Output "Issue detected: Registry key exists."
    exit 1
} else {
    Write-Output "No issue: Registry key does not exist."
    exit 0
}