provider "kubernetes" {
  config_path    = "~/.kube/config"
  config_context = var.core_aks_name
}

provider "helm" {
  kubernetes = {
    config_path    = "~/.kube/config"
    config_context = var.core_aks_name
  }
}

data "azurerm_client_config" "current" {}

data "azurerm_user_assigned_identity" "app" {
  name                = "uami-${var.environment}-navarapp-wi"
  resource_group_name = var.core_resource_group_name
}

# Kubernetes namespace 
resource "kubernetes_namespace_v1" "app_namespace" {
  metadata {
    name = var.app_service_account_namespace
  }
}

# Service Account annotated for workload identity
resource "kubernetes_service_account_v1" "app_sa" {
  metadata {
    name      = var.wi_service_account_name
    namespace = kubernetes_namespace_v1.app_namespace.metadata[0].name
    annotations = {
      "azure.workload.identity/client-id" = data.azurerm_user_assigned_identity.app.client_id
    }
  }
}

# Federated identity credential binding the Kubernetes service account to the UAI
resource "azurerm_federated_identity_credential" "app" {
  name                = "fed-${var.environment}-navarapp-uami"
  resource_group_name = var.core_resource_group_name
  parent_id           = data.azurerm_user_assigned_identity.app.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = var.aks_oidc_issuer_url
  subject             = "system:serviceaccount:${kubernetes_service_account_v1.app_sa.metadata[0].namespace}:${kubernetes_service_account_v1.app_sa.metadata[0].name}"
}

resource "kubernetes_manifest" "app_secret" {
  manifest = {
    apiVersion = "secrets-store.csi.x-k8s.io/v1"
    kind       = "SecretProviderClass"
    metadata = {
      name      = "app-secrets"
      namespace = kubernetes_namespace_v1.app_namespace.metadata[0].name
    }
    spec = {
      provider = "azure"
      parameters = {
        usePodIdentity = "false"
        clientID       = data.azurerm_user_assigned_identity.app.client_id
        keyvaultName   = var.core_key_vault_name
        tenantId       = data.azurerm_client_config.current.tenant_id
        objects        = <<EOT
          array:
            - |
              objectName: "mongo-conn-string"
              objectType: secret
        EOT
      }
    }
  }
}
output "workload_identity_id" {
  description = "Resource ID of the user-assigned workload identity for Key Vault access."
  value       = data.azurerm_user_assigned_identity.app.id
}

output "workload_identity_service_account" {
  description = "Kubernetes service account (namespace/name) bound via federated identity."
  value       = "${var.app_service_account_namespace}/${var.wi_service_account_name}"
}

