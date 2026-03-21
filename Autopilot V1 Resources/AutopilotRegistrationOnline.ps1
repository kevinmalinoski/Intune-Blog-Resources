# Force TLS 1.2 (usually not needed anymore in 2026)
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force

# Create working HWID folder
$path = "C:\HWID"
if (!(Test-Path $path)) { New-Item -Path $path -ItemType Directory -Force | Out-Null }
Set-Location -Path $path

# Ensure script install location is in PATH
$env:Path += ";C:\Program Files\WindowsPowerShell\Scripts"

# Allow scripts for this session
Set-ExecutionPolicy -Scope Process -ExecutionPolicy RemoteSigned -Force

# Install/update the script if missing or outdated
if (-not (Get-Command Get-WindowsAutopilotInfo -ErrorAction SilentlyContinue)) {
    Write-Host "Installing Get-WindowsAutopilotInfo..." -ForegroundColor Cyan
    Install-Script Get-WindowsAutopilotInfo -Force
}

Get-WindowsAutopilotInfo -Online