# Architecture Update Process

Any architecture-changing session must update the affected docs in the same commit as code.

Architecture changes include:

- New provider
- Changed auth flow
- Changed message/action schema
- Changed command contract
- Changed safety rule
- Changed storage behavior
- Changed runbook or operational process

Minimum closeout:

```powershell
.\scripts\session-closeout.ps1 -Title "Short change title" -Summary "What changed and why"
```

Validation-only:

```powershell
.\scripts\validate.ps1
git status --short --untracked-files=all
```

The closeout script creates a timestamped note under:

```text
docs/governance/session-updates/
```

It also appends to:

```text
docs/governance/SESSION_CHANGELOG.md
```
