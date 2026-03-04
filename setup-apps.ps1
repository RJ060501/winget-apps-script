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
    } else {
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

Write-Host "Setup complete! Some apps may require a restart or manual login/setup." -ForegroundColor Cyan