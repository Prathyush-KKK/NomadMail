# Gmail API Provider

Purpose:

- Read Gmail and Google Workspace mailboxes where IMAP/POP is disabled.
- Use Gmail REST API and OAuth.
- Normalize messages into NomadInbox `message.v1`.

Expected environment variables:

- `NOMADINBOX_GMAIL_CLIENT_SECRET_JSON`
- `NOMADINBOX_GMAIL_ACCESS_TOKEN`
- `NOMADINBOX_GMAIL_SCOPES`
- `NOMADINBOX_GMAIL_REDIRECT_PORT`

Default safe scope:

```text
https://www.googleapis.com/auth/gmail.readonly
```

Write actions require broader scopes and must still pass the NomadInbox send confirmation safety gate.

Bootstrap sync can read messages when either:

- `NOMADINBOX_GMAIL_ACCESS_TOKEN` contains a valid Gmail-scoped bearer token.
- `gcloud auth print-access-token` returns a token with Gmail API access.

The sync adapter stores normalized metadata/snippets in `data/messages.jsonl`;
it does not store full Gmail message bodies in the bootstrap adapter.
