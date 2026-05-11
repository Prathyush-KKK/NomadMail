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

Connection order:
1. Prefer the configured `nomadmail` MCP server or launch the stdio MCP server if this chat exposes MCP tools.
2. If MCP tools are not visible in this chat, use the tray-owned local HTTP service at `http://127.0.0.1:8791`.
3. If HTTP is not reachable but local shell access is available, use the direct repo commands from this workspace.

First load the canonical repo-owned context:
- prompts/nomadmail-startup.system.md
- docs/governance/WORKSPACE_STATE.md
- docs/runbooks/agent-user-flow.md
- docs/runbooks/agent-service.md

Then refresh live service status before making current claims:
- .\scripts\nomad-inbox.ps1 env status
- node .\service\nomadmail-service.mjs self-test
- .\scripts\nomad-inbox.ps1 tray status

If your environment supports MCP and the `nomadmail` tools are already visible, call:
- nomadmail_get_agent_guide
- nomadmail_get_startup_system_prompt
- nomadmail_get_workspace_state
- nomadmail_get_agent_user_flow
- nomadmail_get_cross_chat_handoff
- nomadmail_list_agent_events
- nomadmail_ack_agent_event
- nomadmail_open_message
- nomadmail_execute_message_action

If your environment supports MCP but the tools are not already visible, launch:

powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\nomadmail-mcp.ps1

Then call the same MCP tools:
- nomadmail_get_agent_guide
- nomadmail_get_startup_system_prompt
- nomadmail_get_workspace_state
- nomadmail_get_agent_user_flow
- nomadmail_get_cross_chat_handoff
- nomadmail_list_agent_events
- nomadmail_ack_agent_event
- nomadmail_open_message
- nomadmail_execute_message_action

If MCP tools are not visible or cannot be launched, use the tray-owned HTTP service when available:
- GET http://127.0.0.1:8791/health
- GET http://127.0.0.1:8791/agent-guide
- GET http://127.0.0.1:8791/cross-chat-handoff
- GET http://127.0.0.1:8791/agent-events?assignedAgent=codex&status=pending
- GET http://127.0.0.1:8791/messages?query=<query>&limit=5

If both MCP and HTTP are unavailable but local shell access works, use:
- node .\service\nomadmail-service.mjs cross-chat-handoff
- node .\service\nomadmail-service.mjs agent-events --assigned-agent codex --status pending
- node .\service\nomadmail-service.mjs tools

Do not discover accounts, tokens, exports, folders, or mailbox contents until the user approves the exact source and scope.

For latest-mail questions, run one request-scoped live sync against already configured and enabled accounts before answering. If sync cannot complete, say the latest email cannot be confirmed.

For Outlook Desktop direct navigation, prefer `nomadmail_open_message` with the selected message id or conversation id. It resolves the provider-native Outlook EntryID and opens the item through Outlook COM `Display()`. Use search terms only as a fallback when the provider-native ID is missing or stale.

For Outlook Desktop live-message actions, use `nomadmail_execute_message_action` only after user approval. Draft actions save drafts only. `send-draft` requires `confirmSend`; mark/flag/move/archive/save attachment require `confirmAction`; trash/delete requires `confirmDelete` and the returned `confirmFinal` phrase.

For broad generated email reports, write only under ignored scratch locations such as runtime\agent-scratch\ and include source plus date range in filenames.

For assigned-agent automation, call `nomadmail_list_agent_events` with your agent label, such as `codex`, before asking the user which pending mail event to inspect. Acknowledge events with `nomadmail_ack_agent_event` only after they are handled. Event presence does not authorize mailbox mutation.

Keep user-facing status short unless diagnostics are requested.
```

## Agent Connection Order

1. Use the configured `nomadmail` MCP server first when this chat exposes MCP tools.
2. Use tray-owned local HTTP second when MCP tools are not visible or cannot be launched.
3. Use direct repo CLI commands third when the agent has local shell access but MCP/HTTP are unavailable.

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

Use `nomadmail_open_message` or HTTP `POST /messages/open` first. Use `nomadmail_execute_message_action` or HTTP `POST /messages/action` for approved Outlook Desktop actions. Use `conversationId` to group related records and `EntryID` to open a specific Outlook item only when the tool surface is unavailable.
