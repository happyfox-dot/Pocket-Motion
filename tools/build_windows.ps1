param([string]$FlutterPath = '', [switch]$SkipChecks)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $projectRoot
if (-not $FlutterPath) {
    $localFlutter = Join-Path $projectRoot '.tools\flutter\bin\flutter.bat'
    if (Test-Path -LiteralPath $localFlutter) { $FlutterPath = $localFlutter }
    else { $FlutterPath = (Get-Command flutter -ErrorAction Stop).Source }
}

function Repair-PluginJunctions {
    $manifest = Join-Path $projectRoot '.flutter-plugins-dependencies'
    if (-not (Test-Path -LiteralPath $manifest)) { return }
    $plugins = Get-Content -LiteralPath $manifest -Raw | ConvertFrom-Json
    $linkRoot = Join-Path $projectRoot 'windows\flutter\ephemeral\.plugin_symlinks'
    New-Item -ItemType Directory -Path $linkRoot -Force | Out-Null
    foreach ($plugin in $plugins.plugins.windows) {
        if ($plugin.name -notmatch '^[A-Za-z0-9_]+$') { throw 'Invalid plugin name' }
        $linkPath = Join-Path $linkRoot $plugin.name
        if (-not (Test-Path -LiteralPath $linkPath)) {
            # Junctions do not require enabling Windows Developer Mode.
            New-Item -ItemType Junction -Path $linkPath -Target $plugin.path | Out-Null
        }
    }
}

& $FlutterPath pub get
if ($LASTEXITCODE -ne 0) {
    Repair-PluginJunctions
    & $FlutterPath pub get
    if ($LASTEXITCODE -ne 0) { throw 'Dependency setup failed; see output above.' }
}
if (-not $SkipChecks) {
    & $FlutterPath analyze --no-pub
    if ($LASTEXITCODE -ne 0) { throw 'Code analysis failed.' }
    & $FlutterPath test --no-pub
    if ($LASTEXITCODE -ne 0) { throw 'Tests failed.' }
}
Repair-PluginJunctions
& $FlutterPath build windows --release --no-pub
if ($LASTEXITCODE -ne 0) { throw 'Windows build failed.' }
$releaseDir = Join-Path $projectRoot 'build\windows\x64\runner\Release'
$destination = Join-Path $projectRoot 'dist\Pocket4PPort'
New-Item -ItemType Directory -Path $destination -Force | Out-Null
Get-ChildItem -LiteralPath $releaseDir | Copy-Item -Destination $destination -Recurse -Force
foreach ($toolName in @('ffmpeg', 'ffprobe')) {
    $tool = (Get-Command $toolName -ErrorAction Stop).Source
    Copy-Item -LiteralPath $tool -Destination (Join-Path $destination "$toolName.exe") -Force
}
Copy-Item -LiteralPath (Join-Path $projectRoot 'README.md') -Destination $destination -Force
Write-Output "Ready: $(Join-Path $destination 'PocketMotion.exe')"
