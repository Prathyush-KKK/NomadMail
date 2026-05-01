# ADR 0001: Create A Fresh NomadInbox Repository

## Status

Accepted

## Context

The earlier mail-agent experiments proved provider-specific access patterns, but included local worktrees and runtime state tied to a single development machine.

NomadInbox needs to be presented as a clean product bootstrap.

## Decision

Create a new repository named `NomadInbox` with only generic code, docs, schemas, and safe config examples.

Do not carry over:

- mailbox data
- JSONL message/action logs
- OAuth token caches
- local user config
- client secret JSON files
- personal email addresses in config

## Consequences

- The repo is safe to show as a fresh project.
- Provider code can be ported in cleanly behind the adapter contract.
- Local users must configure their own providers before live mailbox access works.

