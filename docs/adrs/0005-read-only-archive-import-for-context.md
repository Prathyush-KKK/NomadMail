# ADR 0005: Read-Only Archive Import For Context

## Status

Accepted

## Context

NomadInbox uses live provider sync for current mailbox state and safe actions. Users also have historical mail exports from Gmail Takeout, Outlook exports, or prior NomadInbox JSONL snapshots that can improve search, summaries, and agent context.

Archive exports are not guaranteed to map to an actionable live provider message. Treating imported mail like live mail could cause unsafe reply, move, delete, or mark-read behavior.

## Decision

Add archive import as a separate read-only context path.

Bootstrap import formats:

- `.eml` file or folder.
- `.mbox` file, including Gmail Takeout-style exports.
- NomadInbox-compatible message `.jsonl`.

Imported records:

- Use `provider = archive-import`.
- Set `sourceType = archive-import`.
- Set `actionable = false`.
- Set `capabilities = []`.
- Preserve provenance through `sourceProvider`, `sourcePathHash`, and `importBatchId`.

Runtime outputs:

- `data/archive-messages.jsonl`
- `data/archive-index.jsonl`
- `data/import-status.json`

Full body storage is opt-in through `--include-bodies`; default import stores metadata, snippets, headers, and a searchable projection.

## Consequences

Positive:

- Users can enrich long-term mailbox context without changing live mailbox state.
- Agents can distinguish live actionable messages from read-only archive context.
- Import status and backup status can tell users how much mail context is available.

Tradeoffs:

- PST and MSG are not implemented in the bootstrap.
- Archive search projection is local JSONL and should later move to SQLite FTS or an encrypted index.
- Imported messages cannot be directly replied to unless a future live-provider reconciliation links them to current provider IDs.
