# Runtime Backup And Restore Runbook

Use this when you want to export or restore NomadInbox / NomadMail's own local runtime data.

This is different from archive import. Archive import reads external mail exports such as Gmail Takeout MBOX or Outlook EML folders. Runtime backup preserves the local NomadMail store that was already built by sync/import operations.

## What Gets Backed Up

Recommended runtime backup contents:

- `data/messages.jsonl` - normalized message records used by agents and UI
- `data/provider-raw.jsonl` - provider-specific snapshots for fields outside the normalized model
- `data/message-extracts.jsonl` - extracted facts or summaries when present
- `data/thread-index.jsonl` - thread-level projections when present
- `data/archive-messages.jsonl` - imported read-only archive messages
- `data/import-status.json` - archive import state
- `data/sync-status.json` - latest sync state
- `data/actions.jsonl` - local action audit log
- `data/attachments/` - locally stored attachments, when enabled
- `config/accounts.json` - local account ids, enabled flags, provider settings, and sync scope

Do not include OAuth client secrets, access tokens, token caches, `.env` files, raw MBOX/PST/EML/MSG exports, `runtime/`, `target/`, `dist/`, `data/sync-worker.pid`, or normal log files unless the user explicitly chooses an encrypted secret backup.

`provider-raw.jsonl`, message bodies, extracts, and attachments can contain sensitive mailbox data. Store backups only on encrypted local storage or a user-approved encrypted backup target.

## Export A Backup

Run from the repository root.

```powershell
$repo = (Get-Location).Path
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$backupRoot = Join-Path $HOME "Documents\NomadInbox Backups"
$stage = Join-Path $env:TEMP "nomadinbox-runtime-$stamp"
$zipPath = Join-Path $backupRoot "nomadinbox-runtime-$stamp.zip"
$manifestPath = Join-Path $backupRoot "nomadinbox-runtime-$stamp.manifest.json"

New-Item -ItemType Directory -Force -Path $backupRoot | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $stage "data"), (Join-Path $stage "config") | Out-Null

$dataItems = @(
  "messages.jsonl",
  "provider-raw.jsonl",
  "message-extracts.jsonl",
  "thread-index.jsonl",
  "archive-messages.jsonl",
  "import-status.json",
  "sync-status.json",
  "actions.jsonl",
  "attachments"
)

foreach ($item in $dataItems) {
  $source = Join-Path $repo "data\$item"
  if (Test-Path -LiteralPath $source) {
    Copy-Item -LiteralPath $source -Destination (Join-Path $stage "data") -Recurse -Force
  }
}

$accounts = Join-Path $repo "config\accounts.json"
if (Test-Path -LiteralPath $accounts) {
  Copy-Item -LiteralPath $accounts -Destination (Join-Path $stage "config\accounts.json") -Force
}

Compress-Archive -Path (Join-Path $stage "*") -DestinationPath $zipPath -Force

$files = Get-ChildItem -LiteralPath $stage -Recurse -File | ForEach-Object {
  $relative = $_.FullName.Substring($stage.Length).TrimStart("\")
  [pscustomobject]@{
    path = $relative
    bytes = $_.Length
    sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
  }
}

[pscustomobject]@{
  service = "NomadInbox"
  backupType = "runtime"
  createdAt = (Get-Date).ToUniversalTime().ToString("o")
  sourceRepo = $repo
  sourceDataDir = (Join-Path $repo "data")
  package = $zipPath
  files = $files
} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

Remove-Item -LiteralPath $stage -Recurse -Force

[pscustomobject]@{
  status = "ok"
  backup = $zipPath
  manifest = $manifestPath
} | ConvertTo-Json
```

Keep the `.zip` and `.manifest.json` together.

## Restore Into The Same Workspace

Stop the tray and sync worker first so files are not changing while restore runs.

```powershell
.\scripts\nomad-inbox.ps1 service stop
.\scripts\nomad-inbox.ps1 tray stop
```

Then restore the backup.

```powershell
$repo = (Get-Location).Path
$zipPath = "$HOME\Documents\NomadInbox Backups\nomadinbox-runtime-YYYYMMDD-HHMMSS.zip"
$restoreStage = Join-Path $env:TEMP ("nomadinbox-restore-" + (Get-Date -Format "yyyyMMdd-HHmmss"))

Expand-Archive -LiteralPath $zipPath -DestinationPath $restoreStage -Force

New-Item -ItemType Directory -Force -Path (Join-Path $repo "data"), (Join-Path $repo "config") | Out-Null

if (Test-Path -LiteralPath (Join-Path $restoreStage "data")) {
  Copy-Item -LiteralPath (Join-Path $restoreStage "data\*") -Destination (Join-Path $repo "data") -Recurse -Force
}

if (Test-Path -LiteralPath (Join-Path $restoreStage "config\accounts.json")) {
  Copy-Item -LiteralPath (Join-Path $restoreStage "config\accounts.json") -Destination (Join-Path $repo "config\accounts.json") -Force
}

Remove-Item -LiteralPath $restoreStage -Recurse -Force

.\scripts\nomad-inbox.ps1 setup
.\scripts\nomad-inbox.ps1 service status
.\scripts\nomad-inbox.ps1 backup status
```

After restore, reconnect provider credentials only when needed. The normal runtime backup should restore account ids and sync scopes, not OAuth token caches or client secrets.

## Test Restore Without Touching Current Data

Use a separate data directory when you want to inspect a backup without replacing the active store.

```powershell
$repo = (Get-Location).Path
$zipPath = "$HOME\Documents\NomadInbox Backups\nomadinbox-runtime-YYYYMMDD-HHMMSS.zip"
$testRoot = Join-Path $env:TEMP ("nomadinbox-test-restore-" + (Get-Date -Format "yyyyMMdd-HHmmss"))

Expand-Archive -LiteralPath $zipPath -DestinationPath $testRoot -Force

$env:NOMADINBOX_DATA_DIR = Join-Path $testRoot "data"
.\scripts\nomad-inbox.ps1 setup
.\scripts\nomad-inbox.ps1 backup status
```

When testing this way, do not start background sync unless you intend that restored test store to become active for the current process environment.

## Current Product Boundary

NomadInbox currently has `backup status` but does not yet expose first-class `backup export` or `backup restore` CLI commands. Until those commands exist, use this runbook for controlled local export and restore.
