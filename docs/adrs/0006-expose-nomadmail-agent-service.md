# ADR 0006: Expose NomadMail Agent Service

## Status

Accepted

## Context

NomadInbox already defines provider-neutral mailbox schemas, local runtime stores,
provider adapter boundaries, archive import, background sync, and a local
OpenAPI contract. Different agents need a callable service instead of invoking
ad hoc PowerShell commands or reading local files directly.

## Decision

Expose a NomadMail service facade over the NomadInbox core with:

- An MCP stdio server for agent-native tool calls.
- A local HTTP server on `127.0.0.1` for non-MCP agents and local tools.
- PowerShell launchers under `scripts/`.
- A dependency-light Node.js runtime under `service/`.

The first service version wraps the existing CLI for command operations and
reads local JSONL message stores for search/get operations. Bootstrap sync
adapters populate that store for Gmail API, Outlook Graph, and Outlook Desktop
when the matching access token, CLI login, or Outlook profile is available.

## Consequences

- Agents get stable tool names and JSON outputs.
- HTTP clients get the same local contracts without MCP support.
- Send and mailbox mutation tools must still pass the existing confirmation and
  audit rules before being exposed.
- Outlook Desktop remains a user-session integration because Outlook COM depends
  on the signed-in desktop profile.
