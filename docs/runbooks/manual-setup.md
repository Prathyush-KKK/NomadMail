# Manual Setup

Use this when you want to try NomadInbox without an AI agent driving the setup.

## Start In The Repository

```powershell
cd C:\Users\prat\Documents\osm\NomadInbox
```

## Initialize And Check The Local Runtime

```powershell
.\scripts\nomad-inbox.ps1 setup
.\scripts\nomad-inbox.ps1 doctor
.\scripts\nomad-inbox.ps1 providers list
.\scripts\nomad-inbox.ps1 config status
```

Expected result:

- setup creates the ignored local runtime folder
- doctor returns `ok`
- provider listing shows Gmail API, Outlook Graph, and Outlook Desktop
- config status does not require mailbox access

## Install The Windows Agent Helper

On Windows, install the local PowerShell helper before connecting accounts:

```powershell
.\scripts\nomad-inbox.ps1 install windows-helper --start-tray --register-startup --show-popup
```

Expected result:

- ignored runtime files are initialized
- `config\accounts.json` is created if missing
- a local helper launcher is written under `%LOCALAPPDATA%\NomadInbox\agent-helper`
- the compiled tray starts now, opens the status popup, and is registered in the current user's Windows Startup folder
- the helper status file records the data directory, account config path, sync status path, and message store paths
- user environment variables are registered for future agent sessions, including `NOMADINBOX_HOME` and `NOMADMAIL_HANDOFF_COMMAND`

The helper does not connect accounts, read mailbox data, or start auto sync by itself. Startup registration only starts the local tray and NomadMail service surface.

Verify cross-chat discovery:

```powershell
.\scripts\nomad-inbox.ps1 env status
```

On non-Windows systems, do not install this helper or offer Outlook Desktop sync. The NomadMail MCP server is Node-based and can still expose local JSONL context tools. Live provider sync currently needs PowerShell Core (`pwsh`) plus a supported provider runtime, or a future native adapter.

## Confirm Private Data Is Ignored

Runtime data and local credentials are ignored by git. Check before connecting accounts:

```powershell
git check-ignore -v data data/messages.jsonl config/accounts.json config/nomad-inbox.ps1
```

Important ignored paths:

- `data/`
- `runtime/`
- `target/`
- `mail-exports/`
- `import-staging/`
- `config/nomad-inbox.ps1`
- `config/accounts.json`
- `client_secret*.json`
- `*token-cache*.json`
- `*credentials*.json`
- `*.jsonl`
- `*.mbox`
- `*.eml`
- `*.pst`
- `*.msg`

Do not force-add those files to git.

## Set User Time Context

NomadInbox stores timestamps as UTC ISO, but parses ambiguous user/source dates with the user locale and time zone. By default it uses the current OS user settings. Override them before launching the CLI, tray, MCP, or HTTP service when needed:

```powershell
$env:NOMADINBOX_USER_CULTURE="en-IN"
$env:NOMADINBOX_USER_TIME_ZONE="India Standard Time"
# Cross-platform agents may use the IANA form:
$env:NOMADINBOX_USER_TIME_ZONE_IANA="Asia/Kolkata"
```

## Create Local Account Config

```powershell
.\scripts\nomad-inbox.ps1 accounts init
notepad .\config\accounts.json
```

Enable only the account you want to test. The default example accounts are:

- `personal-gmail`
- `work-outlook-web`
- `desktop-outlook`

Keep limits small for the first run.

## Provider Auth Notes

Gmail API sync expects one of:

- `NOMADINBOX_GMAIL_ACCESS_TOKEN`
- a Gmail-scoped local `gcloud` login

Outlook Graph sync expects one of:

- `NOMADINBOX_GRAPH_ACCESS_TOKEN`
- Azure CLI access that can return a Microsoft Graph token

Outlook Desktop sync expects:

- Windows Outlook installed
- Outlook open or available in the same signed-in desktop session
- an enabled `outlook-desktop` account in `config\accounts.json`

## Run One Manual Sync

```powershell
.\scripts\nomad-inbox.ps1 sync once
```

Or run one configured account:

```powershell
.\scripts\nomad-inbox.ps1 sync once --account-id desktop-outlook
```

Check status:

```powershell
.\scripts\nomad-inbox.ps1 service status
.\scripts\nomad-inbox.ps1 backup status
```

Live synced messages are written to the active data directory as `messages.jsonl`.

## Use A Separate Data Directory

By default, data is written under `.\data`. To store runtime data elsewhere:

```powershell
$env:NOMADINBOX_DATA_DIR="C:\Users\prat\AppData\Local\NomadInbox\data"
.\scripts\nomad-inbox.ps1 setup
.\scripts\nomad-inbox.ps1 sync once
```

Use the same environment variable before starting the tray, MCP server, or HTTP service if those processes should use that location.

## Back Up Or Restore NomadMail Runtime Data

NomadMail runtime backup/export is separate from importing external mail exports.

Use [Runtime Backup And Restore](runtime-backup-restore.md) to export or restore:

- live synced message records
- provider raw snapshots
- archive imported messages
- sync and import status
- local action audit logs
- attachment files when enabled
- local account config

The current product has `backup status`, but not first-class `backup export` or `backup restore` CLI commands yet. The runbook uses explicit local PowerShell steps and keeps runtime backups out of git.

## Start Or Stop Background Sync

Background sync is optional. It runs in the signed-in user session.

```powershell
.\scripts\nomad-inbox.ps1 service start
.\scripts\nomad-inbox.ps1 service status
```

Stop it:

```powershell
.\scripts\nomad-inbox.ps1 service stop
```

The worker periodically runs the same sync path as `sync once`.

## Use The Tray App

```powershell
.\scripts\nomad-inbox.ps1 tray start
.\scripts\nomad-inbox.ps1 tray status
```

Click the tray icon to open the compact native status popup. Right-click keeps a fallback context menu. The tray popup can:

- refresh current status with visible busy feedback
- run a global `Sync now`
- turn auto sync on or off after accounts are enabled
- show clean per-account sync status
- open Settings and diagnostics for logs, errors, provider details, storage paths, locale, and time-zone state
- open the runtime folder

If no accounts are enabled, the tray will not start an empty background worker. It shows a short note to ask your agent when you want to connect new accounts.

`tray status` returns the compiled tray process state, installed helper status,
local HTTP health, worker state, and the active data directory.

## Import Local Email Exports

Archive imports are read-only context by default.
After a live email is discovered, agents can offer draft reply, draft new mail,
mark/flag/move/archive, and trash/delete guidance. Replies and new mail must be
drafted first and sent only after approval. Trash/delete requires two explicit
approvals before any mailbox mutation.

```powershell
.\scripts\nomad-inbox.ps1 import status
.\scripts\nomad-inbox.ps1 import eml --path .\mail-export --source outlook-export --dry-run
.\scripts\nomad-inbox.ps1 import mbox --path .\takeout\Mail.mbox --source gmail-takeout --dry-run
.\scripts\nomad-inbox.ps1 import jsonl --path .\messages.jsonl --source nomadinbox-export --dry-run
```

Remove `--dry-run` only after the count and format look right.

Add `--include-bodies` only when you explicitly want full archive body storage.

## Run NomadMail For Agents

MCP over stdio:

```powershell
.\scripts\nomadmail-mcp.ps1
```

Local HTTP:

```powershell
.\scripts\nomadmail-http.ps1 -Port 8791
```

Useful HTTP checks:

```powershell
Invoke-RestMethod http://127.0.0.1:8791/agent-guide
Invoke-RestMethod http://127.0.0.1:8791/health
Invoke-RestMethod "http://127.0.0.1:8791/messages?query=test&limit=5"
Invoke-RestMethod -Method Post http://127.0.0.1:8791/sync/once -Body '{"accountId":"desktop-outlook"}' -ContentType 'application/json'
```

## Use Assigned-Agent Automation

NomadInbox can queue local review events for an assigned agent such as Codex.
The events are stored in ignored `data\agent-events.jsonl` and are not approval
to mutate mail.

Create events from already synced live messages:

```powershell
node .\service\nomadmail-service.mjs agent-automation-cycle --assigned-agent codex --limit 10
```

List pending events:

```powershell
node .\service\nomadmail-service.mjs agent-events --assigned-agent codex --status pending
```

When Codex is configured with the NomadMail MCP server, it can call
`nomadmail_list_agent_events` directly. See [Codex Automation](codex-automation.md).

## Validate The Repository

```powershell
.\scripts\validate.ps1
.\tests\smoke.ps1
```

The smoke test uses a temporary `NOMADINBOX_DATA_DIR`, so it does not write real mailbox data to the default store.

## Build A Versioned Installer Package

For a local test package while the working tree is dirty:

```powershell
.\scripts\build-windows-installer.ps1 -AllowDirty
```

For a publish candidate, commit the intended changes first and run:

```powershell
.\scripts\build-windows-installer.ps1
```

The package is written under ignored `dist\` and includes only tracked product
files plus the compiled tray executable. Runtime data, local account config,
Kiro scratch files, secrets, token caches, and mail exports stay out of the
package. See [Release And Installer Packaging](release.md).

## Troubleshooting

| Symptom | Check | Fix |
|---|---|---|
| No account syncs | `.\scripts\nomad-inbox.ps1 accounts list` | Enable only the intended account in `config\accounts.json` |
| Gmail auth pending | provider result reason | Set `NOMADINBOX_GMAIL_ACCESS_TOKEN` or use a Gmail-scoped `gcloud` login |
| Graph auth pending | provider result reason | Set `NOMADINBOX_GRAPH_ACCESS_TOKEN` or sign in with Azure CLI for Graph |
| Outlook Desktop fails | same Windows session | Open Outlook fully in the current desktop session |
| Worker appears stale | `.\scripts\nomad-inbox.ps1 service status` | Run `service stop`, then `service start` |
| Tray icon not visible | Windows notification overflow | Expand hidden tray icons or restart the tray |
| Data appears in git status | `.gitignore` and forced adds | Do not use `git add -f` for runtime data, config, tokens, or exports |
