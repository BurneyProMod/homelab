output "control_plane_ip" {
  value = module.k8s_control_plane.vm_ip
}

output "worker_ips" {
  value = [
    module.k8s_worker_01.vm_ip,
    module.k8s_worker_02.vm_ip,
  ]
}
