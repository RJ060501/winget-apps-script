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
# Sophos - (adjust path)
# if (-not (Get-Service -Name "Sophos*" -ErrorAction SilentlyContinue)) {
#     Write-Status "Installing Sophos Endpoint..."
#     $sophosPath = "\\Vbs6\data\Programs\Sophos Cloud Antivirus\SophosSetup.exe"
#     if (Test-Path $sophosPath) {
#         Start-Process $sophosPath -ArgumentList "--quiet" -Wait
#     } else {
#         Write-Status "Sophos installer not found at $sophosPath" "Yellow"
#     }
# }

Write-Status "Downloading & installing Autodesk products from GitHub Releases (AutoCAD 2026 first, then Revit 2021→2026)..." "Cyan"

#https://github.com/RJ060501/winget-apps-script/releases/tag/custom_apps
# === YOUR RELEASE ASSETS URLs (update once after uploading) ===
$autodeskDownloads = @(
    "https://github.com/RJ060501/winget-apps-script/releases/tag/custom_apps/AutoCAD_2026_English-US-en-US_setup_webinstall.exe",
    "https://github.com/RJ060501/winget-apps-script/releases/tag/custom_apps/Revit_2021_Ship_20200715_r4_Win_64bit_di_cs-CZ_setup_webinstall.exe",
    "https://github.com/RJ060501/winget-apps-script/releases/tag/custom_apps/Revit_2022_Ship_20210224_RTC_Win_64bit_di_cs-CZ_setup_webinstall.exe",
    "https://github.com/RJ060501/winget-apps-script/releases/tag/custom_apps/Revit_2023_1_8_0_1_Win_64bit_di_ML_setup_webinstall.exe",
    "https://github.com/RJ060501/winget-apps-script/releases/tag/custom_apps/Revit_2024_3_3_ML_setup_webinstall.exe",
    "https://github.com/RJ060501/winget-apps-script/releases/tag/custom_apps/Revit_2025_4_2_ML_setup_webinstall.exe",
    "https://github.com/RJ060501/winget-apps-script/releases/tag/custom_apps/Revit_2026_2_ML_setup_webinstall.exe"
)

#A folder that gets created and deleted at the end of the process
$tempFolder = "$env:TEMP\AutodeskInstallers"
New-Item -Path $tempFolder -ItemType Directory -Force | Out-Null

foreach ($url in $autodeskDownloads) {
    $fileName = [System.IO.Path]::GetFileName($url)
    $localPath = Join-Path $tempFolder $fileName
    $logFile = "$env:TEMP\Autodesk-$($fileName -replace '\.exe$','')-install.log"

    Write-Status "Downloading: $fileName" "Yellow"

    $downloadSuccess = $false
    $maxRetries = 3

    for ($retry = 1; $retry -le $maxRetries; $retry++) {
        try {
            # Suppress progress bar for faster/safer downloads
            $ProgressPreference = 'SilentlyContinue'

            # Prefer curl.exe (built-in, more reliable for GitHub large-ish files)
            & curl.exe -L -o $localPath $url --retry 3 --retry-delay 5 --fail --silent --show-error
            if (Test-Path $localPath) {
                Write-Status "  Download success on attempt $retry" "Green"
                $downloadSuccess = $true
                break
            }
        }
        catch {
            Write-Status "  Retry $retry/$maxRetries failed: $_" "Yellow"
            Start-Sleep -Seconds 10
        }
        finally {
            $ProgressPreference = 'Continue'
        }
    }

    if (-not $downloadSuccess) {
        Write-Status "  Failed to download $fileName after retries. Skipping install." "Red"
        continue
    }

    Write-Status "Installing: $fileName" "Green"

    try {
        $process = Start-Process -FilePath $localPath `
            -ArgumentList "-q" `
            -Verb RunAs `
            -Wait -PassThru -NoNewWindow `
            -RedirectStandardOutput $logFile `
            -RedirectStandardError "$logFile.err" `
            -ErrorAction Stop

        $exit = $process.ExitCode
        if ($exit -eq 0 -or $exit -eq 3010 -or $exit -eq 1641) {
            Write-Status "  SUCCESS (exit $exit)" "Green"
        } else {
            Write-Status "  Exit $exit — check log: $logFile" "Yellow"
        }
    }
    catch {
        Write-Status "  Install error: $_" "Red"
    }

    Start-Sleep -Seconds 30  # breathing room between large installs
}

Remove-Item $tempFolder -Recurse -Force -ErrorAction SilentlyContinue

# Reboot check...
if (Test-PendingReboot) {
    Write-Status "Reboot pending after Autodesk — restarting in 60s..." "Yellow"
    Start-Sleep -Seconds 60
    Restart-Computer -Force
}

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