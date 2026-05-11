# Agent User Flow Test Matrix

This document records the inputs and outputs for the complete NomadInbox / NomadMail user-flow scenarios.

Executable source of truth:

- `tests/agent-user-flow.ps1` validates the full synthetic path without touching live mailbox data.
- `tests/smoke.ps1` validates the broader service/tool surface.
- `tests/new-clone.ps1` validates a brand new clone on a new system.

For cross-agent execution instructions and reporting format, see
[Testing Handoff](testing-handoff.md).

The synthetic test uses a temporary `NOMADINBOX_DATA_DIR`, a temporary HTTP port, and one generated EML message. The approved live validation uses the configured local Outlook Desktop account and does not send, delete, move, archive, save attachments, enable body storage, or enable auto sync unless the exact action is explicitly approved.

## Scenario Coverage Summary

| Scenario | Test Type | Input | Expected Output | Validated Output |
|---|---|---|---|---|
| First prompt in fresh workspace | Synthetic | Agent loads startup prompt, workspace state, user-flow doc, repository health, provider/account status, and git ignore boundaries. | User sees capabilities, storage boundary, Windows helper/tray/MCP state, approval gates, and a source/scope choice. | Test confirms `agent-user-flow` contains `Flow 1: First Prompt` and expected first-response content. |
| Source and scope approval | Synthetic | User chooses a source/scope such as Outlook Desktop inbox, Gmail headers, Outlook Graph headers, or local export import. | Agent confirms source/scope, says what will be stored locally, states no send/delete/move/attachment save, and asks before proceeding. | Test confirms output includes `I will set up <source> for <scope>` and `I will not send, delete, move, or save attachments`. |
| First sync or import | Synthetic | Generated EML file, `import eml --dry-run`, then approved `import eml`. | Dry run reports one message; write import stores one read-only archive message; auto sync remains off. | Dry run returned `status=dryRun`, `importedMessages=1`; import returned `status=ok`, `importedMessages=1`, `actionable=false`. |
| Service and tray setup | Synthetic and live | User asks to install/start/run service. On Windows, agent starts or verifies compiled tray; for regular use it can register current-user startup and show the tray popup after approval. | User is told NomadMail is available from the NomadInbox system tray; no endpoint catalog or raw JSON dump; auto sync remains off. | Synthetic contract passed. Live run returned `tray=started`, `trayClient=compiled`, with message telling user NomadMail is available from tray. |
| Daily mail query choices | Synthetic | At least one source is synced/imported, or user asks what to do next. | Agent offers choices: latest email with content, unread today/week, needs-action, search by project/sender/date/attachment, low-priority mail, draft actions, and Outlook Desktop open/navigation when supported. | Test confirms the flow doc contains `Show my latest email with content`, `Summarize unread mail from today`, `Find mail that needs my action`, `Draft a reply or new email`, and `Open a selected Outlook Desktop message or thread in Outlook`. |
| Latest email freshness | Synthetic and live | User asks for latest/recent/newest email. | Agent runs one request-scoped live sync first for enabled live accounts; if sync cannot complete, it says latest email cannot be confirmed. | Synthetic diagnostic check preserved freshness guidance. Live `/messages/latest` ran sync-first and returned `status=ok`, `contentAvailable=true`, `provider=outlook-desktop`, `sourceType=live-sync`. |
| Broad daily digest or range report | Synthetic | User asks for today, weekly unread, project mail, or a broad range. | Agent resolves absolute local date range, groups messages, saves range-aware report under ignored `runtime/agent-scratch/`, and asks which group to open. | Test confirms output contract includes `runtime/agent-scratch`, source/date range naming, and `Which group should I open first?`. |
| Mail action follow-up | Synthetic and live | User selects a message and asks to open it, go to the thread, reply, forward, send, move, archive, mark, flag, trash, or delete. | Agent verifies live/actionable status, opens Outlook Desktop messages by EntryID when supported, uses `nomadmail_execute_message_action` for approved Outlook Desktop actions, drafts before send, asks exact send approval, and requires double confirmation for trash/delete. | Synthetic test confirms draft/send/delete wording, dry-run Outlook open resolution, dry-run action execution, and confirmation gates. Live `/message-actions` returned `actionable=true`, primary actions `Draft reply`, `Draft reply all`, and `Draft new mail`, plus delete approval requiring two confirmations. |
| Archive read-only action boundary | Synthetic | Search imported archive message. | Imported message can be summarized or used to find matching live message; mailbox mutations are blocked. | Search returned one archive result with `sourceType=archive-import`, `actionMenu.available=false`, and quick actions including summarize/find matching live message. |
| Assigned-agent automation | Synthetic | Queue Codex events from a synthetic live message, list pending events, then acknowledge one event. | Event queue stores bounded local references under ignored runtime data; Codex can pull and acknowledge events; event does not authorize mailbox mutation. | HTTP automation cycle created one `codex` event, listing returned the synthetic live message reference, and acknowledgement changed status to `acknowledged`. |
| Agent user flow service surface | Synthetic and live | Agent calls `nomadmail_get_agent_user_flow`, CLI `agent-user-flow`, HTTP `/agent-user-flow`, or `agent-guide`. | Flow is retrievable by agents and embedded in the guide. | Tool exists, CLI output includes Flow 1 and Flow 5, HTTP `/agent-user-flow` returned `ok`, and `/agent-guide` embedded the flow. |
| Git/privacy boundary | Live | After live sync/search/latest-email checks. | Runtime data and local account config stay ignored by git. | `git check-ignore` confirmed `data/`, `data/messages.jsonl`, `data/provider-raw.jsonl`, `data/sync-status.json`, `config/accounts.json`, and `runtime/agent-scratch` are ignored. |

## Synthetic Scenario Inputs And Outputs

Run command:

```powershell
.\tests\agent-user-flow.ps1
```

Runtime inputs:

- temporary `NOMADINBOX_DATA_DIR`
- random local HTTP port in the `18100` to `18900` range
- generated EML file named `daily-flow-scenario.eml`
- generated message headers:
  - `From: Daily Flow Sender <sender@example.com>`
  - `To: Example User <user@example.com>`
  - `Subject: Daily mail flow archive scenario`
  - `Date: Wed, 06 May 2026 09:15:00 +0530`
  - `Message-ID: <daily-flow-scenario@example.com>`

Validated command/API inputs:

| Step | Input | Expected Output |
|---|---|---|
| Node syntax check | `node --check service/nomadmail-service.mjs` | No syntax error. |
| Runtime setup | `scripts/nomad-inbox.ps1 setup` with temp `NOMADINBOX_DATA_DIR` | JSON `status=ok`. |
| Archive import dry run | `import eml --path <temp EML> --source agent-flow-test --max-messages 1 --dry-run` | JSON `status=dryRun`, `importedMessages=1`. |
| Archive import write | `import eml --path <temp EML> --source agent-flow-test --max-messages 1` | JSON `status=ok`, `importedMessages=1`, `actionable=false`. |
| HTTP service start | `node service/nomadmail-service.mjs http --port <random> --host 127.0.0.1` | `/health` becomes reachable with `status=ok`. |
| Tool list | `node service/nomadmail-service.mjs tools` | Includes `nomadmail_get_agent_user_flow`. |
| CLI user flow | `node service/nomadmail-service.mjs agent-user-flow` | JSON `status=ok`, text includes `Flow 1: First Prompt` and `Flow 5: Daily Mail Query Menu`. |
| Startup prompt | `node service/nomadmail-service.mjs system-prompt` | Text requires `docs/runbooks/agent-user-flow.md` and `Your first response must show`. |
| Workspace state | `node service/nomadmail-service.mjs workspace-state` | Text mentions `agent-user-flow.md`. |
| Agent guide | `node service/nomadmail-service.mjs agent-guide` | Embeds `agentUserFlow.text` and startup guidance references `agentUserFlow.text`. |
| HTTP user flow | `GET /agent-user-flow` | JSON `status=ok`, text includes `Flow End State`. |
| HTTP guide | `GET /agent-guide` | JSON `status=ok`, embedded user flow includes `Daily Mail Query Menu`. |
| Search | `GET /messages?query=daily%20flow&limit=5` | JSON `status=ok`, `count >= 1`. |
| Archive action menu | selected imported message | `sourceType=archive-import`, `actionMenu.available=false`, quick actions include summarize and find matching live message. |
| Message action guide | `GET /message-actions?id=<archive-message-id>` | JSON `status=ok`, `actionGuide.actionable=false`, prompt offers summarize or find matching live message. |
| Latest diagnostic read | `POST /messages/latest` with `syncFirst=false`, `requireContent=true` | JSON preserves freshness rule and does not present stale data as latest. |
| Agent automation cycle | `POST /agent-events/automation-cycle` with `assignedAgent=codex` after writing one synthetic live message | JSON `status=ok`, `createdCount=1`, safety text says events do not imply approval. |
| Agent event listing | `GET /agent-events?assignedAgent=codex&status=pending` | JSON `status=ok`, one pending event references the synthetic live message id. |
| Agent event acknowledgement | `POST /agent-events/<event-id>/ack` | JSON `status=ok`, event status becomes `acknowledged`. |
| Self-test | `node service/nomadmail-service.mjs self-test` | JSON `status=ok`, `agentUserFlowStatus=ok`. |

Observed synthetic test output:

```json
{
  "status": "ok",
  "service": "NomadMail",
  "http": {
    "health": "ok",
    "agentUserFlow": "ok",
    "searchCount": 1,
    "latestDiagnosticNoLiveData": "notFound"
  },
  "scenarios": [
    "first prompt in fresh workspace",
    "source and scope approval",
    "first sync or import",
    "service and tray setup",
    "daily mail query choices",
    "latest email freshness",
    "broad daily digest or range report",
    "mail action follow-up",
    "assigned-agent automation"
  ]
}
```

## Approved Live Outlook Validation Inputs And Outputs

Live validation was approved by the user and run against the configured local Outlook Desktop account.

Approved live boundaries:

- allowed: tray start, read-only service checks, one-shot Outlook Desktop sync, search, latest-email lookup, action-guidance lookup
- not allowed/performed without approval: send, delete/trash, move, archive, mark read/unread, save attachments, enable full body storage, enable auto sync

Live account input:

```json
{
  "accountId": "desktop-outlook",
  "provider": "outlook-desktop",
  "enabled": true,
  "folder": "Inbox",
  "limit": 200,
  "includeBodies": false,
  "includeAttachments": true,
  "saveAttachments": false
}
```

Validated live outputs:

| Step | Input | Observed Output |
|---|---|---|
| Tray status before start | `scripts/nomad-inbox.ps1 tray status` | Tray was stopped; compiled tray executable existed; helper installed; HTTP was unreachable; worker stopped. |
| Tray start | `scripts/nomad-inbox.ps1 tray start` | `status=ok`, `tray=started`, `trayClient=compiled`, user-facing message says NomadMail is available from system tray. |
| One-shot live sync | `scripts/nomad-inbox.ps1 sync once --account-id desktop-outlook` | `status=ok`, `accountCount=1`, provider `outlook-desktop`, `synced=190`. |
| HTTP health | `GET http://127.0.0.1:8791/health` | `status=ok`, worker `stopped`. |
| HTTP user flow | `GET /agent-user-flow` | `status=ok`, flow includes daily choices, latest freshness, and action approvals. |
| HTTP guide | `GET /agent-guide` | `status=ok`, embeds `agentUserFlow.text`. |
| Search | `GET /messages?query=&includeLive=true&includeArchive=true&limit=5` | `status=ok`, `count=5`, first live message found. |
| Live action guidance | `GET /message-actions?id=<first-live-message-id>` | `status=ok`, `actionable=true`, primary actions included `Draft reply`, `Draft reply all`, and `Draft new mail`; delete rule required two confirmations. |
| Latest email with content | `POST /messages/latest` with `accountId=desktop-outlook`, `syncFirst=true`, `requireContent=true` | `status=ok`, fresh sync completed, `synced=190`, `contentAvailable=true`, provider `outlook-desktop`, source `live-sync`, local received time present, subject/sender/preview present. |
| Git/privacy check | `git check-ignore` on runtime paths | `data/`, message stores, sync status, account config, and scratch paths are ignored. |

Latest-email observed output shape:

```json
{
  "status": "ok",
  "syncFirst": true,
  "requireContent": true,
  "contentAvailable": true,
  "syncStatus": "ok",
  "synced": 190,
  "provider": "outlook-desktop",
  "sourceType": "live-sync",
  "receivedAtLocal": "May 06, 2026, 08:04 PM GMT+5:30",
  "hasSubject": true,
  "hasSender": true,
  "hasPreview": true,
  "actionGuideStatus": true
}
```

The live final response intentionally did not print email subject/body content. That keeps normal setup validation from exposing private mail content in chat.

## Rerun Checklist

Use this when the startup flow, service guide, daily-mail menu, latest-email behavior, or action approval rules change.

```powershell
node --check .\service\nomadmail-service.mjs
.\scripts\validate.ps1
.\tests\agent-user-flow.ps1
.\tests\smoke.ps1
git diff --check
```

For live validation after explicit approval:

```powershell
.\scripts\nomad-inbox.ps1 accounts list
.\scripts\nomad-inbox.ps1 tray start
.\scripts\nomad-inbox.ps1 sync once --account-id desktop-outlook
Invoke-RestMethod http://127.0.0.1:8791/health
Invoke-RestMethod http://127.0.0.1:8791/agent-user-flow
Invoke-RestMethod "http://127.0.0.1:8791/messages?query=&includeLive=true&includeArchive=true&limit=5"
Invoke-RestMethod -Method Post http://127.0.0.1:8791/messages/latest -Body '{"accountId":"desktop-outlook","syncFirst":true,"requireContent":true}' -ContentType "application/json"
```

Do not run live validation unless the user approves the mailbox source and scope.
