# C4 Level 2: Containers

```mermaid
flowchart TB
    agent["Agent"]
    cli["PowerShell CLI"]
    api["Future Local API / MCP"]
    core["NomadInbox Core"]
    worker["Optional Sync Worker"]
    tray["System Tray Controller"]
    store["Local Message Store"]
    audit["Action Audit Log"]
    gmail["Gmail API Adapter"]
    graph["Outlook Graph Adapter"]
    desktop["Outlook Desktop Adapter"]

    agent --> cli
    agent -. "future" .-> api
    cli --> core
    api --> core
    tray --> cli
    worker --> core
    core --> store
    core --> audit
    core --> gmail
    core --> graph
    core --> desktop

    classDef coreStyle fill:#f0fdf4,stroke:#16a34a,color:#111827
    classDef providerStyle fill:#fff7ed,stroke:#ea580c,color:#111827
    class cli,api,core,worker,tray,store,audit coreStyle
    class gmail,graph,desktop providerStyle
```

## Containers

| Container | Responsibility |
|---|---|
| CLI | Human/agent command surface |
| Future API/MCP | Agent-native integration target |
| Core | Provider registry, safety rules, schema consistency |
| Optional sync worker | User-session background polling for enabled accounts |
| System tray controller | Small local UI for start/stop/status/settings |
| Store | Local message projection |
| Audit | Local mutation history |
| Providers | Provider-specific auth and mailbox operations |
