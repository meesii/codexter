param(
    [switch]$SkipAnalyze,
    [switch]$SkipInstaller,
    [string]$UpdateManifestUrl = ''
)

$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$releaseDir = Join-Path $projectRoot 'build\windows\x64\runner\Release'
$distDir = Join-Path $projectRoot 'dist'
$pubspecPath = Join-Path $projectRoot 'pubspec.yaml'
$installerScript = Join-Path $projectRoot 'installer\windows\codexter.iss'
$toolsDir = Join-Path $projectRoot '.tools'
$innoVersion = '7.0.2'
$innoDir = Join-Path $toolsDir "inno-$innoVersion-x64"
$isccPath = Join-Path $innoDir 'ISCC.exe'
$innoInstaller = Join-Path $toolsDir "innosetup-$innoVersion-x64.exe"
$innoUrl = "https://github.com/jrsoftware/issrc/releases/download/is-7_0_2/innosetup-$innoVersion-x64.exe"

function Ensure-InnoSetup {
    if (Test-Path $isccPath) { return }

    New-Item -ItemType Directory -Path $toolsDir -Force | Out-Null
    if (-not (Test-Path $innoInstaller)) {
        Write-Host "==> Downloading Inno Setup $innoVersion..."
        Invoke-WebRequest -Uri $innoUrl -OutFile $innoInstaller -UseBasicParsing
    }

    Write-Host '==> Preparing portable Inno Setup compiler...'
    $process = Start-Process -FilePath $innoInstaller -ArgumentList @(
        '/VERYSILENT',
        '/SUPPRESSMSGBOXES',
        '/NORESTART',
        '/PORTABLE=1',
        "/DIR=$innoDir"
    ) -Wait -PassThru
    if ($process.ExitCode -ne 0 -or -not (Test-Path $isccPath)) {
        throw "Failed to prepare Inno Setup (exit $($process.ExitCode))"
    }
}

Push-Location $projectRoot
try {
    $versionLine = Select-String -Path $pubspecPath -Pattern '^version:\s*(.+)$' | Select-Object -First 1
    if (-not $versionLine) { throw 'Version not found in pubspec.yaml' }
    $fullVersion = $versionLine.Matches[0].Groups[1].Value.Trim()
    $version = $fullVersion.Split('+')[0]

    Write-Host "==> Building Codexter $fullVersion"
    Write-Host '==> Enabling Windows desktop support...'
    flutter config --enable-windows-desktop
    if ($LASTEXITCODE -ne 0) { throw 'flutter config --enable-windows-desktop failed' }

    Write-Host '==> Resolving Flutter dependencies...'
    flutter pub get
    if ($LASTEXITCODE -ne 0) { throw 'flutter pub get failed' }

    if (-not $SkipAnalyze) {
        Write-Host '==> Running flutter analyze...'
        flutter analyze
        if ($LASTEXITCODE -ne 0) { throw 'flutter analyze failed' }
    }

    Write-Host '==> Building Windows release...'
    $buildArgs = @('build', 'windows', '--release')
    if ($UpdateManifestUrl) {
        $buildArgs += "--dart-define=UPDATE_MANIFEST_URL=$UpdateManifestUrl"
        Write-Host "==> Update manifest: $UpdateManifestUrl"
    }
    flutter @buildArgs
    if ($LASTEXITCODE -ne 0) { throw 'flutter build windows --release failed' }

    if (-not (Test-Path $releaseDir)) {
        throw "Release directory not found: $releaseDir"
    }

    New-Item -ItemType Directory -Path $distDir -Force | Out-Null
    $archivePath = Join-Path $distDir "Codexter-$version-windows-x64.zip"
    if (Test-Path $archivePath) { Remove-Item $archivePath -Force }

    Write-Host '==> Packaging portable ZIP...'
    Compress-Archive -Path (Join-Path $releaseDir '*') -DestinationPath $archivePath -CompressionLevel Optimal

    if (-not $SkipInstaller) {
        Ensure-InnoSetup
        Write-Host '==> Building Setup.exe...'
        & $isccPath "/DAppVersion=$version" $installerScript
        if ($LASTEXITCODE -ne 0) { throw 'Inno Setup compilation failed' }
    }

    Write-Host '==> Build artifacts:'
    Get-ChildItem $distDir -File | Where-Object {
        $_.Name -like "Codexter-$version-*"
    } | ForEach-Object {
        $sizeMb = [math]::Round($_.Length / 1MB, 2)
        Write-Host "    $($_.Name) ($sizeMb MB)"
    }
}
finally {
    Pop-Location
}
