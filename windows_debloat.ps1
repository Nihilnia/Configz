Write-Host "Debloating Windows and applying privacy tweaks..." -ForegroundColor Cyan

# 1. Disable Telemetry
Write-Host "Disabling Telemetry..."
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name "AllowTelemetry" -Value 0 -ErrorAction SilentlyContinue

# 2. Disable Bing Web Search in Start Menu
Write-Host "Disabling Bing Web Search in Start Menu..."
$searchPath = "HKCU:\SOFTWARE\Policies\Microsoft\Windows\Explorer"
if (-not (Test-Path $searchPath)) { New-Item -Path $searchPath -Force | Out-Null }
Set-ItemProperty -Path $searchPath -Name "DisableSearchBoxSuggestions" -Value 1 -ErrorAction SilentlyContinue

# 3. Disable Lock Screen Ads/Tips
Write-Host "Disabling Lock Screen Ads..."
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "RotatingLockScreenOverlayEnabled" -Value 0 -ErrorAction SilentlyContinue
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "SubscribedContent-338387Enabled" -Value 0 -ErrorAction SilentlyContinue

# 4. Uninstall standard bloatware AppxPackages
Write-Host "Uninstalling common bloatware apps..."
$bloatApps = @(
    "*BingNews*",
    "*Microsoft3DViewer*",
    "*ZuneVideo*",
    "*WindowsFeedbackHub*",
    "*GetHelp*",
    "*MicrosoftOfficeHub*",
    "*SkypeApp*",
    "*XboxApp*",
    "*YourPhone*",
    "*CandyCrush*",
    "*TikTok*",
    "*Disney*"
)

foreach ($app in $bloatApps) {
    Get-AppxPackage -Name $app -AllUsers | Remove-AppxPackage -ErrorAction SilentlyContinue
}

Write-Host "Debloat script complete! (Some changes may require a restart to fully apply)." -ForegroundColor Green
