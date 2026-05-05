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
  +-- Provider Catalog / Account Config
  +-- Safety / Approval Gate
  +-- Sync Worker
  +-- Tray Controller
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

MCP over stdio is started by each calling agent. On Windows, the tray controller
is a compiled WinForms client that keeps the local HTTP service available while
the tray is running so agent access can stay live without a separate terminal
window. The tray client reads cached status first and performs HTTP status,
manual sync, and auto-sync start/stop calls asynchronously; tray menu rendering
must not wait on sync or HTTP refresh.

The MCP/HTTP service runtime is Node.js and should remain platform independent.
Provider sync and archive import currently delegate to the NomadInbox PowerShell
core. Windows agents install the PowerShell helper to initialize ignored runtime
state and track connected account config. Non-Windows agents keep the MCP server
available for local JSONL context tools and return clear unsupported-runtime
guidance for Windows-only tray and Outlook Desktop operations.

The command-layer provider catalog is not a second implementation registry. It
is the metadata/config surface behind `providers list` and `accounts list`: which
providers exist, which local accounts are enabled, which capabilities are safe to
expose, and which provider runtime is configured. Provider adapters remain the
implementation layer that actually syncs Gmail, Outlook Graph, or Outlook
Desktop.

The startup system prompt is a versioned system artifact at
`prompts/nomadmail-startup.system.md`. The MCP/HTTP service exposes that exact
prompt through `nomadmail_get_startup_system_prompt`, `/startup-system-prompt`,
and the `startupSystemPrompt` field in `nomadmail_get_agent_guide`.

The living workspace state is tracked at `docs/governance/WORKSPACE_STATE.md`.
The MCP/HTTP service exposes it through `nomadmail_get_workspace_state`,
`/workspace-state`, and the `workspaceState` field in `nomadmail_get_agent_guide`.

Time handling is locale-aware at the command layer. Ambiguous source or user
times are parsed with `NOMADINBOX_USER_CULTURE` / `NOMADINBOX_USER_LOCALE` and
`NOMADINBOX_USER_TIME_ZONE` / `NOMADINBOX_USER_TIME_ZONE_IANA` when set, otherwise with the current OS user culture
and local time zone. Persisted message, sync, import, and action timestamps are
normalized to UTC ISO 8601; user-facing prompts, tray dashboard values, and
agent guidance should present local user time.

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

## Runtime Data Backup And Restore

Runtime backup is a user-owned local backup problem, not a Git workflow.
Mailbox projections, archive imports, attachment files, account ids, sync status,
and action logs must stay out of the repository even when users want durable
backup.

Recommended backup shape:

- Create a timestamped backup bundle outside the repository, such as
  `%USERPROFILE%\Documents\NomadInbox Backups\nomadinbox-runtime-YYYYMMDD-HHMMSS.zip`
  on Windows or an equivalent local backup folder on other operating systems.
- Store the backup folder on an encrypted volume or in a user-approved encrypted
  backup target such as BitLocker-protected storage, OneDrive Personal Vault, or
  an encrypted external drive.
- Include durable runtime files:
  - `data/messages.jsonl`
  - `data/archive-messages.jsonl`
  - `data/import-status.json`
  - `data/sync-status.json`
  - `data/actions.jsonl`
  - `data/attachments/`
  - `config/accounts.json`
- Exclude rebuildable or volatile files by default:
  - `data/archive-index.jsonl`
  - `data/sync-worker.pid`
  - `data/sync-worker.log`
  - generated `target/` binaries
  - temporary `runtime/` and agent scratch files
- Exclude OAuth tokens, client secrets, credential caches, and raw mail exports
  unless the user explicitly chooses an encrypted secret backup. The normal
  restore path should reconnect accounts through the agent-guided provider
  setup instead of silently restoring credentials.
- Write a small manifest next to the bundle containing source repo path, source
  data directory, created-at timestamp, NomadInbox version or commit, included
  files, and SHA-256 hashes for integrity checks.

The safest restore model is explicit and local: stop the tray and sync worker,
extract the bundle into the intended `data/` directory and `config/accounts.json`
location, run `backup status` / `service status`, then reconnect provider
credentials only when needed. For testing or migration, restore into a separate
folder and launch NomadInbox with `NOMADINBOX_DATA_DIR` pointing at that folder
so the default runtime store is not overwritten.

Future CLI support should implement this as request-driven commands, for
example `backup export` and `backup restore --target-data-dir`, with a dry-run
restore preview and no credential backup unless the user provides an encrypted
secret-backup option.

## Agent Service Contract

NomadMail currently exposes these MCP tools:

- `nomadmail_get_agent_guide`
- `nomadmail_get_startup_system_prompt`
- `nomadmail_get_workspace_state`
- `nomadmail_install_windows_helper`
- `nomadmail_health_check`
- `nomadmail_list_providers`
- `nomadmail_list_accounts`
- `nomadmail_sync_once`
- `nomadmail_search_messages`
- `nomadmail_get_latest_message`
- `nomadmail_get_message`
- `nomadmail_get_backup_status`
- `nomadmail_get_service_status`
- `nomadmail_start_service`
- `nomadmail_stop_service`
- `nomadmail_import_archive`

The service runtime is `service/nomadmail-service.mjs`. It uses Node.js with no
external package dependency and calls the existing PowerShell CLI for command
operations. Local message search reads the ignored JSONL stores directly so MCP
and HTTP clients get a fast provider-neutral search surface. Latest-email read
requests use a freshness-gated path: run one-shot live sync first, then return
the newest live message with available preview content. If sync cannot complete,
agents must not describe stale local state as definitely latest.

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
remain governed by the safety / approval gate before service exposure.

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

When archive records contain ambiguous `Date` headers or JSONL `receivedAt` /
`sentAt` values, NomadInbox resolves them using the user locale/time-zone context
before writing UTC ISO timestamps.

## Backup Status And User Prompts

`backup status` combines live sync and archive import stats. It reports how many live synced messages and archive imported messages are locally available, then emits user-facing prompts that guide the user to sync or import more mail exports.

## Safety / Approval Gate

The safety / approval gate is the command policy boundary around mailbox
actions. It is not a separate daemon. It decides which commands are read-only,
which can create drafts, which require explicit action-time user confirmation,
and which must be audited in `data/actions.jsonl`. This is why imported archive
messages are stored as `actionable = false`, while live provider messages can
expose actions only through confirmed workflows.

Rules:

- Read commands can run after provider auth.
- Draft commands do not imply send.
- Send commands require explicit confirmation.
- Bulk state changes should support dry-run first.
- Permanent delete is not a default action. Prefer trash/archive.
- Every mutating command writes an action record.

## Background Sync

Background sync is user-controlled. The default product remains request-driven.

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

The tray controller is user-controlled:

```text
nomad-inbox.ps1 tray start
  -> starts target/NomadInboxTray/NomadInboxTray.exe
  -> compiled from src/NomadInbox.Tray/NomadInboxTray.cs when needed
  -> exposes sync-now/auto-sync-toggle/status/settings/open-runtime-folder
```

It is a small compiled Windows Forms NotifyIcon process, not a full desktop app.
While running, the tray keeps the local NomadMail HTTP service active at
`127.0.0.1:8791`; MCP stdio remains per-agent launch. The default tray
interaction is a compact native menu with Sync now, an auto-sync toggle,
per-account sync status, and a short note to ask an agent for new account
connection. The menu is built only from cached in-memory state, and refresh or
sync work is queued on background tasks. The larger Settings window shows
diagnostics, provider state, storage paths, approval gates, locale, and
time-zone status only when explicitly opened. The tray does not discover account
credentials by itself. If no enabled account exists, Sync now and auto sync show
an account-connection info notification instead of scanning Gmail token state,
Graph or Azure CLI token state, or the local Outlook Desktop profile. Once an
account is enabled, the auto-sync toggle starts or stops the same user-session
worker used by `service start`.

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
