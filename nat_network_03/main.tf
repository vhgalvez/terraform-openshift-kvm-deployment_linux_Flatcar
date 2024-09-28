terraform {
  required_version = ">= 1.9.5"
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "0.8.0"
    }
  }
}

provider "libvirt" {
  uri = "qemu:///system"
}

# Define a storage pool
resource "libvirt_pool" "volumetmp_03" {
  name = "volumetmp_03"
  type = "dir"
  path = "/mnt/lv_data/organized_storage/volumes/volumetmp_03"

  lifecycle {
    create_before_destroy = true
  }
}

# Define individual Ignition resources
locals {
  ignition_files = {
    "bootstrap" = file("/mnt/lv_data/organized_storage/volumes/volumetmp_03/bootstrap.ign")
    "master1"   = file("/mnt/lv_data/organized_storage/volumes/volumetmp_03/master1.ign")
    "master2"   = file("/mnt/lv_data/organized_storage/volumes/volumetmp_03/master2.ign")
    "master3"   = file("/mnt/lv_data/organized_storage/volumes/volumetmp_03/master3.ign")
    "worker1"   = file("/mnt/lv_data/organized_storage/volumes/volumetmp_03/worker1.ign")
    "worker2"   = file("/mnt/lv_data/organized_storage/volumes/volumetmp_03/worker2.ign")
    "worker3"   = file("/mnt/lv_data/organized_storage/volumes/volumetmp_03/worker3.ign")
  }
}

resource "libvirt_ignition" "ignitions" {
  for_each = local.ignition_files

  name    = "${each.key}.ign"
  pool    = libvirt_pool.volumetmp_03.name
  content = each.value
}

# Create a base volume for Fedora CoreOS
resource "libvirt_volume" "fcos_base" {
  name   = "fcos_base.qcow2"
  pool   = libvirt_pool.volumetmp_03.name
  source = var.coreos_image
  format = "qcow2"
}

# Create individual node volumes based on the base image
resource "libvirt_volume" "okd_volumes" {
  for_each = var.vm_definitions
  name     = "${each.key}.qcow2"
  pool     = libvirt_pool.volumetmp_03.name
  size     = each.value.disk_size * 1048576  # Convert MB to bytes
  base_volume_id = libvirt_volume.fcos_base.id
}

# Define VMs with network and disk attachments
resource "libvirt_domain" "nodes" {
  for_each = var.vm_definitions
  name     = "okd-${each.key}"
  memory   = each.value.memory
  vcpu     = each.value.cpus

  # Assign the correct Ignition file to cloudinit based on node type
  cloudinit = libvirt_ignition.ignitions[each.key].id

  network_interface {
    network_name = "kube_network_02"
  }

  disk {
    volume_id = libvirt_volume.okd_volumes[each.key].id
  }
}

# Output node IP addresses
output "node_ips" {
  value = { for node in libvirt_domain.nodes : node.name => node.network_interface[0].addresses[0] }
}
