# Gmail API Provider

Purpose:

- Read Gmail and Google Workspace mailboxes where IMAP/POP is disabled.
- Use Gmail REST API and OAuth.
- Normalize messages into NomadInbox `message.v1`.

Expected environment variables:

- `NOMADINBOX_GMAIL_CLIENT_SECRET_JSON`
- `NOMADINBOX_GMAIL_SCOPES`
- `NOMADINBOX_GMAIL_REDIRECT_PORT`

Default safe scope:

```text
https://www.googleapis.com/auth/gmail.readonly
```

Write actions require broader scopes and must still pass the NomadInbox send confirmation safety gate.

