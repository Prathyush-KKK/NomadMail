# C4 Level 1: System Context

```mermaid
flowchart LR
    user["User / Operator"]
    agent["Codex or Local Agent"]
    nomad["NomadInbox"]
    gmail["Gmail / Google Workspace"]
    graph["Outlook Web / Microsoft Graph"]
    desktop["Outlook Desktop"]

    user -->|"Prompts and approvals"| agent
    agent -->|"MCP tools / local HTTP / CLI JSON"| nomad
    nomad -->|"Gmail REST API"| gmail
    nomad -->|"Graph Mail API"| graph
    nomad -->|"COM automation"| desktop

    classDef system fill:#ecfeff,stroke:#0891b2,color:#111827
    classDef external fill:#f8fafc,stroke:#64748b,color:#111827
    class nomad system
    class user,agent,gmail,graph,desktop external
```

## Scope

NomadInbox provides a safe mailbox operations layer for agents. It does not host email and does not replace provider security/authentication.
