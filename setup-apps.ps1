# setup-apps.ps1
$jsonUrl = "https://gist.githubusercontent.com/.../winget-apps.json"  # your URL here
$tempJson = "$env:TEMP\winget-import.json"

Write-Host "Downloading app list..."
Invoke-WebRequest -Uri $jsonUrl -OutFile $tempJson

Write-Host "Installing apps via winget..."
winget import -i $tempJson --accept-package-agreements --accept-source-agreements --ignore-versions --disable-interactivity

Remove-Item $tempJson -ErrorAction SilentlyContinue
Write-Host "Done! Some apps may require restart or manual setup."