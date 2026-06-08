variable "vm_name" {
  type = string
}

variable "node_name" {
  type = string
}

variable "vm_id" {
  type = number
}

variable "cores" {
  type    = number
  default = 2
}

variable "memory" {
  type    = number
  default = 4096
}

variable "disk_size" {
  type    = number
  default = 32
}

variable "ip_address" {
  type = string
}

variable "gateway" {
  type = string
}

variable "ssh_public_key" {
  type = string
}

variable "tags" {
  type    = list(string)
  default = []
}
