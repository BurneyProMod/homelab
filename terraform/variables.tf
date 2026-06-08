variable "proxmox_endpoint" {
  description = "Proxmox API URL"
  type        = string
}

variable "proxmox_api_token" {
  description = "API token in format terraform@pve!terraform-token=<secret>"
  type        = string
  sensitive   = true
}

variable "ssh_public_key" {
  description = "SSH public key injected into VMs via cloud-init"
  type        = string
}

variable "vm_gateway" {
  description = "Default gateway for VMs"
  type        = string
  default     = "192.168.1.1"
}

variable "proxmox_tls_insecure" {
  description = "Set to true only if you cannot trust the Proxmox CA cert on the machine running Terraform"
  type        = bool
  default     = false
}
