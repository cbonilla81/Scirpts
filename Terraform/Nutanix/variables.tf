variable  "nutanix_username" {
    type = string
}
variable  "nutanix_password" {
    type = string
} 
variable "nutanix_endpoint" {
    type = string
}
variable "nutanix_network_name" {
    type = string
} 
variable "nutanix_vlan_number" {
    type = string
}
variable "nutanix_gateway_ip" {
    type = string
}
variable "nutanix_subnet_ip" {
    type = string
}
variable "nutanix_dns_server_name" {
    description = "List of DNS server IPs for the Nutanix subnet"
    type        = list(string)
    default     = ["8.8.8.8", "8.8.4.4"] # Replace with your actual DNS server IPs
}