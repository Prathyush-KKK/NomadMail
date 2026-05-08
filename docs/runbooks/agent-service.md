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

The MCP server itself is a Node.js process and is intended to start on any OS with Node.js. CLI-backed provider tools delegate to the NomadInbox PowerShell core. On Windows, install the Windows helper first so sync state and connected accounts can be tracked. On non-Windows, the agent should explain that local JSONL context tools can still work, while live sync/import needs PowerShell Core (`pwsh`) plus a supported provider runtime or a future native provider adapter.

MCP over stdio is launched by each calling agent. The Windows tray keeps the loopback HTTP service active at `127.0.0.1:8791` while the tray is running, so non-MCP agents can still reach the same local NomadMail service surface.

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

Workspace discovery after Windows helper install:

```powershell
$nomadInboxHome = [Environment]::GetEnvironmentVariable("NOMADINBOX_HOME", "User")
cd $nomadInboxHome
node .\service\nomadmail-service.mjs cross-chat-handoff
```

The helper registers these user environment variables by default: `NOMADINBOX_HOME`, `NOMADMAIL_HANDOFF_COMMAND`, `NOMADMAIL_HANDOFF_URL`, `NOMADMAIL_HTTP_URL`, `NOMADMAIL_MCP_COMMAND`, and `NOMADMAIL_MCP_SCRIPT`. Use `.\scripts\nomad-inbox.ps1 env status` to verify them. Tests and temporary helper installs should use `--skip-user-env`.

Primary tools:

- `nomadmail_get_agent_guide`
- `nomadmail_get_startup_system_prompt`
- `nomadmail_get_workspace_state`
- `nomadmail_get_agent_user_flow`
- `nomadmail_get_cross_chat_handoff`
- `nomadmail_install_windows_helper`
- `nomadmail_health_check`
- `nomadmail_list_providers`
- `nomadmail_list_accounts`
- `nomadmail_sync_once`
- `nomadmail_search_messages`
- `nomadmail_get_latest_message`
- `nomadmail_get_message`
- `nomadmail_get_message_actions`
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
Invoke-RestMethod http://127.0.0.1:8791/workspace-state
Invoke-RestMethod http://127.0.0.1:8791/agent-user-flow
Invoke-RestMethod http://127.0.0.1:8791/cross-chat-handoff
Invoke-RestMethod http://127.0.0.1:8791/health
Invoke-RestMethod http://127.0.0.1:8791/providers
Invoke-RestMethod "http://127.0.0.1:8791/messages?query=invoice&limit=5"
Invoke-RestMethod -Method Post http://127.0.0.1:8791/sync/once -Body '{"accountId":"personal-gmail"}' -ContentType 'application/json'
Invoke-RestMethod -Method Post http://127.0.0.1:8791/messages/latest -Body '{"syncFirst":true,"requireContent":true}' -ContentType 'application/json'
```

## Guidance for Calling Agents

Other agents should call `nomadmail_get_agent_guide` first. It returns the current storage boundary, safe import workflow, live-sync requirements, target-index handoff pattern, the canonical startup system prompt, and the living workspace state.

Use [Agent User Flow](agent-user-flow.md), `nomadmail_get_agent_user_flow`, or HTTP `/agent-user-flow` as the user-facing conversation contract from first prompt through daily-mail query choices. The service runbook describes callable tools; the user-flow runbook describes what the agent should say and ask at each state.

Use `nomadmail_get_cross_chat_handoff`, HTTP `/cross-chat-handoff`, or `prompts/nomadmail-cross-chat-handoff.md` when a different chat session needs to connect to the same local workspace. The handoff prompt tells the new agent how to load repo-owned context, prefer MCP or tray-owned HTTP, refresh current status, and preserve mailbox/source approval boundaries.

For the tested scenario inputs and expected/observed outputs, see
[Agent User Flow Test Matrix](agent-user-flow-test-matrix.md).

For cross-agent validation and brand-new clone testing, see
[Testing Handoff](testing-handoff.md).

The startup system prompt is owned by NomadInbox in `prompts/nomadmail-startup.system.md`. Agents should load it through `nomadmail_get_startup_system_prompt` or HTTP `/startup-system-prompt` when opening this repository as a workspace. This is system behavior, not a prompt the user is responsible for keeping in sync.

The living workspace state is owned by NomadInbox in `docs/governance/WORKSPACE_STATE.md`. Agents should read it through `nomadmail_get_workspace_state`, HTTP `/workspace-state`, or direct file access before answering.

All time-related parsing must use the user's locale and time zone. On Windows this normally comes from the signed-in user's OS settings; agents may set `NOMADINBOX_USER_CULTURE` or `NOMADINBOX_USER_LOCALE` and `NOMADINBOX_USER_TIME_ZONE` or `NOMADINBOX_USER_TIME_ZONE_IANA` before launching the CLI/MCP/HTTP process when a specific locale context is needed. Persisted timestamps stay UTC ISO 8601; user-facing status should show local user time.

For latest-email questions, run a one-shot live sync first. Use `nomadmail_get_latest_message` with `syncFirst=true`, or call `nomadmail_sync_once` before searching live messages. The latest-email request only implies permission for that one freshness sync against already configured and enabled live accounts. It does not permit enabling accounts, discovering credentials, reading exports, storing full bodies, saving attachments, or mutating mail. If sync fails or no live account is enabled, say the latest email cannot be confirmed.

After a message is discovered, use the `actionMenu` on search/latest results or call `nomadmail_get_message_actions` to present a compact action surface. Good user-facing actions are draft reply, draft reply all, draft forward, draft new mail, mark read/unread, flag/star, move/archive, and trash/delete when the selected live message supports them. Imported archive messages are read-only; offer summarize, extract follow-up, or find the matching live message instead.

Mail actions are permission gated. Replies, forwards, and new mail must be drafted first, then sent only after the user approves the exact draft, recipients, subject, and body. Trash/delete requires double explicit approval: confirm intent first, then ask for a final confirmation naming the message and mailbox effect. Tell the user the action may not complete if provider permissions or runtime access are missing, such as read-only Gmail/Graph scopes, missing Graph write/send scopes, or Outlook Desktop COM not being reachable in the signed-in Windows session.

User-facing setup responses should be short. When the user asks to install, start, or run the service on Windows, start or verify the tray controller instead of starting only the raw HTTP server. When the local service is healthy and the tray is running, tell the user NomadMail is available from the NomadInbox system tray. Do not print endpoint catalogs, raw health JSON, process listings, or message search results unless the user asks for diagnostics.

Use `.\scripts\nomad-inbox.ps1 tray status` for non-interactive tray verification. It is the preferred status check before telling the user whether the compiled tray and tray-owned HTTP service are running.

When an agent opens this repository as a user workspace:

- Load the built-in startup system prompt.
- Detect the operating system first.
- If it is Windows, run `nomadmail_install_windows_helper`, `node .\service\nomadmail-service.mjs install-windows-helper`, or `.\scripts\nomad-inbox.ps1 install windows-helper` before connecting accounts, report tray availability, and ask before starting the tray controller. Starting the tray keeps local HTTP tools available but must not enable auto sync by itself.
- If it is not Windows, do not install the Windows helper, start the tray, or offer Outlook Desktop COM sync. Use the MCP server for platform-independent local context tools and report what provider sync runtime is missing.
- Do not discover credentials, mailbox profiles, exports, or connected accounts until the user approves the exact source and scope.
- For complex PowerShell diagnostics, create temporary scripts only under ignored scratch locations such as `runtime\agent-scratch\` or the OS temp directory. Do not place ad hoc diagnostic scripts in `scripts\`, `src\`, `service\`, `docs\`, or the repository root. Keep tracked scripts for durable sync/service behavior.
- For broad email-range outputs, give generated markdown, HTML, and JSON reports range-aware names. Include the source and a sortable date label in the folder or filename, for example `unread-outlook-2026-04-29-to-2026-05-06.md`, `unread-outlook-week-of-2026-05-06-index.md`, or `gmail-takeout-2025.md`.

Use this rule before parsing or syncing email for another repository:

- If the user wants NomadInbox's own local store updated, use the default service.
- If the user wants another repository updated, start the MCP/HTTP service or CLI with `NOMADINBOX_DATA_DIR` set to a staging folder inside that target repository.
- Run `dryRun=true` on `nomadmail_import_archive` before writing parsed records.
- Hand the generated `archive-messages.jsonl`, `messages.jsonl`, and, when the target needs provider-specific evidence, `provider-raw.jsonl` to the target repository's own importer and index command.
- Treat `messages.jsonl` as the normalized agent/UI contract. Treat `provider-raw.jsonl` as the provider-specific evidence store for fields that do not fit the canonical message model.

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
- MCP stdio is agent-launched. The Windows tray owns the long-running local HTTP service while the tray is open.
- Default imports and syncs write to NomadInbox `data/` unless `NOMADINBOX_DATA_DIR` is set before the CLI/service starts.
- Gmail API sync requires `NOMADINBOX_GMAIL_ACCESS_TOKEN` or a Gmail-scoped `gcloud` login.
- Outlook Graph sync requires `NOMADINBOX_GRAPH_ACCESS_TOKEN` or an Azure CLI Microsoft Graph token.
- Outlook Desktop sync requires Windows and the signed-in Windows Outlook profile.
- The Windows helper tracks sync operations through `sync-status.json` and `actions.jsonl`, and tracks connected account config through ignored `config/accounts.json`.
- Non-Windows agents should keep the MCP server available for `nomadmail_get_agent_guide`, `nomadmail_search_messages`, and `nomadmail_get_message`, and return a clear unsupported-runtime response for Windows-only helper, tray, and Outlook Desktop operations.
- Archive import still requires an explicitly provided local path.
- Full archive body import still requires `includeBodies=true`.
- Send-style mailbox actions must stay behind the existing confirmation gate before they are added to this service.
- Trash/delete must stay behind a double-confirmation gate before any destructive mailbox action is added to this service.
- Outlook Desktop access must run in the signed-in Windows user session because it depends on the local Outlook profile.

## Diagnostics

```powershell
node .\service\nomadmail-service.mjs agent-guide
node .\service\nomadmail-service.mjs workspace-state
node .\service\nomadmail-service.mjs agent-user-flow
node .\service\nomadmail-service.mjs cross-chat-handoff
node .\service\nomadmail-service.mjs install-windows-helper
node .\service\nomadmail-service.mjs self-test
node .\service\nomadmail-service.mjs tools
.\scripts\nomad-inbox.ps1 doctor
.\scripts\nomad-inbox.ps1 env status
.\scripts\nomad-inbox.ps1 service status
.\scripts\nomad-inbox.ps1 tray status
```
