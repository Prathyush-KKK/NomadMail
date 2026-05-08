$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$required = @(
    "README.md",
    "AGENTS.md",
    ".gitignore",
    "VERSION",
    "config\nomad-inbox.example.ps1",
    "config\accounts.example.json",
    "prompts\nomadmail-startup.system.md",
    "prompts\nomadmail-cross-chat-handoff.md",
    "assets\nomadinbox-mark.svg",
    "assets\nomadinbox-logo.svg",
    "assets\nomadinbox-tray.ico",
    "assets\nomadinbox-tray-32.png",
    "assets\nomadinbox-tray-256.png",
    "scripts\build-app-icons.ps1",
    "scripts\install-windows-agent-helper.ps1",
    "scripts\build-nomad-inbox-tray.ps1",
    "scripts\build-windows-installer.ps1",
    "scripts\nomad-inbox.ps1",
    "scripts\nomadmail-http.ps1",
    "scripts\nomadmail-mcp.ps1",
    "scripts\nomad-inbox-worker.ps1",
    "scripts\nomad-inbox-tray.ps1",
    "scripts\update-workspace-state.ps1",
    "scripts\new-architecture-change.ps1",
    "scripts\session-closeout.ps1",
    "src\NomadInbox.Tray\NomadInboxTray.cs",
    "src\NomadInbox\NomadInbox.psm1",
    "service\nomadmail-service.mjs",
    "tests\smoke.ps1",
    "tests\agent-user-flow.ps1",
    "tests\new-clone.ps1",
    "schemas\message.v1.json",
    "schemas\provider-raw.v1.json",
    "schemas\action.v1.json",
    "docs\ARCHITECTURE_INDEX.md",
    "docs\PRODUCT_SPEC.md",
    "docs\ARCHITECTURE.md",
    "docs\c4\01-system-context.md",
    "docs\c4\02-container.md",
    "docs\c4\03-dynamic-flows.md",
    "docs\adrs\0001-create-fresh-nomadinbox-repository.md",
    "docs\adrs\0004-optional-background-sync-and-tray.md",
    "docs\adrs\0005-read-only-archive-import-for-context.md",
    "docs\adrs\0006-expose-nomadmail-agent-service.md",
    "docs\service-catalog\service-catalog.yaml",
    "docs\processes\process-catalog.md",
    "docs\runbooks\local-bootstrap.md",
    "docs\runbooks\agent-user-flow.md",
    "docs\runbooks\agent-user-flow-test-matrix.md",
    "docs\runbooks\background-sync-and-tray.md",
    "docs\runbooks\archive-import.md",
    "docs\runbooks\runtime-backup-restore.md",
    "docs\runbooks\agent-service.md",
    "docs\runbooks\testing-handoff.md",
    "docs\runbooks\release.md",
    "docs\slo\nomadinbox-slo.md",
    "docs\governance\ARCHITECTURE_UPDATE_PROCESS.md",
    "docs\governance\WORKSPACE_STATE.md",
    "docs\governance\SESSION_CHANGELOG.md",
    "api\openapi\nomadinbox.v1.yaml",
    "api\asyncapi\nomadinbox-events.v1.yaml"
)

$missing = @()
foreach ($path in $required) {
    if (-not (Test-Path -LiteralPath (Join-Path $repoRoot $path))) {
        $missing += $path
    }
}

$forbiddenTracked = @()
if (Get-Command git -ErrorAction SilentlyContinue) {
    $tracked = git -C $repoRoot ls-files
    $forbiddenTracked = @($tracked | Where-Object {
        $_ -match '^data/' -or
        $_ -match '^-DataDir/' -or
        $_ -match '^runtime/' -or
        $_ -match '^target/' -or
        $_ -match '^dist/' -or
        $_ -match '^logs/' -or
        $_ -match '^downloads/' -or
        $_ -match '^\.kiro/' -or
        $_ -match '^AGENTS\.continuity\.md$' -or
        $_ -match '^CLAUDE\.continuity\.md$' -or
        $_ -match '^MAYOR_' -or
        $_ -match 'token-cache' -or
        $_ -match 'client_secret' -or
        $_ -match '\.(mbox|eml|pst|msg)$' -or
        $_ -match '^mail-exports/' -or
        $_ -match '^import-staging/' -or
        $_ -match '^scripts/_.*\.ps1$' -or
        $_ -match '^config/nomad-inbox\.ps1$' -or
        $_ -match '^config/accounts\.json$'
    })
}

$parseErrors = @()
foreach ($psPath in @(
    (Join-Path $repoRoot "scripts\nomad-inbox-tray.ps1"),
    (Join-Path $repoRoot "scripts\build-nomad-inbox-tray.ps1"),
    (Join-Path $repoRoot "scripts\build-windows-installer.ps1")
)) {
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($psPath, [ref]$tokens, [ref]$errors) | Out-Null
    if ($errors) {
        $parseErrors += @($errors | ForEach-Object { "$psPath`: $($_.Message)" })
    }
}

$trayPath = Join-Path $repoRoot "scripts\nomad-inbox-tray.ps1"
$trayText = Get-Content -LiteralPath $trayPath -Raw
$traySourcePath = Join-Path $repoRoot "src\NomadInbox.Tray\NomadInboxTray.cs"
$traySourceText = Get-Content -LiteralPath $traySourcePath -Raw
$trayCombinedText = $trayText + "`n" + $traySourceText
$requiredTrayMarkers = @(
    "Sync now",
    "Auto sync: on (turn off)",
    "Auto sync: off (turn on)",
    "Ask your agent if you want to connect new accounts",
    "Settings and diagnostics",
    "BuildMenuFromCache",
    "DoubleClick",
    "SettingsForm",
    "StatusPopupForm",
    "IconFactory",
    "Open status popup",
    "Refreshing status...",
    "BeginRefresh",
    "EnsureHttpServiceAsync",
    "RequestJsonAsync",
    "NOMADINBOX_DATA_DIR",
    "IconPath",
    "LoadAppIcon",
    "nomadinbox-tray.ico"
)
$missingTrayMarkers = @($requiredTrayMarkers | Where-Object { $trayCombinedText -notlike "*$_*" })
$forbiddenTrayMarkers = @(
    "Show-NomadMailHttpStatus",
    "Copy-NomadInboxAgentPrompt",
    "Connect accounts with agent",
    "NomadMail agent service",
    "Invoke-NomadInboxCliJson"
)
$presentForbiddenTrayMarkers = @($forbiddenTrayMarkers | Where-Object { $trayCombinedText -like "*$_*" })

$result = [pscustomobject]@{
    status = if ($missing.Count -eq 0 -and $forbiddenTracked.Count -eq 0 -and $parseErrors.Count -eq 0 -and $missingTrayMarkers.Count -eq 0 -and $presentForbiddenTrayMarkers.Count -eq 0) { "ok" } else { "failed" }
    project = $repoRoot
    missing = $missing
    forbiddenTracked = $forbiddenTracked
    parseErrors = $parseErrors
    missingTrayMarkers = $missingTrayMarkers
    forbiddenTrayMarkers = $presentForbiddenTrayMarkers
}

$result | ConvertTo-Json -Depth 10
if ($result.status -ne "ok") { exit 1 }
