param(
    [Parameter(Mandatory = $true)]
    [string]$Title,

    [Parameter(Mandatory = $true)]
    [string]$Summary,

    [string]$NextAction = "",

    [string]$Status = "in-progress"
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$statePath = Join-Path $repoRoot "docs\governance\WORKSPACE_STATE.md"
$promptPath = Join-Path $repoRoot "prompts\nomadmail-startup.system.md"
$promptRelativePath = $promptPath.Substring($repoRoot.Length + 1)
$today = Get-Date -Format "yyyy-MM-dd"

$branch = "unknown"
$head = "unknown"
if (Get-Command git -ErrorAction SilentlyContinue) {
    try {
        $branch = (git -C $repoRoot rev-parse --abbrev-ref HEAD 2>$null)
        $head = (git -C $repoRoot rev-parse --short HEAD 2>$null)
    } catch {
    }
}

$next = if ([string]::IsNullOrWhiteSpace($NextAction)) {
    "- Refresh live status at startup and continue from the latest user-approved source/action."
} else {
    "- $NextAction"
}

$template = @'
# NomadInbox Workspace State

Last updated: {{TODAY}}

## Current Summary

NomadInbox is a local-first mailbox visibility and action service. NomadMail is the callable MCP and loopback HTTP facade over the same local runtime.

Current workspace state:

- NomadMail exposes agent guidance, startup system prompt, local message search, message lookup, provider/account discovery, one-shot sync, archive import, service status, and background worker controls.
- The startup system prompt is system-owned at prompts/nomadmail-startup.system.md.
- On Windows, the PowerShell helper initializes ignored runtime state and account config without reading mail or starting auto sync.
- On Windows, the tray controller keeps the local NomadMail HTTP service available at 127.0.0.1:8791 while the tray is running. MCP stdio is still launched by each calling agent.
- Date/time parsing uses the user's locale and time zone, then stores normalized UTC ISO timestamps.
- Runtime data, account config, message stores, action logs, imported mail exports, token files, and scratch diagnostics stay out of GitHub.

Exact live counts, worker status, enabled accounts, and provider health are mutable. Agents must refresh those through nomadmail_get_agent_guide, nomadmail_health_check, HTTP /health, or the PowerShell CLI before making current claims.

## Resume Rules For Agents

When opening this workspace:

1. Read this file first.
2. Load {{PROMPT_RELATIVE_PATH}} or call nomadmail_get_startup_system_prompt.
3. Refresh live status using NomadMail tools or service commands.
4. Report current capabilities, storage boundaries, user locale/time-zone context when time scopes matter, approval-gated actions, Windows helper/tray status when applicable, and the safest next action.
5. Do not read mail, discover credentials, scan exports, enable accounts, start auto sync, store bodies, save attachments, or mutate mail without explicit approval.

## Session State Update Rule

At the end of a meaningful session, update this file through:

    .\scripts\session-closeout.ps1 -Title "Short change title" -Summary "What changed and why"

For state-only updates that do not need a full architecture note:

    .\scripts\update-workspace-state.ps1 -Title "Short state title" -Summary "Current state summary"

The state file should capture durable workspace behavior and follow-ups. It should not include secrets, raw mailbox data, token values, message bodies, or private email contents.

## Latest Session

Title: {{TITLE}}

Status: {{STATUS}}

Summary:

- {{SUMMARY}}

Workspace revision:

- Branch: {{BRANCH}}
- HEAD: {{HEAD}}

## Open Follow-Ups

{{NEXT}}
'@

$content = $template.
    Replace("{{TODAY}}", $today).
    Replace("{{PROMPT_RELATIVE_PATH}}", $promptRelativePath).
    Replace("{{TITLE}}", $Title).
    Replace("{{STATUS}}", $Status).
    Replace("{{SUMMARY}}", $Summary).
    Replace("{{BRANCH}}", $branch).
    Replace("{{HEAD}}", $head).
    Replace("{{NEXT}}", $next)

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($statePath, $content, $utf8NoBom)

[pscustomobject]@{
    status = "ok"
    stateFile = $statePath
    title = $Title
    updatedAt = (Get-Date).ToUniversalTime().ToString("o")
} | ConvertTo-Json -Depth 5
