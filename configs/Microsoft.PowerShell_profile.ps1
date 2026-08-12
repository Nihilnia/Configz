# PowerShell Profile Template
Set-Alias -Name ll -Value Get-ChildItem

function prompt {
    $path = (Get-Location).Path
    Write-Host "PS $path" -NoNewline -ForegroundColor Green
    return "> "
}

Write-Host "PowerShell profile loaded." -ForegroundColor Cyan

# Initialize Starship Prompt (Requires Starship to be installed)
if (Get-Command starship -ErrorAction SilentlyContinue) {
    Invoke-Expression (&starship init powershell)
} else {
    Write-Host "Starship is not installed. Run winget_install.ps1 to install it." -ForegroundColor Yellow
}
