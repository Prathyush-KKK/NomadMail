# Release And Installer Packaging

## Purpose

Build a versioned Windows release package that users can unzip and install
without copying local runtime data into the artifact.

## Version Source

The app version lives in the root `VERSION` file. NomadMail health responses and
release packages read from the same file.

Use semantic versions:

```text
0.1.0
0.1.0-beta.1
```

## Build A Local Test Package

Use this while the working tree still has uncommitted changes:

```powershell
.\scripts\build-windows-installer.ps1 -AllowDirty
```

Expected result:

- `dist\NomadInbox-<version>-windows.zip`
- `dist\NomadInbox-<version>-windows.manifest.json`
- `target\release\NomadInbox-<version>-windows\`

`dist\` and `target\` are ignored by git.

## Build A Publish Candidate

For a real publish candidate, the working tree should be clean and `main` should
match `origin/main`.

```powershell
git status --short --branch
.\scripts\validate.ps1
.\tests\smoke.ps1
.\scripts\build-windows-installer.ps1
```

The packaging script fails by default when the tree is dirty. Pass
`-AllowDirty` only for a local test package.

## What The Package Includes

The package copies files returned by `git ls-files`, adds the required `VERSION`
file, then adds the compiled tray executable and release manifests. This keeps
accidental agent scratch output out of the installer.

Included:

- tracked product source, scripts, schemas, prompts, docs, and API specs
- `VERSION`
- compiled `target\NomadInboxTray\NomadInboxTray.exe`
- generated `install.ps1`
- generated `RELEASE_MANIFEST.json`

Excluded:

- `data/`
- `runtime/`
- `target/` build staging outside the package
- `dist/`
- `.kiro/`
- `config/accounts.json`
- `config/nomad-inbox.ps1`
- `scripts/_*.ps1`
- OAuth secrets, token caches, mail exports, JSONL stores, logs, and databases

## User Install Flow

After unzipping the package, install the Windows helper and optionally start the
tray:

```powershell
.\install.ps1 -StartTray
```

The installer delegates to:

```powershell
.\scripts\nomad-inbox.ps1 install windows-helper --start-tray
```

The helper writes to `%LOCALAPPDATA%\NomadInbox\agent-helper` by default and
records its local status in `status.json`.

## Verify After Install

```powershell
.\scripts\nomad-inbox.ps1 tray status
.\scripts\nomad-inbox.ps1 service status
```

Expected result:

- `tray` is `running` after `-StartTray`
- local HTTP health is `ok` when the tray-owned service is up
- runtime data paths point to the user's ignored local data directory

## Publish Checklist

- `VERSION` has the intended release number.
- `git status --short --branch` is clean and synced with `origin/main`.
- `.\scripts\validate.ps1` passes.
- `.\tests\smoke.ps1` passes.
- `.\scripts\build-windows-installer.ps1` creates the zip and sidecar manifest.
- The sidecar manifest SHA-256 is copied into the GitHub release notes.
- No runtime data, local config, secrets, mail exports, or Kiro scratch files are
  inside the zip.
