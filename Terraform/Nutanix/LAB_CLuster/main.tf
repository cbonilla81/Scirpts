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

resource "nutanix_virtual_machine" "vm" {
  name                 = "myVm"
  cluster_uuid         = data.nutanix_clusters.clusters.entities.0.metadata.uuid
  num_vcpus_per_socket = 1
  num_sockets          = 1
  memory_size_mib      = 186

  disk_list {
    disk_size_bytes = 68157440
    disk_size_mib   = 65

    storage_config {
      storage_container_reference {
        kind = "storage_container"
        uuid = "2bbe67bc-fd14-4637-8de1-6379257f4219"
      }
    }
  }
}
