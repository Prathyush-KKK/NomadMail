# Locale-aware time handling

Date: 2026-05-05

## Summary

NomadInbox now resolves user locale and Windows or IANA time-zone context across PowerShell, Node, tray status, archive import, and agent guidance; ambiguous dates are parsed in that context and stored as UTC ISO timestamps.

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

Record what changed and which artifacts were updated.
