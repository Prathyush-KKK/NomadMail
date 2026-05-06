# NomadInbox Workspace State

Last updated: 2026-05-07

## Current Summary

NomadInbox is a local-first mailbox visibility and action service. NomadMail is the callable MCP and loopback HTTP facade over the same local runtime.

Current workspace state:

- NomadMail exposes agent guidance, startup system prompt, local message search, message lookup, permission-gated message action guidance, provider/account discovery, one-shot sync, archive import, service status, and background worker controls.
- The startup system prompt is system-owned at prompts/nomadmail-startup.system.md.
- On Windows, the PowerShell helper initializes ignored runtime state and account config without reading mail or starting auto sync.
- On Windows, the tray controller keeps the local NomadMail HTTP service available at 127.0.0.1:8791 while the tray is running. MCP stdio is still launched by each calling agent.
- Date/time parsing uses the user's locale and time zone, then stores normalized UTC ISO timestamps.
- Runtime data, account config, message stores, action logs, imported mail exports, token files, and scratch diagnostics stay out of GitHub.

Exact live counts, worker status, enabled accounts, and provider health are mutable. Agents must refresh those through nomadmail_get_agent_guide, nomadmail_health_check, HTTP /health, or the PowerShell CLI before making current claims.

## Resume Rules For Agents

When opening this workspace:

1. Read this file first.
2. Load prompts\nomadmail-startup.system.md or call nomadmail_get_startup_system_prompt.
3. Load docs/runbooks/agent-user-flow.md or call nomadmail_get_agent_user_flow.
4. Refresh live status using NomadMail tools or service commands.
5. Report current capabilities, storage boundaries, user locale/time-zone context when time scopes matter, approval-gated actions, Windows helper/tray status when applicable, and the safest next action.
6. Do not read mail, discover credentials, scan exports, enable accounts, start auto sync, store bodies, save attachments, or mutate mail without explicit approval. Draft email before send, and require double explicit confirmation before trash/delete.

## Session State Update Rule

At the end of a meaningful session, update this file through:

    .\scripts\session-closeout.ps1 -Title "Short change title" -Summary "What changed and why"

For state-only updates that do not need a full architecture note:

    .\scripts\update-workspace-state.ps1 -Title "Short state title" -Summary "Current state summary"

The state file should capture durable workspace behavior and follow-ups. It should not include secrets, raw mailbox data, token values, message bodies, or private email contents.

## Latest Session

Title: Testing handoff and health readiness fixes

Status: validated

Summary:

- Added the cross-agent testing handoff with current input-output observations, validated current-workspace and clean-clone style scenarios, and bounded NomadMail health-check CLI calls so HTTP readiness stays responsive.

Workspace revision:

- Branch: main
- HEAD: 7ab49d6

## Open Follow-Ups

- Run tests/new-clone.ps1 -ExpectedCleanClone from a real fresh clone on another machine and compare the generated JSON report against docs/runbooks/testing-handoff.md.