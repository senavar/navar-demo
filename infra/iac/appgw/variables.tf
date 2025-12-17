
variable "resource_group_name" {
  type        = string
  description = "Resource group for the Application Gateway"
}

variable "location" {
  type        = string
  description = "Azure region"
}

variable "vnet_name" {
  type        = string
  description = "Name of the virtual network containing the App Gateway subnet"
}

variable "appgw_subnet_id" {
  type        = string
  description = "ID of the dedicated subnet for Application Gateway"
}

variable "environment" {
  type        = string
  description = "Deployment environment (e.g., dev, prod)"
}

variable "tags" {
  type        = map(string)
  description = "Common resource tags"
  default     = {}
}

variable "node_resource_group" {
  type        = string
  description = "The node resource group of the AKS cluster"
}

variable "probe_path" {
  type        = string
  description = "HTTP path used by the Application Gateway health probe to validate managed NGINX ingress availability. Typically /healthz or /."
  default     = "/healthz"
}

variable "frontend_hosts" {
  type        = list(string)
  description = "Primary host (FQDN) served by the ingress; used as Host header in App Gateway health probe so NGINX returns 200 instead of default backend/404."
  default     = ["birthday.losnavar.com", "*.birthday.losnavar.com"]
}

variable "key_vault_id" {
  type        = string
  description = "Resource ID of the Key Vault storing the TLS certificate secret."
}

variable "appgw_uami_id" {
  type        = string
  description = "Resource ID of the user-assigned managed identity for Application Gateway."
}

variable "certificate_secret_name" {
  type        = string
  description = "Name of the Key Vault secret containing the TLS certificate."
  default     = "APP-TLS-CERT"
}
