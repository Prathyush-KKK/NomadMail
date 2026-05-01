# NomadInbox Product Spec

## Summary

NomadInbox is a local-first email operations layer for coding agents. It normalizes mailbox data from Gmail, Outlook Graph, and Outlook Desktop into stable JSON contracts so agents can search, inspect, summarize, draft, and perform controlled mailbox actions.

## Target User

- A local operator using Codex or another coding agent.
- A developer who wants agent-readable email data without exposing raw provider internals.
- A user whose mailbox provider may disable IMAP/POP and require API/native access.

## Core Jobs

1. Connect a mailbox provider safely.
2. Sync recent messages into a local, inspectable store.
3. Import historical mail exports as read-only context when users want deeper recall.
4. Search messages using prompt-friendly fields.
5. Fetch full message details only when needed.
6. Draft replies or new mail without sending immediately.
7. Send only after explicit user confirmation.
8. Audit every mutating action.
9. Remind users how much live and archived mail context is backed up.

## Providers

| Provider | Use Case | Auth |
|---|---|---|
| Gmail API | Gmail/Workspace where IMAP/POP is disabled | Google OAuth / domain delegation |
| Outlook Graph | Outlook web / Microsoft 365 cloud mailbox | Microsoft OAuth / Graph permissions |
| Outlook Desktop | Local Outlook profile and desktop mailbox state | Windows Outlook profile |

## MVP Scope

- Local PowerShell CLI.
- Optional user-session background sync worker.
- Optional Windows system-tray controller.
- Provider adapter contract.
- JSON message/action schemas.
- Local JSONL runtime store.
- Read-only archive import for `.eml`, `.mbox`, and existing message JSONL.
- Backup/context status prompts.
- Read-only default posture.
- Config examples without secrets.
- C4, ADR, runbook, service catalog, API, and SLO documentation.

## Out Of Scope For Bootstrap

- Shipping user mailbox data.
- Shipping OAuth token caches.
- Shipping personal config.
- Hosted SaaS deployment.
- Permanent delete without explicit multi-step confirmation.
- Privileged Windows Service installation.
- Always-on sync by default.

## Success Criteria

- Fresh clone starts with no personal data.
- `setup`, `doctor`, `providers list`, and schema discovery run locally.
- Users can optionally start background sync and inspect status without making it mandatory.
- Users can configure per-account sync settings through ignored local config.
- Users can import historical mail exports without making those messages directly actionable.
- Users can see backed-up message counts and guidance through `backup status`.
- Provider implementations can be added without changing the normalized data contracts.
- Git ignores runtime data and secrets by default.
