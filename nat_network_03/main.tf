terraform {
  required_version = ">= 1.9.5"
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "~> 0.7.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.1.0"
    }
  }
}

provider "libvirt" {
  uri = "qemu:///system"
}

provider "local" {}

# Create the directory for the pool with correct permissions
resource "null_resource" "create_pool_directory" {
  provisioner "local-exec" {
    command = "sudo mkdir -p /mnt/lv_data/organized_storage/volumes/volumetmp_03 && sudo chown -R libvirt-qemu:kvm /mnt/lv_data/organized_storage/volumes/volumetmp_03"
  }
}

# Define and create the pool using virsh commands
resource "null_resource" "create_and_start_pool" {
  provisioner "local-exec" {
    command = <<EOT
      sudo virsh pool-define-as volumetmp_03 dir --target /mnt/lv_data/organized_storage/volumes/volumetmp_03 && \
      sudo virsh pool-start volumetmp_03 && \
      sudo virsh pool-autostart volumetmp_03
    EOT
  }
  depends_on = [null_resource.create_pool_directory]
}

# Network Configuration for VMs
resource "libvirt_network" "okd_network" {
  name      = "okd_network"
  mode      = "nat"
  autostart = true
  addresses = ["10.17.4.0/24"]
}

# Define Fedora CoreOS base image
resource "libvirt_volume" "fcos_base" {
  name   = "fcos_base"
  pool   = "volumetmp_03"
  source = "https://builds.coreos.fedoraproject.org/prod/streams/stable/builds/34.20210626.3.0/x86_64/fedora-coreos-34.20210626.3.0-qemu.x86_64.qcow2.xz"
  format = "qcow2"

  depends_on = [null_resource.create_and_start_pool]
}

# Define Ignition configs for bootstrap, master, and worker nodes
resource "libvirt_ignition" "bootstrap_ignition" {
  name    = "bootstrap.ign"
  content = file("${path.module}/okd-install/bootstrap.ign")
}

resource "libvirt_ignition" "master_ignition" {
  name    = "master.ign"
  content = file("${path.module}/okd-install/master.ign")
}

resource "libvirt_ignition" "worker_ignition" {
  name    = "worker.ign"
  content = file("${path.module}/okd-install/worker.ign")
}

# Define the bootstrap node
resource "libvirt_domain" "bootstrap" {
  name   = "bootstrap"
  memory = "8192"
  vcpu   = 4

  cloudinit = libvirt_ignition.bootstrap_ignition.id

  network_interface {
    network_name = libvirt_network.okd_network.name
  }

  disk {
    volume_id = libvirt_volume.fcos_base.id
  }
}

# Define the master nodes
resource "libvirt_domain" "master" {
  count  = 3
  name   = "master-${count.index + 1}"
  memory = "16384"
  vcpu   = 4

  cloudinit = libvirt_ignition.master_ignition.id

  network_interface {
    network_name = libvirt_network.okd_network.name
  }

  disk {
    volume_id = libvirt_volume.fcos_base.id
  }
}

# Define the worker nodes
resource "libvirt_domain" "worker" {
  count  = 3
  name   = "worker-${count.index + 1}"
  memory = "8192"
  vcpu   = 4

  cloudinit = libvirt_ignition.worker_ignition.id

  network_interface {
    network_name = libvirt_network.okd_network.name
  }

  disk {
    volume_id = libvirt_volume.fcos_base.id
  }
}

# Output the IP addresses of the nodes
output "ip_addresses" {
  value = {
    bootstrap = libvirt_domain.bootstrap.network_interface.0.addresses[0]
    master1   = libvirt_domain.master[0].network_interface.0.addresses[0]
    master2   = libvirt_domain.master[1].network_interface.0.addresses[0]
    master3   = libvirt_domain.master[2].network_interface.0.addresses[0]
    worker1   = libvirt_domain.worker[0].network_interface.0.addresses[0]
    worker2   = libvirt_domain.worker[1].network_interface.0.addresses[0]
    worker3   = libvirt_domain.worker[2].network_interface.0.addresses[0]
  }
}
