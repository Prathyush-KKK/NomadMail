# Tray dashboard popup

Date: 2026-05-05

## Summary

Added a compact Windows tray dashboard popup for NomadInbox that shows agent HTTP service status, MCP ownership, auto-sync state, live/archive message counts, account and provider readiness, runtime storage paths, ignored data boundaries, and approval gates without dumping raw JSON. Updated the tray menu, docs, startup prompt, service guide, and validation markers to point users to the dashboard.

## Architecture Areas Checked

- Product spec
- C4 diagrams
- ADRs
- Service catalog
- Process catalog
- Runbooks
- OpenAPI/AsyncAPI
- SLOs/SLIs
- Schemas
- Provider docs

## Notes

- Tray double-click and the tray menu now open `Open NomadInbox dashboard` as the primary status surface.
- Dashboard tabs cover status, accounts, providers, and storage/approval boundaries.
- The popup uses existing CLI/service state only; it does not read mailbox bodies or expose message contents.
- The tray process was restarted so the new dashboard code is active in the current Windows session.
