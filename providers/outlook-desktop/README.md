# Outlook Desktop Provider

Purpose:

- Access the locally configured Outlook Desktop profile through Windows Outlook automation.
- Useful when API or IMAP access is unavailable but Outlook Desktop is already authenticated.

Requirements:

- Windows
- Outlook Desktop installed
- Signed-in Outlook profile
- Same user session as the running automation

Constraints:

- Enterprise policy may block or prompt for object-model access.
- Long-running background operation should be designed carefully around desktop session availability.

Bootstrap sync uses Outlook COM from the signed-in Windows session and reads the
default Inbox. It stores normalized metadata/snippets in `data/messages.jsonl`;
full bodies and mutating actions remain outside the bootstrap adapter.
