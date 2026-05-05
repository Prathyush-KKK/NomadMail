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

## Agent Commit Message Rule

Before committing, agents must inspect the staged paths and confirm that runtime
data, generated scratch scripts, mailbox exports, local account config, token
files, and continuity files are not staged.

For documentation-only commits or commits whose primary change is documentation,
use this exact commit subject and avoid spending the subject on individual doc
details:

```text
This directory contains all the documents related to how NomadInbox is set up, not necessarily any code file.
```

Agents may add commit body lines, but they should be generic folder-level
submessages rather than detailed prose. Use only the folders that are staged:

```text
docs/: Documentation set updated.
docs/adrs/: Decision records updated.
docs/c4/: Architecture diagrams updated.
docs/governance/: Governance, session state, and closeout docs updated.
docs/processes/: Process catalog updated.
docs/runbooks/: Operational runbooks updated.
docs/service-catalog/: Service catalog updated.
docs/slo/: Reliability docs updated.
api/: API contract docs updated.
schemas/: Agent-facing schemas updated.
prompts/: Agent startup and behavior prompts updated.
```

If a commit changes executable code in `scripts/`, `service/`, `src/`, or
`tests/` as the primary change, use a normal code-oriented commit subject. It is
still acceptable to include the generic folder submessages in the body for the
doc paths that changed alongside the code.

The closeout script creates a timestamped note under:

```text
docs/governance/session-updates/
```

It also appends to:

```text
docs/governance/SESSION_CHANGELOG.md
```
