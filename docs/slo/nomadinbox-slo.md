# NomadInbox SLOs and SLIs

## Scope

These are local operational targets, not external service-level agreements.

## SLIs

| SLI | Measurement |
|---|---|
| Provider auth success | Successful auth attempts / auth attempts |
| Sync success | Successful sync commands / sync commands |
| Latest-email freshness | Latest-email answers preceded by a successful request-scoped live sync / latest-email answer attempts |
| Search latency | Local search duration |
| Full get latency | Provider-backed full message retrieval duration |
| Audit completeness | Mutating actions with audit records / mutating actions |
| Send safety | Sends requiring explicit confirmation / send attempts |
| Background sync freshness | Current time - `data/sync-status.json.updatedAt` while worker is running |
| Worker availability | Successful `service status` checks reporting worker state / status checks |
| Account sync coverage | Enabled accounts attempted / enabled accounts in each sync cycle |
| Archive import success | Successfully parsed archive messages / archive messages attempted |
| Locale time handling | Ambiguous date/time imports parsed with user locale/time-zone context, stored as UTC ISO |
| Backup status freshness | `backup status` reflects latest sync and import status files |
| Agent service health | MCP self-test and HTTP `/health` return structured JSON |
| Tray menu responsiveness | Tray menu opens from cached status without waiting on HTTP, sync, or CLI calls |

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
| Archive dry-run safety | Dry-run import writes no archive message records |
| Time normalization | 100% of message, sync, import, and action timestamps are persisted as UTC ISO 8601 |
| Latest-email safety | 100% of latest-email failures caused by auth/provider/account issues are reported as not confirmed instead of answered from stale state |
| Imported mail safety | 100% of archive imported messages set `actionable=false` |
| Agent tool discovery | MCP `tools/list` and `node service/nomadmail-service.mjs tools` expose valid tool schemas |

## Operating Targets

| Area | Target | Notes |
|---|---|---|
| Request-driven mode | Available without starting background sync | This remains the default product behavior |
| Optional background mode | User can enable/disable per account | Controlled by ignored `config/accounts.json` |
| Compiled tray client | Compact native menu exposes Sync now, auto-sync toggle, per-account status, Settings, and runtime folder actions without blocking on refresh | Logs, errors, provider diagnostics, locale, and time-zone details stay in Settings |
| Tray menu latency | 95% of tray menu opens complete within 300 ms from cached state | HTTP refresh and sync run asynchronously after the menu is usable |
| Audit stream | 100% of sync attempts create an action record in bootstrap mode | Real provider adapters should preserve this behavior |
| Archive import | `eml`, `mbox`, and `jsonl` imports return counts and provenance | PST/MSG remain planned |
| User prompts | `backup status` always tells users current backup depth and next useful action | Prompts are derived from local stats |
| Agent callable mode | MCP and HTTP wrappers call the same local contracts as the CLI | HTTP binds to loopback by default |
