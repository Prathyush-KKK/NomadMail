param(
    [string]$Version = "",
    [string]$OutputDir = "",
    [switch]$AllowDirty
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$versionPath = Join-Path $repoRoot "VERSION"

if ([string]::IsNullOrWhiteSpace($Version)) {
    if (-not (Test-Path -LiteralPath $versionPath)) {
        throw "VERSION file is missing. Pass -Version or create VERSION."
    }
    $Version = (Get-Content -LiteralPath $versionPath -Raw).Trim()
}

if ($Version -notmatch '^\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?$') {
    throw "Version must use semantic form like 0.1.0 or 0.1.0-beta.1."
}

if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-Path $repoRoot "dist"
}
$resolvedOutputDir = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputDir)
New-Item -ItemType Directory -Force -Path $resolvedOutputDir | Out-Null

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw "git is required for release packaging so only tracked product files are included."
}

$trackedFiles = @(& git -C $repoRoot ls-files)
if ($trackedFiles.Count -eq 0) {
    throw "No tracked files found. Release packaging must run inside the NomadInbox git repository."
}

$dirtyLines = @(& git -C $repoRoot status --porcelain=v1)
$isDirty = $dirtyLines.Count -gt 0
if ($isDirty -and -not $AllowDirty) {
    throw "Working tree has uncommitted changes. Commit or pass -AllowDirty for a local test package."
}

$commit = (& git -C $repoRoot rev-parse HEAD).Trim()
$packageName = "NomadInbox-$Version-windows"
$stagingRoot = Join-Path $repoRoot "target\release\$packageName"
if (Test-Path -LiteralPath $stagingRoot) {
    Remove-Item -LiteralPath $stagingRoot -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $stagingRoot | Out-Null

$excludePatterns = @(
    '^data/',
    '^-DataDir/',
    '^runtime/',
    '^target/',
    '^dist/',
    '^logs/',
    '^downloads/',
    '^mail-exports/',
    '^import-staging/',
    '^\.kiro/',
    '^AGENTS\.continuity\.md$',
    '^CLAUDE\.continuity\.md$',
    '^MAYOR_',
    '^scripts/_.*\.ps1$',
    '^config/accounts\.json$',
    '^config/nomad-inbox\.ps1$',
    'client_secret',
    'token-cache',
    'credentials',
    '\.(mbox|eml|pst|msg|sqlite|sqlite3|db|log|jsonl)$'
)

$includedFiles = New-Object System.Collections.Generic.List[string]
foreach ($relative in $trackedFiles) {
    $normalized = ($relative -replace '\\', '/')
    $excluded = $false
    foreach ($pattern in $excludePatterns) {
        if ($normalized -match $pattern) {
            $excluded = $true
            break
        }
    }
    if ($excluded) { continue }

    $sourcePath = Join-Path $repoRoot ($normalized -replace '/', '\')
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) { continue }

    $destinationPath = Join-Path $stagingRoot ($normalized -replace '/', '\')
    $destinationDir = Split-Path -Parent $destinationPath
    New-Item -ItemType Directory -Force -Path $destinationDir | Out-Null
    Copy-Item -LiteralPath $sourcePath -Destination $destinationPath -Force
    $includedFiles.Add($normalized) | Out-Null
}

foreach ($requiredPackageFile in @("VERSION")) {
    if ($includedFiles -contains $requiredPackageFile) { continue }
    $sourcePath = Join-Path $repoRoot $requiredPackageFile
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
        throw "Required release file is missing: $requiredPackageFile"
    }
    $destinationPath = Join-Path $stagingRoot $requiredPackageFile
    Copy-Item -LiteralPath $sourcePath -Destination $destinationPath -Force
    $includedFiles.Add($requiredPackageFile) | Out-Null
}

$trayOutputPath = Join-Path $stagingRoot "target\NomadInboxTray\NomadInboxTray.exe"
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot "scripts\build-nomad-inbox-tray.ps1") -OutputPath $trayOutputPath | Out-Null
$includedFiles.Add("target/NomadInboxTray/NomadInboxTray.exe") | Out-Null

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$installScriptPath = Join-Path $stagingRoot "install.ps1"
$installScript = @'
param(
    [string]$DataDir = "",
    [string]$InstallRoot = "",
    [switch]$StartTray,
    [switch]$RegisterStartup,
    [switch]$ShowPopup
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$cli = Join-Path $repoRoot "scripts\nomad-inbox.ps1"
$args = @("install", "windows-helper")
if (-not [string]::IsNullOrWhiteSpace($DataDir)) {
    $args += @("--data-dir", $DataDir)
}
if (-not [string]::IsNullOrWhiteSpace($InstallRoot)) {
    $args += @("--install-root", $InstallRoot)
}
if ($StartTray) {
    $args += "--start-tray"
}
if ($RegisterStartup) {
    $args += "--register-startup"
}
if ($ShowPopup) {
    $args += "--show-popup"
}
& $cli @args
'@
[System.IO.File]::WriteAllText($installScriptPath, $installScript, $utf8NoBom)
$includedFiles.Add("install.ps1") | Out-Null

$fileEntries = @(
    Get-ChildItem -LiteralPath $stagingRoot -Recurse -File -Force |
        Where-Object { $_.FullName -ne (Join-Path $stagingRoot "RELEASE_MANIFEST.json") } |
        ForEach-Object {
            $relativePath = $_.FullName.Substring($stagingRoot.Length).TrimStart('\') -replace '\\', '/'
            [pscustomobject]@{
                path = $relativePath
                sizeBytes = $_.Length
                sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
            }
        }
)

$manifest = [pscustomobject]@{
    product = "NomadInbox"
    package = $packageName
    version = $Version
    platform = "windows"
    createdAt = (Get-Date).ToUniversalTime().ToString("o")
    sourceRepo = $repoRoot
    commit = $commit
    dirty = $isDirty
    dirtyEntries = $dirtyLines
    includedFileCount = $fileEntries.Count
    installCommand = ".\install.ps1 -StartTray -RegisterStartup -ShowPopup"
    notes = @(
        "Package contents are copied from git-tracked product files only.",
        "Runtime data, local account config, OAuth secrets, token caches, Kiro scratch files, and mail exports are excluded.",
        "The bundled install.ps1 installs the Windows helper, can start the compiled tray, and can register the tray in Windows Startup after user approval."
    )
    files = $fileEntries
}

$manifestPathInPackage = Join-Path $stagingRoot "RELEASE_MANIFEST.json"
[System.IO.File]::WriteAllText($manifestPathInPackage, ($manifest | ConvertTo-Json -Depth 50), $utf8NoBom)

$zipPath = Join-Path $resolvedOutputDir "$packageName.zip"
if (Test-Path -LiteralPath $zipPath) {
    Remove-Item -LiteralPath $zipPath -Force
}
Compress-Archive -Path (Join-Path $stagingRoot "*") -DestinationPath $zipPath -Force

$zipHash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
$sidecarManifest = [pscustomobject]@{
    product = "NomadInbox"
    package = $packageName
    version = $Version
    platform = "windows"
    createdAt = $manifest.createdAt
    sourceRepo = $repoRoot
    commit = $commit
    dirty = $isDirty
    archivePath = $zipPath
    archiveSha256 = $zipHash
    includedFileCount = $fileEntries.Count
    installCommand = ".\install.ps1 -StartTray -RegisterStartup -ShowPopup"
}
$sidecarManifestPath = Join-Path $resolvedOutputDir "$packageName.manifest.json"
[System.IO.File]::WriteAllText($sidecarManifestPath, ($sidecarManifest | ConvertTo-Json -Depth 20), $utf8NoBom)

[pscustomobject]@{
    status = "ok"
    service = "NomadInbox"
    package = $packageName
    version = $Version
    platform = "windows"
    dirty = $isDirty
    packagePath = $zipPath
    manifestPath = $sidecarManifestPath
    stagingRoot = $stagingRoot
    archiveSha256 = $zipHash
    includedFileCount = $fileEntries.Count
    installCommand = ".\install.ps1 -StartTray -RegisterStartup -ShowPopup"
} | ConvertTo-Json -Depth 20
