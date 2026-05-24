# NomadInbox

![NomadInbox logo](assets/nomadinbox-logo.svg)

NomadInbox is a local-first email workspace for AI agents. It lets Codex, Claude Code, Kiro, Open WebUI, and other agent runtimes search, summarize, open, draft, and safely act on Gmail, Microsoft 365, Outlook Desktop, and local mail exports without committing mailbox data to GitHub.

## What Is NomadInbox?

NomadInbox is an open-source mailbox context layer for AI agents. The repository contains a local mailbox store, a NomadMail MCP server, a loopback HTTP API, a Windows tray controller, provider adapters, schemas, and safety rules for draft-first email actions.

Agents use NomadInbox when they need local email context for questions such as:

- "Find the latest email from Piyush and summarize the action items."
- "Search my Gmail and Outlook for invoices from this week."
- "Open the Outlook thread about MOP generation."
- "Draft a reply, but do not send until I approve it."
- "Give another agent safe access to my local mailbox context through MCP."

Use NomadInbox when you want:

- **Agent-readable email context** through MCP, tray-owned HTTP, OpenAPI, or CLI commands.
- **Local-first privacy** where mailbox data, OAuth tokens, exports, logs, and action audits stay in ignored runtime folders.
- **Safer mail actions** where agents draft first, send only after explicit approval, and delete/trash only after double confirmation.
- **Cross-chat continuity** so another agent session can discover the same local NomadInbox workspace and use the same approved mailbox context.

## Why Use It?

| Need | NomadInbox approach |
|---|---|
| Give agents email context | Exposes normalized local mail through MCP, HTTP, and CLI. |
| Keep private mail out of source control | Ignores runtime stores, account config, token files, exports, and logs. |
| Query Gmail and Outlook together | Normalizes provider records while preserving provider-native IDs. |
| Safely act on mail | Drafts first, sends only after explicit approval, and requires double confirmation for trash/delete. |
| Use from another repo | Clone once, run locally, then let agents call NomadMail from any workspace. |

For product scope and why this exists, read [PRODUCT_SPEC.md](docs/PRODUCT_SPEC.md). For the technical model, read [ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Best Fit

NomadInbox is best for developers, operators, consultants, and power users who want AI agents to work with personal or work email while keeping mailbox data local. It is not a hosted email SaaS, a CRM, or a background service that sends mail without user approval.

## Visual Proof To Add

Before making the public repo launch-ready, upload screenshots or GIFs here:

| Asset to upload | Suggested path | What it should show |
|---|---|---|
| Tray status popup screenshot | `assets/screenshots/tray-status-popup.png` | Accounts, sync status, manual sync, settings entry |
| 60-second demo GIF | `assets/screenshots/nomadinbox-demo.gif` | Install, self-test, tray status, safe mail query |
| GitHub social preview | repository Settings -> Social preview | 1280x640 image with logo, product name, and one-line promise |

After upload, add the images below this line:

<!--
![NomadInbox tray status popup](assets/screenshots/tray-status-popup.png)
![NomadInbox 60-second demo](assets/screenshots/nomadinbox-demo.gif)
-->

## Current Status

| Area | Status | Notes |
|---|---|---|
| Outlook Desktop on Windows | Working | Uses the signed-in local Outlook profile where available. |
| Gmail API | Working / active hardening | Supports OAuth client and refresh-token based local config. |
| Outlook / Microsoft 365 Graph | Adapter scaffolded | Intended for Graph-backed mailboxes. |
| MCP service | Working | `nomadmail` tools expose search, context, handoff, events, and actions. |
| Tray-owned HTTP service | Working | Loopback service at `127.0.0.1:8791` while the tray is running. |
| Windows tray client | Working | Compiled local tray client and helper installer. |
| Local archive import | Working | EML, MBOX, and JSONL imports are read-only context. |
| Runtime backup/restore | Documented | See [runtime-backup-restore.md](docs/runbooks/runtime-backup-restore.md). |
| macOS/Linux | Limited | Node service and local context tools are portable; Windows tray and Outlook Desktop COM are Windows-only. |

See [ROADMAP.md](docs/ROADMAP.md) for the public status and direction.

## Quick Start

Clone and open the workspace:

```powershell
git clone https://github.com/Prathyush-KKK/NomadMail.git
cd NomadMail
```

Run a safe demo without connecting a mailbox:

```powershell
.\scripts\nomad-inbox.ps1 setup
node .\service\nomadmail-service.mjs self-test
.\scripts\validate.ps1
```

On Windows, install the helper, start the compiled tray, register it for user login startup, and open the tray status popup:

```powershell
.\scripts\nomad-inbox.ps1 install windows-helper --start-tray --register-startup --show-popup
```

A clone alone cannot start a tray app. The install command creates the user-local helper and Windows Startup shortcut. It does not connect accounts, read mail, enable auto sync, or send anything.

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

## Use In Your Own Repository

NomadInbox is open source. You can use it as a local mailbox service alongside another project without copying mailbox data into that project.

Recommended pattern:

1. Clone NomadInbox once on the machine.
2. Install or start the local service from this repo.
3. In another repo, tell your agent where NomadInbox lives.
4. Let the agent call NomadMail through MCP first, tray-owned HTTP second, and CLI third.

Agent prompt:

```text
Use NomadInbox from this workspace:

<path-to-NomadInbox>

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

Backup/restore of NomadInbox runtime data: [runtime-backup-restore.md](docs/runbooks/runtime-backup-restore.md). Archive import: [archive-import.md](docs/runbooks/archive-import.md). Storage and retrieval policy: [message-storage.md](docs/runbooks/message-storage.md).

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

## Contribute

NomadInbox is intended to be usable and extensible by other repositories and agents.

- Read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request.
- Report security issues through [SECURITY.md](SECURITY.md).
- Ask usage questions through [SUPPORT.md](SUPPORT.md).
- Check release packaging in [release.md](docs/runbooks/release.md).

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
