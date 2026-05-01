# ADR 0002: Use Provider Adapters

## Status

Accepted

## Context

Gmail API, Outlook Graph, and Outlook Desktop use different authentication, data models, folder semantics, and message IDs.

Agents should not need provider-specific logic for common operations.

## Decision

Expose provider-specific code behind a shared adapter contract and normalize all message/action output through versioned JSON schemas.

## Consequences

- Provider implementations can evolve independently.
- Agent prompts can work across mailbox types.
- Provider capability flags must be included so unsupported actions are visible.

