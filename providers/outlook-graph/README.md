# Outlook Graph Provider

Purpose:

- Read and act on Outlook/Microsoft 365 cloud mailboxes using Microsoft Graph.
- Support Outlook Web mailbox access without relying on browser scraping.

Expected environment variables:

- `NOMADINBOX_GRAPH_CLIENT_ID`
- `NOMADINBOX_GRAPH_TENANT`
- `NOMADINBOX_GRAPH_SCOPES`

Typical scopes:

```text
offline_access User.Read Mail.Read Mail.ReadWrite Mail.Send
```

Send actions must require explicit confirmation.

