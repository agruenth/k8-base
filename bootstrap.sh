#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# K3s Cluster Bootstrap Script
# Idempotent - safe to re-run
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REGISTRY_NAME="registry.localhost"
REGISTRY_PORT="5000"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# ============================================================
# 1. Check root
# ============================================================
if [[ $EUID -ne 0 ]]; then
    error "This script must be run as root (use sudo)"
fi

SUDO_USER="${SUDO_USER:-$USER}"
SUDO_HOME=$(eval echo "~${SUDO_USER}")

# ============================================================
# 2. Install k3s (with Traefik disabled)
# ============================================================
if command -v k3s &>/dev/null; then
    info "k3s is already installed, skipping installation"
else
    info "Installing k3s (Traefik disabled)..."
    curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--disable traefik" sh -
    info "k3s installed"
fi

# ============================================================
# 3. Wait for k3s to be ready
# ============================================================
info "Waiting for k3s to be ready..."
RETRIES=30
until kubectl get nodes &>/dev/null; do
    RETRIES=$((RETRIES - 1))
    if [[ $RETRIES -le 0 ]]; then
        error "Timed out waiting for k3s to become ready"
    fi
    sleep 2
done

kubectl wait --for=condition=Ready node --all --timeout=120s
info "k3s is ready"

# ============================================================
# 4. Set up kubeconfig for the invoking user
# ============================================================
KUBECONFIG_DIR="${SUDO_HOME}/.kube"
KUBECONFIG_FILE="${KUBECONFIG_DIR}/config"

info "Setting up kubeconfig for user '${SUDO_USER}'..."
mkdir -p "${KUBECONFIG_DIR}"
cp /etc/rancher/k3s/k3s.yaml "${KUBECONFIG_FILE}"
chmod 600 "${KUBECONFIG_FILE}"
chown -R "$(id -u "${SUDO_USER}"):$(id -g "${SUDO_USER}")" "${KUBECONFIG_DIR}"

# Also export for the rest of this script
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

info "Kubeconfig written to ${KUBECONFIG_FILE}"

# ============================================================
# 5. Deploy local container registry
# ============================================================
if kubectl get deployment registry -n kube-system &>/dev/null; then
    info "Local registry deployment already exists, skipping"
else
    info "Deploying local container registry..."
    kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: registry
  namespace: kube-system
spec:
  replicas: 1
  selector:
    matchLabels:
      app: registry
  template:
    metadata:
      labels:
        app: registry
    spec:
      containers:
        - name: registry
          image: registry:2
          ports:
            - containerPort: 5000
          volumeMounts:
            - name: registry-data
              mountPath: /var/lib/registry
      volumes:
        - name: registry-data
          emptyDir: {}
---
apiVersion: v1
kind: Service
metadata:
  name: registry
  namespace: kube-system
spec:
  type: ClusterIP
  selector:
    app: registry
  ports:
    - port: 5000
      targetPort: 5000
EOF
    info "Registry deployed on ClusterIP"
fi

# Configure k3s registries mirror so registry.localhost:5000 resolves
REGISTRIES_FILE="/etc/rancher/k3s/registries.yaml"
if [[ ! -f "${REGISTRIES_FILE}" ]] || ! grep -q "${REGISTRY_NAME}" "${REGISTRIES_FILE}" 2>/dev/null; then
    info "Configuring k3s registry mirror for ${REGISTRY_NAME}:${REGISTRY_PORT}..."
    cat > "${REGISTRIES_FILE}" <<EOF
mirrors:
  "${REGISTRY_NAME}:${REGISTRY_PORT}":
    endpoint:
      - "http://registry.kube-system.svc.cluster.local:5000"
EOF
    info "Restarting k3s to pick up registry config..."
    systemctl restart k3s
    sleep 5
    kubectl wait --for=condition=Ready node --all --timeout=120s
fi

# Add /etc/hosts entry so docker push works
if ! grep -q "${REGISTRY_NAME}" /etc/hosts 2>/dev/null; then
    echo "127.0.0.1 ${REGISTRY_NAME}" >> /etc/hosts
    info "Added ${REGISTRY_NAME} to /etc/hosts"
fi

# ============================================================
# 6. Create namespaces
# ============================================================
info "Applying namespaces..."
kubectl apply -f "${SCRIPT_DIR}/namespaces.yaml"
info "Namespaces created"

# ============================================================
# 7. Print status and next steps
# ============================================================
echo ""
echo "============================================"
echo -e "${GREEN}  K3s Cluster Bootstrap Complete${NC}"
echo "============================================"
echo ""
kubectl get nodes -o wide
echo ""
kubectl get namespaces
echo ""
echo "Next steps:"
echo "  1. Source your kubeconfig:  export KUBECONFIG=${KUBECONFIG_FILE}"
echo "  2. Deploy Caddy ingress:   make setup-caddy"
echo "  3. Deploy logging stack:   make setup-logging"
echo "  4. Deploy apps:            make deploy-all"
echo ""
