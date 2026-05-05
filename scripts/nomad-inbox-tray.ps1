param(
    [string]$RepoRoot = "",
    [string]$DataDir = "",
    [switch]$NoBuild,
    [switch]$Wait
)

$ErrorActionPreference = "Stop"

function ConvertTo-NomadInboxProcessArgument {
    param([AllowNull()][string]$Value)

    if ($null -eq $Value) { return '""' }
    if ($Value -notmatch '[\s"]') { return $Value }

    $escaped = $Value -replace '"', '\"'
    $escaped = $escaped -replace '(\\+)$', '$1$1'
    return '"' + $escaped + '"'
}

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = Split-Path -Parent $PSScriptRoot
}
$RepoRoot = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($RepoRoot)

if ([string]::IsNullOrWhiteSpace($DataDir)) {
    $DataDir = if ([string]::IsNullOrWhiteSpace($env:NOMADINBOX_DATA_DIR)) {
        Join-Path $RepoRoot "data"
    } else {
        $env:NOMADINBOX_DATA_DIR
    }
}
$DataDir = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($DataDir)

$exePath = if ([string]::IsNullOrWhiteSpace($env:NOMADINBOX_TRAY_EXE)) {
    Join-Path $RepoRoot "target\NomadInboxTray\NomadInboxTray.exe"
} else {
    $env:NOMADINBOX_TRAY_EXE
}
$exePath = [System.IO.Path]::GetFullPath($exePath)
$sourcePath = Join-Path $RepoRoot "src\NomadInbox.Tray\NomadInboxTray.cs"
$buildScript = Join-Path $RepoRoot "scripts\build-nomad-inbox-tray.ps1"

$needsBuild = -not (Test-Path -LiteralPath $exePath)
if (-not $needsBuild -and (Test-Path -LiteralPath $sourcePath)) {
    $needsBuild = (Get-Item -LiteralPath $sourcePath).LastWriteTimeUtc -gt (Get-Item -LiteralPath $exePath).LastWriteTimeUtc
}

if ($needsBuild) {
    if ($NoBuild) {
        throw "Compiled NomadInbox tray client is missing or stale: $exePath"
    }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $buildScript -OutputPath $exePath | Out-Null
}

$trayArgs = @(
    "--repo-root", $RepoRoot,
    "--data-dir", $DataDir,
    "--host", "127.0.0.1",
    "--port", "8791"
)

if ($Wait) {
    & $exePath @trayArgs
} else {
    $argumentLine = ($trayArgs | ForEach-Object { ConvertTo-NomadInboxProcessArgument $_ }) -join " "
    $process = Start-Process -FilePath $exePath -ArgumentList $argumentLine -WorkingDirectory $RepoRoot -WindowStyle Hidden -PassThru
    [pscustomobject]@{
        status = "ok"
        service = "NomadInbox"
        tray = "started"
        trayClient = "compiled"
        pid = $process.Id
        exePath = $exePath
        message = "NomadMail is available from the NomadInbox system tray icon. Open the Windows notification overflow if the icon is hidden."
    } | ConvertTo-Json -Depth 10
}
