# NomadInbox

NomadInbox is a local-first mailbox visibility and action service for coding agents.

It gives agents a safe, provider-neutral way to read, search, inspect, draft, and act on email across:

- Outlook Desktop
- Outlook / Microsoft 365 via Microsoft Graph
- Gmail / Google Workspace via Gmail API

This repository is intentionally fresh. It does not include copied mailbox data, OAuth token caches, local credential files, or user-specific message exports.

## Product Goal

Expose inbox data as agent-readable JSON while keeping mailbox mutation controlled, auditable, and explicit.

Core principles:

- Read operations are allowed after provider authentication.
- Draft creation is separate from send.
- Sending always requires explicit confirmation.
- Provider-specific message IDs are preserved.
- Runtime data stays local and ignored by git.
- Data contracts stay stable across providers.

## Project Location

```text
C:\Users\prat\Documents\osm\NomadInbox
```

## Quick Start

```powershell
cd C:\Users\prat\Documents\osm\NomadInbox
.\scripts\nomad-inbox.ps1 setup
.\scripts\nomad-inbox.ps1 doctor
.\scripts\nomad-inbox.ps1 providers list
```

Copy the local config template before connecting real providers:

```powershell
Copy-Item .\config\nomad-inbox.example.ps1 .\config\nomad-inbox.ps1
```

Then fill in provider-specific values in the ignored local config file.

## Repository Map

| Path | Purpose |
|---|---|
| `scripts/` | CLI entrypoints and validation scripts |
| `src/NomadInbox/` | Core PowerShell module and provider contract |
| `providers/` | Provider-specific adapters and setup notes |
| `schemas/` | Agent-facing JSON contracts |
| `docs/` | Product, architecture, ADRs, runbooks, service catalog, SLOs |
| `api/` | Future OpenAPI and AsyncAPI contracts |
| `config/` | Safe example config only |
| `tests/` | Smoke/validation checks |

## Available Commands

```powershell
.\scripts\nomad-inbox.ps1 setup
.\scripts\nomad-inbox.ps1 doctor
.\scripts\nomad-inbox.ps1 providers list
.\scripts\nomad-inbox.ps1 accounts init
.\scripts\nomad-inbox.ps1 accounts list
.\scripts\nomad-inbox.ps1 backup status
.\scripts\nomad-inbox.ps1 import status
.\scripts\nomad-inbox.ps1 sync once
.\scripts\nomad-inbox.ps1 service start
.\scripts\nomad-inbox.ps1 service status
.\scripts\nomad-inbox.ps1 service stop
.\scripts\nomad-inbox.ps1 tray start
.\scripts\nomad-inbox.ps1 config status
.\scripts\nomad-inbox.ps1 schemas list
.\scripts\nomad-inbox.ps1 sample message
```

Provider commands are intentionally contract-first in this bootstrap. Implementations should plug into the provider adapter interface without changing the agent-facing message/action schema.

## Archive Ingestion

Live sync is the primary path for current mail and safe actions. Users can also import historical mail exports to enrich search and context:

```powershell
.\scripts\nomad-inbox.ps1 import eml --path .\mail-export --source outlook-export
.\scripts\nomad-inbox.ps1 import mbox --path .\takeout\Mail.mbox --source gmail-takeout
.\scripts\nomad-inbox.ps1 import jsonl --path .\messages.jsonl --source nomadinbox-export
.\scripts\nomad-inbox.ps1 backup status
```

Imported archive messages are read-only by default. They set `actionable=false`, keep source provenance, and do not expose reply, move, delete, mark-read, or send actions unless a future live-provider link is established.

By default, archive import stores metadata, snippets, headers, and a local searchable projection. Add `--include-bodies` only when the user explicitly wants full archive body storage.

`backup status` returns interactive user prompts such as how many live synced messages and archive imported messages are available, when the last sync/import ran, and how the user can add more context from email exports.

## Optional Background Sync

NomadInbox is request-driven by default. Users can also opt into background sync:

```powershell
.\scripts\nomad-inbox.ps1 accounts init
notepad .\config\accounts.json
.\scripts\nomad-inbox.ps1 service start
.\scripts\nomad-inbox.ps1 service status
```

This means a user can query NomadInbox only when needed, or they can do this as well: enable a small local background worker that keeps selected accounts fresh on a schedule.

`config\accounts.json` is ignored by git. Each account can be enabled or disabled independently and can define its own provider, folder, query, limit, and interval.

The tray controller is optional:

```powershell
.\scripts\nomad-inbox.ps1 tray start
```

It adds a Windows system-tray icon for status, start/stop sync, opening account settings, and opening the runtime folder.

## Safety

NomadInbox starts with no connected mailbox. Runtime files are created only when you run setup or connect providers.

The following are ignored by git:

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

## Validation

```powershell
.\scripts\validate.ps1
```

The validation script checks required docs, schemas, scripts, and secret-ignore rules.

## Architecture Updates

When the architecture or project behavior changes during a session, update the affected artifacts and run:

```powershell
.\scripts\session-closeout.ps1 -Title "Short change title" -Summary "What changed and why"
```

This records a session update, appends the architecture changelog, and validates the required documentation pack.
