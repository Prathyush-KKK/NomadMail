# Gmail API Provider

Purpose:

- Read Gmail and Google Workspace mailboxes where IMAP/POP is disabled.
- Use Gmail REST API and OAuth.
- Normalize messages into NomadInbox `message.v1`.

Expected environment variables:

- `NOMADINBOX_GMAIL_CLIENT_SECRET_JSON`
- `NOMADINBOX_GMAIL_ACCESS_TOKEN`
- `NOMADINBOX_GMAIL_AUTH_MODE`
- `NOMADINBOX_GMAIL_OAUTH_CLIENT_ID`
- `NOMADINBOX_GMAIL_OAUTH_CLIENT_SECRET`
- `NOMADINBOX_GMAIL_OAUTH_REFRESH_TOKEN`
- `NOMADINBOX_GMAIL_OAUTH_TOKEN_URI`
- `NOMADINBOX_GMAIL_SCOPES`
- `NOMADINBOX_GMAIL_REDIRECT_PORT`

Default safe scope:

```text
https://www.googleapis.com/auth/gmail.readonly
```

Write actions require broader scopes and must still pass the NomadInbox send confirmation safety gate.

Bootstrap sync can read messages when either:

- `NOMADINBOX_GMAIL_ACCESS_TOKEN` contains a valid Gmail-scoped bearer token.
- the account config sets `authMode` to `refresh-token`, or `NOMADINBOX_GMAIL_AUTH_MODE=refresh-token`, and the OAuth client id, client secret, refresh token, and token URI are available from ignored local config or process environment.
- `gcloud auth print-access-token` returns a token with Gmail API access.
- the account config or environment sets `authMode` / `NOMADINBOX_GMAIL_AUTH_MODE` to `gcloud-adc`, and `gcloud auth application-default print-access-token` returns a Gmail-scoped token.

Use `refresh-token` mode for normal unattended local operation. It avoids the
fragile browser/application-default credential path and mints short-lived access
tokens from a locally ignored refresh token at sync time.

The sync adapter stores normalized metadata/snippets in `data/messages.jsonl`;
it does not store full Gmail message bodies in the bootstrap adapter.
