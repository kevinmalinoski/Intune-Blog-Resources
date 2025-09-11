$ErrorActionPreference = "SilentlyContinue"
#Run DISM
try {Repair-WindowsImage -RestoreHealth -NoRestart -Online -LogPath "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\#DISM.log" -Verbose -ErrorAction SilentlyContinue}
catch {Write-Output "DISM error occurred. Check logs"}
finally {
        #Check registry for pauses
        $Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
        $TestPath = Test-Path $Path
        if  ($TestPath -eq $true)
            {
            Write-Output "Deleting $Path"
            Remove-Item -Path $Path -Recurse -Verbose
            }

        #Check registry for pauses
        $Path2 = "HKLM:\SOFTWARE\Microsoft\CloudManagedUpdate"
        $TestPath = Test-Path $Path2
        if  ($TestPath -eq $true)
            {
            Write-Output "Deleting $Path2"
            Remove-Item -Path $Path2 -Recurse -Verbose
            }   
            
        #Check registry for pauses
        $Path3 = "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UpdatePolicy"
        $TestPath = Test-Path $Path3
        if  ($TestPath -eq $true)
            {
            Write-Output "Deleting $Path3"
            Remove-Item -Path $Path3 -Recurse -Verbose
            }     

        $key = "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UpdatePolicy\Settings"
        $TestKey = Test-Path $key
        if  ($TestKey -eq $true)
            {
            $val = (Get-Item $key -EA Ignore);
            $PausedQualityDate = (Get-Item $key -EA Ignore).Property -contains "PausedQualityDate"
            $PausedFeatureDate = (Get-Item $key -EA Ignore).Property -contains "PausedFeatureDate"
            $PausedQualityStatus = (Get-Item $key -EA Ignore).Property -contains "PausedQualityStatus"
            $PausedQualityStatusValue = $val.GetValue("PausedQualityStatus");
            $PausedFeatureStatus = (Get-Item $key -EA Ignore).Property -contains "PausedFeatureStatus"
            $PausedFeatureStatusValue = $val.GetValue("PausedFeatureStatus");

            if  ($PausedQualityDate -eq $true)
                {
                Write-Output "PausedQualityDate under $key present"
                Remove-ItemProperty -Path $key -Name "PausedQualityDate" -Verbose -ErrorAction SilentlyContinue
                $PausedQualityDate = (Get-Item $key -EA Ignore).Property -contains "PausedQualityDate"
                }

            if  ($PausedFeatureDate -eq $true)
                {
                Write-Output "PausedFeatureDate under $key present"
                Remove-ItemProperty -Path $key -Name "PausedFeatureDate" -Verbose -ErrorAction SilentlyContinue
                $PausedFeatureDate = (Get-Item $key -EA Ignore).Property -contains "PausedFeatureDate"
                }

            if  ($PausedQualityStatus -eq $true)
                {
                Write-Output "PausedQualityStatus under $key present"
                Write-Output "Currently set to $PausedQualityStatusValue"
                if  ($PausedQualityStatusValue -ne "0")
                    {
                    Set-ItemProperty -Path $key -Name "PausedQualityStatus" -Value "0" -Verbose
                    $PausedQualityStatusValue = $val.GetValue("PausedQualityStatus");
                    }
                }

            if  ($PausedFeatureStatus -eq $true)
                {
                Write-Output "PausedFeatureStatus under $key present"
                Write-Output "Currently set to $PausedFeatureStatusValue"
                if  ($PausedFeatureStatusValue -ne "0")
                    {
                    Set-ItemProperty -Path $key -Name "PausedFeatureStatus" -Value "0" -Verbose
                    $PausedFeatureStatusValue = $val.GetValue("PausedFeatureStatus");
                    }
                }
            }

        $key2 = "HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\Update"
        $TestKey2 = Test-Path $key2
        if  ($TestKey2 -eq $true)
            {
            $val2 = (Get-Item $key2 -EA Ignore);

            $PauseQualityUpdatesStartTime = (Get-Item $key2 -EA Ignore).Property -contains "PauseQualityUpdatesStartTime"
            $PauseFeatureUpdatesStartTime = (Get-Item $key2 -EA Ignore).Property -contains "PauseFeatureUpdatesStartTime"
            $PauseQualityUpdates = (Get-Item $key2 -EA Ignore).Property -contains "PauseQualityUpdates"
            $PauseQualityUpdatesValue = $val2.GetValue("PauseQualityUpdates");
            $PauseFeatureUpdates = (Get-Item $key2 -EA Ignore).Property -contains "PauseFeatureUpdates"
            $PauseFeatureUpdatesValue = $val2.GetValue("PauseFeatureUpdates");
            $DeferFeatureUpdates = (Get-Item $key2 -EA Ignore).Property -contains "DeferFeatureUpdatesPeriodInDays"
            $DeferFeatureUpdatesValue = $val2.GetValue("DeferFeatureUpdatesPeriodInDays");

            if  ($DeferFeatureUpdates -eq $true)
                {
                Write-Output "DeferFeatureUpdatesPeriodInDays under $key2 present"
                Write-Output "Currently set to $DeferFeatureUpdatesValue"
                if  ($DeferFeatureUpdatesValue -ne "0")
                    {
                    Set-ItemProperty -Path $key2 -Name "DeferFeatureUpdatesPeriodInDays" -Value "0" -Verbose
                    $DeferFeatureUpdatesValue = $val2.GetValue("DeferFeatureUpdatesPeriodInDays");
                    }
                }    

            if  ($PauseQualityUpdatesStartTime -eq $true)
                {
                Write-Output "PauseQualityUpdatesStartTime under $key2 present"
                Remove-ItemProperty -Path $key2 -Name "PauseQualityUpdatesStartTime" -Verbose -ErrorAction SilentlyContinue
                Remove-ItemProperty -Path $key2 -Name "PauseQualityUpdatesStartTime_ProviderSet" -Verbose -ErrorAction SilentlyContinue
                Remove-ItemProperty -Path $key2 -Name "PauseQualityUpdatesStartTime_WinningProvider" -Verbose -ErrorAction SilentlyContinue
                $PauseQualityUpdatesStartTime = (Get-Item $key2 -EA Ignore).Property -contains "PauseQualityUpdatesStartTime"
                }

            if  ($PauseFeatureUpdatesStartTime -eq $true)
                {
                Write-Output "PauseFeatureUpdatesStartTime under $key2 present"
                Remove-ItemProperty -Path $key2 -Name "PauseFeatureUpdatesStartTime" -Verbose -ErrorAction SilentlyContinue
                Remove-ItemProperty -Path $key2 -Name "PauseFeatureUpdatesStartTime_ProviderSet" -Verbose -ErrorAction SilentlyContinue
                Remove-ItemProperty -Path $key2 -Name "PauseFeatureUpdatesStartTime_WinningProvider" -Verbose -ErrorAction SilentlyContinue
                $PauseFeatureUpdatesStartTime = (Get-Item $key2 -EA Ignore).Property -contains "PauseFeatureUpdatesStartTime"
                }

            if  ($PauseQualityUpdates -eq $true)
                {
                Write-Output "PauseQualityUpdates under $key2 present"
                Write-Output "Currently set to $PauseQualityUpdatesValue"
                if  ($PauseQualityUpdatesValue -ne "0")
                    {
                    Set-ItemProperty -Path $key2 -Name "PauseQualityUpdates" -Value "0" -Verbose
                    $PauseQualityUpdatesValue = $val2.GetValue("PauseQualityUpdates");
                    }
                }

            if  ($PauseFeatureUpdates -eq $true)
                {
                Write-Output "PauseFeatureUpdates under $key2 present"
                Write-Output "Currently set to $PauseFeatureUpdatesValue"
                if  ($PauseFeatureUpdatesValue -ne "0")
                    {
                    Set-ItemProperty -Path $key2 -Name "PauseFeatureUpdates" -Value "0" -Verbose
                    $PauseFeatureUpdatesValue = $val2.GetValue("PauseFeatureUpdates");
                    }
                }
            }

        $key3 = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"
        $TestKey3 = Test-Path $key3
        if  ($TestKey3 -eq $true)
            {
            $val3 = (Get-Item $key3 -EA Ignore);

            $AllowDeviceNameInTelemetry = (Get-Item $key3 -EA Ignore).Property -contains "AllowDeviceNameInTelemetry"
            $AllowTelemetry_PolicyManager = (Get-Item $key3 -EA Ignore).Property -contains "AllowTelemetry_PolicyManager"
            $AllowDeviceNameInTelemetryValue = $val3.GetValue("AllowDeviceNameInTelemetry");
            $AllowTelemetry_PolicyManagerValue = $val3.GetValue("AllowTelemetry_PolicyManager");

            if  ($AllowDeviceNameInTelemetry -eq $true)
                {
                Write-Output "AllowDeviceNameInTelemetry under $key3 present"
                Write-Output "Currently set to $AllowDeviceNameInTelemetryValue"
                }
            else{New-ItemProperty -Path $key3 -PropertyType DWORD -Name "AllowDeviceNameInTelemetry" -Value "1" -Verbose}

            if  ($AllowDeviceNameInTelemetryValue -ne "1")
                {Set-ItemProperty -Path $key3 -Name "AllowDeviceNameInTelemetry" -Value "1" -Verbose}

            if  ($AllowTelemetry_PolicyManager -eq $true)
                {
                Write-Output "AllowTelemetry_PolicyManager under $key3 present"
                Write-Output "Currently set to $AllowTelemetry_PolicyManagerValue"
                }
            else{New-ItemProperty -Path $key3 -PropertyType DWORD -Name "AllowTelemetry_PolicyManager" -Value "1" -Verbose}

            if  ($AllowTelemetry_PolicyManagerValue -ne "1")
                {Set-ItemProperty -Path $key3 -Name "AllowTelemetry_PolicyManager" -Value "1" -Verbose}
            }


        $key4 = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Appraiser\GWX"
        $TestKey4 = Test-Path $key4
        if  ($TestKey4 -eq $true)
            {
            $val4 = (Get-Item $key4 -EA Ignore);

            $GStatus = (Get-Item $key4 -EA Ignore).Property -contains "GStatus"
            $GStatusValue = $val4.GetValue("GStatus");
            
            if  ($GStatus -eq $true) 
                {
                Write-Output "GStatus under $key4 present"
                Write-Output "Currently set to $GStatusValue"
                }
            else{New-ItemProperty -Path $key4 -PropertyType DWORD -Name "GStatus" -Value "2" -Verbose}

            if  ($GStatusValue -ne "2")
                {Set-ItemProperty -Path $key4 -Name "GStatus" -Value "2" -Verbose}
            }

       
}