# setup-apps.ps1

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