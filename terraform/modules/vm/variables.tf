variable "node_name" {}
variable "vm_id"     {}
variable "name"      {}
variable "username"  {}
variable "password"  { sensitive = true }
variable "ip"        {}
variable "gateway"   {}
variable "ssh_keys"  { type = list(string) }
