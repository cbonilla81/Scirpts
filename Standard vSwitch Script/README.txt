### Explanation:
1. **vSwitch Creation**:
   - The script checks if the `vSwitchBmc` already exists on each ESXi host. If not, it creates the vSwitch with 128 ports and an MTU of 1500.

2. **Port Group Creation**:
   - The script checks if the `host-bmc-pg` port group already exists on the vSwitch. If not, it creates the port group.

3. **Error Handling**:
   - If the vSwitch or port group already exists, the script skips creation and logs a message.

4. **Connection Management**:
   - The script connects to the vCenter Server at the beginning and disconnects at the end.

### Usage:

1. Save the script as standardvswitch.ps1.
2. Run the script in PowerShell.
3. Enter the vCenter Server hostname/IP and credentials when prompted.
4. The script will create the `vSwitchBmc` and `host-bmc-pg` on all ESXi hosts managed by the vCenter Server.