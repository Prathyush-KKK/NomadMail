# Process Catalog

NomadInbox processes are documented explicitly so provider behavior, safety rules, API contracts, and runbooks remain aligned as the project changes.

## Process Inventory

| Process | Trigger | Inputs | Outputs | Runtime State | Docs To Update When Changed |
|---|---|---|---|---|---|
| Bootstrap setup | `setup` command | Data directory config | Runtime folders and empty JSONL files | `data/` | README, local bootstrap runbook |
| Health check | `doctor` command | Repo files, config, provider status | JSON health result | None unless provider checks cache | Runbooks, SLOs |
| Provider discovery | `providers list` | Provider registry | Provider capability JSON | None | Service catalog, C4 container diagram |
| Config inspection | `config status` | Local env/config | Redacted config status | None | Config template, runbooks |
| Account sync configuration | `accounts init`, `accounts list` | `config/accounts.example.json`, local `config/accounts.json` | Redacted account status | Local ignored config | README, config template, runbooks |
| Schema discovery | `schemas list` | Schema files | Schema location JSON | None | Schemas, OpenAPI/AsyncAPI |
| Message sync | Provider sync command | Provider, folder/query, limit/cursor | Normalized messages | `data/messages.jsonl` | Schemas, AsyncAPI, runbooks, SLOs |
| Archive import | `import eml`, `import mbox`, `import jsonl` | Mail export path, source label, max messages, body-storage choice | Read-only normalized archive messages and search projection | `data/archive-messages.jsonl`, `data/archive-index.jsonl`, `data/import-status.json` | Schemas, AsyncAPI, runbooks, SLOs |
| Backup/context status | `backup status` | Live sync status and import status | Counts and interactive user prompts | Reads `data/` status and JSONL files | README, OpenAPI, runbooks |
| Background sync worker | `service start` | Enabled accounts and intervals | Periodic sync runs and status JSON | `data/sync-status.json`, pid/log files | C4, runbook, SLOs |
| System tray controller | `tray start` | Local CLI and account config | Tray menu for start/stop/status/settings | User-session tray process | Runbook, README |
| Local search | Search command/API | Query/filter fields | Message result summaries | Reads message store | OpenAPI, runbooks, SLOs |
| Full message get | Get command/API | Message ID | Full message body/headers/attachments metadata | May hydrate provider data | Schemas, OpenAPI, runbooks |
| Attachment save | Attachment command/API | Message ID, attachment ID, output dir | Local attachment file | `data/attachments/` or selected output | Schemas, runbooks, safety notes |
| Compose draft | Draft command/API | Recipients, subject, body, attachments | Draft ID | Provider draft state, action audit | Action schema, runbooks, ADRs if safety changes |
| Reply draft | Reply command/API | Message ID, body, attachments | Threaded draft ID | Provider draft state, action audit | Action schema, runbooks |
| Confirmed send | Send command/API with confirmation | Draft ID, explicit confirmation | Sent result | Provider mailbox, action audit | ADR 0003, runbooks, SLOs |
| State mutation | Mark/flag/move/archive/trash command | Message ID, action | Provider state result | Provider mailbox, action audit | Safety docs, action schema, runbooks |
| Audit logging | Any mutation | Action input/result/error | Audit JSON record | `data/actions.jsonl` | AsyncAPI, SLOs |
| Architecture closeout | End of architecture-changing session | Title, summary, changed artifacts | Changelog entry, session note, validation | `docs/governance/session-updates/` | Governance docs |

## Provider Coverage

| Provider | Sync | Search | Full Get | Attachments | Draft | Send | State Mutation | Notes |
|---|---|---|---|---|---|---|---|---|
| Gmail API | Planned | Planned | Planned | Planned | Scope dependent | Confirmed, scope dependent | Scope dependent | Gmail/Workspace where IMAP/POP is disabled |
| Outlook Graph | Planned | Planned | Planned | Planned | Planned | Confirmed | Planned | Outlook web/cloud mailbox via Graph |
| Outlook Desktop | Planned | Planned | Planned | Planned | Planned | Confirmed | Planned | Local Outlook profile via Windows automation |

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
