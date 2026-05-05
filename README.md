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

On first response, the agent should show what NomadInbox can do in this workspace now, which mail sources are available or need setup, where local data will be stored, which files are protected from GitHub, what actions need approval, and the safest next step.

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

Agents should call `nomadmail_get_agent_guide` or HTTP `/agent-guide` before syncing mail or parsing email backups for another repository.

Agents should load the built-in startup system prompt from `nomadmail_get_startup_system_prompt` or HTTP `/startup-system-prompt` when opening this repository as a workspace.

The MCP server is a Node.js service intended to start on any OS, including direct launch with `node service/nomadmail-service.mjs mcp`. Windows agents should install the PowerShell helper for sync/account tracking. Non-Windows agents should keep using MCP for local JSONL context tools and return a clear unsupported-runtime response for Windows-only helper, tray, and Outlook Desktop operations.

## Repository Map

| Path | Purpose |
|---|---|
| `scripts/` | CLI entrypoints, tray launcher, MCP/HTTP launchers, validation scripts |
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

NomadInbox is request-driven by default. Background sync starts only when the user enables accounts and starts the worker or tray auto-sync toggle.

Imported archive mail is read-only context. Live provider actions such as reply, send, move, archive, trash, flag, mark-read, or attachment save must remain explicit action-time workflows.

## Manual Setup

For command-by-command setup, provider checks, imports, tray usage, MCP/HTTP launch, validation, and troubleshooting, use [Manual Setup](docs/runbooks/manual-setup.md).
