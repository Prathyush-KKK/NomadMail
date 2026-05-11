# NomadInbox

NomadInbox is a local-first mailbox workspace for AI agents. NomadMail is the callable service layer that lets agents use the same local mail context through MCP, tray-owned HTTP, or CLI commands.

Use it when you want an agent to search, summarize, open, and safely prepare actions for Gmail, Microsoft 365, Outlook Desktop, or local email exports without pushing mailbox runtime data to GitHub.

For product scope and why this exists, read [PRODUCT_SPEC.md](docs/PRODUCT_SPEC.md). For architecture, read [ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Quick Start

Clone and open the workspace:

```powershell
git clone https://github.com/Prathyush-KKK/Nomad-Inbox.git
cd Nomad-Inbox
```

On Windows, install the helper, start the compiled tray, register it for user login startup, and open the tray status popup:

```powershell
.\scripts\nomad-inbox.ps1 install windows-helper --start-tray --register-startup --show-popup
```

A clone alone cannot start a tray app; the install command above creates the user-local helper and Windows Startup shortcut. It does not connect accounts, read mail, enable auto sync, or send anything.

Check the install:

```powershell
.\scripts\nomad-inbox.ps1 tray status
.\scripts\nomad-inbox.ps1 env status
node .\service\nomadmail-service.mjs self-test
```

## What It Does

NomadInbox can:

- sync an approved mailbox scope into a local ignored store
- search and fetch local mail records with provider-native IDs preserved
- open synced Outlook Desktop messages and threads
- draft replies, forwards, and new messages before any send
- run approved Outlook Desktop actions such as mark read/unread, flag, move, archive, save attachment, and trash
- import EML, MBOX, or compatible JSONL exports as read-only archive context
- queue local review events for Codex, Claude Code, Kiro, or another assigned agent
- keep a tray-owned local HTTP service available while the Windows tray is running
- expose the same tools through MCP for agent platforms

Supported source paths:

- Outlook Desktop on Windows
- Outlook / Microsoft 365 through Microsoft Graph
- Gmail / Google Workspace through Gmail API
- local mail exports: EML, MBOX, JSONL

## Use From Another Chat

Give another agent this prompt:

```text
Use NomadInbox from this workspace:

C:\Users\prat\Documents\osm\NomadInbox

First read AGENTS.md, then run:

node .\service\nomadmail-service.mjs cross-chat-handoff

Prefer MCP first, tray-owned HTTP second, and direct CLI third. Do not read mailbox data, discover accounts, sync mail, store bodies, send, delete, move, or mutate mail until I approve the exact source and scope.
```

If the Windows helper has registered environment variables, the other agent can discover the workspace:

```powershell
$nomadInboxHome = [Environment]::GetEnvironmentVariable("NOMADINBOX_HOME", "User")
if (-not $nomadInboxHome) { $nomadInboxHome = $env:NOMADINBOX_HOME }
cd $nomadInboxHome
node .\service\nomadmail-service.mjs cross-chat-handoff
```

More detail: [nomadmail-cross-chat-handoff.md](prompts/nomadmail-cross-chat-handoff.md).

## Agent Access Order

Use the strongest available local surface:

1. MCP: configured `nomadmail` server or `.\scripts\nomadmail-mcp.ps1`
2. HTTP: tray-owned loopback service at `http://127.0.0.1:8791`
3. CLI: `node .\service\nomadmail-service.mjs ...` or `.\scripts\nomad-inbox.ps1 ...`

If a chat cannot see `nomadmail_*` MCP tools, fall back to HTTP or CLI. That is a chat/tool injection issue, not necessarily a NomadMail failure.

Codex checks:

```powershell
codex mcp get nomadmail
codex mcp list
```

NomadMail checks:

```powershell
node .\service\nomadmail-service.mjs tools
Invoke-RestMethod http://127.0.0.1:8791/health
```

## Storage And Privacy

Runtime data defaults to:

```text
.\data
```

Ignored local data includes:

- `data/`
- `runtime/`
- `target/`
- `dist/`
- `mail-exports/`
- `import-staging/`
- `config/nomad-inbox.ps1`
- `config/accounts.json`
- OAuth secrets, token caches, message/action JSONL logs, and mail export files

Use `NOMADINBOX_DATA_DIR` to place runtime data somewhere else.

Backup/restore of NomadInbox runtime data: [runtime-backup-restore.md](docs/runbooks/runtime-backup-restore.md). Archive import: [archive-import.md](docs/runbooks/archive-import.md).

## Safety Rules

- Mailbox access starts only after the user approves the source and scope.
- Latest-mail requests must run a one-shot live sync first for already enabled accounts.
- Draft before send.
- Send requires explicit approval of the exact draft.
- Trash/delete requires two explicit confirmations.
- Archive imports are read-only context.
- Auto sync is off until the user enables it.
- Startup tray registration starts the local tray service only; it does not enable mailbox sync.

Detailed agent behavior: [agent-user-flow.md](docs/runbooks/agent-user-flow.md) and [agent-service.md](docs/runbooks/agent-service.md).

## First-Time Agent Flow

An agent opening this repo should read:

1. [AGENTS.md](AGENTS.md)
2. [nomadmail-startup.system.md](prompts/nomadmail-startup.system.md)
3. [WORKSPACE_STATE.md](docs/governance/WORKSPACE_STATE.md)
4. [agent-user-flow.md](docs/runbooks/agent-user-flow.md)

The first response should tell the user what is available, what needs setup, where data is stored, what is ignored by Git, helper/tray/MCP status, and the next source/scope choice.

## Common Commands

```powershell
# setup and status
.\scripts\nomad-inbox.ps1 doctor
.\scripts\nomad-inbox.ps1 accounts list
.\scripts\nomad-inbox.ps1 tray status

# one-shot sync after source/scope approval
.\scripts\nomad-inbox.ps1 sync once --account-id desktop-outlook

# service surfaces
node .\service\nomadmail-service.mjs mcp
node .\service\nomadmail-service.mjs http
node .\service\nomadmail-service.mjs cross-chat-handoff

# tests
.\scripts\validate.ps1
.\tests\smoke.ps1
.\tests\agent-user-flow.ps1
.\tests\new-clone.ps1
```

## Release

For a local dirty-tree package:

```powershell
.\scripts\build-windows-installer.ps1 -AllowDirty
```

For a publish candidate:

```powershell
.\scripts\validate.ps1
.\tests\smoke.ps1
.\scripts\build-windows-installer.ps1
```

Release details: [release.md](docs/runbooks/release.md). Cross-agent testing: [testing-handoff.md](docs/runbooks/testing-handoff.md).

## Repository Map

| Path | Purpose |
|---|---|
| `scripts/` | CLI, helper install, tray launcher/build, MCP/HTTP launchers, validation |
| `src/NomadInbox.Tray/` | compiled Windows tray client |
| `src/NomadInbox/` | core PowerShell module and provider sync contract |
| `service/` | NomadMail MCP and HTTP service |
| `prompts/` | agent startup and handoff prompts |
| `providers/` | provider setup notes |
| `schemas/` | agent-facing JSON contracts |
| `docs/` | product, architecture, runbooks, governance |
| `api/` | OpenAPI and AsyncAPI contracts |
| `config/` | safe examples only |
| `tests/` | smoke and scenario checks |
