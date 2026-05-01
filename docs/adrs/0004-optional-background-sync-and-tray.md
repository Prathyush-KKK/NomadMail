# ADR 0004: Optional Background Sync And Tray Controller

## Status

Accepted

## Context

NomadInbox is request-driven by default so agents can query mail only when a user asks. Some users also need fresh local message state without manually running `sync once` before every prompt.

The product must support Outlook Desktop, Outlook Graph, and Gmail API. Outlook Desktop automation runs in the signed-in Windows user session, so a privileged Windows Service would create avoidable complexity and may not be able to access the active Outlook profile.

## Decision

Add an optional user-session background worker and a lightweight Windows system-tray controller.

The worker:

- Starts through `.\scripts\nomad-inbox.ps1 service start`.
- Runs `scripts\nomad-inbox-worker.ps1` in the signed-in user session.
- Reads ignored local account settings from `config/accounts.json`.
- Polls enabled accounts at their configured intervals.
- Writes `data/sync-status.json`, `data/sync-worker.pid`, and worker logs under ignored runtime storage.

The tray controller:

- Starts through `.\scripts\nomad-inbox.ps1 tray start`.
- Uses a Windows Forms `NotifyIcon`.
- Provides status, start, stop, account config, runtime folder, and repo folder menu actions.

## Consequences

Positive:

- Users can keep NomadInbox request-driven or opt into routine sync.
- The bootstrap works without administrator rights.
- Desktop provider compatibility stays realistic because the worker runs in the user session.
- Account-specific sync settings are explicit and local.

Tradeoffs:

- The worker stops when the user session exits.
- This is not yet a durable service supervisor.
- Status is file-backed rather than exposed through a long-running HTTP daemon.

## Follow-Up

- Add Windows Task Scheduler integration for launch-at-login.
- Add an MCP or local HTTP service wrapper when agent tooling needs a long-lived endpoint.
- Revisit a privileged service wrapper only for API-only providers that do not depend on desktop session state.
