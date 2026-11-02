# AD Infrastructure Explorer v0.2

Read-only PowerShell 5.1 Active Directory discovery and self-contained HTML reporting.

## Requirements
- Windows PowerShell 5.1, ActiveDirectory RSAT module, domain connectivity and appropriate read access.
- Replication metadata queries may require additional rights and connectivity.

## Run
```powershell
Import-Module ActiveDirectory
.\Invoke-ADExplorer.ps1 -OutputPath C:\AD-Assessment -IncludeReplication
```

## Outputs
- `AD-Infrastructure.html`: offline dashboard, logical forest hierarchy, replication and site-link visualization, clickable site/DC details, filterable tables, CSV exports.
- `AD-Inventory.json`: machine-readable inventory and collection errors.

## Limitations
- Current forest only. Does not traverse external or trusted forests.
- ICMP is not a comprehensive DC health test; ICMP blocked/failed does not imply the DC is down.
- Replication partner resolution is best effort; DN and FQDN variations may prevent a line being drawn.
- Replication link colors are derived from returned metadata and should not replace `repadmin /replsummary` or detailed AD diagnostics.
- Site links are configuration, not physical connectivity.
- No changes are made to Active Directory.
- Treat reports as sensitive infrastructure information; store securely.
- Run in a test environment before enterprise use. No live AD testing has been performed here.
