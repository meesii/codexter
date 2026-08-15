param(
    [Parameter(Mandatory = $true)][string]$Version,
    [Parameter(Mandatory = $true)][string]$Tag,
    [string]$Repository = 'meesii/codexter',
    [string]$DistDir = 'dist',
    [string]$AssetBaseUrl = ''
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$distPath = if ([IO.Path]::IsPathRooted($DistDir)) { $DistDir } else { Join-Path $projectRoot $DistDir }
$setupName = "Codexter-$Version-Setup.exe"
$zipName = "Codexter-$Version-windows-x64.zip"
$setupPath = Join-Path $distPath $setupName
$zipPath = Join-Path $distPath $zipName

if (-not (Test-Path $setupPath)) { throw "Installer not found: $setupPath" }
if (-not (Test-Path $zipPath)) { throw "Portable ZIP not found: $zipPath" }

if (-not $AssetBaseUrl) {
    $AssetBaseUrl = "https://github.com/$Repository/releases/download/$Tag"
}
$AssetBaseUrl = $AssetBaseUrl.TrimEnd('/')

$manifest = [ordered]@{
    schema = 1
    version = $Version
    tag = $Tag
    published_at = [DateTime]::UtcNow.ToString('o')
    release_url = "https://github.com/$Repository/releases/tag/$Tag"
    windows = [ordered]@{
        installer_url = "$AssetBaseUrl/$setupName"
        installer_sha256 = (Get-FileHash $setupPath -Algorithm SHA256).Hash.ToLowerInvariant()
        portable_url = "$AssetBaseUrl/$zipName"
        portable_sha256 = (Get-FileHash $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
    }
}

$output = Join-Path $distPath 'latest.json'
$manifest | ConvertTo-Json -Depth 4 | Set-Content -Path $output -Encoding utf8NoBOM
Write-Host "==> Update manifest: $output"
