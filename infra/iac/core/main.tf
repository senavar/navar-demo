terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
    }
    azuread = {
      source = "hashicorp/azuread"
    }
    azapi = {
      source = "azure/azapi"
    }
  }
}

module "naming" {
  source  = "Azure/naming/azurerm"
  version = "~> 0.4.0"
  suffix  = [var.environment, "navarlab"]
}

module "naming_mongodb" {
  source  = "Azure/naming/azurerm"
  version = "~> 0.4.0"
  suffix  = [var.environment, "mongo"]
}

data "azurerm_client_config" "current" {}

# Resource Group
resource "azurerm_resource_group" "this" {
  name     = module.naming.resource_group.name
  location = var.location
  tags = merge({
    environment = var.environment
    managed_by  = "terraform"
  }, var.tags)
}


# Networking - VNet & Subnets
resource "azurerm_virtual_network" "this" {
  name                = module.naming.virtual_network.name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  address_space       = var.vnet_address_space
  tags                = azurerm_resource_group.this.tags
}

resource "azurerm_subnet" "aks_system" {
  name                 = "snet-aks-system"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.subnet_cidrs.aks_system]
}

resource "azurerm_subnet" "aks_user" {
  name                 = "snet-aks-app"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.subnet_cidrs.aks_user]
}

resource "azurerm_subnet" "appgw" {
  name                 = "snet-appgw"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.subnet_cidrs.appgw]
}

resource "azurerm_subnet" "data" {
  name                 = "snet-backend"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.subnet_cidrs.data]
}

resource "azurerm_subnet" "ops" {
  name                 = "snet-ops"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.subnet_cidrs.ops]
}

resource "azurerm_role_assignment" "network_contributor_on_resource_group" {
  principal_id         = azurerm_user_assigned_identity.aks.principal_id
  scope                = azurerm_resource_group.this.id
  role_definition_name = "Network Contributor"
}

resource "azurerm_network_security_group" "appgw" {
  name                = "nsg-appgw-${var.environment}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = azurerm_resource_group.this.tags
  security_rule {
    name                       = "AllowHTTP"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  security_rule {
    name                       = "AllowHTTPS"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  security_rule {
    name                       = "AllowAppGwGatewayManager"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "65200-65535"
    source_address_prefix      = "GatewayManager"
    destination_address_prefix = "*"
    description                = "Required for App Gateway v2 infrastructure provisioning"
  }
}

resource "azurerm_subnet_network_security_group_association" "appgw" {
  subnet_id                 = azurerm_subnet.appgw.id
  network_security_group_id = azurerm_network_security_group.appgw.id
}

resource "azurerm_network_security_group" "ops" {
  name                = "nsg-ops-${var.environment}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = azurerm_resource_group.this.tags
}

resource "azurerm_subnet_network_security_group_association" "ops" {
  subnet_id                 = azurerm_subnet.ops.id
  network_security_group_id = azurerm_network_security_group.ops.id
}

# Key Vault
resource "azurerm_key_vault" "this" {
  name                            = "kv-navarlab-${var.environment}"
  location                        = azurerm_resource_group.this.location
  resource_group_name             = azurerm_resource_group.this.name
  tenant_id                       = data.azurerm_client_config.current.tenant_id
  sku_name                        = lower(var.key_vault_sku) == "premium" ? "premium" : "standard"
  rbac_authorization_enabled      = true
  purge_protection_enabled        = true
  enabled_for_deployment          = true
  enabled_for_template_deployment = true
  soft_delete_retention_days      = 7
  tags                            = azurerm_resource_group.this.tags
}

resource "azurerm_role_assignment" "akv_admin" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = data.azurerm_client_config.current.object_id
}

# Key for etcd (AKS secret) encryption
resource "azurerm_key_vault_key" "aks_etcd" {
  name         = "kv-aks-etcd-cmk"
  key_vault_id = azurerm_key_vault.this.id
  key_type     = "RSA"
  key_size     = 2048
  key_opts     = ["decrypt", "encrypt", "wrapKey", "unwrapKey"]
  depends_on   = [azurerm_role_assignment.akv_admin]
}

resource "azurerm_private_dns_zone" "kv" {
  name                = "privatelink.vaultcore.azure.net"
  resource_group_name = azurerm_resource_group.this.name
  tags                = azurerm_resource_group.this.tags
}


resource "azurerm_private_dns_zone_virtual_network_link" "kv" {
  name                  = "link-kv-primary"
  resource_group_name   = azurerm_resource_group.this.name
  private_dns_zone_name = azurerm_private_dns_zone.kv.name
  virtual_network_id    = azurerm_virtual_network.this.id
  registration_enabled  = false
  tags                  = azurerm_resource_group.this.tags
}

resource "azurerm_private_endpoint" "kv" {
  name                = "pe-${azurerm_key_vault.this.name}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  subnet_id           = azurerm_subnet.ops.id
  tags                = azurerm_resource_group.this.tags
  private_service_connection {
    name                           = "psc-kv"
    private_connection_resource_id = azurerm_key_vault.this.id
    is_manual_connection           = false
    subresource_names              = ["vault"]
  }
  private_dns_zone_group {
    name                 = "kv-dns"
    private_dns_zone_ids = [azurerm_private_dns_zone.kv.id]
  }
  depends_on = [azurerm_private_dns_zone.kv, azurerm_key_vault_key.aks_etcd]
}


# Storage Account for workload
resource "azurerm_storage_account" "this" {
  name                     = module.naming.storage_account.name_unique
  resource_group_name      = azurerm_resource_group.this.name
  location                 = azurerm_resource_group.this.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_storage_container" "media" {
  name               = "birthdays-images"
  storage_account_id = azurerm_storage_account.this.id
}

resource "azurerm_storage_container" "db" {
  name               = "db-backups"
  storage_account_id = azurerm_storage_account.this.id
}

# Azure Container Registry
resource "azurerm_container_registry" "this" {
  name                = module.naming.container_registry.name_unique
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  sku                 = var.acr_sku
  admin_enabled       = false
  tags                = azurerm_resource_group.this.tags
}

resource "azurerm_private_dns_zone" "acr" {
  name                = "privatelink.azurecr.io"
  resource_group_name = azurerm_resource_group.this.name
  tags                = azurerm_resource_group.this.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "acr" {
  name                  = "link-acr"
  resource_group_name   = azurerm_resource_group.this.name
  private_dns_zone_name = azurerm_private_dns_zone.acr.name
  virtual_network_id    = azurerm_virtual_network.this.id
  registration_enabled  = false
  tags                  = azurerm_resource_group.this.tags
}

resource "azurerm_private_endpoint" "acr" {
  name                = "pe-${azurerm_container_registry.this.name}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  subnet_id           = azurerm_subnet.ops.id
  tags                = azurerm_resource_group.this.tags

  private_service_connection {
    name                           = "psc-acr"
    private_connection_resource_id = azurerm_container_registry.this.id
    is_manual_connection           = false
    subresource_names              = ["registry"]
  }

  private_dns_zone_group {
    name                 = "acr-dns"
    private_dns_zone_ids = [azurerm_private_dns_zone.acr.id]
  }
}

# Allow AKS kubelet identity to pull from ACR (if kubelet identity available)
resource "azurerm_role_assignment" "aks_acr_pull" {
  scope                = azurerm_container_registry.this.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.this.kubelet_identity[0].object_id
  depends_on           = [azurerm_kubernetes_cluster.this, azurerm_container_registry.this]
}

# AKS Cluster (basic skeleton; to be expanded with workload identity, node pools, RBAC)

resource "azurerm_user_assigned_identity" "aks" {
  name                = "uami-aks-${var.environment}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = azurerm_resource_group.this.tags
}

# Grant Crypto User permissions to the KMS identity on the Key Vault
resource "azurerm_role_assignment" "aks_kms_crypto" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Crypto User"
  principal_id         = azurerm_user_assigned_identity.aks.principal_id
}

# Allow AKS user-assigned identity to retrieve secrets via CSI driver
resource "azurerm_role_assignment" "aks_kv_secrets" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.aks.principal_id
}

resource "azurerm_kubernetes_cluster" "this" {
  name                      = module.naming.kubernetes_cluster.name
  location                  = azurerm_resource_group.this.location
  resource_group_name       = azurerm_resource_group.this.name
  dns_prefix                = module.naming.kubernetes_cluster.name
  private_cluster_enabled   = false
  kubernetes_version        = var.aks_kubernetes_version != "" ? var.aks_kubernetes_version : null
  oidc_issuer_enabled       = true
  workload_identity_enabled = true
  local_account_disabled    = true
  # Apply IP allow list only if user provided ranges (empty list leaves API open to Internet).
  #dynamic "api_server_access_profile" {
  #  for_each = length(var.api_server_authorized_ip_ranges) == 0 ? [] : [1]
  #  content {
  #    authorized_ip_ranges = var.api_server_authorized_ip_ranges
  #  }
  #}

  # Etcd secret encryption via Azure Key Vault KMS (customer-managed key)
  key_management_service {
    key_vault_key_id         = azurerm_key_vault_key.aks_etcd.id
    key_vault_network_access = "Public"
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.aks.id]
  }

  # Enable Key Vault CSI Secrets Provider addon
  key_vault_secrets_provider {
    secret_rotation_enabled = false
  }

  default_node_pool {
    name                 = "system"
    node_count           = var.aks_system_node_count
    vm_size              = var.aks_system_vm_size
    vnet_subnet_id       = azurerm_subnet.aks_system.id
    orchestrator_version = var.aks_kubernetes_version != "" ? var.aks_kubernetes_version : null
    os_disk_size_gb      = 128
    os_sku               = "AzureLinux"
    type                 = "VirtualMachineScaleSets"

    upgrade_settings {
      max_surge = "10%"
    }
  }

  monitor_metrics {
    annotations_allowed = null
    labels_allowed      = null
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_policy      = "cilium"
    network_data_plane  = "cilium"
    pod_cidr            = var.aks_pod_cidr
    dns_service_ip      = "10.0.0.10"
    service_cidr        = "10.0.0.0/16"
    outbound_type       = var.aks_outbound_type
  }

  azure_active_directory_role_based_access_control {
    azure_rbac_enabled     = true
    tenant_id              = data.azurerm_client_config.current.tenant_id
    admin_group_object_ids = ["fb0906fe-3df0-4a0c-8c2f-2e52d33d549f"]
  }

  web_app_routing {
    dns_zone_ids = [azurerm_private_dns_zone.webapp_routing.id]
  }

  microsoft_defender {
    log_analytics_workspace_id = var.log_analytics_workspace_id
  }

  tags       = azurerm_resource_group.this.tags
  depends_on = [azurerm_role_assignment.aks_kms_crypto]
}

resource "azurerm_kubernetes_cluster_node_pool" "user" {
  name                  = "user"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.this.id
  vm_size               = var.aks_user_vm_size
  node_count            = var.aks_user_node_count
  os_sku                = "AzureLinux"
  vnet_subnet_id        = azurerm_subnet.aks_user.id
  orchestrator_version  = var.aks_kubernetes_version != "" ? var.aks_kubernetes_version : null
  mode                  = "User"
  upgrade_settings {
    max_surge = "10%"
  }

  tags                        = azurerm_resource_group.this.tags
  temporary_name_for_rotation = "userrotate"
}

locals {
  log_analytics_tables = ["AKSAudit", "AKSAuditAdmin", "AKSControlPlane", "ContainerLogV2"]
}

resource "azurerm_log_analytics_workspace_table" "this" {
  for_each = toset(local.log_analytics_tables)

  name                    = each.value
  workspace_id            = var.log_analytics_workspace_id
  plan                    = "Basic"
  total_retention_in_days = 30
}

resource "random_string" "name" {
  length  = 3
  special = false
}

resource "azurerm_monitor_diagnostic_setting" "aks" {
  name                           = "amds-${var.environment}-aks-${random_string.name.result}"
  target_resource_id             = azurerm_kubernetes_cluster.this.id
  log_analytics_destination_type = "Dedicated"
  log_analytics_workspace_id     = var.log_analytics_workspace_id

  # Kubernetes API Server
  enabled_log {
    category = "kube-apiserver"
  }
  # Kubernetes Audit
  enabled_log {
    category = "kube-audit"
  }
  # Kubernetes Audit Admin Logs
  enabled_log {
    category = "kube-audit-admin"
  }
  # Kubernetes Controller Manager
  enabled_log {
    category = "kube-controller-manager"
  }
  # Kubernetes Scheduler
  enabled_log {
    category = "kube-scheduler"
  }
  #Kubernetes Cluster Autoscaler
  enabled_log {
    category = "cluster-autoscaler"
  }
  #Kubernetes Cloud Controller Manager
  enabled_log {
    category = "cloud-controller-manager"
  }
  #guard
  enabled_log {
    category = "guard"
  }
  #csi-azuredisk-controller
  enabled_log {
    category = "csi-azuredisk-controller"
  }
  #csi-azurefile-controller
  enabled_log {
    category = "csi-azurefile-controller"
  }
  #csi-snapshot-controller
  enabled_log {
    category = "csi-snapshot-controller"
  }
  metric {
    category = "AllMetrics"
  }
}

resource "azapi_update_resource" "aks_cluster_patch_acns" {
  type        = "Microsoft.ContainerService/ManagedClusters@2024-09-01"
  resource_id = azurerm_kubernetes_cluster.this.id
  depends_on  = [azurerm_kubernetes_cluster_node_pool.user]
  body = {
    properties = {
      networkProfile = {
        advancedNetworking = {
          enabled = true
          observability = {
            enabled = true
          }
          security = {
            enabled = false
          }
        }
      }
    }
  }
}

resource "azurerm_role_assignment" "cluster_admin" {
  scope                = azurerm_kubernetes_cluster.this.id
  role_definition_name = "Azure Kubernetes Service RBAC Cluster Admin"
  principal_id         = "fb0906fe-3df0-4a0c-8c2f-2e52d33d549f"
}


# Private DNS Zone for Web App Routing (Ingress)
resource "azurerm_private_dns_zone" "webapp_routing" {
  name                = var.web_app_routing_zone_name
  resource_group_name = azurerm_resource_group.this.name
  tags                = azurerm_resource_group.this.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "webapp_routing" {
  name                  = "link-webapp-routing"
  resource_group_name   = azurerm_resource_group.this.name
  private_dns_zone_name = azurerm_private_dns_zone.webapp_routing.name
  virtual_network_id    = azurerm_virtual_network.this.id
  registration_enabled  = false
  tags                  = azurerm_resource_group.this.tags
}

#Managed Prometheus and Grafana

resource "azurerm_monitor_workspace" "this" {
  name                = "prometheus-aks-${var.environment}"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
}

resource "azurerm_monitor_data_collection_endpoint" "dataCollectionEndpoint" {
  name                = "prom-aks-endpoint-${var.environment}"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  kind                = "Linux"
}

resource "azurerm_monitor_data_collection_rule" "dataCollectionRule" {
  name                        = "prom-aks-dcr-${var.environment}"
  location                    = var.location
  resource_group_name         = azurerm_resource_group.this.name
  data_collection_endpoint_id = azurerm_monitor_data_collection_endpoint.dataCollectionEndpoint.id
  kind                        = "Linux"
  description                 = "DCR for Azure Monitor Metrics Profile (Managed Prometheus)"
  destinations {
    monitor_account {
      monitor_account_id = azurerm_monitor_workspace.this.id
      name               = "PrometheusAzMonitorAccount"
    }
  }
  data_flow {
    streams      = ["Microsoft-PrometheusMetrics"]
    destinations = ["PrometheusAzMonitorAccount"]
  }
  data_sources {
    prometheus_forwarder {
      streams = ["Microsoft-PrometheusMetrics"]
      name    = "PrometheusDataSource"
    }
  }

}

resource "azurerm_monitor_data_collection_rule_association" "dataCollectionRuleAssociation" {
  name                    = "prom-aks-dcra-${var.environment}"
  target_resource_id      = azurerm_kubernetes_cluster.this.id
  data_collection_rule_id = azurerm_monitor_data_collection_rule.dataCollectionRule.id
  description             = "Association of data collection rule. Deleting this association will break the data collection for this AKS Cluster."
}

resource "azurerm_dashboard_grafana" "this" {
  name                              = "grafana-aks-${var.environment}"
  location                          = var.location
  resource_group_name               = azurerm_resource_group.this.name
  api_key_enabled                   = true
  deterministic_outbound_ip_enabled = true
  public_network_access_enabled     = true
  grafana_major_version             = 11

  azure_monitor_workspace_integrations {
    resource_id = azurerm_monitor_workspace.this.id
  }

  identity {
    type = "SystemAssigned"
  }
}

resource "azurerm_role_assignment" "grafana_monitoring_reader" {
  scope                            = azurerm_resource_group.this.id
  role_definition_name             = "Monitoring Reader"
  principal_id                     = azurerm_dashboard_grafana.this.identity[0].principal_id
  skip_service_principal_aad_check = true
}

# MongoDB VM (Linux)
resource "azurerm_network_security_group" "mongodb" {
  name                = "nsg-mongodb-${var.environment}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = azurerm_resource_group.this.tags
  security_rule {
    name                       = "AllowSSHAdminIPs"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefixes    = var.admin_source_ips
    destination_address_prefix = "*"
  }
  security_rule {
    name                       = "AllowMongoFromAKS"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "27017"
    source_address_prefix      = [azurerm_subnet.aks_system.address_prefixes[0], azurerm_subnet.aks_user.address_prefixes[0]]
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "mongodb" {
  subnet_id                 = azurerm_subnet.data.id
  network_security_group_id = azurerm_network_security_group.mongodb.id
}

resource "azurerm_network_interface" "mongodb" {
  name                = module.naming_mongodb.network_interface.name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  ip_configuration {
    name                          = "ipconfig"
    subnet_id                     = azurerm_subnet.data.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.mongodb.id
  }
  tags = azurerm_resource_group.this.tags
}

# User-assigned identity for MongoDB VM
resource "azurerm_user_assigned_identity" "mongodb" {
  name                = "uami-mongodb-${var.environment}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = azurerm_resource_group.this.tags
}

resource "azurerm_public_ip" "mongodb" {
  name                = module.naming_mongodb.public_ip.name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = azurerm_resource_group.this.tags
}

resource "azurerm_linux_virtual_machine" "mongodb" {
  name                            = module.naming_mongodb.virtual_machine.name
  resource_group_name             = azurerm_resource_group.this.name
  location                        = azurerm_resource_group.this.location
  size                            = var.mongodb_vm_size
  admin_username                  = var.mongodb_admin_username
  disable_password_authentication = var.ssh_public_key != ""
  network_interface_ids           = [azurerm_network_interface.mongodb.id]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
    disk_size_gb         = var.mongodb_disk_size_gb
  }
  source_image_reference {
    publisher = var.linux_image.publisher
    offer     = var.linux_image.offer
    sku       = var.linux_image.sku
    version   = var.linux_image.version
  }

  plan {
    name      = var.linux_image.sku
    product   = var.linux_image.offer
    publisher = var.linux_image.publisher
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.mongodb.id]
  }

  custom_data = base64encode(templatefile("${path.module}/scripts/mongodb-install.sh", {
    kv_name        = azurerm_key_vault.this.name
    secret_name    = "mongo-conn-string"
    app_user       = var.mongodb_admin_username
    private_ip     = azurerm_network_interface.mongodb.private_ip_address
    uami_client_id = azurerm_user_assigned_identity.mongodb.client_id
  }))

  dynamic "admin_ssh_key" {
    for_each = var.ssh_public_key != "" ? [1] : []
    content {
      username   = var.mongodb_admin_username
      public_key = var.ssh_public_key
    }
  }
  admin_password = var.ssh_public_key == "" ? var.mongodb_admin_password : null
  tags           = azurerm_resource_group.this.tags

  depends_on = [
    azurerm_role_assignment.mongodb_kv_secret_officer,
    azurerm_role_assignment.mongodb_owner
  ]
}

resource "azurerm_role_assignment" "mongodb_kv_secret_officer" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = azurerm_user_assigned_identity.mongodb.principal_id
}

resource "azurerm_role_assignment" "mongodb_owner" {
  scope                = azurerm_resource_group.this.id
  role_definition_name = "Owner"
  principal_id         = azurerm_user_assigned_identity.mongodb.principal_id
}

#UAMI for Application
resource "azurerm_user_assigned_identity" "app" {
  name                = "uami-${var.environment}-navarapp-wi"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
}

## Role assignment granting secret get/list to the identity at Key Vault scope
resource "azurerm_role_assignment" "app_kv_rbac" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = azurerm_user_assigned_identity.app.principal_id
}

## Allow user-assigned identity to write/read blobs for backups
resource "azurerm_role_assignment" "aks_storage_blob_contributor" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.app.principal_id
}

# Outputs 
output "resource_group_name" { value = azurerm_resource_group.this.name }
output "aks_name" { value = azurerm_kubernetes_cluster.this.name }
output "acr_name" { value = azurerm_container_registry.this.name }
output "acr_private_endpoint_id" { value = azurerm_private_endpoint.acr.id }
output "key_vault_name" { value = azurerm_key_vault.this.name }
output "key_vault_private_endpoint_id" { value = azurerm_private_endpoint.kv.id }
output "mongodb_private_ip" { value = azurerm_network_interface.mongodb.private_ip_address }
output "aks_kubelet_identity_object_id" { value = azurerm_kubernetes_cluster.this.kubelet_identity[0].object_id }
output "virtual_network_id" { value = azurerm_virtual_network.this.id }
output "virtual_network_name" { value = azurerm_virtual_network.this.name }
output "subnet_appgw_id" { value = azurerm_subnet.appgw.id }
output "subnet_appgw_name" { value = azurerm_subnet.appgw.name }
output "aks_principal_id" { value = azurerm_kubernetes_cluster.this.identity[0].principal_id }
output "aks_oidc_issuer_url" { value = azurerm_kubernetes_cluster.this.oidc_issuer_url }
output "aks_api_restricted" { value = length(var.api_server_authorized_ip_ranges) > 0 }
output "aks_etcd_cmk_key_id" { value = azurerm_key_vault_key.aks_etcd.id }
output "aks_kms_identity_principal_id" { value = azurerm_user_assigned_identity.aks.principal_id }
output "aks_user_assigned_identity_client_id" { value = azurerm_user_assigned_identity.aks.client_id }
output "aks_host" { value = azurerm_kubernetes_cluster.this.kube_config[0].host }
output "aks_cluster_ca" { value = azurerm_kubernetes_cluster.this.kube_config[0].cluster_ca_certificate }
output "key_vault_id" { value = azurerm_key_vault.this.id }
output "node_resource_group" { value = azurerm_kubernetes_cluster.this.node_resource_group }
output "storage_account_id" { value = azurerm_storage_account.this.id }
output "storage_account_name" { value = azurerm_storage_account.this.name }
