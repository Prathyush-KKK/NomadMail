# Architecture Index

Project location:

```text
C:\Users\prat\Documents\osm\NomadInbox
```

## Artifact Map

| Artifact | Location | Purpose |
|---|---|---|
| Product spec | `docs/PRODUCT_SPEC.md` | Product scope, MVP boundaries, user-facing goals |
| Architecture overview | `docs/ARCHITECTURE.md` | System boundary, runtime model, provider contract, safety model |
| C4 diagrams | `docs/c4/` | System context, containers, dynamic flows |
| ADRs | `docs/adrs/` | Architecture decisions and rationale |
| Service catalog | `docs/service-catalog/` | Services/processes, status, ownership, auth model |
| Process catalog | `docs/processes/process-catalog.md` | End-to-end operational process inventory |
| Runbooks | `docs/runbooks/` | Operating procedures and troubleshooting |
| Release packaging | `docs/runbooks/release.md` | Versioned Windows installer/package flow |
| SLOs/SLIs | `docs/slo/nomadinbox-slo.md` | Local reliability targets and measurements |
| OpenAPI | `api/openapi/nomadinbox.v1.yaml` | Local HTTP service contract |
| AsyncAPI | `api/asyncapi/nomadinbox-events.v1.yaml` | Local JSONL/event contract |
| Governance | `docs/governance/` | Required architecture update workflow |
| Workspace state | `docs/governance/WORKSPACE_STATE.md` | Living current-state file for agent session resume |
| Schemas | `schemas/` | Agent-readable message/action contracts |
| NomadMail service | `service/nomadmail-service.mjs` | MCP and local HTTP callable agent runtime |
| Compiled tray client | `src/NomadInbox.Tray/` | Windows tray UI source; compiled to ignored `target/NomadInboxTray/NomadInboxTray.exe` |
| Version file | `VERSION` | Shared app version for service health and release packages |

## Required Update Rule

When a session changes architecture, provider behavior, command contracts, schemas, storage, safety rules, auth flow, runtime assumptions, or operational process, update the affected architecture artifacts in the same session.

Preferred closeout:

```powershell
.\scripts\session-closeout.ps1 -Title "Short change title" -Summary "What changed and why"
```

State-only refresh:

```powershell
.\scripts\update-workspace-state.ps1 -Title "Short state title" -Summary "Current state summary"
```

Validation-only:

```powershell
.\scripts\validate.ps1
```
