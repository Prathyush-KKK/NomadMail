# Agent Callable Service Runbook

NomadMail is the callable service facade over the NomadInbox core.

## MCP

Use MCP when an agent supports stdio MCP servers:

```powershell
.\scripts\nomadmail-mcp.ps1
```

Cross-platform agents can also launch the Node service directly:

```bash
node service/nomadmail-service.mjs mcp
```

The MCP server itself is a Node.js process and is intended to start on any OS with Node.js. CLI-backed provider tools delegate to the NomadInbox PowerShell core. On Windows, install the Windows helper first so sync state and connected accounts can be tracked. On non-Windows, the agent should explain that local JSONL context tools can still work, while live sync/import needs PowerShell Core (`pwsh`) plus a supported provider runtime or a future native adapter.

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
- `nomadmail_get_startup_system_prompt`
- `nomadmail_install_windows_helper`
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
Invoke-RestMethod http://127.0.0.1:8791/startup-system-prompt
Invoke-RestMethod http://127.0.0.1:8791/health
Invoke-RestMethod http://127.0.0.1:8791/providers
Invoke-RestMethod "http://127.0.0.1:8791/messages?query=invoice&limit=5"
Invoke-RestMethod -Method Post http://127.0.0.1:8791/sync/once -Body '{"accountId":"personal-gmail"}' -ContentType 'application/json'
```

## Guidance for Calling Agents

Other agents should call `nomadmail_get_agent_guide` first. It returns the current storage boundary, safe import workflow, live-sync requirements, target-index handoff pattern, and the canonical startup system prompt.

The startup system prompt is owned by NomadInbox in `prompts/nomadmail-startup.system.md`. Agents should load it through `nomadmail_get_startup_system_prompt` or HTTP `/startup-system-prompt` when opening this repository as a workspace. This is system behavior, not a prompt the user is responsible for keeping in sync.

When an agent opens this repository as a user workspace:

- Load the built-in startup system prompt.
- Detect the operating system first.
- If it is Windows, run `nomadmail_install_windows_helper` or `.\scripts\nomad-inbox.ps1 install windows-helper` before connecting accounts.
- If it is not Windows, do not install the Windows helper, start the tray, or offer Outlook Desktop COM sync. Use the MCP server for platform-independent local context tools and report what provider sync runtime is missing.
- Do not discover credentials, mailbox profiles, exports, or connected accounts until the user approves the exact source and scope.

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
- Outlook Desktop sync requires Windows and the signed-in Windows Outlook profile.
- The Windows helper tracks sync operations through `sync-status.json` and `actions.jsonl`, and tracks connected account config through ignored `config/accounts.json`.
- Non-Windows agents should keep the MCP server available for `nomadmail_get_agent_guide`, `nomadmail_search_messages`, and `nomadmail_get_message`, and return a clear unsupported-runtime response for Windows-only helper, tray, and Outlook Desktop operations.
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
