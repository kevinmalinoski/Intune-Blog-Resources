# Pre Check for Update status
$CheckForUpdatePre = Get-WinEvent -FilterHashtable @{
    LogName   = 'Microsoft-Windows-WindowsUpdateClient/Operational'
   }
$TopPre = $CheckForUpdatePre  | Select-Object -First 1

# Trigger Check for Windows update
Start-Process -FilePath "C:\Windows\System32\USOClient.exe" -ArgumentList "StartInteractiveScan" -WindowStyle Hidden
Start-Sleep 120

# Post Check for Update status
$CheckForUpdatePost = Get-WinEvent -FilterHashtable @{
    LogName   = 'Microsoft-Windows-WindowsUpdateClient/Operational'
    }
$TopPost = $CheckForUpdatePost | Select-Object -First 1

#OutPut
Write-host "PreCFU:-$($TopPre.TimeCreated) ; PostCFU:-$($TopPost.TimeCreated)"