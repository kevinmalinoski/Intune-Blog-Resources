# PowerShell script to configure Edge kiosk shortcut for Intune deployment
# Launches in maximized window + kiosk mode

# Define the All Users Start Menu Programs directory
$startMenuPrograms = "$env:ALLUSERSPROFILE\Microsoft\Windows\Start Menu\Programs"

# Create the new Edge Kiosk shortcut - maximized window
$shell = New-Object -ComObject WScript.Shell
$kioskShortcutPath = Join-Path -Path $startMenuPrograms -ChildPath "Microsoft Edge Kiosk.lnk"
$shortcut = $shell.CreateShortcut($kioskShortcutPath)

$shortcut.TargetPath = "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
# Modify line 14 to include desired kiosk arguments (example: public browsing mode with no idle timeout)
$shortcut.Arguments  = "--kiosk https://malinoski.me/ --edge-kiosk-type=public-browsing --kiosk-idle-timeout-minutes=0 --no-first-run"
$shortcut.WindowStyle = 3  # 3 = Maximized (1 = Normal, 7 = Minimized)

$shortcut.Save()