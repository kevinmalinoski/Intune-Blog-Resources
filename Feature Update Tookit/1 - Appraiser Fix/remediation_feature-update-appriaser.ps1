# Define the registry key path
$regKeyPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\TargetVersionUpgradeExperienceIndicators"

# Check if the registry key exists and delete it if it does
if (Test-Path $regKeyPath) {
    Remove-Item -Path $regKeyPath -Recurse -Force
    Write-Output "Registry key deleted."
} else {
    Write-Output "Registry key does not exist."
}

# Run the specified command
# Note: The executable is typically named CompatTelRunner.exe (case-sensitive file system consideration)
Start-Process -FilePath "C:\Windows\System32\CompatTelRunner.exe" -ArgumentList "-m:appraiser.dll -f:DoScheduledTelemetryRun" -NoNewWindow -Wait
Write-Output "Command executed."