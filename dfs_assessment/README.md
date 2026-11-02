# DFS Topology Assessment

Read-only Windows PowerShell 5.1+ DFS Namespace and DFS Replication discovery, producing an interactive, self-contained HTML report and JSON inventory.

## Requirements
- Windows PowerShell 5.1 or PowerShell 7 on Windows
- RSAT DFS Management tools (`DFSN`, `DFSR` modules)
- Permissions to read DFS namespaces, replication configuration, and remote DFSR status
- Optional remote CIM/WMI access for richer DFSR health data

## Run
```powershell
.\Invoke-DFSTopologyAssessment.ps1 -OutputDirectory C:\DFSAssessment
# Limit namespace discovery if needed
.\Invoke-DFSTopologyAssessment.ps1 -NamespaceRoots '\\contoso.com\Files','\\contoso.com\Public' -OutputDirectory C:\DFSAssessment
```

Open `DFS-Assessment.html` in a browser. The script does not change DFS configuration. Failed checks are shown as warnings, not silently treated as healthy.

## Coverage and limitations
- Enumerates domain DFS namespace roots, root targets, namespace folders and folder targets.
- Enumerates DFSR groups, members, connections and replicated folder configuration.
- Attempts DFSR backlog checks for enabled connections and replicated folders, using source and destination partners. These checks can be slow and may fail due to access or offline nodes.
- DFSR connection topology is shown independently of namespace target associations. Neither is a guarantee of live replication.
- Backlog count is a point-in-time sample, not a comprehensive replication health metric.
- DFSR replication event logs, full SYSVOL diagnostics, file-level ACL comparison, and Panzura migration readiness require additional checks.
- For very large environments, run off-peak; the script queries multiple remote systems.

###### NOTE ######

Import-Module DFSN
Import-Module DFSR

.\Invoke-DFSTopologyAssessment.ps1 `
    -OutputDirectory "C:\DFSAssessment"
