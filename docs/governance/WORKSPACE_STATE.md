# NomadInbox Workspace State

Last updated: 2026-05-11

## Current Summary

NomadInbox is a local-first mailbox visibility and action service. NomadMail is the callable MCP and loopback HTTP facade over the same local runtime.

Current workspace state:

- NomadMail exposes agent guidance, startup system prompt, local message search, message lookup, permission-gated message action guidance and Outlook Desktop action execution, provider/account discovery, one-shot sync, archive import, service status, and background worker controls.
- The startup system prompt is system-owned at prompts/nomadmail-startup.system.md.
- Cross-chat handoff is system-owned at prompts/nomadmail-cross-chat-handoff.md and is exposed through nomadmail_get_cross_chat_handoff and HTTP /cross-chat-handoff.
- On Windows, the PowerShell helper initializes ignored runtime state and account config without reading mail or starting auto sync.
- On Windows, the helper registers user environment variables such as NOMADINBOX_HOME so future terminals and agent sessions can discover the workspace.
- On Windows, the tray controller keeps the local NomadMail HTTP service available at 127.0.0.1:8791 while the tray is running. MCP stdio is still launched by each calling agent.
- Date/time parsing uses the user's locale and time zone, then stores normalized UTC ISO timestamps.
- Runtime data, account config, message stores, action logs, imported mail exports, token files, and scratch diagnostics stay out of GitHub.

Exact live counts, worker status, enabled accounts, and provider health are mutable. Agents must refresh those through nomadmail_get_agent_guide, nomadmail_health_check, HTTP /health, or the PowerShell CLI before making current claims.

## Resume Rules For Agents

When opening this workspace:

1. Read AGENTS.md and this file first.
2. Load prompts\nomadmail-startup.system.md or call nomadmail_get_startup_system_prompt.
3. Load docs/runbooks/agent-user-flow.md or call nomadmail_get_agent_user_flow.
4. For another chat session, use prompts/nomadmail-cross-chat-handoff.md, nomadmail_get_cross_chat_handoff, HTTP /cross-chat-handoff, or NOMADINBOX_HOME.
5. Refresh live status using NomadMail tools or service commands.
6. Report current capabilities, storage boundaries, user locale/time-zone context when time scopes matter, approval-gated actions, Windows helper/tray status when applicable, and the safest next action.
7. Do not read mail, discover credentials, scan exports, enable accounts, start auto sync, store bodies, save attachments, or mutate mail without explicit approval. Draft email before send, and require double explicit confirmation before trash/delete.

## Session State Update Rule

At the end of a meaningful session, update this file through:

    .\scripts\session-closeout.ps1 -Title "Short change title" -Summary "What changed and why"

For state-only updates that do not need a full architecture note:

    .\scripts\update-workspace-state.ps1 -Title "Short state title" -Summary "Current state summary"

The state file should capture durable workspace behavior and follow-ups. It should not include secrets, raw mailbox data, token values, message bodies, or private email contents.

## Latest Session

Title: Windows startup tray popup and README onboarding

Status: completed

Summary:

- Added approved Windows helper install flow for current-user startup shortcut and tray popup on launch, simplified README onboarding, widened NomadMail health CLI timeout, and validated tray, HTTP, MCP, smoke, agent-flow, and new-clone paths.

Workspace revision:

- Branch: main
- HEAD: 08aedb1

## Open Follow-Ups

- Refresh live status at startup and continue from the latest user-approved source/action.