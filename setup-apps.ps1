# setup-apps.ps1


param (
    $UserAccountName,
    $ComputerSuffix = "-PC",
    $SkipDomainJoin,
    $Role
)



# -------------------------------
#  Helper Functions
# -------------------------------
function Write-Status {
    param([string]$Message, [string]$Color = "Green")
    Write-Host $Message -ForegroundColor $Color
}

function Test-PendingReboot {
    # Simple check - expand if needed
    if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending") { return $true }
    return $false
}

# -------------------------------
#  1. Gather Info
# -------------------------------
Write-Status "New Computer Setup - Resolut Style" "Cyan"

if (-not $UserAccountName) {
    $UserAccountName = Read-Host "Enter user logon name (e.g. jsmith)"
}
$computerName = "$($UserAccountName.Substring(0,1).ToUpper())$($UserAccountName.Substring(1))${ComputerSuffix}"
Write-Status "Target computer name: $computerName"
Write-Status "User: $UserAccountName    Role: $Role"

# -------------------------------
#  2. Rename computer (if needed)
# -------------------------------
$currentName = $env:COMPUTERNAME
if ($currentName -ne $computerName) {
    Write-Status "Renaming computer to $computerName ..."
    Rename-Computer -NewName $computerName -Force -Restart
    Write-Status "Restart required — run script again after reboot" "Yellow"
    exit
}

# -------------------------------
#  3. Domain Join (if not already)
# -------------------------------
if (-not $SkipDomainJoin) {
    $domain = "vbfa.com"
    if ((Get-WmiObject Win32_ComputerSystem).Domain -ne $domain) {
        Write-Status "Joining domain $domain ..."
        $cred = Get-Credential -Message "Enter DOMAIN ADMIN credentials for join"
        Add-Computer -DomainName $domain -Credential $cred -Force -Restart
        Write-Status "Domain join initiated — rebooting" "Yellow"
        exit
    }
    else {
        Write-Status "Already domain-joined" "Gray"
    }
}

# -------------------------------
#  4. Driver Check
# -------------------------------
Write-Status "Checking for missing or problem drivers..." "Cyan"
 
# Report any devices with errors or missing drivers
$problemDevices = Get-PnpDevice | Where-Object { $_.Status -ne 'OK' }
 
if ($problemDevices) {
    Write-Status "The following devices have issues:" "Yellow"
    $problemDevices | Format-Table -AutoSize FriendlyName, Status, Class, InstanceId
} else {
    Write-Status "All devices report OK in Device Manager." "Green"
}
 
# Attempt Windows Update-based driver delivery via PSWindowsUpdate
Write-Status "Attempting to install missing drivers via Windows Update..." "Cyan"
 
if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) {
    Write-Status "Installing PSWindowsUpdate module..." "Yellow"
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Confirm:$false | Out-Null
    Install-Module -Name PSWindowsUpdate -Force -Confirm:$false -Scope CurrentUser
}
 
Import-Module PSWindowsUpdate -ErrorAction SilentlyContinue
 
try {
    $driverUpdates = Get-WindowsUpdate -UpdateType Driver -AcceptAll -IgnoreReboot -ErrorAction Stop
    if ($driverUpdates) {
        Write-Status "Installing $($driverUpdates.Count) driver update(s)..." "Yellow"
        Install-WindowsUpdate -UpdateType Driver -AcceptAll -IgnoreReboot -Confirm:$false
        Write-Status "Driver updates installed." "Green"
    } else {
        Write-Status "No driver updates found via Windows Update." "Gray"
    }
} catch {
    Write-Status "Could not pull driver updates automatically: $_" "Red"
    Write-Status "Please review Device Manager manually for any remaining issues." "Yellow"
}
 
# Re-check after driver install attempt
$stillProblem = Get-PnpDevice | Where-Object { $_.Status -ne 'OK' }
if ($stillProblem) {
    Write-Status "Devices still showing issues after driver pass — manual attention may be needed:" "Yellow"
    $stillProblem | Format-Table -AutoSize FriendlyName, Status, Class, InstanceId
} else {
    Write-Status "All devices OK after driver pass." "Green"
}

# -------------------------------
#  5. Install Applications
# -------------------------------
$jsonUrl = "https://raw.githubusercontent.com/RJ060501/winget-apps-script/refs/heads/main/winget-apps.json"  # your URL here

$tempJson = "$env:TEMP\winget-apps.json"

Write-Host "Downloading app list from GitHub repo..." -ForegroundColor Green
Invoke-WebRequest -Uri $jsonUrl -OutFile $tempJson

Write-Host "Installing apps via winget import..." -ForegroundColor Green
winget import -i $tempJson `
    --accept-package-agreements `
    --accept-source-agreements `
    --ignore-versions `
    --disable-interactivity

Remove-Item $tempJson -ErrorAction SilentlyContinue

Write-Host "Apps installed! Some apps may require a restart or manual login/setup." -ForegroundColor Cyan

# -------------------------------
#  6. Custom / non-winget installs
# -------------------------------

# # Now switch to NON-ELEVATED context for Autodesk (and future custom installers)
# Write-Status "Launching non-elevated PowerShell for Autodesk installs..." "Cyan"

# # Create a temporary sub-script that runs non-elevated
# $autodeskSubScript = "$env:TEMP\Install-Autodesk-NonElevated.ps1"

# @'
# # Non-elevated Autodesk sub-script

# function Write-Status {
#     param([string]$Message, [string]$Color = "Green")
#     Write-Host $Message -ForegroundColor $Color
# }

# Write-Status "Non-elevated Autodesk installer running..." "Cyan"
# $autodeskDownloads = @(
#     "https://github.com/RJ060501/winget-apps-script/releases/tag/custom_apps/AutoCAD_2026_English-US-en-US_setup_webinstall.exe",
#     "https://github.com/RJ060501/winget-apps-script/releases/tag/custom_apps/Revit_2021_Ship_20200715_r4_Win_64bit_di_cs-CZ_setup_webinstall.exe",
#     "https://github.com/RJ060501/winget-apps-script/releases/tag/custom_apps/Revit_2022_Ship_20210224_RTC_Win_64bit_di_cs-CZ_setup_webinstall.exe",
#     "https://github.com/RJ060501/winget-apps-script/releases/tag/custom_apps/Revit_2023_1_8_0_1_Win_64bit_di_ML_setup_webinstall.exe",
#     "https://github.com/RJ060501/winget-apps-script/releases/tag/custom_apps/Revit_2024_3_3_ML_setup_webinstall.exe",
#     "https://github.com/RJ060501/winget-apps-script/releases/tag/custom_apps/Revit_2025_4_2_ML_setup_webinstall.exe",
#     "https://github.com/RJ060501/winget-apps-script/releases/tag/custom_apps/Revit_2026_2_ML_setup_webinstall.exe"
# )

# $tempFolder = "$env:TEMP\AutodeskInstallers"
# New-Item -Path $tempFolder -ItemType Directory -Force | Out-Null

# foreach ($url in $autodeskDownloads) {
#     $fileName = [System.IO.Path]::GetFileName($url)
#     $localPath = Join-Path $tempFolder $fileName

#     Write-Status "Downloading: $fileName" "Yellow"

#     $ProgressPreference = 'SilentlyContinue'
#     & curl.exe -L -o $localPath $url --retry 3 --retry-delay 5 --fail --silent --show-error

#     if (Test-Path $localPath) {
#         Write-Status "  Download success" "Green"

#         Write-Status "Installing: $fileName" "Green"

#         try {
#             Add-Type -AssemblyName System.Windows.Forms
#             [System.Windows.Forms.Application]::DoEvents()

#             $psi = New-Object System.Diagnostics.ProcessStartInfo
#             $psi.FileName = $localPath
#             $psi.Arguments = "-q"
#             $psi.UseShellExecute = $true
#             $psi.WorkingDirectory = $tempFolder

#             $process = [System.Diagnostics.Process]::Start($psi)
#             $process.WaitForExit()
#             $exit = $process.ExitCode

#             if ($exit -eq 0 -or $exit -eq 3010 -or $exit -eq 1641) {
#                 Write-Status "  SUCCESS (exit $exit)" "Green"
#             } else {
#                 Write-Status "  Exit $exit" "Yellow"
#             }
#         }
#         catch {
#             Write-Status "  Install error: $_" "Red"
#         }

#         Start-Sleep -Seconds 30
#     } else {
#         Write-Status "  Download failed for $fileName" "Red"
#     }
# }

# Remove-Item $tempFolder -Recurse -Force -ErrorAction SilentlyContinue

# Write-Status "Autodesk installs complete in non-elevated context." "Cyan"

# if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') {
#     Write-Status "Reboot pending — restarting in 60 seconds..." "Yellow"
#     Start-Sleep -Seconds 60
#     Restart-Computer -Force
# }
# '@ | Set-Content -Path $autodeskSubScript -Encoding UTF8

# # Launch the sub-script NON-ELEVATED
# Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$autodeskSubScript`"" -NoNewWindow

# Write-Status "Non-elevated Autodesk installer launched. Follow any UAC prompts if they appear." "Yellow"
# Write-Status "Script will continue after sub-process finishes or you can close this window." "Cyan"

# -------------------------------
#  7. Power settings (High Performance, skip laptops)
# -------------------------------
$battery = Get-CimInstance -ClassName Win32_Battery
if ($null -eq $battery -or $battery.BatteryStatus -eq 0) {
    # Desktop
    Write-Status "Setting High Performance power plan (desktop)"
    powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c
    powercfg -change -monitor-timeout-ac 30    # 30 min screen
    powercfg -change -standby-timeout-ac 120   # 2 hr sleep
    powercfg -h off                            # no hibernation
}