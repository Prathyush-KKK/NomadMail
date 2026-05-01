# ADR 0003: Confirm Before Send

## Status

Accepted

## Context

Mailbox send operations can create external side effects. Agents may draft content, but sending must remain user-controlled.

## Decision

All send operations require explicit confirmation, represented by a command flag or future API confirmation field.

## Consequences

- Drafting and sending are separate actions.
- Accidental sends are harder.
- Audit records can distinguish pending confirmation from confirmed send.

