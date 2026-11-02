# Active Directory Explorer v0.3

Read-only AD forest inventory, logical and replication topology diagrams, interactive offline HTML dashboard, JSON and CSV export, plus optional health/security checks.

## Requirements
Windows PowerShell 5.1; RSAT ActiveDirectory module; domain connectivity and read permissions. DNS resolution and UNC access may require network/firewall permissions. For full replication data, appropriate AD replication permissions are required.

## Run
```powershell
Import-Module ActiveDirectory
.\Invoke-ADExplorer.ps1 -OutputPath C:\AD-Assessment -IncludeReplication -IncludeHealth -StaleDays 90
```

Outputs: `AD-Infrastructure.html`, `AD-Inventory.json`. Open HTML locally in Edge or Chrome.

## New in v0.3
- DNS A-record resolution per DC (not full DNS service diagnostics)
- SYSVOL and NETLOGON share accessibility
- Replication error rollup (requires `-IncludeReplication`)
- Default domain password policies
- Selected high-privilege groups and member counts
- Enabled computer accounts with old `lastLogonTimestamp` (approximate, not definitive inactivity)
- Health summary and searchable/exportable result tables

## Limitations and security
This is an inventory and basic assessment, not a complete AD security audit. `lastLogonTimestamp` is replicated with delay. DNS checks only verify name resolution; SMB share checks do not prove DFSR health. Missing/blocked data is not healthy. The forest is discovered from the current AD context and trusted forests are not crawled. Protect reports as sensitive infrastructure information. Run first in a test environment. PowerShell has not been tested against a live AD forest in this delivery.
