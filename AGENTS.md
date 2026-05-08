# NomadInbox Agent Bootstrap

This repository is a local-first mailbox workspace. NomadInbox is the local workspace and NomadMail is the callable agent service.

If you are an AI agent opened in this workspace, start here:

1. Read `README.md`.
2. Load `prompts/nomadmail-startup.system.md`.
3. Read `docs/governance/WORKSPACE_STATE.md`.
4. Read `docs/runbooks/agent-user-flow.md`.
5. Fetch the cross-chat handoff prompt:

```powershell
node .\service\nomadmail-service.mjs cross-chat-handoff
```

If you are not already inside the workspace, first try the user environment variable registered by the Windows helper:

```powershell
$nomadInboxHome = [Environment]::GetEnvironmentVariable("NOMADINBOX_HOME", "User")
if (-not $nomadInboxHome) { $nomadInboxHome = $env:NOMADINBOX_HOME }
cd $nomadInboxHome
node .\service\nomadmail-service.mjs cross-chat-handoff
```

If the tray-owned HTTP service is running, use:

```powershell
Invoke-RestMethod http://127.0.0.1:8791/cross-chat-handoff
```

Do not discover accounts, tokens, exports, folders, or mailbox contents until the user approves the exact source and scope.
