# Compiled Windows tray client

Date: 2026-05-06

## Summary

Replaced the blocking PowerShell tray UI with a compiled Windows tray client. The tray renders cached state only, starts or calls the existing NomadMail HTTP service asynchronously, and leaves provider sync and service logic in Node.js and PowerShell.

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
