# Codex Automation

This runbook describes the local NomadMail automation pattern for Codex.

NomadInbox does not push private mailbox content into a hosted chat. It queues local review events, and Codex pulls those events through the NomadMail MCP server.

## Flow

```text
NomadInbox sync/tray/worker
  -> NomadMail automation cycle
  -> data\agent-events.jsonl
  -> Codex MCP tool call
  -> user-approved follow-up
```

The event queue is ignored by git. It contains bounded local references and short summaries, not full message bodies by default.

## Codex MCP Server

Register NomadMail as a local Codex MCP server:

```toml
[mcp_servers.nomadmail]
command = "node"
args = ["C:/Users/prat/Documents/osm/NomadInbox/service/nomadmail-service.mjs", "mcp"]
```

After the Windows helper is installed, this path can also be discovered from `NOMADINBOX_HOME`, but Codex config works best with an explicit command.

## Agent Startup Prompt

When Codex starts in this workspace, ask it:

```text
Use the nomadmail MCP server. First call nomadmail_get_agent_guide, then call nomadmail_list_agent_events with assignedAgent=codex and status=pending. If events exist, summarize the pending event list without dumping raw JSON. Ask me which event to inspect. Do not fetch full bodies or perform mailbox actions unless I approve.
```

## Creating Events

Run one local automation cycle without syncing first:

```powershell
node .\service\nomadmail-service.mjs agent-automation-cycle --assigned-agent codex --limit 10
```

Run a freshness sync first, using only already configured and enabled accounts:

```powershell
node .\service\nomadmail-service.mjs agent-automation-cycle --assigned-agent codex --sync-first --limit 10
```

The MCP equivalent is `nomadmail_run_agent_automation_cycle`.

## Reading Events

CLI:

```powershell
node .\service\nomadmail-service.mjs agent-events --assigned-agent codex --status pending
```

HTTP, when the tray-owned service is running:

```powershell
Invoke-RestMethod "http://127.0.0.1:8791/agent-events?assignedAgent=codex&status=pending"
```

MCP:

```text
nomadmail_list_agent_events({ "assignedAgent": "codex", "status": "pending" })
```

## Acknowledging Events

CLI:

```powershell
node .\service\nomadmail-service.mjs ack-agent-event --event-id <event-id> --acknowledged-by codex
```

HTTP:

```powershell
Invoke-RestMethod -Method Post "http://127.0.0.1:8791/agent-events/<event-id>/ack" -Body '{"acknowledgedBy":"codex"}' -ContentType 'application/json'
```

MCP:

```text
nomadmail_ack_agent_event({ "eventId": "<event-id>", "acknowledgedBy": "codex" })
```

## Safety

- An event is only a review prompt.
- An event is not approval to fetch more content.
- An event is not approval to send, delete, move, archive, mark, flag, or save attachments.
- Drafts must be created before send.
- Send requires explicit approval of the exact draft.
- Trash/delete requires double explicit approval.
- Full bodies and attachment bytes stay out unless the user explicitly enables that scope.

## Expected Codex Behavior

On session start or when asked to check mail automation, Codex should:

1. Call `nomadmail_get_agent_guide`.
2. Call `nomadmail_list_agent_events` with `assignedAgent=codex`.
3. Show a compact pending-event summary.
4. Ask which event to inspect.
5. Fetch the referenced message only after the user chooses it.
6. Offer the normal NomadMail action menu after message discovery.
7. Acknowledge the event only after the user says it is handled or Codex has completed the requested follow-up.
