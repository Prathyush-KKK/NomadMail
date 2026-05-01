# NomadInbox SLOs and SLIs

## Scope

These are local operational targets, not external service-level agreements.

## SLIs

| SLI | Measurement |
|---|---|
| Provider auth success | Successful auth attempts / auth attempts |
| Sync success | Successful sync commands / sync commands |
| Search latency | Local search duration |
| Full get latency | Provider-backed full message retrieval duration |
| Audit completeness | Mutating actions with audit records / mutating actions |
| Send safety | Sends requiring explicit confirmation / send attempts |
| Background sync freshness | Current time - `data/sync-status.json.updatedAt` while worker is running |
| Worker availability | Successful `service status` checks reporting worker state / status checks |
| Account sync coverage | Enabled accounts attempted / enabled accounts in each sync cycle |

## Bootstrap Targets

| Process | Target |
|---|---|
| CLI doctor | 100% passes in a fresh clone |
| Schema discovery | 100% passes in a fresh clone |
| Runtime ignore safety | 100% of runtime state ignored by git |
| Send confirmation | 100% of send actions require confirmation |
| Service status | 100% returns JSON even when worker is stopped |
| Worker start/stop | Start and stop complete without requiring administrator privileges |
| Background freshness | Status file updated within 2x the configured interval while worker is running |

## Operating Targets

| Area | Target | Notes |
|---|---|---|
| Request-driven mode | Available without starting background sync | This remains the default product behavior |
| Optional background mode | User can enable/disable per account | Controlled by ignored `config/accounts.json` |
| Tray controller | Menu exposes start, stop, status, config, and runtime folder actions | Tray is an activity indicator, not a full app |
| Audit stream | 100% of sync attempts create an action record in bootstrap mode | Real provider adapters should preserve this behavior |
