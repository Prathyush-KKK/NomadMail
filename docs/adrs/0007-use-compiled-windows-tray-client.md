# ADR 0007: Use a compiled Windows tray client

## Status

Accepted

## Context

The NomadInbox tray started as a PowerShell WinForms script. That kept the bootstrap fast, but it made tray interactions easy to block because status refresh and sync calls lived near UI event handlers.

The NomadMail service logic should stay Node.js plus PowerShell for now. Provider sync, account config, MCP, and HTTP contracts already depend on those surfaces and should not be moved into a desktop UI client.

## Decision

Replace tray UI logic with a compiled Windows Forms client:

- source: `src/NomadInbox.Tray/NomadInboxTray.cs`
- build script: `scripts/build-nomad-inbox-tray.ps1`
- output: `target/NomadInboxTray/NomadInboxTray.exe`
- installed output: `%LOCALAPPDATA%/NomadInbox/agent-helper/NomadInboxTray.exe`
- compatibility launcher: `scripts/nomad-inbox-tray.ps1`

The tray client reads cached status first and performs HTTP refresh, Sync now, and auto-sync start/stop through background tasks. The left-click status popup and right-click fallback menu render only from cached in-memory state, so opening tray controls does not wait on HTTP, provider sync, or CLI execution.

The tray may start the existing Node HTTP service when needed, but provider/service behavior remains owned by `service/nomadmail-service.mjs` and the PowerShell core.

## Consequences

- Tray startup still works through `nomad-inbox.ps1 tray start`.
- Windows hosts do not need `dotnet`; Windows PowerShell compiles the tray with the local .NET Framework compiler path.
- The repository-local compiled executable is generated under ignored `target/` and should not be committed.
- The Windows helper install creates an installed tray executable and sets `NOMADINBOX_TRAY_EXE` so the installed helper uses that copy instead of the repository-local build output.
- PowerShell remains as a launcher/build wrapper and service layer, not as the tray UI runtime.
- Future tray changes must preserve the nonblocking UI rule: no HTTP, sync, or CLI calls during popup or menu construction.
