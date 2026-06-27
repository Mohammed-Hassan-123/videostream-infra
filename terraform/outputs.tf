output "k3s_master_ip" {
  description = "k3s master node IP"
  value       = module.k3s_master.vm_ip
}

output "k3s_worker1_ip" {
  description = "k3s worker1 node IP"
  value       = module.k3s_worker1.vm_ip
}

output "k3s_worker2_ip" {
  description = "k3s worker2 node IP"
  value       = module.k3s_worker2.vm_ip
}
