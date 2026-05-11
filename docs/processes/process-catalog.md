# Process Catalog

NomadInbox processes are documented explicitly so provider behavior, safety rules, API contracts, and runbooks remain aligned as the project changes.

## Process Inventory

| Process | Trigger | Inputs | Outputs | Runtime State | Docs To Update When Changed |
|---|---|---|---|---|---|
| Bootstrap setup | `setup` command | Data directory config | Runtime folders and empty JSONL files | `data/` | README, local bootstrap runbook |
| Health check | `doctor` command | Repo files, config, provider status | JSON health result | None unless provider checks cache | Runbooks, SLOs |
| Provider discovery | `providers list` | Provider catalog and adapter capability metadata | Provider capability JSON | None | Service catalog, C4 container diagram |
| Agent tool discovery | MCP `tools/list`, `node service/nomadmail-service.mjs tools` | NomadMail tool registry | MCP tool schemas | None | README, service catalog, OpenAPI |
| Startup system prompt discovery | `nomadmail_get_startup_system_prompt`, `/startup-system-prompt` | `prompts/nomadmail-startup.system.md` | System prompt JSON | None | README, agent service runbook, OpenAPI |
| Agent user flow | First prompt, setup continuation, daily mail query choices, `nomadmail_get_agent_user_flow`, `/agent-user-flow` | Startup prompt, workspace state, provider/account status, `docs/runbooks/agent-user-flow.md` | User-facing next steps and daily-mail choices | None | README, startup prompt, agent service runbook, OpenAPI |
| Cross-chat handoff | Another chat or agent needs to connect, `nomadmail_get_cross_chat_handoff`, `/cross-chat-handoff` | `prompts/nomadmail-cross-chat-handoff.md` | Canonical handoff prompt JSON | None | README, startup prompt, agent service runbook, OpenAPI |
| Workspace state discovery | `nomadmail_get_workspace_state`, `/workspace-state` | `docs/governance/WORKSPACE_STATE.md` | Current workspace state JSON | None | README, agent service runbook, OpenAPI |
| Workspace state update | `update-workspace-state.ps1`, `session-closeout.ps1` | Session title, summary, follow-up | Refreshed `WORKSPACE_STATE.md` | `docs/governance/WORKSPACE_STATE.md` | Governance docs |
| Locale/time context | CLI/MCP/HTTP startup and date parsing | OS user culture/time zone or `NOMADINBOX_USER_*` overrides | UTC ISO timestamps plus local display context | None | README, schemas, OpenAPI, runbooks |
| Agent callable service | `nomadmail-mcp.ps1`, `nomadmail-http.ps1` | MCP/HTTP requests | Agent-readable JSON responses | Reads local stores and may call CLI | Agent service runbook, C4, OpenAPI |
| Windows agent helper install | `install windows-helper`, `nomadmail_install_windows_helper` | OS check, optional data/install paths, optional tray/startup flags | Helper launcher, helper status JSON, user environment variables, optional current-user Startup shortcut | `%LOCALAPPDATA%\NomadInbox\agent-helper`, ignored runtime data, user env `NOMADINBOX_HOME` and `NOMADMAIL_*` discovery variables, optional Startup `.lnk` | README, runbooks, service catalog, OpenAPI |
| Windows release package | `build-windows-installer.ps1` | `VERSION`, clean git tree, tracked product files | Versioned zip, sidecar manifest, SHA-256 hash | Ignored `dist/` and `target/release/` | README, release runbook, service catalog |
| Config inspection | `config status` | Local env/config | Redacted config status | None | Config template, runbooks |
| Account sync configuration | `accounts init`, `accounts list` | `config/accounts.example.json`, local `config/accounts.json` | Redacted account status | Local ignored config | README, config template, runbooks |
| Schema discovery | `schemas list` | Schema files | Schema location JSON | None | Schemas, OpenAPI/AsyncAPI |
| Message sync | Provider sync command | Provider, folder/query, limit/cursor | Normalized messages | `data/messages.jsonl` | Schemas, AsyncAPI, runbooks, SLOs |
| Latest live message read | Latest-email user question, `nomadmail_get_latest_message`, `POST /messages/latest` | Optional account/provider/folder, content requirement | Newest live message summary after one-shot sync | Reads/writes `data/messages.jsonl`, `data/sync-status.json` | README, agent service runbook, OpenAPI, tests |
| Archive import | `import eml`, `import mbox`, `import jsonl` | Mail export path, source label, max messages, body-storage choice | Read-only normalized archive messages and search projection | `data/archive-messages.jsonl`, `data/archive-index.jsonl`, `data/import-status.json` | Schemas, AsyncAPI, runbooks, SLOs |
| Backup/context status | `backup status` | Live sync status and import status | Counts and interactive user prompts | Reads `data/` status and JSONL files | README, OpenAPI, runbooks |
| Background sync worker | `service start` | Enabled accounts and intervals | Periodic sync runs and status JSON | `data/sync-status.json`, pid/log files | C4, runbook, SLOs |
| Compiled system tray client | `tray start` | Cached status file, local HTTP, account config, optional startup popup flag | Nonblocking tray popup for sync/status/settings | User-session `NomadInboxTray.exe` process | Runbook, README, C4, SLOs |
| Tray status check | `tray status` | Process table, helper status, local HTTP health | JSON tray/helper/HTTP/worker status | Reads helper status and local runtime status | Runbook, README, tests |
| Local search | Search command/API | Query/filter fields | Message result summaries | Reads message store | OpenAPI, runbooks, SLOs |
| Full message get | Get command/API | Message ID | Full message body/headers/attachments metadata | May hydrate provider data | Schemas, OpenAPI, runbooks |
| Attachment save | Attachment command/API | Message ID, attachment ID, output dir | Local attachment file | `data/attachments/` or selected output | Schemas, runbooks, safety notes |
| Compose draft | Draft command/API | Recipients, subject, body, attachments | Draft ID | Provider draft state, action audit | Action schema, runbooks, ADRs if safety changes |
| Reply draft | Reply command/API | Message ID, body, attachments | Threaded draft ID | Provider draft state, action audit | Action schema, runbooks |
| Confirmed send | Send command/API with confirmation | Draft ID, explicit confirmation | Sent result | Provider mailbox, action audit | ADR 0003, runbooks, SLOs |
| Message action guidance | `nomadmail_get_message_actions`, message `actionMenu` | Optional message ID | UI-ready allowed actions and permission gates | Local message projection only | Agent service runbook, startup prompt |
| State mutation | Mark/flag/move/archive/trash command | Message ID, action, explicit confirmation; trash/delete needs second confirmation | Provider state result | Provider mailbox, action audit | Safety docs, action schema, runbooks |
| Audit logging | Any mutation | Action input/result/error | Audit JSON record | `data/actions.jsonl` | AsyncAPI, SLOs |
| Architecture closeout | End of architecture-changing session | Title, summary, changed artifacts | Changelog entry, session note, workspace state refresh, validation | `docs/governance/session-updates/`, `docs/governance/WORKSPACE_STATE.md` | Governance docs |

## Provider Coverage

| Provider | Sync | Search | Full Get | Attachments | Draft | Send | State Mutation | Notes |
|---|---|---|---|---|---|---|---|---|
| Gmail API | Bootstrapped | Local store | Local store | Planned | Scope dependent | Confirmed, scope dependent | Scope dependent | Uses bearer token env or gcloud access token |
| Outlook Graph | Bootstrapped | Local store | Local store | Planned | Planned | Confirmed | Planned | Uses bearer token env or Azure CLI Graph token |
| Outlook Desktop | Bootstrapped | Local store | Local store | Planned | Planned | Confirmed | Planned | Uses local Outlook COM in signed-in Windows session |

## Required Documentation Updates By Change Type

| Change Type | Required Artifacts |
|---|---|
| New provider | C4 diagrams, service catalog, provider runbook, config template, ADR if decision-level |
| New command/API | README, runbook, OpenAPI, process catalog, tests |
| Schema change | JSON schema, OpenAPI/AsyncAPI, runbooks, process catalog |
| Safety rule change | ADR, architecture overview, runbooks, SLOs |
| Runtime storage change | Architecture overview, C4 container, AsyncAPI, runbook, SLOs |
| Auth flow change | Provider README, runbook, service catalog, config example |
| Archive import format change | Import runbook, schema, AsyncAPI, OpenAPI, process catalog |
