variable "node_name" { type = string }
variable "template_vm_id" { type = number }
variable "template_node_name" { type = string }
variable "vm_count" {
  type = number
  default = 10
  validation {
    condition = var.vm_count >= 1 && var.vm_count <= 50
    error_message = "vm_count must be between 1 and 50."
  }
}
variable "vm_id_start" { type = number; default = 2200 }
variable "name_prefix" { type = string; default = "WIN11" }
variable "cpu_cores" { type = number; default = 4 }
variable "memory_mb" { type = number; default = 8192 }
variable "enable_guest_agent" { type = bool; default = true }
