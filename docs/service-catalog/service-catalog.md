# Service Catalog

| Service / Process | Type | Status | Owner | Criticality |
|---|---|---|---|---|
| NomadInbox CLI | Local command surface | Bootstrapped | Local operator | High |
| NomadMail MCP Server | Agent-native stdio service | Bootstrapped | Local operator | High |
| NomadMail HTTP Service | Local REST-style service | Bootstrapped | Local operator | High |
| Windows Agent Helper | Local PowerShell helper install | Bootstrapped | Local operator | Medium |
| NomadInbox Core | Provider registry, safety, schemas | Bootstrapped | Local operator | High |
| Background Sync Worker | Optional user-session polling | Bootstrapped | Local operator | Medium |
| System Tray Controller | Local status/settings UI | Bootstrapped | Local operator | Medium |
| Archive Importer | Read-only historical mail context ingestion | Bootstrapped | Local operator | Medium |
| Backup Status Prompter | Live/archive backup counts and user guidance | Bootstrapped | Local operator | Medium |
| Gmail API Provider | Provider adapter | Bootstrapped sync | Local operator | High |
| Outlook Graph Provider | Provider adapter | Bootstrapped sync | Local operator | High |
| Outlook Desktop Provider | Provider adapter | Bootstrapped sync | Local operator | Medium |
| Local Message Store | Runtime data projection | Bootstrapped | Local operator | High |
| Archive Context Store | Imported mail projection and search index | Bootstrapped | Local operator | Medium |
| Action Audit Log | Mutation audit stream | Bootstrapped | Local operator | High |
