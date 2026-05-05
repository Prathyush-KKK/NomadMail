# Background Sync And Tray Runbook

## Purpose

Operate the optional NomadInbox background sync worker and system-tray status controller.

## Start From A Fresh Clone

```powershell
cd C:\Users\prat\Documents\osm\NomadInbox
.\scripts\nomad-inbox.ps1 setup
.\scripts\nomad-inbox.ps1 accounts init
notepad .\config\accounts.json
```

Enable only the accounts that should sync. `config\accounts.json` is local and ignored by git.

## Run One Manual Sync

```powershell
.\scripts\nomad-inbox.ps1 sync once
```

Expected result:

- JSON status is `ok`.
- Each configured account reports `skipped`, `pendingProviderAdapter`, or `ok`.
- `data\sync-status.json` is updated.

## Start Background Sync

```powershell
.\scripts\nomad-inbox.ps1 service start
.\scripts\nomad-inbox.ps1 service status
```

Expected result:

- `worker` is `running`.
- `pid` is populated.
- Runtime files exist under `data\`.

## Stop Background Sync

```powershell
.\scripts\nomad-inbox.ps1 service stop
.\scripts\nomad-inbox.ps1 service status
```

Expected result:

- `worker` is `stopped`.
- `data\sync-worker.pid` is removed or ignored by status checks.

## Start The Tray Controller

```powershell
.\scripts\nomad-inbox.ps1 tray start
```

Right-click the tray icon to:

- Show sync instructions when auto sync is off.
- Show auto sync status when auto sync is on.
- Connect accounts with an agent-guided prompt that asks permission before discovering Gmail, Graph, Azure CLI, or Outlook Desktop profile state.
- Turn auto sync on or off.
- Open account settings.
- Open the runtime folder.
- Open the NomadInbox repo folder.

The tray will not start an empty background worker when no accounts are enabled. It opens the agent connection path first and copies a prompt the user can paste into an agent chat. After an account is connected and enabled, `Turn on auto sync` starts the same user-session worker as `service start`.

When auto sync is off, status text tells the user to open their agent and run a request-driven NomadMail sync. When auto sync is on, status text summarizes worker state, live and archive message counts, last and next run times, and per-account sync results from `service status`.

## Troubleshooting

| Symptom | Check | Fix |
|---|---|---|
| Worker will not start | `.\scripts\nomad-inbox.ps1 service status` | Stop stale PID with `service stop`, then start again |
| No accounts sync | `config\accounts.json` | Use the tray's agent connection prompt, then enable only the intended account |
| Provider returns `pendingProviderAdapter` | Provider adapter not installed in fresh bootstrap | Implement or port the provider adapter |
| Tray icon not visible | Windows notification overflow area | Expand hidden tray icons or relaunch `tray start` |
| Outlook Desktop cannot sync | Outlook desktop session/profile availability | Open Outlook fully in the same Windows session |

## Safety

The bootstrap worker does not mutate mail. Real provider adapters must preserve the safety gate:

- Draft before send.
- Explicit confirmation before send.
- Audit record for every mutation.
- No permanent delete by default.
