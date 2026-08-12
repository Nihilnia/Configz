$ErrorActionPreference = "Continue"

Write-Host "Installing apps via Winget..." -ForegroundColor Cyan

$apps = @(
    "Mozilla.Firefox"
    "Mozilla.Firefox.DeveloperEdition"
    "Mozilla.Firefox.Nightly"
    "Discord.Discord"
    "Spotify.Spotify"
    "Deezer.Deezer"
    "Microsoft.VisualStudioCode"
    "Valve.Steam"
    "GitHub.GitHubDesktop"
    "OpenJS.NodeJS"
    "Obsidian.Obsidian"
    "Notepad++.Notepad++"
    "RARLab.WinRAR"
    "7zip.7zip"
    "Gyan.FFmpeg"
    "yt-dlp.yt-dlp"
    "Starship.Starship"
)

foreach ($app in $apps) {
    Write-Host "Installing $app..."
    winget install --id $app --exact --accept-package-agreements --accept-source-agreements --silent
}

Write-Host ""
Write-Host "NOTE: Lyra and Vega need to be downloaded manually or added with custom direct links once available." -ForegroundColor Yellow
Write-Host "NOTE: Antigravity CLI does not currently have a known public Winget ID. Please install manually if it is a private package." -ForegroundColor Yellow
Write-Host ""
Write-Host "Winget installation complete!" -ForegroundColor Green
