# Windows 11 golden-template checklist

1. Create a Windows 11 VM (e.g. VMID 9000) in Proxmox VE 9.
2. Configure q35, OVMF/UEFI, EFI disk with Secure Boot as appropriate, TPM 2.0, VirtIO SCSI, VirtIO NIC on the intended bridge, and a 100 GB Windows system disk.
3. Install Windows 11 with valid licensing and sufficient resources; install signed VirtIO drivers, QEMU Guest Agent, Windows updates, and baseline security configuration.
4. Ensure DHCP works, the template is NOT domain-joined, and unique local admin credentials can be provisioned safely. Do not bake shared production secrets into a template.
5. For this sample domain-join workflow, configure a WinRM HTTPS listener with a valid certificate trusted by the Windows controller and matching the address used to connect. Permit TCP 5986 only from the controller. This is an administrator-controlled prerequisite, NOT enabled automatically by Terraform.
6. Check Windows Firewall, DNS resolution, domain-controller connectivity, time synchronization, AD join delegation and OU permissions.
7. Clean temporary files and sensitive artifacts. Run from elevated Command Prompt:
   %WINDIR%\System32\Sysprep\Sysprep.exe /generalize /oobe /shutdown
8. In Proxmox convert the powered-off VM to a template. Do not start the template again. Test with ONE clone before creating 10.
9. Verify per-clone TPM identity and disk encryption behavior. Do not capture BitLocker recovery secrets in the golden image.

## Important first-boot caveat
Sysprep /oobe may leave each clone waiting for interactive OOBE; WinRM may not be reachable until an approved unattended first-boot configuration completes. Supply a separately tested unattend.xml or provisioning process that completes OOBE, creates/rotates local credentials, configures the trusted WinRM HTTPS listener and firewall, and allows remote management. This repository intentionally does not invent passwords or deploy an insecure unattended answer file.

## Storage and migration
A full clone needs sufficient capacity and may require accessible source storage. Cross-node cloning depends on source storage visibility and target storage support. Start with template_node_name = node_name and test before scaling.
