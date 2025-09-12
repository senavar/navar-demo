variable "environment" {
  type    = string
  default = "prod"
}

variable "location" {
  type    = string
  default = "canadacentral"
}

variable "acr_sku" {
  type    = string
  default = "Premium"
}

variable "aks_system_node_count" {
  type    = number
  default = 2
}

variable "aks_user_node_count" {
  type    = number
  default = 3
}

variable "mongodb_vm_size" {
  type    = string
  default = "Standard_D16s_v3"
}

variable "admin_source_ips" {
  type    = list(string)
  default = []
}

variable "api_server_authorized_ip_ranges" {
  type    = list(string)
  default = []
}

variable "vnet_address_space" {
  type    = list(string)
  default = ["10.20.0.0/20"]
}

variable "subnet_cidrs" {
  type = object({
    aks_system = string
    aks_user   = string
    appgw      = string
    data       = string
    ops        = string
  })
}

variable "aks_system_vm_size" {
  type    = string
  default = "Standard_D4s_v4"
}

variable "aks_user_vm_size" {
  type    = string
  default = "Standard_D8s_v4"
}

variable "mongodb_admin_password" {
  type      = string
  sensitive = true
  default   = "" # supply via tfvars or environment; don't commit real secret
}

variable "linux_image" {
  type = object({
    publisher = string
    offer     = string
    sku       = string
    version   = string
  })
  default = {
    publisher : "cognosys"
    offer : "ubuntu-18-04-lts-free"
    sku : "hardened-ubuntu-18-04-lts-freesku"
    version : "latest"
  }
}

variable "app_service_account_namespace" {
  type        = string
  description = "Namespace for the application."
  default     = "navarapp"
}

variable "wi_service_account_name" {
  type        = string
  description = "Name of the workload identity service account for application"
  default     = "birthdayapp-sa"
}

variable "arc_github_config_url" {
  type        = string
  description = "URL for Github repo what will use ARC runners"
  default     = "https://github.com/senavar/navar-demo"
}
