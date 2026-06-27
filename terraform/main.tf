module "k3s_master" {
  source    = "./modules/vm"
  node_name = var.node_name
  vm_id     = 112
  name      = "k3s-master"
  username  = "k3smaster"
  password  = var.vm_password
  ip        = "192.168.100.35/24"
  gateway   = var.gateway
  ssh_keys  = var.ssh_keys
}

module "k3s_worker1" {
  source    = "./modules/vm"
  node_name = var.node_name
  vm_id     = 113
  name      = "k3s-worker1"
  username  = "k3sworker1"
  password  = var.vm_password
  ip        = "192.168.100.36/24"
  gateway   = var.gateway
  ssh_keys  = var.ssh_keys
}

module "k3s_worker2" {
  source    = "./modules/vm"
  node_name = var.node_name
  vm_id     = 114
  name      = "k3s-worker2"
  username  = "k3sworker2"
  password  = var.vm_password
  ip        = "192.168.100.37/24"
  gateway   = var.gateway
  ssh_keys  = var.ssh_keys
}
