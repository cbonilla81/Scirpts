terraform {
    required_providers {
        nutanix = {
            source = "nutanix/nutanix"
            version = "1.3.0"
        }
    }
}

provider "nutanix" {
    username     = var.nutanix_username
    password     = var.nutanix_password
    endpoint     = var.nutanix_endpoint
    insecure     = true
    wait_timeout = 60
}

data "nutanix_clusters" "clusters" {}

output "cluster" {
    value = data.nutanix_clusters.clusters.entities.0.metadata.uuid
}

resource "nutanix_subnet" "LAB Network" {
    cluster_uuid = "${data.nutanix_clusters.clusters.entities.0.metadata.uuid}"
    name                         = var.nutanix_network_name
    vlan_id                      = var.nutanix_vlan_number
    subnet_type                  = "VLAN"
    prefix_length                = 25
    default_gateway_ip           = var.nutanix_gateway_ip
    subnet_ip                    = var.nutanix_subnet_ip
    dhcp_domain_name_server_list = var.nutanix_dns_server_name
    dhcp_domain_search_list      = "nutanixlab.local"
}