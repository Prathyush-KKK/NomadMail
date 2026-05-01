# Runbook: Provider Porting

## Goal

Move a proven provider implementation into NomadInbox without carrying over local data or machine-specific config.

## Rules

- Copy code only.
- Do not copy `data/`, `target/`, `runtime/`, token caches, local config, or client secret JSON.
- Rename environment variables to the `NOMADINBOX_*` namespace.
- Keep output compatible with `schemas/message.v1.json` and `schemas/action.v1.json`.
- Preserve send confirmation behavior.

## Verification

```powershell
.\scripts\nomad-inbox.ps1 doctor
.\scripts\validate.ps1
git status --short --untracked-files=all
```

Check that no secrets or mailbox data are shown in git status.

