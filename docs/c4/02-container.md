# C4 Level 2: Containers

```mermaid
flowchart TB
    agent["Agent"]
    cli["PowerShell CLI"]
    api["NomadMail MCP / HTTP"]
    core["NomadInbox Core"]
    worker["Optional Sync Worker"]
    tray["System Tray Controller"]
    importer["Archive Importer"]
    backup["Backup Status / User Prompts"]
    store["Local Message Store"]
    archive["Archive Context Store"]
    audit["Action Audit Log"]
    gmail["Gmail API Adapter"]
    graph["Outlook Graph Adapter"]
    desktop["Outlook Desktop Adapter"]

    agent --> cli
    agent --> api
    cli --> core
    api --> core
    tray --> cli
    worker --> core
    cli --> importer
    importer --> archive
    core --> store
    core --> backup
    backup --> store
    backup --> archive
    core --> audit
    core --> gmail
    core --> graph
    core --> desktop

    classDef coreStyle fill:#f0fdf4,stroke:#16a34a,color:#111827
    classDef providerStyle fill:#fff7ed,stroke:#ea580c,color:#111827
    class cli,api,core,worker,tray,importer,backup,store,archive,audit coreStyle
    class gmail,graph,desktop providerStyle
```

## Containers

| Container | Responsibility |
|---|---|
| CLI | Human/agent command surface |
| NomadMail MCP / HTTP | Agent-native stdio tools and local REST-style calls |
| Core | Provider registry, safety rules, schema consistency |
| Optional sync worker | User-session background polling for enabled accounts |
| System tray controller | Small local UI for start/stop/status/settings |
| Archive importer | Read-only ingestion of `.eml`, `.mbox`, and message JSONL exports |
| Backup status / prompts | Combines sync/import counts into agent/user guidance |
| Store | Local message projection |
| Archive context store | Read-only imported mail records and disposable search projection |
| Audit | Local mutation history |
| Providers | Provider-specific auth and mailbox operations |
