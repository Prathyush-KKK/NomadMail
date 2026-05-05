# Fresh sync before latest-email answers

Date: 2026-05-05

## Summary

NomadMail now exposes a latest-message helper and startup guidance requiring latest-email questions to run a one-shot live sync against already configured enabled accounts before answering; if sync cannot complete, agents must say the latest email cannot be confirmed instead of using stale local state.

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
