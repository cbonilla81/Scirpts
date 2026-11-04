locals {
  machines = {
    for i in range(var.vm_count) :
    format("%s-%02d", var.name_prefix, i + 1) => var.vm_id_start + i
  }
}
resource "proxmox_virtual_environment_vm" "windows11" {
  for_each    = local.machines
  name        = each.key
  vm_id       = each.value
  node_name   = var.node_name
  description = "Windows 11 | Terraform-managed | AD join via separate PowerShell stage"
  tags        = ["terraform", "windows11"]

  clone {
    vm_id     = var.template_vm_id
    node_name = var.template_node_name
    full      = true
  }
  cpu {
    cores = var.cpu_cores
  }
  memory {
    dedicated = var.memory_mb
  }
  agent {
    enabled = var.enable_guest_agent
  }
  started = true
}
