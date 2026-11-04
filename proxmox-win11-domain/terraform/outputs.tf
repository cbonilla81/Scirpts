output "vm_inventory" {
  description = "VM name to Proxmox VM ID mapping. IPs are assigned by DHCP and discovered separately."
  value = { for name, vm in proxmox_virtual_environment_vm.windows11 : name => {
    vm_id = vm.vm_id
    node  = vm.node_name
  } }
}
