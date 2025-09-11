# Check for pending Windows updates
$updateSession = New-Object -ComObject Microsoft.Update.Session
$updateSearcher = $updateSession.CreateUpdateSearcher()
$updates = $updateSearcher.Search("IsInstalled=0")

# Check if there are pending updates
if ($updates.Updates.Count -gt 0) {
    Write-Output "Pending updates detected. Device is compliant."

} else {
    Write-Output "No pending updates detected. Device is non-compliant."

}