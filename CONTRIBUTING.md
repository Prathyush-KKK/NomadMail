# Contributing To NomadInbox

NomadInbox is a local-first mailbox workspace and agent service. Contributions are welcome, especially provider adapters, safer action flows, better tests, platform support, and documentation that helps users run this from other repositories.

## Development Setup

Use PowerShell from the repository root:

```powershell
git clone https://github.com/Prathyush-KKK/Nomad-Inbox.git
cd Nomad-Inbox
.\scripts\nomad-inbox.ps1 setup
node .\service\nomadmail-service.mjs self-test
.\scripts\validate.ps1
```

Windows tray work may also need:

```powershell
.\scripts\build-nomad-inbox-tray.ps1
```

## Contribution Rules

- Do not commit mailbox data, OAuth tokens, token caches, logs, exports, local config, generated scratch scripts, or runtime stores.
- Keep live mailbox access behind explicit user approval for the exact source and scope.
- Preserve the draft-before-send rule.
- Preserve double explicit confirmation for delete/trash operations.
- Keep archive imports read-only.
- Prefer provider adapters and normalized contracts over ad hoc provider-specific shortcuts.
- Add or update tests when behavior changes.

## Useful Validation Commands

```powershell
node --check .\service\nomadmail-service.mjs
.\scripts\validate.ps1
.\tests\agent-user-flow.ps1
.\tests\new-clone.ps1
```

Run the full release gate before publishing installer changes:

```powershell
.\tests\smoke.ps1
.\scripts\build-windows-installer.ps1
```

## Pull Request Checklist

- [ ] I did not commit runtime mailbox data or secrets.
- [ ] I updated docs or runbooks for user-facing behavior changes.
- [ ] I ran the relevant validation command and included the result in the PR.
- [ ] Mail actions still require the documented approvals.
- [ ] New provider behavior preserves provider-native IDs and normalized records.

## Provider Adapter Contributions

Provider adapters should document:

- supported provider and auth mode
- data fields captured
- normalized fields emitted
- action capabilities
- unsupported or risky actions
- setup and test steps without exposing personal mailbox data

Start with the existing provider notes under [providers/](providers/).
