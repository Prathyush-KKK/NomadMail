# NomadInbox Architecture

## Boundary

NomadInbox is independent from OSM, WebLogic, JMS, and any earlier local test harness. It is a user-facing product bootstrap for agent-readable mailbox access.

## High-Level Model

```text
Agent / User Prompt
  |
  v
NomadInbox CLI / future local API
  |
  v
Command Layer
  |
  +-- Provider Registry
  +-- Safety Gate
  +-- Message Store
  +-- Action Audit Log
  |
  v
Provider Adapters
  |
  +-- Gmail API
  +-- Outlook Graph
  +-- Outlook Desktop
```

## Runtime Data

Runtime data is local and ignored by git:

- `data/messages.jsonl`
- `data/actions.jsonl`
- `data/attachments/`
- token cache files
- provider-specific temporary files

## Provider Contract

Providers should expose these capabilities where supported:

- `doctor`
- `sync`
- `search`
- `get`
- `attachments list`
- `attachments save`
- `compose draft`
- `reply draft`
- `reply-all draft`
- `draft send --confirm`
- `mark-read`
- `mark-unread`
- `flag` / `star`
- `move`
- `archive`
- `trash`

## Safety Gate

Rules:

- Read commands can run after provider auth.
- Draft commands do not imply send.
- Send commands require explicit confirmation.
- Bulk state changes should support dry-run first.
- Permanent delete is not a default action. Prefer trash/archive.
- Every mutating command writes an action record.

## Storage Evolution

Bootstrap:

- JSONL for messages and actions.

Next:

- SQLite for durable local store.
- SQLite FTS for search.
- Encrypted local vault for secrets and tokens.
- MCP server for agent-native tool calls.

