# Message Storage And Retrieval Policy

## Purpose

NomadInbox is not just a Gmail or Outlook MCP wrapper. Many email MCP projects call the provider live for each user request and return the provider response directly. NomadInbox keeps a local, provider-neutral working set so agents can search, summarize, group, and prepare safe actions without repeatedly asking the provider or leaking provider-specific shapes into every UI/tool surface.

## Storage Layers

| Layer | File | Purpose | Efficiency rule |
|---|---|---|---|
| Live normalized messages | `data/messages.jsonl` | Stable agent/UI contract for live synced mail | Upsert by deterministic message id. Read this first for search, summaries, digests, and action menus. |
| Provider raw snapshots | `data/provider-raw.jsonl` | Provider-specific evidence for fields that do not fit the normalized contract | Upsert by deterministic raw id. Capture only approved body/attachment detail. |
| Archive messages | `data/archive-messages.jsonl` | Read-only historical mail context | Upsert by deterministic archive id. Never actionable. |
| Archive search index | `data/archive-index.jsonl` | Smaller search projection for archive imports | Upsert beside archive messages. Rebuildable. |
| Action audit log | `data/actions.jsonl` | Immutable action/sync/audit events | Append-only. |

## Query Path

Agents and UI surfaces should use this order:

1. Search `messages.jsonl` and `archive-index.jsonl`.
2. Fetch the selected record from `messages.jsonl` or `archive-messages.jsonl`.
3. Use `providerRawRef` only when a provider-specific field is required.
4. For actions, use only live synced records with provider-native IDs preserved.
5. For latest-mail questions, run a one-shot live sync first; do not present stale local rows as definitely latest.

This keeps common reads cheap and provider-neutral while preserving raw evidence for deeper inspection.

## Gmail Capture Rules

Gmail API sync may need `format=full` to discover nested attachment metadata. That response can also include inline base64 body data. NomadInbox therefore uses these rules:

- `includeBodies=false`: normalized rows store snippets/metadata only; provider raw snapshots strip inline `body.data` fields before writing.
- `includeBodies=true`: normalized rows store decoded text/html body content when available; provider raw snapshots may preserve inline body data.
- `includeAttachments=true`: store attachment metadata only.
- `saveAttachments=false`: do not fetch or persist attachment bytes.

This avoids accidental full-body storage while keeping attachment discovery useful.

## Archive Import Rules

Archive imports are context, not live mailbox authority:

- Imported messages have `actionable=false`.
- Re-importing the same export should update existing rows rather than duplicate them.
- Full archive body storage requires explicit `--include-bodies`.
- Agents must locate a matching live provider message before offering live mailbox actions.

## When To Use Provider Raw Data

Use `provider-raw.jsonl` only for:

- provider-specific IDs, headers, labels, flags, categories, or attachment metadata not present in the normalized record
- debugging provider adapters
- future re-normalization after schema changes
- source-backed evidence when an agent needs to explain exactly where a field came from

Do not make tray UI, summaries, or ordinary search depend on provider raw shape.

## Future Storage Direction

JSONL is the bootstrap storage format because it is inspectable, portable, and easy for agents to audit. For high-volume mailboxes, the next storage step should be a local SQLite/read-model layer built from the same normalized contract:

- keep `messages.jsonl` / `provider-raw.jsonl` as portable source files or backup/export format
- build indexed tables for message search, sender lookup, date ranges, threads, labels, attachments, and action state
- keep provider raw snapshots separate from the agent/UI read model
- preserve the same approval gates before actions
