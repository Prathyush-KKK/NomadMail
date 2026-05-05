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
```

The tray menu can:

- show sync instructions when auto sync is off
- show auto sync status when auto sync is on
- copy an agent connection prompt
- turn auto sync on or off after accounts are enabled
- open account settings
- open the runtime folder
- open the NomadInbox repository folder

If no accounts are enabled, the tray will not start an empty background worker. It points you to account connection first.

## Import Local Email Exports

Archive imports are read-only context by default.

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

## Validate The Repository

```powershell
.\scripts\validate.ps1
.\tests\smoke.ps1
```

The smoke test uses a temporary `NOMADINBOX_DATA_DIR`, so it does not write real mailbox data to the default store.

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
