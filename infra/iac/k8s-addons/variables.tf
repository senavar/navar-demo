variable "environment" {
  description = "Deployment environment identifier (e.g. dev, prod)."
  type        = string
}
variable "ingress_service_namespace" {
  description = "Namespace where the AKS Web App Routing (NGINX) service runs."
  type        = string
  default     = "app-routing-system"
}
variable "ingress_service_name" {
  description = "Name of the ingress controller service to patch for internal load balancing."
  type        = string
  default     = "nginx"
}
variable "ingress_wait_seconds" {
  description = "Seconds to wait after patching ingress service before reading its assigned IP."
  type        = number
  default     = 60
}

variable "core_resource_group_name" {
  description = "Name of the resource group where core infrastructure (including AKS) resides."
  type        = string
}
variable "core_aks_name" {
  description = "Name of the AKS cluster from the core module outputs."
  type        = string
}
variable "aks_host" {
  description = "AKS API server host URL (from kube_config host output)."
  type        = string
}
variable "aks_cluster_ca" {
  description = "Base64 encoded cluster CA certificate for AKS (from kube_config)."
  type        = string
}
variable "aks_oidc_issuer_url" {
  description = "OIDC issuer URL for AKS."
  type        = string
}
variable "key_vault_id" {
  description = "Azure Resource ID of the Key Vault used for secrets (from core outputs)."
  type        = string
}
variable "location" {
  description = "Azure region (propagated from core)."
  type        = string
}

# Workload Identity settings
variable "app_service_account_namespace" {
  type        = string
  description = "Namespace where workload identity service account will be created."
  default     = "birthdayapp"
}

variable "wi_service_account_name" {
  type        = string
  description = "Service account name used for workload identity bound to Key Vault access."
  default     = "birthdayapp-sa"
}

variable "core_key_vault_name" {
  description = "Key Vault name (still required for certain references or naming conventions)."
  type        = string
}
variable "aks_user_assigned_identity_client_id" {
  description = "Client ID of the AKS user-assigned identity (for SecretProviderClass / CSI driver)."
  type        = string
  default     = ""
}
