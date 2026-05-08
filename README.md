# NomadInbox

NomadInbox is a local-first mailbox visibility and action service for AI agents.

The callable service surface is named NomadMail. NomadMail wraps the NomadInbox core so different agents can use the same Gmail, Outlook Graph, Outlook Desktop, sync, search, import, and status contracts through MCP or local HTTP.

This repository starts with no copied mailbox data, OAuth token caches, local credential files, or user-specific message exports. Runtime data stays local and is ignored by git.

To understand why NomadInbox was built and what product scope it aims to cover,
read [PRODUCT_SPEC.md](docs/PRODUCT_SPEC.md).

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
- Trash/delete needs a second explicit confirmation before any destructive mailbox action.
- Provider-specific message IDs are preserved.
- Local runtime data is not pushed to GitHub.

## Start With An AI Agent

Give this repository link to your AI agent and ask it to clone and open the workspace:

```text
https://github.com/Prathyush-KKK/Nomad-Inbox
```

If the repository is already cloned, open that local workspace instead. Example local path:

```text
C:\Users\prat\Documents\osm\NomadInbox
```

After the Windows helper is installed, new terminals and agent sessions can also discover the workspace through the user environment variable `NOMADINBOX_HOME`. The helper also registers `NOMADMAIL_HANDOFF_COMMAND`, `NOMADMAIL_HANDOFF_URL`, `NOMADMAIL_HTTP_URL`, `NOMADMAIL_MCP_COMMAND`, and `NOMADMAIL_MCP_SCRIPT`.

NomadInbox owns the startup system prompt. The user should not have to paste or maintain it.

Agents should load [nomadmail-startup.system.md](prompts/nomadmail-startup.system.md) or call `nomadmail_get_startup_system_prompt` / HTTP `/startup-system-prompt`. The same prompt is also embedded in `nomadmail_get_agent_guide`.

Agents should also read [WORKSPACE_STATE.md](docs/governance/WORKSPACE_STATE.md) before answering. It is the living current-state file that gets refreshed as sessions continue.

The definitive user-facing setup and daily-mail query flow is documented in [Agent User Flow](docs/runbooks/agent-user-flow.md) and is exposed through `nomadmail_get_agent_user_flow` / HTTP `/agent-user-flow`.

For a different chat session or another agent, use [nomadmail-cross-chat-handoff.md](prompts/nomadmail-cross-chat-handoff.md), `nomadmail_get_cross_chat_handoff`, or HTTP `/cross-chat-handoff`. This is the repo-owned handoff prompt for reconnecting another chat to the same local workspace, tray-owned HTTP service, MCP server, and ignored runtime store.

If the other agent only gets the workspace path, it should read [AGENTS.md](AGENTS.md) first. If it does not get the path, it can try `NOMADINBOX_HOME`:

```powershell
$nomadInboxHome = [Environment]::GetEnvironmentVariable("NOMADINBOX_HOME", "User")
cd $nomadInboxHome
node .\service\nomadmail-service.mjs cross-chat-handoff
```

On first response, the agent should show what NomadInbox can do in this workspace now, which mail sources are available or need setup, where local data will be stored, which files are protected from GitHub, Windows helper and tray status on Windows, where temporary diagnostic scripts may be created if needed, the latest durable workspace state, what actions need approval, and the safest next step.

After cloning and opening the workspace, the agent should explain to the user:

- NomadInbox is the local workspace; NomadMail is the callable service agents use.
- It can connect approved Gmail, Outlook Graph, Outlook Desktop, or local email exports.
- Runtime data, account config, message indexes, logs, and tokens stay local and are ignored by git.
- On Windows, the helper and compiled tray app can keep local service access available from the system tray.
- MCP stdio is available for agents on any OS; Outlook Desktop and tray features are Windows-only.
- Mail actions are draft-first; send requires approval, and trash/delete requires double explicit approval.
- The next step is to choose one source and one scope, such as Outlook Desktop inbox for the last 30 days, Gmail inbox headers, or a local export import.

On Windows, the tray controller is a compiled WinForms tray client. It keeps the local NomadMail HTTP service available at `127.0.0.1:8791` while the tray is running. MCP over stdio is still launched by each calling agent, but the HTTP surface stays available for agents that use loopback HTTP. The normal tray click opens a compact native status popup with icon buttons for Refresh, Sync now, auto sync, Settings, and Runtime, plus message counts and per-account sync status. Refresh, Sync now, and auto-sync changes show immediate UI feedback and run asynchronously, so opening the popup never waits on mail sync or HTTP refresh. Settings and diagnostics stay behind the Settings action.

The Windows helper install builds and uses an installed tray executable at `%LOCALAPPDATA%\NomadInbox\agent-helper\NomadInboxTray.exe`. The repository-local `target\` executable remains only a build fallback and is ignored by Git.

Use `.\scripts\nomad-inbox.ps1 tray status` to verify whether the compiled tray is running, which helper install it is using, and whether local HTTP health is reachable.

Use `.\scripts\nomad-inbox.ps1 env status` to verify whether the user environment variables for cross-chat discovery are registered.

Agent status responses should stay short. If the user asks to install, start, or run the service on Windows, start or verify the tray controller and tell the user NomadMail is available from the NomadInbox system tray icon. Do not dump endpoint catalogs, raw health JSON, process lists, or message search results unless asked.

What the agent can do with NomadInbox:

- connect one approved Gmail or Outlook source
- sync a small approved mailbox scope into the local ignored store
- import approved email backups as read-only context
- search local mail context and fetch cited messages
- show mail action choices after discovery, including draft reply, draft new mail, mark/flag/move/archive, and trash/delete only when the message is live and actionable
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

To back up or restore NomadMail's own local runtime store, use [Runtime Backup And Restore](docs/runbooks/runtime-backup-restore.md). Archive import for external MBOX/EML/JSONL mail exports is separate and covered in [Archive Import](docs/runbooks/archive-import.md).

## Agent Callable Service

NomadMail exposes NomadInbox to agents through:

- MCP over stdio
- local HTTP on `127.0.0.1`
- the underlying PowerShell CLI

The service supports provider/account discovery, one-shot sync, local message search, message lookup, UI-ready message action guidance, backup status, service status, background worker start/stop, agent guidance, and read-only archive import.

Provider data is stored in two layers. `data\messages.jsonl` is the canonical normalized message view for agents and UI, while `data\provider-raw.jsonl` stores provider-specific snapshots keyed back to the canonical message. Account settings control whether raw provider data, bodies, attachment metadata, and attachment bytes are captured; attachment bytes stay off by default.

Time handling is locale-aware. Set `NOMADINBOX_USER_CULTURE` or `NOMADINBOX_USER_LOCALE`, plus `NOMADINBOX_USER_TIME_ZONE` or `NOMADINBOX_USER_TIME_ZONE_IANA`, when an agent needs a specific user locale/time-zone context; otherwise NomadInbox uses the current OS user culture and local time zone. Stored timestamps remain UTC ISO 8601, while tray/dashboard/status text is shown in local user time.

Latest-email questions are freshness-gated. When a user asks for the latest email, newest message, recent mail, or latest email content, agents must run one request-scoped live sync against already configured/enabled accounts before answering. If sync cannot complete, the agent must say it cannot confirm the latest email instead of treating stale local state as definite.

After finding a live email, agents should offer a short action menu instead of stopping at the summary. Replies, forwards, and new mail must be drafted first, then sent only after approval of the exact draft. Trash/delete requires two explicit approvals. Actions may still fail when provider permissions or local runtime access are missing, such as read-only Gmail/Graph scopes or Outlook Desktop COM not being reachable.

Agents should call `nomadmail_get_agent_guide` or HTTP `/agent-guide` before syncing mail or parsing email backups for another repository.

Agents should load the built-in startup system prompt from `nomadmail_get_startup_system_prompt` or HTTP `/startup-system-prompt` when opening this repository as a workspace.

Agents should load the user-facing conversation contract from `nomadmail_get_agent_user_flow` or HTTP `/agent-user-flow` before presenting first-run setup or daily-mail query choices.

Agents should use `nomadmail_get_cross_chat_handoff` or HTTP `/cross-chat-handoff` when the user wants another chat session or agent to connect to this same local workspace.

Agents may create temporary diagnostic scripts for complex local checks only under ignored scratch locations such as `runtime\agent-scratch\` or the OS temp directory. Tracked repository code should stay limited to durable sync, service, provider, tray, schema, and documented product behavior.

For broad email reports, generated markdown, HTML, or JSON files should include the mail source and date range in the folder or filename. Use sortable, readable names such as `unread-outlook-2026-04-29-to-2026-05-06.md`, `unread-outlook-week-of-2026-05-06-index.md`, or `gmail-takeout-2025.md`; avoid vague names such as `unread-outlook-week.md` once the range contains many messages.

The MCP server is a Node.js service intended to start on any OS, including direct launch with `node service/nomadmail-service.mjs mcp`. Windows agents should install the PowerShell helper for sync/account tracking. Non-Windows agents should keep using MCP for local JSONL context tools and return a clear unsupported-runtime response for Windows-only helper, tray, and Outlook Desktop operations. The Windows tray owns the long-running local HTTP service; MCP stdio remains client-launched.

## Release Packaging

NomadInbox has a versioned Windows package flow. The version is stored in `VERSION`.

For a local test package while changes are still uncommitted:

```powershell
.\scripts\build-windows-installer.ps1 -AllowDirty
```

For a publish candidate, commit the intended changes first, verify `main` is clean and synced, then run:

```powershell
.\scripts\validate.ps1
.\tests\smoke.ps1
.\scripts\build-windows-installer.ps1
```

The package is written to ignored `dist\` as `NomadInbox-<version>-windows.zip` with a sidecar manifest and SHA-256 hash. It includes tracked product files, the required `VERSION` file, and the compiled tray executable, so runtime data, local account config, Kiro scratch scripts, tokens, and mail exports are excluded. See [release.md](docs/runbooks/release.md).

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
| `VERSION` | Version used by NomadMail and release packaging |

## Safety

NomadInbox is request-driven by default. Background sync starts only when the user enables accounts and starts the worker or tray auto-sync toggle. Starting the tray can keep the local HTTP agent service alive, but it does not enable mailbox auto sync.

Imported archive mail is read-only context. Live provider actions such as reply, send, move, archive, trash, flag, mark-read, or attachment save must remain explicit action-time workflows. Draft email first; send only after explicit approval. Trash/delete requires a second explicit confirmation naming the message and mailbox effect.

## Manual Setup

For command-by-command setup, provider checks, imports, tray usage, MCP/HTTP launch, validation, and troubleshooting, use [Manual Setup](docs/runbooks/manual-setup.md).

For cross-agent validation, current-workspace scenario testing, and brand-new clone testing, use [Testing Handoff](docs/runbooks/testing-handoff.md).

## Session State

`docs/governance/WORKSPACE_STATE.md` is updated as meaningful sessions complete. Use `scripts/session-closeout.ps1` for architecture or contract changes, or `scripts/update-workspace-state.ps1` for state-only refreshes.
