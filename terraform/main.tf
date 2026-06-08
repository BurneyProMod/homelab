terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.98"
    }
  }
}

provider "proxmox" {
  endpoint  = var.proxmox_endpoint
  api_token = var.proxmox_api_token
  insecure  = var.proxmox_tls_insecure

  ssh {
    agent    = true
    username = "root"
  }
}

module "k8s_control_plane" {
  source         = "./modules/vm"
  vm_name        = "k8s-cp-01"
  node_name      = "proxmox1"
  vm_id          = 101
  cores          = 5
  memory         = 12288
  disk_size      = 60
  ip_address     = "192.168.1.60/24"
  gateway        = var.vm_gateway
  ssh_public_key = var.ssh_public_key
  tags           = ["k8s", "control-plane"]
}

module "k8s_worker_01" {
  source         = "./modules/vm"
  vm_name        = "k8s-worker-01"
  node_name      = "proxmox2"
  vm_id          = 102
  cores          = 6
  memory         = 12288
  disk_size      = 60
  ip_address     = "192.168.1.61/24"
  gateway        = var.vm_gateway
  ssh_public_key = var.ssh_public_key
  tags           = ["k8s", "worker"]
}

module "k8s_worker_02" {
  source         = "./modules/vm"
  vm_name        = "k8s-worker-02"
  node_name      = "proxmox3"
  vm_id          = 103
  cores          = 5
  memory         = 12288
  disk_size      = 60
  ip_address     = "192.168.1.62/24"
  gateway        = var.vm_gateway
  ssh_public_key = var.ssh_public_key
  tags           = ["k8s", "worker"]
}
