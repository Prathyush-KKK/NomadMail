param(
    [string]$DataDir = "",
    [string]$InstallRoot = "",
    [switch]$StartTray,
    [switch]$SkipUserEnvironment
)

$ErrorActionPreference = "Stop"

if (-not $IsWindows -and $PSVersionTable.PSEdition -eq "Core") {
    [pscustomobject]@{
        status = "unsupportedPlatform"
        service = "NomadInbox"
        platform = $PSVersionTable.Platform
        message = "The Windows PowerShell helper installs only on Windows. Use the platform-independent NomadMail MCP server for local JSONL context, and use a supported provider runtime for live sync."
    } | ConvertTo-Json -Depth 10
    exit 2
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$cli = Join-Path $repoRoot "scripts\nomad-inbox.ps1"

if ([string]::IsNullOrWhiteSpace($DataDir)) {
    $DataDir = Join-Path $repoRoot "data"
}
$resolvedDataDir = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($DataDir)
New-Item -ItemType Directory -Force -Path $resolvedDataDir | Out-Null

$localAppData = if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
    Join-Path $env:USERPROFILE "AppData\Local"
} else {
    $env:LOCALAPPDATA
}
if ([string]::IsNullOrWhiteSpace($InstallRoot)) {
    $InstallRoot = Join-Path $localAppData "NomadInbox\agent-helper"
}
$resolvedInstallRoot = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($InstallRoot)
New-Item -ItemType Directory -Force -Path $resolvedInstallRoot | Out-Null
$installedTrayPath = Join-Path $resolvedInstallRoot "NomadInboxTray.exe"
$trayBuildScript = Join-Path $repoRoot "scripts\build-nomad-inbox-tray.ps1"
$runningTrayProcesses = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
    $_.Name -eq "NomadInboxTray.exe" -and ([string]$_.CommandLine).IndexOf($installedTrayPath, [System.StringComparison]::OrdinalIgnoreCase) -ge 0
})
foreach ($trayProcess in $runningTrayProcesses) {
    Stop-Process -Id $trayProcess.ProcessId -Force -ErrorAction SilentlyContinue
}
if ($runningTrayProcesses.Count -gt 0) {
    Start-Sleep -Milliseconds 500
}
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $trayBuildScript -OutputPath $installedTrayPath | Out-Null

$previousDataDir = $env:NOMADINBOX_DATA_DIR
$env:NOMADINBOX_DATA_DIR = $resolvedDataDir
try {
    & $cli setup | Out-Null
    & $cli accounts init | Out-Null
} finally {
    if ($null -eq $previousDataDir) {
        Remove-Item Env:\NOMADINBOX_DATA_DIR -ErrorAction SilentlyContinue
    } else {
        $env:NOMADINBOX_DATA_DIR = $previousDataDir
    }
}

$helperPath = Join-Path $resolvedInstallRoot "nomadmail.ps1"
$statusPath = Join-Path $resolvedInstallRoot "status.json"
$escapedCli = $cli.Replace("'", "''")
$escapedDataDir = $resolvedDataDir.Replace("'", "''")
$escapedTrayPath = $installedTrayPath.Replace("'", "''")
$helperScript = @"
param(
    [Parameter(ValueFromRemainingArguments = `$true)]
    [string[]]`$Argv
)

`$ErrorActionPreference = "Stop"
`$env:NOMADINBOX_DATA_DIR = '$escapedDataDir'
`$env:NOMADINBOX_TRAY_EXE = '$escapedTrayPath'
& '$escapedCli' @Argv
"@
$helperScript | Set-Content -LiteralPath $helperPath -Encoding UTF8

$handoffCommand = "node `"$repoRoot\service\nomadmail-service.mjs`" cross-chat-handoff"
$mcpCommand = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$repoRoot\scripts\nomadmail-mcp.ps1`""
$environmentVariables = [ordered]@{
    NOMADINBOX_HOME = $repoRoot
    NOMADMAIL_HANDOFF_COMMAND = $handoffCommand
    NOMADMAIL_HANDOFF_URL = "http://127.0.0.1:8791/cross-chat-handoff"
    NOMADMAIL_HTTP_URL = "http://127.0.0.1:8791"
    NOMADMAIL_MCP_COMMAND = $mcpCommand
    NOMADMAIL_MCP_SCRIPT = Join-Path $repoRoot "scripts\nomadmail-mcp.ps1"
}
$environmentStatus = [pscustomobject]@{
    registered = $false
    scope = "User"
    skipped = [bool]$SkipUserEnvironment
    variables = $environmentVariables
    message = ""
}
if (-not $SkipUserEnvironment) {
    foreach ($name in $environmentVariables.Keys) {
        $value = [string]$environmentVariables[$name]
        [System.Environment]::SetEnvironmentVariable($name, $value, "User")
        Set-Item -Path "Env:\$name" -Value $value
    }
    $environmentStatus.registered = $true
    $environmentStatus.message = "Registered user environment variables. New terminals and agent sessions can discover NomadInbox through NOMADINBOX_HOME."
} else {
    $environmentStatus.message = "User environment variable registration was skipped for this install run."
}

$accountsConfigPath = Join-Path $repoRoot "config\accounts.json"
$state = [pscustomobject]@{
    status = "ok"
    service = "NomadInbox"
    installedAt = (Get-Date).ToUniversalTime().ToString("o")
    platform = "windows"
    repoRoot = $repoRoot
    dataDir = $resolvedDataDir
    helperPath = $helperPath
    trayExePath = $installedTrayPath
    accountsConfigPath = $accountsConfigPath
    syncStatusPath = Join-Path $resolvedDataDir "sync-status.json"
    messagesPath = Join-Path $resolvedDataDir "messages.jsonl"
    providerRawPath = Join-Path $resolvedDataDir "provider-raw.jsonl"
    archiveMessagesPath = Join-Path $resolvedDataDir "archive-messages.jsonl"
    environment = $environmentStatus
    notes = @(
        "This helper tracks sync operations through sync-status.json and actions.jsonl in the configured data directory.",
        "Connected accounts are tracked in config/accounts.json, which is ignored by git.",
        "The helper does not connect accounts, read mailbox data, or start auto sync by itself.",
        "NOMADINBOX_HOME lets new terminals and agent sessions discover this workspace after the helper has registered user environment variables."
    )
}
$state | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $statusPath -Encoding UTF8

$trayStartResult = $null
if ($StartTray) {
    $previousTrayDataDir = $env:NOMADINBOX_DATA_DIR
    $previousTrayExe = $env:NOMADINBOX_TRAY_EXE
    $env:NOMADINBOX_DATA_DIR = $resolvedDataDir
    $env:NOMADINBOX_TRAY_EXE = $installedTrayPath
    try {
        $trayStartText = & $cli tray start
        if (-not [string]::IsNullOrWhiteSpace(($trayStartText | Out-String))) {
            $trayStartResult = ($trayStartText | Out-String | ConvertFrom-Json)
        }
    } finally {
        if ($null -eq $previousTrayDataDir) {
            Remove-Item Env:\NOMADINBOX_DATA_DIR -ErrorAction SilentlyContinue
        } else {
            $env:NOMADINBOX_DATA_DIR = $previousTrayDataDir
        }
        if ($null -eq $previousTrayExe) {
            Remove-Item Env:\NOMADINBOX_TRAY_EXE -ErrorAction SilentlyContinue
        } else {
            $env:NOMADINBOX_TRAY_EXE = $previousTrayExe
        }
    }
}

[pscustomobject]@{
    status = "ok"
    service = "NomadInbox"
    installed = $true
    platform = "windows"
    helperPath = $helperPath
    statusPath = $statusPath
    dataDir = $resolvedDataDir
    trayExePath = $installedTrayPath
    accountsConfigPath = $accountsConfigPath
    environment = $environmentStatus
    trayStarted = [bool]$StartTray
    trayStatus = if ($trayStartResult) { $trayStartResult.tray } else { $null }
    trayPid = if ($trayStartResult) { $trayStartResult.pid } else { $null }
} | ConvertTo-Json -Depth 20
