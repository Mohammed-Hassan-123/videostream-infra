variable "pm_api_token" {
  description = "Proxmox API token"
  sensitive   = true
}

variable "pm_ssh_username" {
  description = "Proxmox SSH username"
  sensitive   = true
}

variable "pm_ssh_password" {
  description = "Proxmox SSH password"
  sensitive   = true
}

variable "node_name" {
  description = "Proxmox node name"
}

variable "gateway" {
  description = "Network gateway"
}

variable "vm_password" {
  description = "Default VM user password"
  sensitive   = true
}

variable "ssh_keys" {
  description = "List of SSH public keys to inject into VMs"
  type        = list(string)
}
