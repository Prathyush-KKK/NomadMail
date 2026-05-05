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

The command builds `target\NomadInboxTray\NomadInboxTray.exe` from `src\NomadInbox.Tray\NomadInboxTray.cs` when the executable is missing or stale, then starts that compiled client.

Click or right-click the tray icon to open the compact native status menu. The menu renders from cached status and must not block on sync/status refresh. Refresh, Sync now, HTTP checks, and auto-sync start/stop run in background tasks. The menu can:

- Run a global `Sync now`.
- Turn auto sync on or off after accounts are enabled.
- Show per-account sync status, such as Outlook Desktop or Gmail account rows.
- Keep the local NomadMail HTTP service available at `127.0.0.1:8791` while the tray is running.
- Open Settings and diagnostics.
- Open the runtime folder.

The compatibility launcher remains at `scripts\nomad-inbox-tray.ps1`, but it only builds/starts the compiled client. Do not put tray UI logic back into PowerShell unless the compiled client cannot be built on a target Windows host.

The compact menu does not expose account-connection buttons or raw diagnostics. It shows a short note: ask your agent if you want to connect new accounts. The tray will not start an empty background worker when no accounts are enabled. After an account is connected and enabled, `Auto sync: off (turn on)` starts the same user-session worker as `service start`.

The Settings and diagnostics window shows:

- agent HTTP service status and URL
- MCP stdio ownership
- user locale and time zone used for time parsing
- auto-sync worker state
- live and archive message counts
- enabled account count and per-account sync result
- provider readiness
- runtime, message, archive, status, and log paths
- ignored storage boundaries and approval gates

When auto sync is off, the compact menu keeps the toggle visible but only shows account-connection guidance. When auto sync is on, it summarizes worker state and per-account sync results from `service status`. Logs, error paths, provider details, storage paths, and raw operational details stay in Settings and diagnostics.

## Troubleshooting

| Symptom | Check | Fix |
|---|---|---|
| Tray executable missing | `.\scripts\build-nomad-inbox-tray.ps1` | Rebuild the compiled client; `tray start` also does this automatically |
| Tray menu opens slowly | Confirm menu code uses cached state only | Keep HTTP calls, sync, and CLI work inside background tasks, not menu opening |
| Worker will not start | `.\scripts\nomad-inbox.ps1 service status` | Stop stale PID with `service stop`, then start again |
| No accounts sync | `config\accounts.json` | Ask an agent to connect or enable only the intended account |
| Provider returns `pendingProviderAdapter` | Provider adapter not installed in fresh bootstrap | Implement or port the provider adapter |
| Tray icon not visible | Windows notification overflow area | Expand hidden tray icons or relaunch `tray start` |
| Outlook Desktop cannot sync | Outlook desktop session/profile availability | Open Outlook fully in the same Windows session |

## Safety

The bootstrap worker does not mutate mail. Real provider adapters must preserve the safety gate:

- Draft before send.
- Explicit confirmation before send.
- Audit record for every mutation.
- No permanent delete by default.
