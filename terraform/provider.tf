terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.46.4"
    }
  }
}

provider "proxmox" {
  endpoint  = "https://192.168.100.9:8006/"
  api_token = var.pm_api_token
  insecure  = true

  ssh {
    agent    = false
    username = var.pm_ssh_username
    password = var.pm_ssh_password
  }
}
