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

## Bootstrap Targets

| Process | Target |
|---|---|
| CLI doctor | 100% passes in a fresh clone |
| Schema discovery | 100% passes in a fresh clone |
| Runtime ignore safety | 100% of runtime state ignored by git |
| Send confirmation | 100% of send actions require confirmation |

