# Agent User Flow

This runbook defines the user-facing flow an agent should follow from the first NomadInbox prompt through the point where the user can query daily mail.

NomadInbox owns this flow. The user should not have to maintain a startup prompt or remember service commands.

The tested scenario inputs and outputs are documented in
[Agent User Flow Test Matrix](agent-user-flow-test-matrix.md).

## Default User-Facing Mode

Default responses are compact and action-oriented:

- show status in plain language
- show only the next useful choices
- hide raw JSON, endpoint catalogs, process lists, message IDs, and logs unless diagnostics are requested
- show local user time for mail timestamps and date scopes
- treat mailbox access, body storage, attachments, send, move, archive, trash, delete, and auto sync as explicit approval gates

The agent may use detailed diagnostics internally, but user-facing setup and mail summaries should stay short.

## Flow End State

The flow is complete when the user has at least one available mail source path and the agent can present daily-mail query choices such as:

- latest email with content
- unread mail from today
- unread mail from this week
- priority mail that likely needs action
- mail by project, topic, sender, account, folder, or date range
- mail with attachments
- follow-ups, blockers, approvals, or waiting-on-me items
- newsletters, promotions, bills, statements, or low-priority mail
- draft a reply, reply all, forward, or new email from a selected live message
- mark read/unread, flag/star, move/archive, or trash/delete when the live provider supports it

The end state is not "all mail is synced". The end state is that the user understands what source is connected, what scope is local, how fresh it is, and what they can ask next.

## Flow 1: First Prompt In A Fresh Workspace

Trigger:

- the user opens the cloned repository with an agent
- the user says `start`, `hello`, `setup`, or asks what NomadInbox can do

Agent actions:

1. Load `prompts/nomadmail-startup.system.md` or call `nomadmail_get_startup_system_prompt`.
2. Read `docs/governance/WORKSPACE_STATE.md`.
3. Detect OS, workspace path, Node availability, helper support, tray support, and git ignore protection.
4. Run non-mail checks only: repository health, provider list, account config status, service health when available.
5. On Windows, install the Windows helper if it is not installed. For regular use after user approval, start the tray, register it for current-user Windows startup, and show the status popup. This initializes local status/config paths but does not read mail or start auto sync.
6. Do not connect accounts, discover credentials, scan mail exports, read mail, store bodies, save attachments, start auto sync, or mutate mail yet.

User-facing response shape:

```text
NomadInbox is ready as the local workspace. NomadMail is the callable service agents use.

Available now:
- local MCP/HTTP service checks
- provider/account discovery
- local message search after sync/import
- read-only archive import
- draft-first mail action guidance

Local data stays in <data path> and is ignored by git.
On this system, <Windows helper/tray/MCP status>.

Choose one source and one scope:
1. Outlook Desktop inbox for the last 30 days
2. Gmail inbox headers
3. Outlook Graph inbox headers
4. local MBOX/EML/JSONL export as read-only archive context
```

If the workspace already has synced or imported data, do not re-onboard as blank. Report the current counts and freshness, then present daily-mail query choices.

## Flow 2: User Chooses A Source

Trigger:

- the user chooses Gmail, Outlook Graph, Outlook Desktop, or local export

Agent actions:

1. Confirm the source and scope in local user time.
2. Check only the required provider runtime.
3. Ask for missing prerequisites only when needed.
4. Enable or configure only the approved account/scope.
5. Keep the first sync/import small unless the user asks for a wider range.

User-facing response shape:

```text
I will set up <source> for <scope>. This will store <headers/snippets/bodies/attachments metadata> in the local ignored data folder.

I will not send, delete, move, or save attachments.
Proceed?
```

Source-specific notes:

- Outlook Desktop uses the signed-in Windows Outlook profile and local COM access.
- Outlook Graph needs a Microsoft Graph token or app setup.
- Gmail needs Gmail OAuth/token access.
- Local exports need an explicit path and import dry run first.

## Flow 3: First Sync Or Import

Trigger:

- the user approves a source/scope

Agent actions:

1. Run `sync once` for live providers or import dry run for archive exports.
2. For local exports, show dry-run count and ask before writing imported records.
3. Store canonical records in `data/messages.jsonl` for live sync or `data/archive-messages.jsonl` for archive import.
4. Store provider-specific snapshots in `data/provider-raw.jsonl` only when account settings allow raw capture.
5. Write sync/import status and action audit records locally.
6. Do not enable background sync automatically.

User-facing response shape:

```text
Sync/import completed.

Local store now has:
- <N> live synced messages
- <N> imported archive messages
- last sync/import: <local time>

Auto sync is off. You can query this local mail context now, or enable auto sync from the tray after accounts are connected.
```

If sync/import fails, report the reason and the next recoverable step. Do not present stale data as fresh.

## Flow 4: Start Tray Or Service

Trigger:

- the user asks to install, start, run, or keep NomadMail available

Agent actions:

1. On Windows, start or verify the compiled tray client. For regular use after approval, register it in the current user's Windows Startup folder and show the status popup on launch.
2. Do not start duplicate tray instances.
3. Tell the user the tray owns the long-running local HTTP service.
4. Do not dump endpoint catalogs or health JSON unless diagnostics are requested.

User-facing response shape:

```text
NomadMail is running from the NomadInbox system tray.

Click the tray icon for Refresh, Sync now, auto sync, and account status. Open Settings from the tray for diagnostics.
Auto sync is still off until you enable it.
```

On non-Windows, keep MCP available and explain that Windows tray and Outlook Desktop COM are not supported on that OS.

## Flow 5: Daily Mail Query Menu

Trigger:

- at least one source is synced/imported, or the user asks what they can do next

Agent response:

```text
You can ask:
1. Show my latest email with content.
2. Summarize unread mail from today.
3. Show unread mail from this week.
4. Find mail that needs my action.
5. Find mail about a project, person, account, folder, date range, or attachment.
6. Show bills, statements, promotions, or low-priority mail separately.
7. Draft a reply or new email from a selected live message.
8. Open a selected Outlook Desktop message or thread in Outlook.
```

The agent should adapt this list to the available data:

- If only archive data exists, remove live mailbox actions and offer summarize/extract/find matching live message.
- If no body/snippet is stored, say content summaries may be limited and offer to sync/import with approved body snippets.
- If no live account is enabled, latest-email freshness cannot be confirmed.
- If the tray is running, mention the tray only as the place for status, sync now, and auto sync.

## Flow 6: Latest Email Or Recent Mail

Trigger:

- the user asks for latest email, newest mail, recent mail, or latest mail content

Agent actions:

1. Run one request-scoped live sync against already configured and enabled live accounts.
2. Prefer `nomadmail_get_latest_message` with `syncFirst=true` and `requireContent=true`.
3. If sync fails, say the latest email cannot be confirmed.
4. Report local received time, sender, subject, and snippet/body preview.
5. Offer the compact action menu for the selected live message.

User-facing response shape:

```text
I synced first and found the latest email with content.

<local time> - <sender>
<subject>
<short snippet/body preview>

Actions available: open in Outlook when supported, draft reply, reply all, forward, draft new email, mark read/unread, flag, move/archive, or trash/delete when supported.
```

Do not expose raw IDs unless diagnostics are requested.

## Flow 7: Broad Daily Digest Or Range Report

Trigger:

- the user asks for today's mail, weekly unread mail, project mail, or a large range

Agent actions:

1. Resolve relative dates into absolute local date/time ranges before reading.
2. Sync first when the request is about current live mail and enabled accounts exist.
3. Search/filter local records by source, account, folder, read state, sender, subject, body/snippet, attachments, and timestamps.
4. If the range is large, save generated markdown/HTML/JSON under ignored `runtime/agent-scratch/`.
5. Include the source and date range in generated filenames.

User-facing response shape:

```text
I checked <source> for <absolute local date range>.

Found <N> relevant messages.
Top groups:
- needs action: <N>
- informational: <N>
- attachments: <N>
- low priority: <N>

I saved the detailed report at <runtime/agent-scratch/...range-aware-name.md>.
Which group should I open first?
```

## Flow 8: Mail Action Follow-Up

Trigger:

- the user selects a message and asks to open it, go to the thread, reply, forward, send, move, archive, mark, flag, trash, or delete

Agent actions:

1. Verify the message is live and actionable, not archive-only.
2. Check `actionMenu` or `nomadmail_get_message_actions`.
3. For Outlook Desktop open/navigation, use `nomadmail_open_message` with the selected message id or conversation id.
4. For approved Outlook Desktop actions, use `nomadmail_execute_message_action`.
5. Draft before send. Draft actions save an Outlook draft and do not send it.
6. Send only after explicit approval of exact recipients, subject, and body, then call `send-draft` with `confirmSend=true`.
7. For mark/flag/move/archive/save attachment, call the action with `confirmAction=true`.
8. For trash/delete, ask twice. The second confirmation must name the message and mailbox effect; then call the action with `confirmDelete=true` and the returned `confirmFinal` phrase.
9. Log actions locally.

User-facing response shape for draft/send:

```text
I drafted this reply:

To: <recipients>
Subject: <subject>
Body:
<body>

Approve sending this exact draft?
```

User-facing response shape for trash/delete:

```text
This will move/delete "<subject>" from <mailbox/folder>.

First confirmation: do you want to continue?
```

Then:

```text
Final confirmation required: reply with approval to trash/delete "<subject>" from <mailbox/folder>.
```

## Flow 9: Auto Sync

Trigger:

- the user toggles auto sync in the tray or asks the agent to enable it

Agent actions:

1. Confirm at least one account is enabled.
2. Tell the user what accounts/scopes will refresh.
3. Start the background worker only after explicit approval.
4. Keep status visible in tray; keep logs in Settings.

User-facing response shape:

```text
Auto sync is on for <accounts/scopes>.

The tray will show last sync, next sync, account status, and errors. Use Sync now for an immediate refresh.
```

If auto sync is off:

```text
Auto sync is off. Open your agent and ask it to sync, or use Sync now from the tray for a manual refresh.
```

## Flow 10: Assigned-Agent Automation

Trigger:

- the user asks NomadInbox to push updates to Codex, Claude Code, Kiro, or another assigned agent
- the tray/worker has synced mail and the user wants pending mail review prompts queued for an agent

Agent actions:

1. Explain that NomadInbox queues local review events and the assigned agent pulls them through MCP/HTTP.
2. Run `nomadmail_run_agent_automation_cycle` only for already synced mail, or with `syncFirst=true` only when the user approves a freshness sync against already enabled accounts.
3. Store pending events in ignored `data/agent-events.jsonl`.
4. Tell the assigned agent to call `nomadmail_list_agent_events` with its agent label, such as `codex`.
5. Acknowledge events with `nomadmail_ack_agent_event` only after they are handled.
6. Do not treat an event as approval to fetch additional content, send, move, archive, mark, save attachments, trash, or delete.

User-facing response shape:

```text
I queued <N> local NomadMail events for <assigned agent>.

Open <assigned agent> and ask it to check pending NomadMail events. It will show the event list first, then ask which message to inspect.
```

If there are no events:

```text
No pending NomadMail events are queued for <assigned agent>. You can run Sync now or ask for a fresh automation cycle after accounts are connected.
```

## Flow 10: Closeout

At the end of meaningful setup or docs/contract work:

1. Update `docs/governance/WORKSPACE_STATE.md`.
2. Run validation when repository behavior/docs were changed.
3. Do not stage or commit runtime data.
4. Summarize what changed and what remains pending.

For normal mail-query sessions, do not update product docs unless behavior changed.
