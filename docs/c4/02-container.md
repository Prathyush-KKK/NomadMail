# C4 Level 2: Containers

```mermaid
flowchart TB
    agent["Agent"]
    cli["PowerShell CLI"]
    api["Future Local API / MCP"]
    core["NomadInbox Core"]
    store["Local Message Store"]
    audit["Action Audit Log"]
    gmail["Gmail API Adapter"]
    graph["Outlook Graph Adapter"]
    desktop["Outlook Desktop Adapter"]

    agent --> cli
    agent -. "future" .-> api
    cli --> core
    api --> core
    core --> store
    core --> audit
    core --> gmail
    core --> graph
    core --> desktop

    classDef coreStyle fill:#f0fdf4,stroke:#16a34a,color:#111827
    classDef providerStyle fill:#fff7ed,stroke:#ea580c,color:#111827
    class cli,api,core,store,audit coreStyle
    class gmail,graph,desktop providerStyle
```

## Containers

| Container | Responsibility |
|---|---|
| CLI | Human/agent command surface |
| Future API/MCP | Agent-native integration target |
| Core | Provider registry, safety rules, schema consistency |
| Store | Local message projection |
| Audit | Local mutation history |
| Providers | Provider-specific auth and mailbox operations |

