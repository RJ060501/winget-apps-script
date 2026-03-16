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
Write-Status "Checking Device Manager for problem drivers..." "Cyan"
 
# Filter to only genuinely broken devices — Error status means missing/failed driver.
# 'Unknown' is normal for USB drives, phones, virtual/remote devices and is NOT a real problem.
$problemDevices = Get-PnpDevice | Where-Object { $_.Status -eq 'Error' }
 
if ($problemDevices) {
    Write-Status "The following devices have driver errors — may need manual attention:" "Yellow"
    $problemDevices | Format-Table -AutoSize FriendlyName, Status, Class, InstanceId
} else {
    Write-Status "No driver errors found in Device Manager." "Green"
}

# -------------------------------
#  4b. Windows Updates)
# -------------------------------
# Uses built-in Windows Update COM API — no PSWindowsUpdate or external publishers needed.
 
Write-Status "Starting Windows Update process (native COM API)..." "Cyan"
Write-Status "This may take a while. Script will loop until no updates remain." "Yellow"
 
$updateRound = 0
$maxRounds   = 6   # safety cap
 
do {
    $updateRound++
    Write-Status "--- Windows Update Round $updateRound of $maxRounds ---" "Cyan"
 
    try {
        $updateSession  = New-Object -ComObject Microsoft.Update.Session
        $updateSearcher = $updateSession.CreateUpdateSearcher()
 
        Write-Status "Searching for updates..." "Gray"
        $searchResult = $updateSearcher.Search("IsInstalled=0 and Type='Software' and IsHidden=0")
 
        if ($searchResult.Updates.Count -eq 0) {
            Write-Status "No more updates found. Windows is up to date!" "Green"
            break
        }
 
        Write-Status "Found $($searchResult.Updates.Count) update(s). Downloading..." "Yellow"
 
        $updatesToInstall = New-Object -ComObject Microsoft.Update.UpdateColl
        foreach ($update in $searchResult.Updates) {
            $updatesToInstall.Add($update) | Out-Null
        }
 
        $downloader        = $updateSession.CreateUpdateDownloader()
        $downloader.Updates = $updatesToInstall
        $downloader.Download() | Out-Null
 
        Write-Status "Installing updates..." "Yellow"
        $installer         = $updateSession.CreateUpdateInstaller()
        $installer.Updates = $updatesToInstall
        $installResult     = $installer.Install()
 
        Write-Status "Install result code: $($installResult.ResultCode)  (2 = Success, 3 = Success w/ errors)" "Gray"
 
        if ($installResult.RebootRequired -or (Test-PendingReboot)) {
            Write-Status "Reboot required after update round $updateRound." "Yellow"
            $restart = Read-Host "Restart now to continue patching? (Y/N)"
            if ($restart -eq "Y" -or $restart -eq "y") {
                #Put this code block at the end!
                Write-Status "Rebooting — re-run this script after restart to continue." "Yellow"
                Restart-Computer -Force
                exit
            } else {
                Write-Status "Skipping reboot. Some updates may not fully apply until rebooted." "Yellow"
                break
            }
        }
 
    } catch {
        Write-Status "Windows Update error on round $updateRound`: $_" "Red"
        break
    }
 
} while ($updateRound -lt $maxRounds)
 
if ($updateRound -ge $maxRounds) {
    Write-Status "Reached max update rounds ($maxRounds). Verify in Settings > Windows Update." "Yellow"
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

# -------------------------------
#  8. Firefox Config & User Profiles
# -------------------------------
Write-Status "Configuring Firefox (default browser, homepage, uBlock Origin)..." "Cyan"

# --- Set Firefox as default browser ---
# Uses Windows built-in 'start' verb on the Firefox registration URL handler.
# Silently sets defaults via the registry for .html, .htm, http, https associations.
$firefoxPath = "${env:ProgramFiles}\Mozilla Firefox\firefox.exe"
if (-not (Test-Path $firefoxPath)) {
    $firefoxPath = "${env:ProgramFiles(x86)}\Mozilla Firefox\firefox.exe"
}
 
if (Test-Path $firefoxPath) {
    # Set HTTPS/HTTP default via DISM/UserAssociation — works on Win10/11
    $assocXml = @"
<?xml version="1.0" encoding="UTF-8"?>
<DefaultAssociations>
  <Association Identifier=".htm"   ProgId="FirefoxHTML-308046B0AF4A39CB" ApplicationName="Firefox" />
  <Association Identifier=".html"  ProgId="FirefoxHTML-308046B0AF4A39CB" ApplicationName="Firefox" />
  <Association Identifier="http"   ProgId="FirefoxURL-308046B0AF4A39CB"  ApplicationName="Firefox" />
  <Association Identifier="https"  ProgId="FirefoxURL-308046B0AF4A39CB"  ApplicationName="Firefox" />
  <Association Identifier="ftp"    ProgId="FirefoxURL-308046B0AF4A39CB"  ApplicationName="Firefox" />
</DefaultAssociations>
"@
    $assocFile = "$env:TEMP\firefox-defaults.xml"
    $assocXml | Set-Content -Path $assocFile -Encoding UTF8
    & dism.exe /Online /Import-DefaultAppAssociations:"$assocFile" | Out-Null
    Remove-Item $assocFile -ErrorAction SilentlyContinue
    Write-Status "Firefox set as default browser." "Green"
} else {
    Write-Status "Firefox not found — skipping default browser setting. Is it installed?" "Yellow"
}

# --- Firefox policies.json (uBlock Origin + homepage) ---
# This is the official enterprise method for managing Firefox settings.
# Mozilla documents it here: https://mozilla.github.io/policy-templates/
# uBlock Origin extension ID is: uBlock0@raymondhill.net (verified on Mozilla Add-ons)
 
$firefoxPoliciesDir = "${env:ProgramFiles}\Mozilla Firefox\distribution"
New-Item -Path $firefoxPoliciesDir -ItemType Directory -Force | Out-Null
 
$sharepointUrl = "https://theresolutgroup.sharepoint.com/sites/ResolutLandingPage?web=1"
$policiesJson = @"
{
  "policies": {
    "Homepage": {
      "URL": "$sharepointUrl",
      "Locked": false,
      "StartPage": "homepage"
    },
    "Extensions": {
      "Install": [
        "https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/latest.xpi"
      ]
    },
    "ExtensionSettings": {
      "uBlock0@raymondhill.net": {
        "installation_mode": "force_installed",
        "install_url": "https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/latest.xpi"
      }
    }
  }
}
"@

$policiesJson | Set-Content -Path "$firefoxPoliciesDir\policies.json" -Encoding UTF8
Write-Status "Firefox policies.json written (homepage + uBlock Origin)." "Green"
Write-Status "uBlock will auto-install on first Firefox launch." "Gray"
 
# Remove Edge from taskbar via registry (common OEM pin location)
$edgeTaskbarKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Taskband"
if (Test-Path $edgeTaskbarKey) {
    # Clearing FavoritesResolve forces taskbar to rebuild without OEM pins on next Explorer restart
    Remove-ItemProperty -Path $edgeTaskbarKey -Name "FavoritesResolve" -ErrorAction SilentlyContinue
}

Write-Status "Reminder: Taskbar items will need to be removed manually." "Yellow"
Write-Status "Reminder: Startup items should be reviewed manually in Task Manager > Startup." "Yellow"