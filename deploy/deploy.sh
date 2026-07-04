#!/usr/bin/env bash
#
# Build the SynchronAIse backend image into k3s and deploy with Helm.
#
# Usage:
#   ./deploy/deploy.sh
#   ./deploy/deploy.sh --skip-build
#   ./deploy/deploy.sh --namespace hackathon --release synchronaise
#
set -euo pipefail

NAMESPACE="hackathon"
RELEASE_NAME="synchronaise"
EXPECTED_CONTEXT="rancher-desktop"
IMAGE_TAG="synchronaise-backend:dev"
IMAGE_PULL_SECRET="application-collection"
SKIP_BUILD=0
SKIP_HELM=0

usage() {
    cat <<'EOF'
Usage: deploy.sh [OPTIONS]

Options:
  --namespace NAME       Kubernetes namespace (default: hackathon)
  --release NAME         Helm release name (default: synchronaise)
  --context NAME         Required kubectl context (default: rancher-desktop)
  --image-tag TAG        Image tag to build (default: synchronaise-backend:dev)
  --pull-secret NAME     Image pull secret name (default: application-collection)
  --skip-build           Skip container image build
  --skip-helm            Skip helm upgrade --install
  -h, --help             Show this help
EOF
}

err() {
    echo ""
    echo "ERROR: $*" >&2
    exit 1
}

info() {
    echo "$*"
}

ok() {
    echo "OK: $*"
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        --release)
            RELEASE_NAME="$2"
            shift 2
            ;;
        --context)
            EXPECTED_CONTEXT="$2"
            shift 2
            ;;
        --image-tag)
            IMAGE_TAG="$2"
            shift 2
            ;;
        --pull-secret)
            IMAGE_PULL_SECRET="$2"
            shift 2
            ;;
        --skip-build)
            SKIP_BUILD=1
            shift
            ;;
        --skip-helm)
            SKIP_HELM=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            err "Unknown option: $1 (try --help)"
            ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CHART_PATH="$SCRIPT_DIR/helm/synchronaise"
BACKEND_PATH="$REPO_ROOT/backend"

cd "$REPO_ROOT"

echo ""
echo "SynchronAIse deploy"
echo "==================="
echo ""

for cmd in kubectl helm; do
    command_exists "$cmd" || err "$cmd is not installed or not in PATH."
done

if [[ "$SKIP_BUILD" -eq 0 ]]; then
    [[ -d "$BACKEND_PATH" ]] || err "Backend directory not found at $BACKEND_PATH"
    [[ -f "$BACKEND_PATH/Dockerfile" ]] || err "Dockerfile not found at $BACKEND_PATH/Dockerfile"
fi

if [[ "$SKIP_HELM" -eq 0 ]]; then
    [[ -d "$CHART_PATH" ]] || err "Helm chart not found at $CHART_PATH"
fi

info "Checking kubectl context..."
current_context="$(kubectl config current-context 2>/dev/null || true)"
if [[ -z "$current_context" ]]; then
    err "$(cat <<EOF
kubectl has no current context. Is Rancher Desktop running?

  kubectl config use-context rancher-desktop
EOF
)"
fi
if [[ "$current_context" != "$EXPECTED_CONTEXT" ]]; then
    err "$(cat <<EOF
kubectl context is '$current_context', expected '$EXPECTED_CONTEXT'.

  kubectl config use-context $EXPECTED_CONTEXT
EOF
)"
fi
ok "kubectl context is $EXPECTED_CONTEXT"

info "Checking namespace '$NAMESPACE'..."
if ! kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
    err "$(cat <<EOF
Namespace '$NAMESPACE' does not exist.

Run init.bat from the rancher-hackathon-paris repo once to bootstrap k3s,
the hackathon namespace, and the application-collection pull secret.
EOF
)"
fi
ok "namespace $NAMESPACE exists"

info "Checking image-pull secret '$IMAGE_PULL_SECRET'..."
if ! kubectl get secret "$IMAGE_PULL_SECRET" -n "$NAMESPACE" >/dev/null 2>&1; then
    err "$(cat <<EOF
Secret '$IMAGE_PULL_SECRET' not found in namespace '$NAMESPACE'.

The hackathon bootstrap has not been applied on this machine.
Run init.bat from the rancher-hackathon-paris repo once, then retry.

That script creates:
  - kubectl context: rancher-desktop
  - namespace: hackathon
  - secret: application-collection (dp.apps.rancher.io pull credentials)
EOF
)"
fi
ok "secret $IMAGE_PULL_SECRET exists in $NAMESPACE"

info "Checking LLM secret 'synchronaise-llm'..."
if ! kubectl get secret synchronaise-llm -n "$NAMESPACE" >/dev/null 2>&1; then
    echo ""
    echo "WARNING: Secret 'synchronaise-llm' not found. Pods will not start until it exists."
    echo "  Create from backend/.env (mock mode works with empty keys):"
    echo "    kubectl create secret generic synchronaise-llm --from-env-file=backend/.env -n $NAMESPACE"
    echo "  Or let Helm create it: add --set secret.create=true (and set secret.data.* keys)"
    echo ""
else
    ok "secret synchronaise-llm exists"
fi

detect_container_engine() {
    if command_exists rdctl; then
        local engine_name
        engine_name="$(rdctl list-settings 2>/dev/null | sed -n 's/.*"name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1 || true)"
        if [[ "$engine_name" == "dockerd" ]]; then
            echo "docker"
            return
        fi
        echo "nerdctl"
        return
    fi

    if command_exists nerdctl && ! command_exists docker; then
        echo "nerdctl"
        return
    fi

    if command_exists docker && docker info >/dev/null 2>&1; then
        echo "docker"
        return
    fi

    if command_exists nerdctl; then
        echo "nerdctl"
        return
    fi

    echo ""
}

if [[ "$SKIP_BUILD" -eq 0 ]]; then
    info "Building image $IMAGE_TAG..."
    engine="$(detect_container_engine)"

    case "$engine" in
        docker)
            command_exists docker || err "Rancher Desktop is using dockerd but docker CLI is not in PATH."
            info "Using docker build (dockerd engine)..."
            docker build -t "$IMAGE_TAG" "$BACKEND_PATH"
            ;;
        nerdctl)
            info "Using nerdctl build (containerd / k8s.io namespace)..."
            nerdctl --namespace k8s.io build -t "$IMAGE_TAG" "$BACKEND_PATH"
            ;;
        *)
            err "$(cat <<EOF
No container build tool found. Install nerdctl or docker, or enable a container
engine in Rancher Desktop (Container Engine -> containerd or dockerd).
EOF
)"
            ;;
    esac

    ok "image built: $IMAGE_TAG"
fi

if [[ "$SKIP_HELM" -eq 0 ]]; then
    info "Running helm upgrade --install $RELEASE_NAME..."
    helm upgrade --install "$RELEASE_NAME" "$CHART_PATH" \
        --namespace "$NAMESPACE" \
        --set "global.imagePullSecrets={$IMAGE_PULL_SECRET}"
    ok "Helm release '$RELEASE_NAME' deployed to namespace '$NAMESPACE'"
fi

echo ""
echo "Deploy complete."
echo ""
echo "Forward the service to your machine:"
echo "  kubectl port-forward -n $NAMESPACE svc/$RELEASE_NAME 8080:8080"
echo ""
echo "Then verify:"
echo "  curl http://localhost:8080/healthz"
echo ""
