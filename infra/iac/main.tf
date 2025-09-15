terraform {
  required_version = ">= 1.6.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.116.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = ">= 2.53.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.6.0"
    }
    time = {
      source  = "hashicorp/time"
      version = ">= 0.11.1"
    }
    azapi = {
      source  = "azure/azapi"
      version = ">= 2.0.0"
    }
  }
  backend "azurerm" {}
}
provider "azurerm" {
  features {}
  subscription_id = "1e40f54e-a0a4-422d-9b45-a51c554c2636"
}

provider "azuread" {}

provider "azapi" {}

# Core infrastructure module
module "core" {
  source = "./core"

  environment                     = var.environment
  location                        = var.location
  vnet_address_space              = var.vnet_address_space
  subnet_cidrs                    = var.subnet_cidrs
  aks_system_node_count           = var.aks_system_node_count
  aks_user_node_count             = var.aks_user_node_count
  aks_system_vm_size              = var.aks_system_vm_size
  aks_user_vm_size                = var.aks_user_vm_size
  acr_sku                         = var.acr_sku
  mongodb_vm_size                 = var.mongodb_vm_size
  mongodb_admin_password          = var.mongodb_admin_password
  linux_image                     = var.linux_image
  admin_source_ips                = var.admin_source_ips
  api_server_authorized_ip_ranges = var.api_server_authorized_ip_ranges
}

# Kubernetes add-ons module
# (Workload Identity, Nginx)
module "k8s_addons" {
  source = "./k8s-addons"

  location                             = var.location
  environment                          = var.environment
  core_resource_group_name             = module.core.resource_group_name
  core_aks_name                        = module.core.aks_name
  core_key_vault_name                  = module.core.key_vault_name
  aks_user_assigned_identity_client_id = module.core.aks_user_assigned_identity_client_id
  app_service_account_namespace        = var.app_service_account_namespace
  wi_service_account_name              = var.wi_service_account_name
  aks_host                             = module.core.aks_host
  aks_cluster_ca                       = module.core.aks_cluster_ca
  key_vault_id                         = module.core.key_vault_id
  aks_oidc_issuer_url                  = module.core.aks_oidc_issuer_url
  storage_account_id                   = module.core.storage_account_id
}

# Application Gateway module (depends on ingress private IP)
module "appgw" {
  source = "./appgw"

  environment         = var.environment
  resource_group_name = module.core.resource_group_name
  location            = var.location
  vnet_name           = module.core.virtual_network_name
  appgw_subnet_id     = module.core.subnet_appgw_id
  node_resource_group = module.core.node_resource_group
  key_vault_id        = module.core.key_vault_id
  appgw_uami_id       = module.k8s_addons.workload_identity_id
}

# Aggregated Outputs
output "resource_group_name" { value = module.core.resource_group_name }
output "aks_name" { value = module.core.aks_name }
output "key_vault_name" { value = module.core.key_vault_name }
output "application_gateway_public_ip" { value = try(module.appgw.application_gateway_public_ip, null) }
output "storage_account_name" { value = module.core.storage_account_name }

