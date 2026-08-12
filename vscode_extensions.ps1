param (
    [switch]$Export,
    [switch]$Import
)

$extFile = "C:\Configz\configs\vscode_extensions.txt"

if ($Export) {
    Write-Host "Exporting VS Code extensions to $extFile..."
    if (Get-Command code -ErrorAction SilentlyContinue) {
        code --list-extensions > $extFile
        Write-Host "Extensions exported successfully!" -ForegroundColor Green
    } else {
        Write-Host "Error: VS Code ('code' command) not found in PATH." -ForegroundColor Red
    }
} elseif ($Import) {
    Write-Host "Importing VS Code extensions from $extFile..."
    if (-not (Test-Path $extFile)) {
        Write-Host "Error: $extFile not found." -ForegroundColor Red
        return
    }
    
    if (Get-Command code -ErrorAction SilentlyContinue) {
        $extensions = Get-Content $extFile
        foreach ($ext in $extensions) {
            Write-Host "Installing $ext..."
            code --install-extension $ext --force
        }
        Write-Host "Extensions imported successfully!" -ForegroundColor Green
    } else {
        Write-Host "Error: VS Code ('code' command) not found in PATH." -ForegroundColor Red
    }
} else {
    Write-Host "Usage: .\vscode_extensions.ps1 -Export OR .\vscode_extensions.ps1 -Import"
}
