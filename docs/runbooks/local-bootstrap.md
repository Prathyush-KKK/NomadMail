# Runbook: Local Bootstrap

## Setup

```powershell
cd C:\Users\prat\Documents\osm\NomadInbox
.\scripts\nomad-inbox.ps1 setup
```

## Health Check

```powershell
.\scripts\nomad-inbox.ps1 doctor
```

Expected:

```json
{
  "status": "ok",
  "service": "NomadInbox"
}
```

## Provider Discovery

```powershell
.\scripts\nomad-inbox.ps1 providers list
```

## Configure A Provider

```powershell
Copy-Item .\config\nomad-inbox.example.ps1 .\config\nomad-inbox.ps1
```

Edit the ignored local config. Do not commit it.

## Validate Repo

```powershell
.\scripts\validate.ps1
```

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Provider is `unconfigured` | Local config is missing provider values | Edit `config/nomad-inbox.ps1` |
| Runtime files appear in git status | Ignore rules missing or path outside expected area | Check `.gitignore` and move runtime files under `data/` |
| CLI cannot import module | Running outside repo or missing files | Run from repo root and validate |

