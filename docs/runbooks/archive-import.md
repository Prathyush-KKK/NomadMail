# Archive Import Runbook

## Purpose

Import historical mail exports into NomadInbox as read-only context. This enriches search and summarization without enabling unsafe mailbox actions against archived messages.

## Supported Bootstrap Formats

| Format | Command | Notes |
|---|---|---|
| EML file/folder | `import eml` | Good for Outlook-exported folders or converted mail |
| MBOX | `import mbox` | Good for Gmail Takeout |
| NomadInbox JSONL | `import jsonl` | Good for re-importing prior normalized snapshots |

PST and MSG import are planned. For now, export or convert those messages to EML, or use the live Outlook Desktop/Graph provider.

## Dry Run

```powershell
.\scripts\nomad-inbox.ps1 import eml --path .\mail-export --source outlook-export --dry-run
```

Expected result:

- JSON status is `dryRun`.
- No archive records are written.
- The response still reports how many messages would be imported.

## Import Gmail Takeout

```powershell
.\scripts\nomad-inbox.ps1 import mbox --path .\takeout\Mail.mbox --source gmail-takeout
```

## Import EML Folder

```powershell
.\scripts\nomad-inbox.ps1 import eml --path .\mail-export --source outlook-export
```

## Include Full Bodies

```powershell
.\scripts\nomad-inbox.ps1 import mbox --path .\takeout\Mail.mbox --source gmail-takeout --include-bodies
```

Use `--include-bodies` only when the user explicitly wants full body storage. The default keeps metadata, snippets, headers, and a searchable projection.

## Status

```powershell
.\scripts\nomad-inbox.ps1 import status
.\scripts\nomad-inbox.ps1 backup status
```

`backup status` reports:

- Live synced message count.
- Archive imported message count.
- Total backed-up context.
- User-facing prompts for syncing or importing more mail.

## Safety

- Archive imported messages are `actionable=false`.
- Archive imported messages have no reply/move/delete/mark-read capabilities.
- Runtime import data stays under ignored `data/`.
- Export files such as `.mbox`, `.eml`, `.pst`, and `.msg` are ignored by git.
