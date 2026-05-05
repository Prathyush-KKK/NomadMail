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

## Easy Setup With An AI Agent Workspace

Open this repository in your AI agent workspace:

```text
C:\Users\prat\Documents\osm\NomadInbox
```

Then ask the agent:

```text
I want to try NomadInbox/NomadMail.

First verify setup, validation, provider status, account status, and git ignore boundaries.
Do not connect accounts, scan exports, read mailbox data, or start auto sync until I approve.

Show me the safe next choices:
- Gmail API
- Outlook Graph
- Outlook Desktop
- local email export import
- tray app with auto sync
```

The agent should:

- verify that runtime data and secrets are ignored by git
- check whether Gmail, Graph, or Outlook Desktop are available
- ask before discovering tokens, profiles, exports, or account data
- keep broad mailbox access, body storage, attachments, and auto sync as explicit choices
- use `NOMADINBOX_DATA_DIR` when you want data staged somewhere other than NomadInbox's default local store

## Quick Trial Flow

Use the agent workspace to run a safe status check first. After that, choose one path:

- **Outlook Desktop** if you already have Outlook open and signed in on Windows.
- **Outlook Graph** if you want Microsoft 365 mail through Graph.
- **Gmail API** if you want Gmail or Google Workspace mail.
- **Local export import** if you already have EML, MBOX, or NomadMail JSONL backups.
- **Tray auto sync** if you want a system-tray toggle for background sync after accounts are connected.

The tray app can guide users back to the agent when no account is connected, and can start or stop the background worker once accounts are enabled.

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

## Repository Map

| Path | Purpose |
|---|---|
| `scripts/` | CLI entrypoints, tray launcher, MCP/HTTP launchers, validation scripts |
| `src/NomadInbox/` | Core PowerShell module and provider sync contract |
| `service/` | NomadMail MCP and HTTP service |
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
