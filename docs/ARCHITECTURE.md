# NomadInbox Architecture

## Boundary

NomadInbox is independent from OSM, WebLogic, JMS, and any earlier local test harness. It is a user-facing product bootstrap for agent-readable mailbox access.

## High-Level Model

```text
Agent / User Prompt
  |
  v
NomadInbox CLI / future local API
  |
  v
Command Layer
  |
  +-- Provider Registry
  +-- Safety Gate
  +-- Optional Sync Worker
  +-- Optional Tray Controller
  +-- Message Store
  +-- Action Audit Log
  |
  v
Provider Adapters
  |
  +-- Gmail API
  +-- Outlook Graph
  +-- Outlook Desktop
```

## Runtime Data

Runtime data is local and ignored by git:

- `data/messages.jsonl`
- `data/actions.jsonl`
- `data/sync-status.json`
- `data/sync-worker.pid`
- `data/sync-worker.log`
- `data/attachments/`
- token cache files
- provider-specific temporary files

Per-account background sync settings are local and ignored by git:

- `config/accounts.json`

The tracked `config/accounts.example.json` shows the shape users can copy and customize.

## Provider Contract

Providers should expose these capabilities where supported:

- `doctor`
- `accounts list`
- `sync once`
- `service start`
- `service stop`
- `service status`
- `sync`
- `search`
- `get`
- `attachments list`
- `attachments save`
- `compose draft`
- `reply draft`
- `reply-all draft`
- `draft send --confirm`
- `mark-read`
- `mark-unread`
- `flag` / `star`
- `move`
- `archive`
- `trash`

## Safety Gate

Rules:

- Read commands can run after provider auth.
- Draft commands do not imply send.
- Send commands require explicit confirmation.
- Bulk state changes should support dry-run first.
- Permanent delete is not a default action. Prefer trash/archive.
- Every mutating command writes an action record.

## Background Sync

Background sync is optional. The default product remains request-driven.

The first implementation is a user-session PowerShell worker:

```text
nomad-inbox.ps1 service start
  -> starts scripts/nomad-inbox-worker.ps1
  -> reads config/accounts.json
  -> periodically invokes sync once
  -> writes data/sync-status.json
```

This is deliberately not a privileged Windows Service yet. It is easier to explain, safer to run locally, and compatible with desktop providers that require a signed-in user session.

## Tray Controller

The tray controller is also optional:

```text
nomad-inbox.ps1 tray start
  -> starts scripts/nomad-inbox-tray.ps1
  -> exposes start/stop/status/open-config/open-runtime-folder
```

It is a small Windows Forms NotifyIcon process, not a full desktop app.

## Storage Evolution

Bootstrap:

- JSONL for messages and actions.

Next:

- SQLite for durable local store.
- SQLite FTS for search.
- Encrypted local vault for secrets and tokens.
- MCP server for agent-native tool calls.
- Durable scheduler / Windows Task Scheduler integration.
- Optional Windows Service wrapper for non-desktop API providers.
