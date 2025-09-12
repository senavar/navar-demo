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

# Workload Identity for Application
resource "azurerm_user_assigned_identity" "app" {
  name                = "uami-${var.environment}-navarapp-wi"
  location            = var.location
  resource_group_name = var.core_resource_group_name
}

# Role assignment granting secret get/list to the identity at Key Vault scope
resource "azurerm_role_assignment" "kv_secrets_user" {
  scope                = var.key_vault_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.app.principal_id
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
      "azure.workload.identity/client-id" = azurerm_user_assigned_identity.app.client_id
    }
  }
}

# Federated identity credential binding the Kubernetes service account to the UAI
resource "azurerm_federated_identity_credential" "app" {
  name                = "fed-${var.environment}-navarapp-uami"
  resource_group_name = var.core_resource_group_name
  parent_id           = azurerm_user_assigned_identity.app.id
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
        clientID       = azurerm_user_assigned_identity.app.principal_id
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

# Patch NGINX service to force internal load balancer (idempotent)
resource "kubernetes_manifest" "ingress_internal" {
  manifest = {
    "apiVersion" = "approuting.kubernetes.azure.com/v1alpha1"
    "kind"       = "NginxIngressController"
    "metadata" = {
      "name" = "nginx-internal"
    }
    "spec" = {
      "ingressClassName"     = "nginx-internal"
      "controllerNamePrefix" = "nginx-internal"
      "loadBalancerAnnotations" = {
        "service.beta.kubernetes.io/azure-load-balancer-internal" = "true"
      }
    }
  }
}

output "workload_identity_client_id" {
  description = "Client ID of the user-assigned workload identity for Key Vault access."
  value       = azurerm_user_assigned_identity.app.client_id
}

output "workload_identity_service_account" {
  description = "Kubernetes service account (namespace/name) bound via federated identity."
  value       = "${var.app_service_account_namespace}/${var.wi_service_account_name}"
}

