variable "environment" {
  description = "Deployment environment identifier (e.g. dev, test, prod)."
  type        = string
}

variable "location" {
  description = "Azure region for deployment."
  type        = string
  default     = "canadacentral"
}

variable "tags" {
  description = "Additional tags applied to resources (baseline tags added automatically)."
  type        = map(string)
  default     = {}
}

variable "vnet_address_space" {
  description = "Address space for the virtual network."
  type        = list(string)
  default     = ["10.30.0.0/16"]
}

variable "subnet_cidrs" {
  description = "CIDR blocks keyed by logical name. Keys: aks_system, aks_user, appgw, data, ops"
  type = object({
    aks_system = string
    aks_user   = string
    appgw      = string
    data       = string
    ops        = string
  })
}

// AKS
variable "aks_kubernetes_version" {
  description = "AKS Kubernetes version (leave blank for default)."
  type        = string
  default     = "1.33.2"
}

variable "aks_system_node_count" {
  description = "Initial node count for system node pool."
  type        = number
  default     = 2
}

variable "aks_user_node_count" {
  description = "Initial node count for user workload node pool."
  type        = number
  default     = 2
}

variable "aks_system_vm_size" {
  description = "VM size for system node pool."
  type        = string
  default     = "Standard_DS2_v2"
}

variable "aks_user_vm_size" {
  description = "VM size for user node pool."
  type        = string
  default     = "Standard_DS3_v2"
}

variable "aks_outbound_type" {
  description = "AKS outbound type."
  type        = string
  default     = "loadBalancer"
}

variable "aks_pod_cidr" {
  description = "Pod CIDR for Azure CNI Overlay (must not overlap node subnet CIDRs)."
  type        = string
  default     = "10.254.0.0/16"
}

variable "enable_web_app_routing" {
  description = "Enable AKS Web App Routing (NGINX ingress) addon."
  type        = bool
  default     = true
}

variable "web_app_routing_zone_name" {
  description = "Private DNS zone name used by AKS Web App Routing addon (must be unique in subscription)."
  type        = string
  default     = "priv.ingress.local"
}

variable "key_vault_sku" {
  description = "Key Vault SKU"
  type        = string
  default     = "Premium"
}

variable "acr_sku" {
  description = "ACR SKU tier."
  type        = string
  default     = "Premium"
}

// MongoDB VM
variable "mongodb_vm_size" {
  description = "Azure VM size for MongoDB."
  type        = string
  default     = "Standard_B2ms"
}

variable "mongodb_admin_username" {
  description = "Admin username for MongoDB VM (Linux)."
  type        = string
  default     = "mongoadmin"
}

variable "mongodb_admin_password" {
  description = "Admin password (or supply ssh_public_key instead)."
  type        = string
  sensitive   = true
  default     = ""
}

variable "ssh_public_key" {
  description = "Optional SSH public key for VM access (overrides password if provided)."
  type        = string
  default     = ""
}

variable "mongodb_disk_size_gb" {
  description = "OS disk size for MongoDB VM."
  type        = number
  default     = 128
}

variable "linux_image" {
  description = "Linux image descriptor object (publisher, offer, sku, version). Override to select different distro/version."
  type = object({
    publisher = string
    offer     = string
    sku       = string
    version   = string
  })
}


variable "admin_source_ips" {
  description = "List of public IPs allowed SSH (22) access to MongoDB VM. Empty = SSH blocked externally."
  type        = list(string)
  default     = []
}

variable "api_server_authorized_ip_ranges" {
  description = "List of public IPv4 CIDRs allowed to access the AKS API (required; populate with your trusted egress IPs)."
  type        = list(string)
}

variable "blob_container_name" {
  description = "Name of the Azure Storage blob container for application media (images)."
  type        = string
  default     = "birthdays-images"
}

variable "log_analytics_workspace_id" {
  description = "Log Analytics Workspace ID for monitoring and Microsoft Defender."
  type        = string
  default     = "/subscriptions/1e40f54e-a0a4-422d-9b45-a51c554c2636/resourceGroups/DefaultResourceGroup-CUS/providers/Microsoft.OperationalInsights/workspaces/DefaultWorkspace-1e40f54e-a0a4-422d-9b45-a51c554c2636-CUS"
}
