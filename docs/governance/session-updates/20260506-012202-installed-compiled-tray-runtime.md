# Installed compiled tray runtime

Date: 2026-05-06

## Summary

Windows helper install now builds and uses an installed compiled tray executable under the local app-data helper folder. The helper sets NOMADINBOX_TRAY_EXE so tray start uses the installed executable, and tray-running detection now matches the configured executable path instead of a generic process-name substring.

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

