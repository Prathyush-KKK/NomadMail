# NomadInbox

NomadInbox is a local-first mailbox visibility and action service for AI agents.

The callable service surface is named NomadMail. NomadMail wraps the NomadInbox core so different agents can use the same Gmail, Outlook Graph, Outlook Desktop, sync, search, import, and status contracts through MCP or local HTTP.

This repository starts with no copied mailbox data, OAuth token caches, local credential files, or user-specific message exports. Runtime data stays local and is ignored by git.

## What It Does

NomadInbox gives agents a provider-neutral way to read, search, inspect, and safely prepare actions for email across:

- Outlook Desktop
- Outlook / Microsoft 365 through Microsoft Graph
- Gmail / Google Workspace through Gmail API
- Local email exports such as EML, MBOX, and compatible JSONL

Core principles:

- Read operations happen only after provider authentication or approved local import.
- Archive imports are read-only context by default.
- User-facing and ambiguous time scopes are interpreted in the user's locale and time zone, then persisted as UTC ISO timestamps.
- Drafting is separate from sending.
- Sending and mailbox mutations require explicit confirmation.
- Provider-specific message IDs are preserved.
- Local runtime data is not pushed to GitHub.

## Start With An AI Agent

Open this repository in your AI agent workspace:

```text
C:\Users\prat\Documents\osm\NomadInbox
```

NomadInbox owns the startup system prompt. The user should not have to paste or maintain it.

Agents should load [nomadmail-startup.system.md](prompts/nomadmail-startup.system.md) or call `nomadmail_get_startup_system_prompt` / HTTP `/startup-system-prompt`. The same prompt is also embedded in `nomadmail_get_agent_guide`.

Agents should also read [WORKSPACE_STATE.md](docs/governance/WORKSPACE_STATE.md) before answering. It is the living current-state file that gets refreshed as sessions continue.

On first response, the agent should show what NomadInbox can do in this workspace now, which mail sources are available or need setup, where local data will be stored, which files are protected from GitHub, Windows helper and tray status on Windows, where temporary diagnostic scripts may be created if needed, the latest durable workspace state, what actions need approval, and the safest next step.

On Windows, the tray controller is a compiled WinForms tray client. It keeps the local NomadMail HTTP service available at `127.0.0.1:8791` while the tray is running. MCP over stdio is still launched by each calling agent, but the HTTP surface stays available for agents that use loopback HTTP. The tray menu is rendered from cached status and performs status refresh, Sync now, and auto-sync changes asynchronously, so opening the menu never waits on mail sync or HTTP refresh. The normal tray click opens a compact native menu with Sync now, an auto-sync toggle, and per-account sync status. Settings and diagnostics open only from the tray menu.

Agent status responses should stay short. If the user asks to install, start, or run the service on Windows, start or verify the tray controller and tell the user NomadMail is available from the NomadInbox system tray icon. Do not dump endpoint catalogs, raw health JSON, process lists, or message search results unless asked.

What the agent can do with NomadInbox:

- connect one approved Gmail or Outlook source
- sync a small approved mailbox scope into the local ignored store
- import approved email backups as read-only context
- search local mail context and fetch cited messages
- report sync status, backup counts, worker state, and storage location
- start the tray app and turn on auto sync after accounts are connected
- stage data in another local folder with `NOMADINBOX_DATA_DIR`
- expose the same local context tools to other agent chats through the platform-independent NomadMail MCP server

## Storage And Privacy

By default, runtime data is stored under:

```text
C:\Users\prat\Documents\osm\NomadInbox\data
```

Ignored local files include:

- `data/`
- `runtime/`
- `target/`
- `mail-exports/`
- `import-staging/`
- `config/nomad-inbox.ps1`
- `config/accounts.json`
- OAuth client secrets
- token caches
- JSONL message/action logs
- `.mbox`, `.eml`, `.pst`, and `.msg` mail export files

For another storage location, start the agent, CLI, tray, MCP server, or HTTP service with `NOMADINBOX_DATA_DIR` set to the target local data folder.

## Agent Callable Service

NomadMail exposes NomadInbox to agents through:

- MCP over stdio
- local HTTP on `127.0.0.1`
- the underlying PowerShell CLI

The service supports provider/account discovery, one-shot sync, local message search, message lookup, backup status, service status, background worker start/stop, agent guidance, and read-only archive import.

Time handling is locale-aware. Set `NOMADINBOX_USER_CULTURE` or `NOMADINBOX_USER_LOCALE`, plus `NOMADINBOX_USER_TIME_ZONE` or `NOMADINBOX_USER_TIME_ZONE_IANA`, when an agent needs a specific user locale/time-zone context; otherwise NomadInbox uses the current OS user culture and local time zone. Stored timestamps remain UTC ISO 8601, while tray/dashboard/status text is shown in local user time.

Latest-email questions are freshness-gated. When a user asks for the latest email, newest message, recent mail, or latest email content, agents must run one request-scoped live sync against already configured/enabled accounts before answering. If sync cannot complete, the agent must say it cannot confirm the latest email instead of treating stale local state as definite.

Agents should call `nomadmail_get_agent_guide` or HTTP `/agent-guide` before syncing mail or parsing email backups for another repository.

Agents should load the built-in startup system prompt from `nomadmail_get_startup_system_prompt` or HTTP `/startup-system-prompt` when opening this repository as a workspace.

Agents may create temporary diagnostic scripts for complex local checks only under ignored scratch locations such as `runtime\agent-scratch\` or the OS temp directory. Tracked repository code should stay limited to durable sync, service, provider, tray, schema, and documented product behavior.

The MCP server is a Node.js service intended to start on any OS, including direct launch with `node service/nomadmail-service.mjs mcp`. Windows agents should install the PowerShell helper for sync/account tracking. Non-Windows agents should keep using MCP for local JSONL context tools and return a clear unsupported-runtime response for Windows-only helper, tray, and Outlook Desktop operations. The Windows tray owns the long-running local HTTP service; MCP stdio remains client-launched.

## Repository Map

| Path | Purpose |
|---|---|
| `scripts/` | CLI entrypoints, compiled tray launcher/build wrapper, MCP/HTTP launchers, validation scripts |
| `src/NomadInbox.Tray/` | Compiled Windows tray client source |
| `src/NomadInbox/` | Core PowerShell module and provider sync contract |
| `service/` | NomadMail MCP and HTTP service |
| `prompts/` | System prompts owned by NomadInbox/NomadMail |
| `providers/` | Provider-specific setup notes |
| `schemas/` | Agent-facing JSON contracts |
| `docs/` | Product, architecture, ADRs, runbooks, service catalog, SLOs |
| `api/` | OpenAPI and AsyncAPI contracts |
| `config/` | Safe example config only |
| `tests/` | Smoke checks |

## Safety

NomadInbox is request-driven by default. Background sync starts only when the user enables accounts and starts the worker or tray auto-sync toggle. Starting the tray can keep the local HTTP agent service alive, but it does not enable mailbox auto sync.

Imported archive mail is read-only context. Live provider actions such as reply, send, move, archive, trash, flag, mark-read, or attachment save must remain explicit action-time workflows.

## Manual Setup

For command-by-command setup, provider checks, imports, tray usage, MCP/HTTP launch, validation, and troubleshooting, use [Manual Setup](docs/runbooks/manual-setup.md).

## Session State

`docs/governance/WORKSPACE_STATE.md` is updated as meaningful sessions complete. Use `scripts/session-closeout.ps1` for architecture or contract changes, or `scripts/update-workspace-state.ps1` for state-only refreshes.
