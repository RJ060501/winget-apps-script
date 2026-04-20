# setup-apps.ps1

#stop watch
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

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

# # -------------------------------
# #  1. Gather Info
# # -------------------------------
# Write-Status "New Computer Setup - Resolut Style" "Cyan"

# if (-not $UserAccountName) {
#     $UserAccountName = Read-Host "Enter user logon name (e.g. jsmith)"
# }
# $computerName = "$($UserAccountName.Substring(0,1).ToUpper())$($UserAccountName.Substring(1))${ComputerSuffix}"
# Write-Status "Target computer name: $computerName"
# Write-Status "User: $UserAccountName    Role: $Role"

# # -------------------------------
# #  2. Rename computer (if needed)
# # -------------------------------
# $currentName = $env:COMPUTERNAME
# if ($currentName -ne $computerName) {
#     Write-Status "Renaming computer to $computerName ..."
#     Rename-Computer -NewName $computerName -Force -Restart
#     Write-Status "Restart required — run script again after reboot" "Yellow"
#     exit
# }

# # -------------------------------
# #  3. Domain Join (if not already)
# # -------------------------------

# Will prompt me to enter in DOMAIN ADMIN credentials. I will and then the script seems to stop running. It looks like it's in a paused state

# if (-not $SkipDomainJoin) {
#     $domain = "vbfa.com"
#     if ((Get-WmiObject Win32_ComputerSystem).Domain -ne $domain) {
#         Write-Status "Joining domain $domain ..."
#         $cred = Get-Credential -Message "Enter DOMAIN ADMIN credentials for join"
#         Add-Computer -DomainName $domain -Credential $cred # -Force -Restart
#         Write-Status "Domain join initiated — rebooting" "Yellow"
#         exit
#     }
#     else {
#         Write-Status "Already domain-joined" "Gray"
#     }
# }

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
#  5. Power settings (High Performance, skip laptops)
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
#  6. Install Applications
# -------------------------------
$jsonUrl = "https://raw.githubusercontent.com/RJ060501/winget-apps-script/refs/heads/main/winget-apps.json" 

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
#  7. Firefox Config & User Profiles
# -------------------------------

Write-Status "Configuring Firefox (homepage, uBlock Origin)..." "Cyan"

$firefoxPath = "${env:ProgramFiles}\Mozilla Firefox\firefox.exe"
if (-not (Test-Path $firefoxPath)) {
    $firefoxPath = "${env:ProgramFiles(x86)}\Mozilla Firefox\firefox.exe"
}

if (-not (Test-Path $firefoxPath)) {
    Write-Status "Firefox not found — skipping Firefox configuration. Is it installed?" "Yellow"
} else {

    # --- Default Browser ---
    # Windows 11 blocks silent default browser changes by design (no script can bypass this).
    # Best approach: open the Settings page so the user can confirm with one click.
    Write-Status "Windows 11 requires user confirmation to set default browser." "Yellow"
    Write-Status "Launching Default Apps settings for the user to confirm Firefox..." "Cyan"
    Start-Process "ms-settings:defaultapps"
    # Optionally pre-register Firefox so it appears at the top of the list:
    # (This writes the ProgId hint — Firefox's own installer usually handles this)
    # NOTE: Windows 11 hashes the ProgId value — you cannot write this manually without
    # triggering a hash mismatch reset. Let the user click through Settings instead.

    # --- Firefox policies.json (uBlock Origin + homepage) ---
    # Official enterprise policy method: https://mozilla.github.io/policy-templates/
    $firefoxPoliciesDir = "${env:ProgramFiles}\Mozilla Firefox\distribution"
    New-Item -Path $firefoxPoliciesDir -ItemType Directory -Force | Out-Null

    $sharepointUrl = "https://theresolutgroup.sharepoint.com/sites/ResolutLandingPage?web=1"

    $policiesJson = @"
{
  "policies": {
    "Homepage": {
      "URL": "$sharepointUrl",
      "Locked": true,
      "StartPage": "homepage-locked"
    },
    "ExtensionSettings": {
      "uBlock0@raymondhill.net": {
        "installation_mode": "force_installed",
        "install_url": "https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/addon-607454-latest.xpi"
      }
    }
  }
}
"@
    # Write policies.json — Firefox reads this on every launch (no restart needed)
    $policiesJson | Set-Content -Path "$firefoxPoliciesDir\policies.json" -Encoding UTF8
    Write-Status "Firefox policies.json written (homepage locked + uBlock Origin force-installed)." "Green"
    Write-Status "uBlock will auto-install on first Firefox launch." "Gray"
}

# --- Remove Edge from taskbar ---
# Windows 11 has no reliable scripting API for taskbar pinning.
$edgeTaskbarKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Taskband"
if (Test-Path $edgeTaskbarKey) {
    Remove-ItemProperty -Path $edgeTaskbarKey -Name "FavoritesResolve" -ErrorAction SilentlyContinue
    Write-Status "Edge taskbar pin cleared (will rebuild on next Explorer restart)." "Gray"
}

# -------------------------------
#  8. Custom / non-winget installs
# -------------------------------

Write-Status "Starting custom installs..." "Cyan"

$CustomDownloads = @(
    "https://github.com/RJ060501/winget-apps-script/releases/download/custom_apps/CTCBIMSuitesMultiUserSetup.msi",
    "https://github.com/RJ060501/winget-apps-script/releases/download/custom_apps/NaviateNexusMultiUserSetup.msi",
    "https://github.com/RJ060501/winget-apps-script/releases/download/custom_apps/setup.exe",
    "https://github.com/RJ060501/winget-apps-script/releases/download/custom_apps/Client_Setup.-.Shortcut.lnk",
    "https://github.com/RJ060501/winget-apps-script/releases/download/custom_apps/SophosSetup.exe",
    "https://github.com/RJ060501/winget-apps-script/releases/download/custom_apps/SophosConnect_2.5.0_GA_IPsec_and_SSLVPN.msi",
    "https://github.com/RJ060501/winget-apps-script/releases/download/custom_apps/HVACSolutionsPro.exe",

    "https://github.com/RJ060501/winget-apps-script/releases/download/custom_apps/AutoCAD_2026_1_English-US_en-US_setup_webinstall.exe",
    "https://github.com/RJ060501/winget-apps-script/releases/download/custom_apps/Revit_2021_Ship_20200715_r4_Win_64bit_di_cs-CZ_setup_webinstall.exe",
    "https://github.com/RJ060501/winget-apps-script/releases/download/custom_apps/Revit_2022_Ship_20210224_RTC_Win_64bit_di_ML_setup_webinstall.exe",
    "https://github.com/RJ060501/winget-apps-script/releases/download/custom_apps/Revit_2023_1_8_0_1_Win_64bit_di_ML_setup_webinstall.exe",
    "https://github.com/RJ060501/winget-apps-script/releases/download/custom_apps/Revit_2024_3_3_ML_setup_webinstall.exe",
    "https://github.com/RJ060501/winget-apps-script/releases/download/custom_apps/Revit_2025_4_2_ML_setup_webinstall.exe",
    "https://github.com/RJ060501/winget-apps-script/releases/download/custom_apps/Revit_2026_2_ML_setup_webinstall.exe"
)



$tempFolder = "$env:TEMP\CustomInstallers"
New-Item -Path $tempFolder -ItemType Directory -Force | Out-Null

foreach ($url in $CustomDownloads) {
    $fileName = [System.IO.Path]::GetFileName($url)
    $localPath = Join-Path $tempFolder $fileName

    Write-Status "Downloading: $fileName" "Yellow"
    & curl.exe -L -o $localPath $url --retry 3 --retry-delay 5 --fail --silent --show-error

    if (Test-Path $localPath) {
        Write-Status "Installing: $fileName" "Green"
        
        $ext = [System.IO.Path]::GetExtension($fileName).ToLower()
        
        if ($ext -eq ".msi") {
            $process = Start-Process msiexec.exe -ArgumentList "/i `"$localPath`" /qn /norestart" -Wait -PassThru
        } else {
            $process = Start-Process $localPath -ArgumentList "/q" -Wait -PassThru
        }

        if ($process.ExitCode -eq 0 -or $process.ExitCode -eq 3010 -or $process.ExitCode -eq 1641) {
            Write-Status "  SUCCESS (exit $($process.ExitCode))" "Green"
        } else {
            Write-Status "  Exit $($process.ExitCode)" "Yellow"
        }
    } else {
        Write-Status "  Download failed for $fileName" "Red"
    }
}

Remove-Item $tempFolder -Recurse -Force -ErrorAction SilentlyContinue
Write-Status "Custom installs complete." "Cyan"

# -------------------------------
#  9. Windows Updates
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


# --- Manual steps reminder ---
Write-Status "Reminder: Taskbar items will need to be removed manually." "Yellow"
Write-Status "Reminder: Startup items should be reviewed manually in Task Manager > Startup." "Yellow"

$ScriptStopwatch.Stop()
$elapsed = $ScriptStopwatch.Elapsed
Write-Status ("Total script time: {0:hh\:mm\:ss}" -f $elapsed) "Cyan"