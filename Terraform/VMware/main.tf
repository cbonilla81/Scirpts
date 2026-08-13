provider "vsphere" {
    user        = var.vsphere_user
    password    = var.vsphere_password
    vsphere_server = var.vsphere_server

    allow_unverified_ssl = true
}

data "vsphere_datacenter" "dc" {
    name = "Datacenter1"
}

data "vsphere_datastore" "datastore" {
    name          = "vmContainer1"
    datacenter_id = "${data.vsphere_datacenter.dc.id}"
}

data "vsphere_compute_cluster" "cluster" {
    name          = "Cluster1"
    datacenter_id = "${data.vsphere_datacenter.dc.id}"
}

data "vsphere_network" "network" {
    name          = "LAB Network"
    datacenter_id = "${data.vsphere_datacenter.dc.id}"
}

data "vsphere_resource_pool" "default" {
  name          = format("%s%s", data.vsphere_compute_cluster.cluster.name, "/Resources")
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_host" "host" {
  name          = var.host_name
  datacenter_id = data.vsphere_datacenter.dc.id
}

resource "vsphere_content_library" "publisher_content_library" {
  name            = "publisher Content Library"
  description     = "A publishing content library"
  storage_backing = [data.vsphere_datastore.datastore.id]
}

data "vsphere_content_library" "content_library" {
  name = "publisher Content Library"
}

resource "vsphere_content_library_item" "content_library_item" {
  name         = "Linux CentOS7 Image File"
  description  = "Linux CentOS7 Image File"
  file_url     = "https://s3.amazonaws.com/nutanixobjectdemo/ova/CentOS7.ova"
  library_id   = "${data.vsphere_content_library.content_library.id}"
}

resource "vsphere_virtual_machine" "vmFromRemoteOvf" {
  name                 = "LAB-Terraform-${count.index + 1}"
  count                = "3"
  datacenter_id        = data.vsphere_datacenter.dc.id
  datastore_id         = data.vsphere_datastore.datastore.id
  host_system_id       = data.vsphere_host.host.id
  resource_pool_id     = data.vsphere_resource_pool.default.id

  wait_for_guest_net_timeout = 0
  wait_for_guest_ip_timeout  = 0

  ovf_deploy {
    allow_unverified_ssl_cert = false
    remote_ovf_url            = "https://s3.amazonaws.com/nutanixobjectdemo/ova/CentOS7.ova"
    disk_provisioning         = "thin"
    ip_protocol               = "IPV4"
    ip_allocation_policy      = "STATIC_MANUAL"
    ovf_network_map = {
      "LAB Network" : data.vsphere_network.network.id
      
    }
  }
}

resource "vsphere_virtual_machine" "vmFromRemoteOvfWM" {
  name                 = "LAB-Terraform-WS-${count.index + 1}"
  count                = "4"
  datacenter_id        = data.vsphere_datacenter.dc.id
  datastore_id         = data.vsphere_datastore.datastore.id
  host_system_id       = data.vsphere_host.host.id
  resource_pool_id     = data.vsphere_resource_pool.default.id

  wait_for_guest_net_timeout = 0
  wait_for_guest_ip_timeout  = 0

  ovf_deploy {
    allow_unverified_ssl_cert = false
    remote_ovf_url            = "https://s3.amazonaws.com/nutanixobjectdemo/ova/WinTools-VM-v2.ova"
    disk_provisioning         = "thin"
    ip_protocol               = "IPV4"
    ip_allocation_policy      = "STATIC_MANUAL"
    ovf_network_map = {
      "LAB Network" : data.vsphere_network.network.id
      
    }
  }
}