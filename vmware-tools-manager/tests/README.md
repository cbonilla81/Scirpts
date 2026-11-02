# Validation checklist

Run PowerShell parser validation (does not require vCenter):

```powershell
$tokens=$null; $errors=$null
[System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path '.\scripts\Invoke-VMToolsManager.ps1'),[ref]$tokens,[ref]$errors) | Out-Null
if ($errors.Count) { $errors | Format-List; throw 'Parser errors' }
```

Then verify in a nonproduction vCenter:

- Assess with one Windows VM and one Linux VM.
- Verify powered-off VMs are classified Powered Off.
- Verify healthy guest-managed Linux is not upgraded.
- Verify upgrade mode without approval file fails safely.
- Verify dry-run never invokes Update-Tools.
- Verify execution only targets exact approved names.
- Reassess after a single test VM upgrade.
- Verify the standalone HTML works without Internet access and exports filtered CSV.
