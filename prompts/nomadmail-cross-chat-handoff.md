# NomadMail Cross-Chat Handoff

Use this when a user opens a different AI chat session and wants that agent to use the same local NomadInbox/NomadMail workspace.

This does not connect to a previous chat transcript. It connects the new agent to the same local repository, ignored runtime store, MCP server, and loopback HTTP service.

On Windows, the helper registers user environment variables so future terminals and agent sessions can discover the workspace without memorizing commands. Prefer `NOMADINBOX_HOME` when the user gives only "use NomadInbox" or only gives the workspace path.

## Prompt To Give Another Agent

```text
Open this workspace:

C:\Users\prat\Documents\osm\NomadInbox

If this path was not provided, discover it from the user environment:

$nomadInboxHome = [Environment]::GetEnvironmentVariable("NOMADINBOX_HOME", "User")
if (-not $nomadInboxHome) { $nomadInboxHome = $env:NOMADINBOX_HOME }
cd $nomadInboxHome

Use NomadInbox as the local mailbox workspace and NomadMail as the callable agent service.

First load the canonical repo-owned context:
- prompts/nomadmail-startup.system.md
- docs/governance/WORKSPACE_STATE.md
- docs/runbooks/agent-user-flow.md
- docs/runbooks/agent-service.md

Then refresh live service status before making current claims:
- .\scripts\nomad-inbox.ps1 env status
- node .\service\nomadmail-service.mjs self-test
- .\scripts\nomad-inbox.ps1 tray status

If the tray-owned HTTP service is already available, use:
- GET http://127.0.0.1:8791/health
- GET http://127.0.0.1:8791/agent-guide
- GET http://127.0.0.1:8791/cross-chat-handoff
- GET http://127.0.0.1:8791/messages?query=<query>&limit=5

If your environment supports MCP, launch:

powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\nomadmail-mcp.ps1

Then call:
- nomadmail_get_agent_guide
- nomadmail_get_startup_system_prompt
- nomadmail_get_workspace_state
- nomadmail_get_agent_user_flow
- nomadmail_get_cross_chat_handoff

Do not discover accounts, tokens, exports, folders, or mailbox contents until the user approves the exact source and scope.

For latest-mail questions, run one request-scoped live sync against already configured and enabled accounts before answering. If sync cannot complete, say the latest email cannot be confirmed.

For Outlook Desktop direct navigation, prefer provider-native Outlook EntryID and call Outlook COM Display(). Use search terms only as a fallback when the provider-native ID is missing or stale.

For broad generated email reports, write only under ignored scratch locations such as runtime\agent-scratch\ and include source plus date range in filenames.

Keep user-facing status short unless diagnostics are requested.
```

## Agent Connection Order

1. Use MCP if the agent platform supports stdio MCP.
2. Use local HTTP if the Windows tray or HTTP launcher is running.
3. Use direct repo scripts only when the agent has local shell access.

## Storage Boundary

Default writes go to NomadInbox's ignored `data/` directory. For another repository, set `NOMADINBOX_DATA_DIR` before launching the CLI, MCP server, HTTP server, or tray.

## Direct Mail Navigation

Outlook Desktop messages should preserve their Outlook `EntryID`. To open a specific message:

```powershell
$ol = New-Object -ComObject Outlook.Application
$ns = $ol.GetNamespace("MAPI")
$item = $ns.GetItemFromID("<outlook-entry-id>")
$item.Display()
```

Use `conversationId` to group related records and `EntryID` to open a specific Outlook item.
