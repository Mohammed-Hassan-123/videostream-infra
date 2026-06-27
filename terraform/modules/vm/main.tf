terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.46.4"
    }
  }
}

resource "proxmox_virtual_environment_vm" "vm" {
  name            = var.name
  node_name       = var.node_name
  vm_id           = var.vm_id
  stop_on_destroy = true

  clone {
    vm_id = 9001
    full  = true
  }

  agent { enabled = true }

  cpu {
    cores = 2
    type  = "host"
  }

  memory { dedicated = 2048 }

  disk {
    datastore_id = "local-lvm"
    interface    = "scsi0"
    size         = 20
  }

  network_device {
    bridge = "vmbr0"
    model  = "virtio"
  }

  initialization {
    ip_config {
      ipv4 {
        address = var.ip
        gateway = var.gateway
      }
    }
    dns { servers = ["192.168.100.5"] }
    user_account {
      username = var.username
      password = var.password
      keys     = var.ssh_keys
    }
  }
}
