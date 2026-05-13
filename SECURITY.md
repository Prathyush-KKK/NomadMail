# Security Policy

NomadInbox handles local mailbox metadata, optional message content, OAuth configuration, token caches, mail exports, and action audit logs. Treat any security issue that can expose or mutate this data as sensitive.

## Supported Versions

Security fixes target the current `main` branch and the latest tagged release.

| Version | Supported |
|---|---|
| Latest release | Yes |
| `main` | Yes |
| Older releases | Best effort |

## Reporting A Vulnerability

Use GitHub private vulnerability reporting if it is enabled for the repository.

If private vulnerability reporting is not available, open a public issue with only a high-level description and no secrets, tokens, mailbox content, provider IDs, logs, or screenshots containing private data.

Include:

- affected version or commit
- operating system
- provider path involved, such as Gmail API, Outlook Graph, Outlook Desktop, MCP, HTTP, tray, or archive import
- whether the issue can expose data, mutate mail, bypass approval, or access local files
- safe reproduction steps using synthetic data where possible

## Security Boundaries

NomadInbox is designed around these boundaries:

- Runtime data is local and ignored by Git.
- Mailbox access requires user-approved source and scope.
- Sending requires explicit approval of the exact draft.
- Trash/delete requires two explicit confirmations.
- Archive imports are read-only.
- The local HTTP service binds to loopback by default.
- Secrets and token caches must not be committed.

Report any bypass of those boundaries as a security issue.
