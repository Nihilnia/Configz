# PowerShell Profile Template
Set-Alias -Name ll -Value Get-ChildItem

function prompt {
    $path = (Get-Location).Path
    Write-Host "PS $path" -NoNewline -ForegroundColor Green
    return "> "
}

Write-Host "PowerShell profile loaded." -ForegroundColor Cyan
