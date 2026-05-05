# NomadMail Agent Service

Date: 2026-05-05

## Summary

Added the NomadMail MCP and local HTTP callable service, launch scripts, account-scoped sync support, direct local message search, bootstrap Gmail/Graph/Desktop sync adapters, and matching architecture docs.

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

- Added `service/nomadmail-service.mjs` as the dependency-light Node runtime for MCP stdio and loopback HTTP.
- Added `scripts/nomadmail-mcp.ps1` and `scripts/nomadmail-http.ps1` launchers.
- Added account-scoped `sync once --account-id` and `service start --interval-seconds` CLI options for service callers.
- Added bootstrap sync adapters for Gmail API, Outlook Graph, and Outlook Desktop.
- Added architecture, OpenAPI, runbook, service catalog, process, SLO, and ADR coverage for the callable service.
