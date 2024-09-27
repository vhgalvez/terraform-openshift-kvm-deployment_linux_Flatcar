terraform {
  required_version = ">= 1.9.5"
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "~> 0.8.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5.2"
    }
  }
}

provider "libvirt" {
  uri = "qemu:///system"
}

# Definir el pool de almacenamiento para volúmenes
resource "libvirt_pool" "volumetmp_03" {
  name = "volumetmp_03"
  type = "dir"
  path = "/mnt/lv_data/organized_storage/volumes/volumetmp_03"
  # Crear el directorio si no existe
  lifecycle {
    create_before_destroy = true
  }
}

# Definir configuraciones de nodos con URLs directas para archivos Ignition
locals {
  nodes = {
    bootstrap = { size = var.bootstrap_volume_size, url = "http://10.17.3.14/okd/bootstrap.ign" },
    master1   = { size = var.master_volume_size, url = "http://10.17.3.14/okd/master.ign" },
    master2   = { size = var.master_volume_size, url = "http://10.17.3.14/okd/master.ign" },
    master3   = { size = var.master_volume_size, url = "http://10.17.3.14/okd/master.ign" },
    worker1   = { size = var.worker_volume_size, url = "http://10.17.3.14/okd/worker.ign" },
    worker2   = { size = var.worker_volume_size, url = "http://10.17.3.14/okd/worker.ign" },
    worker3   = { size = var.worker_volume_size, url = "http://10.17.3.14/okd/worker.ign" }
  }
}

# Descargar archivos Ignition al disco local antes de crear volúmenes
data "http" "ignition_files" {
  for_each = local.nodes
  url      = each.value.url
}

resource "local_file" "ignition_files" {
  for_each = local.nodes
  content  = data.http.ignition_files[each.key].response_body
  filename = "/tmp/${each.key}.ign"
}

# Crear volúmenes Ignition para los nodos
resource "libvirt_volume" "ignition_volumes" {
  for_each = local.nodes
  name     = "${each.key}-ignition"
  pool     = libvirt_pool.volumetmp_03.name
  source   = local_file.ignition_files[each.key].filename
  format   = "raw"
}

# Definir volumen base para Fedora CoreOS
resource "libvirt_volume" "fcos_base" {
  name   = "fcos_base.qcow2"
  pool   = libvirt_pool.volumetmp_03.name
  source = var.coreos_image
  format = "qcow2"
}

# Crear volúmenes de nodos
resource "libvirt_volume" "okd_volumes" {
  for_each       = local.nodes
  name           = "${each.key}.qcow2"
  pool           = libvirt_pool.volumetmp_03.name
  size           = each.value.size * 1073741824
  base_volume_id = libvirt_volume.fcos_base.id
}

# Definir dominios libvirt para nodos
resource "libvirt_domain" "nodes" {
  for_each = local.nodes
  name     = each.key
  memory   = var.vm_definitions[each.key].memory
  vcpu     = var.vm_definitions[each.key].cpus

  cloudinit = libvirt_volume.ignition_volumes[each.key].id

  network_interface {
    network_name = "nat_network_02"
  }

  disk {
    volume_id = libvirt_volume.okd_volumes[each.key].id
  }
}

# Salida de direcciones IP de los nodos
output "node_ips" {
  value = { for node in libvirt_domain.nodes : node.name => node.network_interface[0].addresses[0] }
}
