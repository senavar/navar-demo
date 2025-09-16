#!/usr/bin/env bash
set -euo pipefail

# Simple bootstrap script for cluster add-ons:
#  - Kyverno (policy engine)
#  - Tetragon (security observability / eBPF)
#  - GitHub Actions Runner Controller (ARC) via PAT auth (repo/org scope)


# Namespace helper (create if missing)
ensure_ns() {
  local ns="$1"
  if ! kubectl get ns "$ns" >/dev/null 2>&1; then
    echo "Creating namespace $ns"
    kubectl create namespace "$ns"
  fi
}

########################
# Kyverno
########################
KYVERNO_NS="kyverno"
ensure_ns "$KYVERNO_NS"
if ! helm ls -n "$KYVERNO_NS" | grep -q "kyverno"; then
  echo "Installing Kyverno"
  helm repo add kyverno https://kyverno.github.io/kyverno/ 
  helm repo update
  helm install kyverno kyverno/kyverno -n "$KYVERNO_NS" \
    --set admissionController.replicas=2 \
    --set backgroundController.replicas=1 \
    --set cleanupController.replicas=1
    
  helm install kyverno-policies kyverno/kyverno-policies -n kyverno
else
  echo "Kyverno already installed"
fi

########################
# Tetragon
########################
if ! helm ls -n "kube-system" | grep -q tetragon; then
  echo "Installing Tetragon"
  helm repo add cilium https://helm.cilium.io/ 
  helm repo update 
  helm install tetragon ${EXTRA_HELM_FLAGS[@]} cilium/tetragon -n kube-system
  kubectl rollout status -n kube-system ds/tetragon -w
else
  echo "Tetragon already installed"
fi

########################
# GitHub Actions Runner Controller (ARC) - PAT Auth
########################
ARC_NS="actions-runner-system"
RUNNER_NS="actions-runner"  
ensure_ns "$ARC_NS"
ensure_ns "$RUNNER_NS"
if ! helm ls -n "$ARC_NS" | grep -q arc; then
    echo "Installing ARC (PAT auth)"
    helm install arc --namespace "${ARC_NS}" oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set-controller
    helm install arc-runner-set \
        --namespace "${RUNNER_NS}" \
        --set githubConfigUrl="${GITHUB_TARGET}" \
        --set githubConfigSecret.github_token="${GITHUB_PAT}" \
        oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set

  echo "ARC controller installed."
else
  echo "ARC already installed"
fi

echo "All addon steps attempted."
