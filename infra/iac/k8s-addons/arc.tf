// Actions Runner Controller installation aligned with GitHub quickstart

data "azurerm_client_config" "current" {}

resource "kubernetes_namespace_v1" "arc_controller" {
  metadata {
    name = var.arc_controller_namespace
  }
}

resource "kubernetes_namespace_v1" "arc_runners" {
  metadata {
    name = var.arc_runners_namespace
  }
}

# Controller chart (installs CRDs & controller)
resource "helm_release" "arc_controller" {
  name             = var.arc_controller_release_name
  repository       = "oci://ghcr.io/actions/actions-runner-controller-charts"
  chart            = "gha-runner-scale-set-controller"
  namespace        = var.arc_controller_namespace
  version          = var.arc_chart_version != "" ? var.arc_chart_version : null
  create_namespace = false
  depends_on       = [kubernetes_namespace_v1.arc_controller]
}

# Runner scale set chart (provides autoscaling runner pods)
resource "helm_release" "arc_runner_scale_set" {
  name             = var.arc_runner_scale_set_name
  repository       = "oci://ghcr.io/actions/actions-runner-controller-charts"
  chart            = "gha-runner-scale-set"
  namespace        = var.arc_runners_namespace
  version          = var.arc_chart_version != "" ? var.arc_chart_version : null
  create_namespace = false
  values = [yamlencode({
    githubConfigUrl    = var.arc_github_config_url != "" ? var.arc_github_config_url : null
    githubConfigSecret = var.arc_github_config_url != "" ? "arc-github-auth" : null # pre-defined secret name expected
  })]
  depends_on = [helm_release.arc_controller, kubernetes_namespace_v1.arc_runners]
}

# SecretProviderClass to sync GitHub PAT from Key Vault to a Kubernetes secret consumed by ARC
resource "kubernetes_manifest" "arc_pat_secretproviderclass" {
  manifest = {
    apiVersion = "secrets-store.csi.x-k8s.io/v1"
    kind       = "SecretProviderClass"
    metadata = {
      name      = "arc-github-pat-spc"
      namespace = var.arc_runners_namespace
    }
    spec = {
      provider = "azure"
      parameters = {
        usePodIdentity         = "false"
        useVMManagedIdentity   = "true" # AKS cluster managed identity
        userAssignedIdentityID = var.aks_user_assigned_identity_client_id
        keyvaultName           = var.core_key_vault_name
        tenantId               = data.azurerm_client_config.current.tenant_id
        objects                = <<EOT
          array:
            - |-
              objectName: ${var.arc_pat_key_vault_secret_name}
              objectType: secret
              objectAlias: ${var.arc_pat_key_vault_secret_name}
        EOT
      }
      secretObjects = [
        {
          secretName = var.arc_pat_key_vault_secret_name
          type       = "Opaque"
          data = [
            {
              objectName = var.arc_pat_key_vault_secret_name
              key        = var.arc_pat_key_vault_secret_name
            }
          ]
        }
      ]
    }
  }
  depends_on = [helm_release.arc_controller]
}

output "arc_controller_namespace" { value = var.arc_controller_namespace }
output "arc_runners_namespace" { value = var.arc_runners_namespace }
output "arc_runner_scale_set_name" { value = var.arc_runner_scale_set_name }
