# Tray-first service startup

Date: 2026-05-05

## Summary

Updated NomadMail startup guidance and service runbook so Windows service setup starts or verifies the NomadInbox tray instead of only raw HTTP, keeps user-facing setup responses short, and avoids endpoint or JSON dumps unless diagnostics are requested. Updated the tray launcher to use STA mode, return tray availability in the CLI response, and avoid duplicate tray instances.

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

- The Windows tray is the service-facing user surface for long-running local HTTP access.
- Agent responses for successful service setup should be tray-focused and concise.
- Diagnostics such as endpoint catalogs, raw health JSON, process listings, and search result samples are opt-in.
- The launcher uses Windows PowerShell STA mode for the tray UI and reports `alreadyRunning` instead of spawning duplicates.
