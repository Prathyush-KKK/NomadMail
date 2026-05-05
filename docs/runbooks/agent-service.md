# Agent Callable Service Runbook

NomadMail is the callable service facade over the NomadInbox core.

## MCP

Use MCP when an agent supports stdio MCP servers:

```powershell
.\scripts\nomadmail-mcp.ps1
```

Client command shape:

```json
{
  "command": "powershell.exe",
  "args": [
    "-NoProfile",
    "-ExecutionPolicy",
    "Bypass",
    "-File",
    "C:\\Users\\prat\\Documents\\osm\\NomadInbox\\scripts\\nomadmail-mcp.ps1"
  ]
}
```

Primary tools:

- `nomadmail_get_agent_guide`
- `nomadmail_health_check`
- `nomadmail_list_providers`
- `nomadmail_list_accounts`
- `nomadmail_sync_once`
- `nomadmail_search_messages`
- `nomadmail_get_message`
- `nomadmail_import_archive`

## HTTP

Use HTTP for local tools that cannot speak MCP:

```powershell
.\scripts\nomadmail-http.ps1 -Port 8791
```

The service binds to `127.0.0.1` by default.

Common calls:

```powershell
Invoke-RestMethod http://127.0.0.1:8791/agent-guide
Invoke-RestMethod http://127.0.0.1:8791/health
Invoke-RestMethod http://127.0.0.1:8791/providers
Invoke-RestMethod "http://127.0.0.1:8791/messages?query=invoice&limit=5"
Invoke-RestMethod -Method Post http://127.0.0.1:8791/sync/once -Body '{"accountId":"personal-gmail"}' -ContentType 'application/json'
```

## Guidance for Calling Agents

Other agents should call `nomadmail_get_agent_guide` first. It returns the current storage boundary, safe import workflow, live-sync requirements, and target-index handoff pattern.

Use this rule before parsing or syncing email for another repository:

- If the user wants NomadInbox's own local store updated, use the default service.
- If the user wants another repository updated, start the MCP/HTTP service or CLI with `NOMADINBOX_DATA_DIR` set to a staging folder inside that target repository.
- Run `dryRun=true` on `nomadmail_import_archive` before writing parsed records.
- Hand the generated `archive-messages.jsonl` or `messages.jsonl` to the target repository's own importer and index command.

Example external-repository staging flow:

```powershell
$targetRepo = "C:\path\to\target-repo"
$env:NOMADINBOX_DATA_DIR = Join-Path $targetRepo ".nomadmail-staging"

cd C:\Users\prat\Documents\osm\NomadInbox
.\scripts\nomad-inbox.ps1 import mbox --path "$targetRepo\mail-backups\Mail.mbox" --source gmail-takeout --dry-run
.\scripts\nomad-inbox.ps1 import mbox --path "$targetRepo\mail-backups\Mail.mbox" --source gmail-takeout

cd $targetRepo
# Run this repository's own importer and index command.
```

For `personal-context-workspace`, the handoff command is:

```powershell
cd C:\Users\prat\Code\personal-context-workspace
npm run import:mail-agent-jsonl -- --path "$targetRepo\.nomadmail-staging" --dataset email-backups
npm run index
```

## Safety

- MCP and HTTP use the same local ignored runtime data as the CLI.
- Default imports and syncs write to NomadInbox `data/` unless `NOMADINBOX_DATA_DIR` is set before the CLI/service starts.
- Gmail API sync requires `NOMADINBOX_GMAIL_ACCESS_TOKEN` or a Gmail-scoped `gcloud` login.
- Outlook Graph sync requires `NOMADINBOX_GRAPH_ACCESS_TOKEN` or an Azure CLI Microsoft Graph token.
- Outlook Desktop sync requires the signed-in Windows Outlook profile.
- Archive import still requires an explicitly provided local path.
- Full archive body import still requires `includeBodies=true`.
- Send-style mailbox actions must stay behind the existing confirmation gate before they are added to this service.
- Outlook Desktop access must run in the signed-in Windows user session because it depends on the local Outlook profile.

## Diagnostics

```powershell
node .\service\nomadmail-service.mjs agent-guide
node .\service\nomadmail-service.mjs self-test
node .\service\nomadmail-service.mjs tools
.\scripts\nomad-inbox.ps1 doctor
.\scripts\nomad-inbox.ps1 service status
```
