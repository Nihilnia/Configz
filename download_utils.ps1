$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$destDir = "C:\Configz\downloadedz"
if (-not (Test-Path $destDir)) {
    New-Item -ItemType Directory -Force -Path $destDir | Out-Null
}

# Helper function for GitHub latest release
function Get-GitHubLatestAssetUrl {
    param($repo, $match)
    $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/releases/latest"
    $asset = $release.assets | Where-Object { $_.name -match $match } | Select-Object -First 1
    if ($asset) {
        Write-Host "Found asset: $($asset.name)"
        return @($asset.browser_download_url, $asset.name)
    }
    return $null
}

$tools = @()

$res = Get-GitHubLatestAssetUrl -repo "microsoft/PowerToys" -match "PowerToysSetup-.*-x64\.exe"
if ($res) { $tools += ,$res }

$res = Get-GitHubLatestAssetUrl -repo "ShareX/ShareX" -match "ShareX-.*-setup\.exe"
if ($res) { $tools += ,$res }

$res = Get-GitHubLatestAssetUrl -repo "git-for-windows/git" -match "Git-.*-64-bit\.exe"
if ($res) { $tools += ,$res }

$res = Get-GitHubLatestAssetUrl -repo "notepad-plus-plus/notepad-plus-plus" -match "npp\..*\.Installer\.x64\.exe"
if ($res) { $tools += ,$res }

$tools += ,@("https://download.sysinternals.com/files/SysinternalsSuite.zip", "SysinternalsSuite.zip")
$tools += ,@("https://diskanalyzer.com/files/wiztree_4_32_setup.exe", "wiztree_4_32_setup.exe")

foreach ($tool in $tools) {
    $url = $tool[0]
    $name = $tool[1]
    Write-Host "Downloading $name..."
    try {
        Invoke-WebRequest -Uri $url -OutFile "$destDir\$name"
    } catch {
        Write-Host "Failed to download $name"
    }
}
Write-Host "Downloads complete."
