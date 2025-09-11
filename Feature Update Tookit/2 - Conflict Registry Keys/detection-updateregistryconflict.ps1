$GetOS = Get-ComputerInfo -property OsVersion
$OSversion = [Version]$GetOS.OsVersion

if ($OSversion.Major -eq 10 -and $OSversion.Build -le 19045)
    {
    Write-Output "OS version currently on $OSversion"
    exit 1
    }
    else{
        Write-Output "OS version currently on $OSversion"
        exit 0
    }