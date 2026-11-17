param([string]$CrtDirectory = '')
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $projectRoot
$utf8 = New-Object System.Text.UTF8Encoding($false)
$spec = Get-Content -LiteralPath 'pubspec.yaml' -Raw
$match = [regex]::Match($spec, '(?m)^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$')
if (-not $match.Success) { throw 'Expected a semantic version and build number in pubspec.yaml.' }
$version = $match.Groups[1].Value
$sourceDir = Join-Path $projectRoot 'dist\Pocket4PPort'
$exe = Get-Item -LiteralPath (Join-Path $sourceDir 'PocketMotion.exe')
if ($exe.VersionInfo.ProductVersion -ne "$version+$($match.Groups[2].Value)") {
    throw 'The executable version differs from pubspec.yaml. Rebuild before packaging.'
}
$required = @('PocketMotion.exe', 'flutter_windows.dll', 'ffmpeg.exe', 'ffprobe.exe',
    'libmpv-2.dll', 'media_kit_video_plugin.dll', 'media_kit_libs_windows_video_plugin.dll',
    'data\app.so', 'data\icudtl.dat', 'data\flutter_assets\assets\watermarks\pocket4p_device.png')
foreach ($relative in $required) {
    if (-not (Test-Path -LiteralPath (Join-Path $sourceDir $relative) -PathType Leaf)) {
        throw "Missing runtime file: $relative"
    }
}
if (-not $CrtDirectory) {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    $vsPath = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    if (-not $vsPath) { throw 'Visual C++ Build Tools not found. Pass -CrtDirectory explicitly.' }
    $redistRoot = Join-Path $vsPath 'VC\Redist\MSVC'
    $redist = Get-ChildItem -LiteralPath $redistRoot -Directory |
        Where-Object { $_.Name -match '^\d+\.\d+\.\d+$' } |
        Sort-Object { [version]$_.Name } -Descending | Select-Object -First 1
    $CrtDirectory = Join-Path $redist.FullName 'x64\Microsoft.VC143.CRT'
}
foreach ($name in @('msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll')) {
    if (-not (Test-Path -LiteralPath (Join-Path $CrtDirectory $name))) { throw "Missing C++ runtime: $name" }
}
$packageName = "PocketMotion-$version-windows-x64"
$releaseDir = Join-Path $projectRoot 'dist\releases'
$stage = Join-Path $releaseDir $packageName
$zipPath = Join-Path $releaseDir "$packageName.zip"
if ((Test-Path -LiteralPath $stage) -or (Test-Path -LiteralPath $zipPath)) {
    throw 'This release already has staging/output files. Use a new version; existing releases are never overwritten.'
}
New-Item -ItemType Directory -Path $stage -Force | Out-Null
# Copy only runtime binaries and Flutter data, never local samples or settings.
Get-ChildItem -LiteralPath $sourceDir -File | Where-Object { $_.Extension -in @('.exe', '.dll') } |
    Copy-Item -Destination $stage
Copy-Item -LiteralPath (Join-Path $sourceDir 'data') -Destination $stage -Recurse
Get-ChildItem -LiteralPath $CrtDirectory -Filter '*.dll' -File | Copy-Item -Destination $stage
Copy-Item -LiteralPath 'README.md' -Destination $stage
New-Item -ItemType Directory -Path (Join-Path $stage 'assets') | Out-Null
Copy-Item -LiteralPath 'assets\SOURCES.md' -Destination (Join-Path $stage 'assets')
$licenses = Join-Path $stage 'licenses'
New-Item -ItemType Directory -Path $licenses | Out-Null
$ffmpegRoot = Split-Path -Parent (Split-Path -Parent (Get-Command ffmpeg -ErrorAction Stop).Source)
Copy-Item -LiteralPath (Join-Path $ffmpegRoot 'LICENSE') -Destination (Join-Path $licenses 'FFmpeg-GPL.txt')
Copy-Item -LiteralPath (Join-Path $ffmpegRoot 'README.txt') -Destination (Join-Path $licenses 'FFmpeg-build.txt')
$flutter = (Get-Content -LiteralPath '.dart_tool\package_config.json' -Raw | ConvertFrom-Json).packages |
    Where-Object name -eq 'flutter'
$flutterPackage = ([Uri]$flutter.rootUri).LocalPath
Copy-Item -LiteralPath (Join-Path (Split-Path -Parent (Split-Path -Parent $flutterPackage.TrimEnd('/\'))) 'LICENSE') -Destination (Join-Path $licenses 'Flutter-LICENSE.txt')
$plugins = Get-Content -LiteralPath '.flutter-plugins-dependencies' -Raw | ConvertFrom-Json
$mediaKit = $plugins.plugins.windows | Where-Object name -eq 'media_kit_libs_windows_video'
Copy-Item -LiteralPath (Join-Path $mediaKit.path 'LICENSE') -Destination (Join-Path $licenses 'media-kit-LICENSE.txt')
Copy-Item -LiteralPath 'docs\THIRD_PARTY_NOTICES.md' -Destination $stage
Copy-Item -LiteralPath 'docs\WINDOWS_QUICK_START.txt' -Destination (Join-Path $stage 'START_HERE.txt')
$commit = (git rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0) { throw 'Cannot identify source commit.' }
$metadata = [ordered]@{
    version = "$version+$($match.Groups[2].Value)"
    source_commit = $commit
    repository = 'https://github.com/happyfox-dot/Pocket-Motion'
    platform = 'windows-x64'
    built_at_utc = [DateTime]::UtcNow.ToString('o')
}
[IO.File]::WriteAllText((Join-Path $stage 'BUILD_INFO.json'), ($metadata | ConvertTo-Json), $utf8)
$fileHashes = Get-ChildItem -LiteralPath $stage -Recurse -File | Sort-Object FullName | ForEach-Object {
    $relative = $_.FullName.Substring($stage.Length + 1).Replace('\', '/')
    "$((Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLower())  $relative"
}
[IO.File]::WriteAllLines((Join-Path $stage 'FILES.sha256'), [string[]]$fileHashes, $utf8)
Add-Type -AssemblyName System.IO.Compression.FileSystem
[IO.Compression.ZipFile]::CreateFromDirectory($stage, $zipPath, [IO.Compression.CompressionLevel]::Optimal, $true)
$archiveHash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLower()
[IO.File]::WriteAllText("$zipPath.sha256", "$archiveHash  $packageName.zip`n", $utf8)
Write-Output "Packaged: $zipPath"
Write-Output "SHA256: $archiveHash"
