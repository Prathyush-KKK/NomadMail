# Session Architecture Changelog

## 2026-05-11 - Windows startup tray popup and README onboarding

Summary:

- Added approved Windows helper install flow for current-user startup shortcut and tray popup on launch, simplified README onboarding, widened NomadMail health CLI timeout, and validated tray, HTTP, MCP, smoke, agent-flow, and new-clone paths.

Session note:

- docs/governance/session-updates/20260511-233538-windows-startup-tray-popup-and-readme-onboarding.md
## 2026-05-11 - Assigned-agent automation events

Summary:

- Added local NomadMail automation events for assigned agents such as Codex, including MCP and HTTP event listing, acknowledgement, automation-cycle tools, Codex setup documentation, schema coverage, and synthetic tests.

Session note:

- docs/governance/session-updates/20260511-002106-assigned-agent-automation-events.md
## 2026-05-10 - Outlook Desktop action execution

Summary:

- Implemented permission-gated Outlook Desktop actions for draft creation, approved draft sending, mark read/unread, flag/unflag, move, archive, attachment save, and trash/delete with dry-run and confirmation gates.

Session note:

- docs/governance/session-updates/20260510-215712-outlook-desktop-action-execution.md
## 2026-05-07 - Cross-chat environment discovery

Summary:

- Added root agent bootstrap guidance and Windows user environment registration for NOMADINBOX_HOME and NomadMail handoff variables so another chat can discover the workspace and fetch the cross-chat handoff without the user memorizing commands.

Session note:

- docs/governance/session-updates/20260507-215854-cross-chat-environment-discovery.md
## 2026-05-07 - Cross-chat handoff service surface

Summary:

- Added a repo-owned cross-chat handoff prompt and exposed it through NomadMail MCP, HTTP, CLI, agent guide, OpenAPI, runbooks, and tests so another chat session can reconnect to the same local workspace safely.

Session note:

- docs/governance/session-updates/20260507-164649-cross-chat-handoff-service-surface.md
## 2026-05-06 - Message action guidance

Summary:

- NomadMail now returns UI-ready mail action guidance after message discovery, with draft-before-send, explicit send approval, provider-runtime caveats, archive read-only handling, and double confirmation for trash/delete.

Session note:

- docs/governance/session-updates/20260506-014308-message-action-guidance.md
## 2026-05-06 - Native tray status popup

Summary:

- The compiled Windows tray now opens a compact native status popup with icon buttons, visible refresh feedback, clean account sync rows, and locale-aware status times.

Session note:

- docs/governance/session-updates/20260506-012528-native-tray-status-popup.md
## 2026-05-06 - Installed compiled tray runtime

Summary:

- Windows helper install now builds and uses an installed compiled tray executable under the local app-data helper folder. The helper sets NOMADINBOX_TRAY_EXE so tray start uses the installed executable, and tray-running detection now matches the configured executable path instead of a generic process-name substring.

Session note:

- docs/governance/session-updates/20260506-012202-installed-compiled-tray-runtime.md
## 2026-05-06 - Compiled Windows tray client

Summary:

- Replaced the blocking PowerShell tray UI with a compiled Windows tray client. The tray renders cached state only, starts or calls the existing NomadMail HTTP service asynchronously, and leaves provider sync and service logic in Node.js and PowerShell.

Session note:

- docs/governance/session-updates/20260506-002225-compiled-windows-tray-client.md
## 2026-05-06 - NomadInbox app logo and tray icon

Summary:

- Added a deterministic NomadInbox logo system with SVG mark, SVG wordmark, generated PNG sizes, and a Windows ICO. The tray and settings window now use the NomadInbox icon instead of the generic Windows application icon.

Session note:

- docs/governance/session-updates/20260506-000904-nomadinbox-app-logo-and-tray-icon.md
## 2026-05-05 - Compact native tray status menu

Summary:

- The Windows tray now opens a compact native menu for Sync now, auto sync, per-account status, Settings, and runtime folder access. Logs, errors, provider details, and storage diagnostics stay in Settings; connection setup is shown as ask-agent guidance only, and auto-sync notifications are human-readable.

Session note:

- docs/governance/session-updates/20260505-233953-compact-native-tray-status-menu.md
## 2026-05-05 - Fresh sync before latest-email answers

Summary:

- NomadMail now exposes a latest-message helper and startup guidance requiring latest-email questions to run a one-shot live sync against already configured enabled accounts before answering; if sync cannot complete, agents must say the latest email cannot be confirmed instead of using stale local state.

Session note:

- docs/governance/session-updates/20260505-232808-fresh-sync-before-latest-email-answers.md
## 2026-05-05 - Locale-aware time handling

Summary:

- NomadInbox now resolves user locale and Windows or IANA time-zone context across PowerShell, Node, tray status, archive import, and agent guidance; ambiguous dates are parsed in that context and stored as UTC ISO timestamps.

Session note:

- docs/governance/session-updates/20260505-231807-locale-aware-time-handling.md
## 2026-05-05 - Tray dashboard popup

Summary:

- Added a compact Windows tray dashboard popup for NomadInbox that shows agent HTTP service status, MCP ownership, auto-sync state, live/archive message counts, account and provider readiness, runtime storage paths, ignored data boundaries, and approval gates without dumping raw JSON. Updated the tray menu, docs, startup prompt, service guide, and validation markers to point users to the dashboard.

Session note:

- docs/governance/session-updates/20260505-225809-tray-dashboard-popup.md
## 2026-05-05 - Tray-first service startup

Summary:

- Updated NomadMail startup guidance and service runbook so Windows service setup starts or verifies the NomadInbox tray instead of only raw HTTP, keeps user-facing setup responses short, and avoids endpoint or JSON dumps unless diagnostics are requested. Updated the tray launcher to use STA mode, return tray availability in the CLI response, and avoid duplicate tray instances.

Session note:

- docs/governance/session-updates/20260505-222823-tray-first-service-startup.md
## 2026-05-05 - Workspace State Continuity

Summary:

- Added a living workspace state file, state update script, and NomadMail workspace-state tool so future agent sessions resume from durable state before refreshing live status.

Session note:

- docs/governance/session-updates/20260505-222058-workspace-state-continuity.md
## 2026-05-05 - Agent Email Sync Guidance

Summary:

- Added agent-facing NomadMail guidance for parsing email backups, redirecting storage to target-repository staging, syncing live mail, and handing normalized JSONL to target indexers.

Session note:

- docs/governance/session-updates/20260505-181544-agent-email-sync-guidance.md
## 2026-05-05 - NomadMail Agent Service

Summary:

- Added the NomadMail MCP and local HTTP callable service, launch scripts, account-scoped sync support, direct local message search, bootstrap Gmail/Graph/Desktop sync adapters, and matching architecture docs.

Session note:

- docs/governance/session-updates/20260505-021907-nomadmail-agent-service.md
## 2026-05-01 - Read Only Archive Import

Summary:

- Added read-only archive import for EML, MBOX, and message JSONL exports, backup status prompts that combine sync/import depth, schema provenance fields, and matching architecture artifacts.

Session note:

- docs/governance/session-updates/20260501-200738-read-only-archive-import.md
## 2026-05-01 - Optional Background Sync And Tray

Summary:

- Added optional user-session background sync worker, per-account sync config, service controls, tray controller, and updated architecture artifacts.

Session note:

- docs/governance/session-updates/20260501-191202-optional-background-sync-and-tray.md
## 2026-05-01 - NomadInbox Architecture Bootstrap

Summary:

- Added C4 diagrams, ADRs, service catalog, process catalog, runbooks, OpenAPI, AsyncAPI, SLOs/SLIs, schemas, and governance scripts for the fresh NomadInbox repository.

Session note:

- docs/governance/session-updates/20260501-184417-nomadinbox-architecture-bootstrap.md
Newest entries should appear at the top.

## 2026-05-01 - NomadInbox Bootstrap

Summary:

- Created a fresh NomadInbox repository with C4 diagrams, ADRs, service catalog, process catalog, runbooks, OpenAPI, AsyncAPI, SLO/SLI documentation, schemas, and governance scripts.

Affected areas:

- Product boundary.
- Local-first runtime model.
- Provider adapter architecture.
- Documentation update process.
