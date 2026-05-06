# Testing Handoff For AI Agents

This handoff is for another AI agent validating NomadInbox / NomadMail from the current workspace or from a brand new clone on another system.

The goal is to test the complete application path with varied user scenarios, validate the outputs, and produce an input-output-observation report that can be compared across agents and machines.

## Safety Boundary

Default tests are synthetic and read-only. They must not touch live mailbox content.

Live mailbox validation is allowed only after the user approves the exact source and scope. Even then, the validating agent must not:

- send mail
- delete or trash mail
- move or archive mail
- mark mail read/unread
- save attachment bytes
- enable full body storage
- enable auto sync
- print private email subject/body content in the final report unless the user explicitly asks

Runtime data, account config, token files, message stores, and scratch outputs must stay ignored by git.

## Current Workspace Test Plan

Run from the repository root.

```powershell
cd C:\Users\prat\Documents\osm\NomadInbox
```

Required context reads:

```powershell
node .\service\nomadmail-service.mjs system-prompt
node .\service\nomadmail-service.mjs workspace-state
node .\service\nomadmail-service.mjs agent-user-flow
node .\service\nomadmail-service.mjs agent-guide
```

Core validation:

```powershell
node --check .\service\nomadmail-service.mjs
.\scripts\validate.ps1
.\tests\agent-user-flow.ps1
.\tests\smoke.ps1
git diff --check
```

Expected outputs:

- `validate.ps1`: JSON `status=ok`
- `agent-user-flow.ps1`: JSON `status=ok`, eight scenarios `status=ok`
- `smoke.ps1`: JSON `status=ok`
- `git diff --check`: no whitespace errors

## Current Workspace Validation Snapshot

Validated from `C:\Users\prat\Documents\osm\NomadInbox` on
`2026-05-07T01:40:57+05:30`.

| Scenario | Input | Observed Output | Observation |
|---|---|---|---|
| Repository contract validation | `.\scripts\validate.ps1` | JSON `status=ok`; no missing required files, forbidden tracked runtime files, parse errors, missing tray markers, or forbidden tray markers. | Pass. Required handoff files and new-clone test are now part of the validated repo contract. |
| Service syntax | `node --check .\service\nomadmail-service.mjs` | Exit code `0`. | Pass. Node service parses cleanly. |
| Synthetic complete user flow | `.\tests\agent-user-flow.ps1` | JSON `status=ok`; eight scenarios returned `status=ok`; temp HTTP health, `/agent-user-flow`, archive search, message-actions, and latest diagnostic all passed. | Pass. Validates first prompt, source approval, first import, tray wording, daily choices, latest freshness, broad range report naming, and action confirmation wording without live mailbox access. |
| Current workspace bootstrap/new-clone harness | `.\tests\new-clone.ps1` | JSON `status=ok`; account config existed in this workspace; `accountCount=3`, `enabledCount=1`; synthetic EML import/search and HTTP surfaces passed; Windows helper dry bootstrap passed. | Pass for current workspace mode. Do not use this result as proof of a clean clone because this checkout intentionally has ignored local account config. |
| Clean-clone simulation from current working tree | Temporary git repo copied from tracked plus untracked non-ignored files, then `.\tests\new-clone.ps1 -ExpectedCleanClone` | JSON `status=ok`; `accountsConfigExists=false`, `repoDataDirExists=false`, `configExists=false`, `enabledCount=0`; git-ignore boundary, synthetic import/search, HTTP health, and Windows helper dry bootstrap all passed. | Pass. This validates the pending working tree as a clean clone without copying local mailbox config or runtime data. A real clone on another machine should still run the same command and submit its JSON report. |
| Broader smoke suite | `.\tests\smoke.ps1` | JSON `status=ok`; covered doctor, providers, accounts, helper install, tray status, sync account, service/backup/import status, sample/import, locale parsing, self-test, latest, message actions, user flow, guide, startup prompt, workspace state, and installer package. | Pass. Main tool/script surfaces are callable with synthetic or safe local state. |
| Whitespace check | `git diff --check` | Exit code `0`; Git printed line-ending normalization warnings only. | Pass. No whitespace errors in the working diff. |

The clean-state mode has been simulated from the current working tree. Run the
same clean-state command in a real fresh clone on another machine before release:

```powershell
.\tests\new-clone.ps1 -ExpectedCleanClone -OutputPath runtime\agent-scratch\new-clone-validation.json
```

## Main Functionality Coverage

| Area | What To Test | Default Command Or Surface | Expected Output |
|---|---|---|---|
| Context-aware startup | Startup prompt, workspace state, agent-user-flow, agent-guide | `node service/nomadmail-service.mjs system-prompt`, `workspace-state`, `agent-user-flow`, `agent-guide` | All return `status=ok`; guide embeds user flow; prompt tells agent what first response must show. |
| Tool discovery | MCP tool registry | `node service/nomadmail-service.mjs tools` | Includes startup, workspace state, agent user flow, search, latest, message actions, sync, import, backup/status tools. |
| HTTP service | Local loopback service | `node service/nomadmail-service.mjs http --port <port>` then `GET /health` | Health returns `status=ok`; service binds to `127.0.0.1`. |
| PowerShell CLI | Setup, doctor, providers, accounts, status | `scripts/nomad-inbox.ps1 setup`, `doctor`, `providers list`, `accounts list` | JSON outputs return `status=ok`; providers include Gmail API, Outlook Graph, Outlook Desktop. |
| Archive import | Dry-run and write read-only import | `import eml --dry-run`, then `import eml` against generated EML | Dry-run reports one message; import writes one `actionable=false` archive message. |
| Search | Search live/archive store | `GET /messages?query=<term>&limit=5` | JSON `status=ok`; synthetic test returns at least one archive result. |
| Message actions | Action guide for archive and live messages | `GET /message-actions?id=<id>` | Archive is non-actionable; live messages expose draft-first action guidance when supported. |
| Latest email freshness | Latest-email path | `POST /messages/latest` | With live approval, syncs first. Without live sync, preserves freshness rule and does not present stale data as definite latest. |
| Tray | Windows compiled tray status/start | `scripts/nomad-inbox.ps1 tray status`, `tray start` | Tray status is JSON; start tells user NomadMail is available from system tray. |
| Windows helper | Helper install without mail access | `install windows-helper --data-dir <temp> --install-root <temp>` | Initializes helper/status paths; does not read mail or enable auto sync. |
| Runtime privacy | Git ignore protections | `git check-ignore -v data/messages.jsonl data/provider-raw.jsonl config/accounts.json runtime/agent-scratch` | All paths are ignored. |
| Backup docs | Runtime backup/restore guidance | `docs/runbooks/runtime-backup-restore.md` | Explains what to include/exclude and says first-class export/restore CLI is not implemented yet. |
| Release/package smoke | Versioned package path | `tests/smoke.ps1` includes installer package check | Package is generated in ignored output during smoke; runtime data is excluded. |

## Synthetic Scenario Test

Run:

```powershell
.\tests\agent-user-flow.ps1
```

This test validates:

- first prompt in fresh workspace
- source and scope approval
- first sync/import
- service and tray setup wording
- daily mail query choices
- latest email freshness
- broad digest/range report output
- mail action follow-up
- archive read-only action boundary
- `nomadmail_get_agent_user_flow`
- HTTP `/agent-user-flow`
- guide embedding
- latest diagnostic freshness rule

Use [Agent User Flow Test Matrix](agent-user-flow-test-matrix.md) for exact scenario inputs and outputs.

## Approved Live Workspace Test

Only run this section after the user approves the mailbox source and scope.

Example for the current Windows Outlook Desktop scope:

```powershell
.\scripts\nomad-inbox.ps1 accounts list
.\scripts\nomad-inbox.ps1 tray start
.\scripts\nomad-inbox.ps1 sync once --account-id desktop-outlook
Invoke-RestMethod http://127.0.0.1:8791/health
Invoke-RestMethod http://127.0.0.1:8791/agent-user-flow
Invoke-RestMethod http://127.0.0.1:8791/agent-guide
Invoke-RestMethod "http://127.0.0.1:8791/messages?query=&includeLive=true&includeArchive=true&limit=5"
Invoke-RestMethod -Method Post http://127.0.0.1:8791/messages/latest -Body '{"accountId":"desktop-outlook","syncFirst":true,"requireContent":true}' -ContentType "application/json"
```

Expected observations:

- tray starts or is already running
- HTTP health is `ok`
- worker can remain `stopped` unless auto sync was explicitly enabled
- one-shot sync returns `status=ok`
- latest email response has `syncFirst=true`, `contentAvailable=true`, and provider `outlook-desktop`
- final report redacts email subject/body unless the user asked to see it

## Brand New Clone Test Plan

On a new machine:

```powershell
git clone https://github.com/Prathyush-KKK/Nomad-Inbox
cd Nomad-Inbox
.\tests\new-clone.ps1 -ExpectedCleanClone -OutputPath runtime\agent-scratch\new-clone-validation.json
```

Expected output:

- JSON `status=ok`
- no local `config/accounts.json` before setup
- account templates are present but all disabled
- required files exist
- tool registry includes the context/user-flow/search/latest/action/import tools
- synthetic EML import/search succeeds in a temp data dir
- HTTP `/health`, `/agent-user-flow`, `/messages`, and `/message-actions` work on a random local port
- Windows helper install works on Windows without reading mail
- non-Windows systems return a clear unsupported-platform boundary for Windows helper/tray/Outlook Desktop

Optional full smoke after the new clone baseline:

```powershell
.\tests\new-clone.ps1 -ExpectedCleanClone -IncludeSmoke -OutputPath runtime\agent-scratch\new-clone-validation-with-smoke.json
```

## Required Agent Report Format

Every validating agent should produce a concise report with this structure:

```json
{
  "agent": "<agent name/session>",
  "testedAtLocal": "<local timestamp and zone>",
  "workspace": "<repo path>",
  "git": {
    "branch": "<branch>",
    "head": "<short sha>",
    "dirty": true
  },
  "testMode": "synthetic-current-workspace | approved-live-current-workspace | new-clone",
  "approvedLiveScope": "<none or provider/account/folder/range>",
  "commandsRun": [
    {
      "command": "<command or endpoint>",
      "input": "<important input only>",
      "outputSummary": "<status/counts/key fields>",
      "status": "ok | failed | skipped"
    }
  ],
  "scenarioResults": [
    {
      "scenario": "<scenario name>",
      "input": "<user/tool/script input>",
      "expectedOutput": "<expected user/system output>",
      "observedOutput": "<observed status/counts/key fields>",
      "observation": "<pass/fail note>"
    }
  ],
  "privacyCheck": {
    "runtimeDataIgnored": true,
    "mailContentRedactedInFinalReport": true,
    "mutatingActionsPerformed": false
  },
  "blockers": [],
  "recommendedFixes": []
}
```

Do not paste raw health JSON, message IDs, private subjects, private bodies, token values, or account secrets into the user-facing report unless explicitly requested.

## Comparison Criteria

When comparing outputs from multiple agents or systems, treat these as required:

- startup/system prompt, workspace state, and user-flow retrieval must work
- synthetic archive import and search must work without live mail
- daily-mail choices must be present
- latest-email path must enforce freshness
- archive messages must stay non-actionable
- live action guidance must be draft-first and delete must require double confirmation
- runtime data and account config must stay ignored by git
- new clones must start with no enabled accounts and no copied mailbox data

Any difference should be reported as one of:

- product bug
- documentation drift
- environment prerequisite missing
- expected platform boundary
- user approval required
