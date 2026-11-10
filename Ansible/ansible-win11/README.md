# Windows 11 Ansible patch-first domain join

## Prerequisites
- Linux Ansible controller with `ansible-core`, `pywinrm`, and collections in `requirements.yml`.
- Windows 11 Pro/Enterprise/Education guests (Home cannot join on-prem AD).
- WinRM HTTPS listener with valid, trusted certificate on port 5986; firewall permits controller access.
- A local administrator for pre-domain-join operations; domain join service account with delegated permissions to the target OU.
- Windows Update or WSUS connectivity, domain controller DNS reachability, and accurate time synchronization.
- Use a maintenance window: Windows updates and domain join may reboot the VMs.

## Setup
```bash
python3 -m venv .venv
source .venv/bin/activate
pip install ansible-core pywinrm
ansible-galaxy collection install -r requirements.yml
```

Edit `inventory/hosts.yml` and `group_vars/windows11.yml` to match your environment. Avoid placing passwords in either file. Use Ansible Vault or a secret manager in production.

For a quick test in a secured terminal (shell history and environment exposure are considerations):
```bash
export WIN_LOCAL_USER='Administrator'
read -rs WIN_LOCAL_PASSWORD; export WIN_LOCAL_PASSWORD; echo
export AD_JOIN_USER='CORP\\svc-ansible-join'
read -rs AD_JOIN_PASSWORD; export AD_JOIN_PASSWORD; echo
ansible windows11 -m ansible.windows.win_ping
ansible-playbook playbooks/patch-and-join.yml
```

## Behavior
1. Confirm WinRM connectivity and configuration.
2. Install SecurityUpdates, CriticalUpdates and UpdateRollups with automatic reboot.
3. Scan again and stop if matching updates remain.
4. Check common pending reboot registry markers; stop if pending.
5. Configure AD DNS on active interfaces (review multi-NIC environments).
6. Join AD, reboot if required, verify domain membership.

## Important notes
- Windows Update categories do not guarantee every relevant update (e.g. Defender definitions, drivers, feature updates). Adapt to your patch baseline and validate update policy. Some environments require WSUS approval.
- If a patch install fails or is not applicable, the playbook will stop that host before domain join. A second scan only checks offered updates, not compliance with a separate vulnerability baseline.
- DNS changes can disrupt WinRM or networking; prefer preconfiguring DNS in your Windows template and remove the DNS task when already correct.
- For large fleets, tune `serial` and update/reboot timeouts.
- Domain join credentials are marked `no_log` on the join task. Protect controller logs and secret storage.
- If NTLM is prohibited, configure a suitable approved WinRM authentication method; do not disable certificate validation to make connections work.
