# ADR 0008: Draft First And Double Confirm Delete

## Status

Accepted

## Context

After NomadMail discovers a live email, agents should help the user continue into
mail actions such as reply, reply all, forward, new mail, mark, flag, move,
archive, or trash. These actions can create external side effects, and prior
local runs showed that provider permissions and runtime access can be incomplete
or unavailable.

## Decision

NomadMail exposes action guidance after message discovery, but mutation execution
must remain gated:

- Replies, forwards, and new mail must be drafted first.
- Sending is allowed only after explicit user approval of the exact draft,
  recipients, subject, and body.
- Trash/delete requires double explicit approval: first confirm the user's
  intent, then ask for a final confirmation naming the message and mailbox
  effect.
- Imported archive messages stay read-only and cannot be directly replied to,
  moved, archived, trashed, or deleted.
- Agents must tell users that actions may not complete when provider write/send
  permissions or local runtime access are missing.

## Consequences

- Discovery responses can offer a clear action menu without implying permission
  to mutate mail.
- Draft and send remain separate workflow steps.
- Destructive actions have stronger protection than ordinary mailbox state
  changes.
- Provider adapters and future MCP/HTTP mutation tools must preserve the same
  confirmation requirements.
