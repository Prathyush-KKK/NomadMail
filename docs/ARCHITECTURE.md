# NomadInbox Architecture

## Boundary

NomadInbox is independent from OSM, WebLogic, JMS, and any earlier local test harness. It is a user-facing product bootstrap for agent-readable mailbox access.

## High-Level Model

```text
Agent / User Prompt
  |
  v
NomadMail MCP Server / NomadMail Local HTTP / NomadInbox CLI
  |
  v
Command Layer
  |
  +-- Provider Registry
  +-- Safety Gate
  +-- Optional Sync Worker
  +-- Optional Tray Controller
  +-- Archive Importer
  +-- Backup Status / User Prompts
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

NomadMail is the callable service facade over the NomadInbox core. It exposes
the same local contracts to different agents through:

- MCP over stdio via `scripts/nomadmail-mcp.ps1`.
- Local HTTP on `127.0.0.1:8791` via `scripts/nomadmail-http.ps1`.
- Existing direct PowerShell CLI calls via `scripts/nomad-inbox.ps1`.

The MCP/HTTP service runtime is Node.js and should remain platform independent.
Provider sync and archive import currently delegate to the NomadInbox PowerShell
core. Windows agents install the PowerShell helper to initialize ignored runtime
state and track connected account config. Non-Windows agents keep the MCP server
available for local JSONL context tools and return clear unsupported-runtime
guidance for Windows-only tray and Outlook Desktop operations.

## Runtime Data

Runtime data is local and ignored by git:

- `data/messages.jsonl`
- `data/archive-messages.jsonl`
- `data/archive-index.jsonl`
- `data/import-status.json`
- `data/actions.jsonl`
- `data/sync-status.json`
- `data/sync-worker.pid`
- `data/sync-worker.log`
- `data/attachments/`
- token cache files
- provider-specific temporary files
- local mail export files such as `.mbox`, `.eml`, `.pst`, and `.msg`

Per-account background sync settings are local and ignored by git:

- `config/accounts.json`

The tracked `config/accounts.example.json` shows the shape users can copy and customize.

## Agent Service Contract

NomadMail currently exposes these MCP tools:

- `nomadmail_get_agent_guide`
- `nomadmail_install_windows_helper`
- `nomadmail_health_check`
- `nomadmail_list_providers`
- `nomadmail_list_accounts`
- `nomadmail_sync_once`
- `nomadmail_search_messages`
- `nomadmail_get_message`
- `nomadmail_get_backup_status`
- `nomadmail_get_service_status`
- `nomadmail_start_service`
- `nomadmail_stop_service`
- `nomadmail_import_archive`

The service runtime is `service/nomadmail-service.mjs`. It uses Node.js with no
external package dependency and calls the existing PowerShell CLI for command
operations. Local message search reads the ignored JSONL stores directly so MCP
and HTTP clients get a fast provider-neutral search surface.

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

Bootstrap provider sync is implemented for:

- Gmail API using `NOMADINBOX_GMAIL_ACCESS_TOKEN` or `gcloud auth print-access-token`.
- Outlook Graph using `NOMADINBOX_GRAPH_ACCESS_TOKEN` or Azure CLI Graph token acquisition.
- Outlook Desktop using Windows Outlook COM in the signed-in desktop session.

These bootstrap adapters store normalized metadata and snippets in
`data/messages.jsonl`. Draft, send, attachment hydration, and state mutation
remain governed by the safety gate before service exposure.

## Archive Import Contract

Archive import is an optional context-enrichment layer. It is not the primary live mailbox control path.

Supported bootstrap formats:

- `eml`: one `.eml` file or a folder of `.eml` files.
- `mbox`: Gmail Takeout-style mailbox export.
- `jsonl`: existing NomadInbox-style message records.

Planned formats:

- `pst`
- `msg`

Imported records use the same message schema but set:

- `provider = archive-import`
- `sourceType = archive-import`
- `actionable = false`
- `capabilities = []`
- `sourceProvider`, `sourcePathHash`, and `importBatchId` for provenance

Archive data writes to `data/archive-messages.jsonl` and `data/archive-index.jsonl`. The index is a disposable search projection; the message record preserves normalized metadata and optional body text. Full archive body storage requires explicit `--include-bodies`.

## Backup Status And User Prompts

`backup status` combines live sync and archive import stats. It reports how many live synced messages and archive imported messages are locally available, then emits user-facing prompts that guide the user to sync or import more mail exports.

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
  -> exposes agent-connect/auto-sync-toggle/status/open-config/open-runtime-folder
```

It is a small Windows Forms NotifyIcon process, not a full desktop app. The tray does not discover account credentials by itself. If no enabled account exists, it routes the user to an agent-guided connection prompt that asks before checking Gmail token state, Graph or Azure CLI token state, or the local Outlook Desktop profile. Once an account is enabled, the auto-sync toggle starts or stops the same user-session worker used by `service start`.

## Storage Evolution

Bootstrap:

- JSONL for messages and actions.
- JSONL for read-only archive imports and archive search projection.

Next:

- SQLite for durable local store.
- SQLite FTS for search.
- Encrypted local vault for secrets and tokens.
- Durable scheduler / Windows Task Scheduler integration.
- Optional Windows Service wrapper for non-desktop API providers.
