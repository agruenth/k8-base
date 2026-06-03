#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Deploy Logging Stack (Loki + Promtail + Grafana)
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# ============================================================
# Pre-flight checks
# ============================================================
command -v kubectl &>/dev/null || error "kubectl not found. Run bootstrap.sh first."
command -v helm &>/dev/null    || error "helm not found. Install helm first: https://helm.sh/docs/intro/install/"

# Ensure logging namespace exists
if ! kubectl get namespace logging &>/dev/null; then
    info "Creating logging namespace..."
    kubectl create namespace logging
fi

# ============================================================
# 1. Add / update Grafana Helm repo
# ============================================================
info "Adding Grafana Helm repository..."
helm repo add grafana https://grafana.github.io/helm-charts 2>/dev/null || true
helm repo update grafana
info "Helm repo ready"

# ============================================================
# 2. Install Loki
# ============================================================
info "Installing Loki..."
helm upgrade --install loki grafana/loki \
    -n logging \
    -f "${SCRIPT_DIR}/logging/loki-values.yaml" \
    --wait --timeout 5m
info "Loki installed"

# ============================================================
# 3. Install Promtail
# ============================================================
info "Installing Promtail..."
helm upgrade --install promtail grafana/promtail \
    -n logging \
    -f "${SCRIPT_DIR}/logging/promtail-values.yaml" \
    --wait --timeout 5m
info "Promtail installed"

# ============================================================
# 4. Install Grafana
# ============================================================
info "Installing Grafana..."
helm upgrade --install grafana grafana/grafana \
    -n logging \
    -f "${SCRIPT_DIR}/logging/grafana-values.yaml" \
    --wait --timeout 5m
info "Grafana installed"

# ============================================================
# 5. Apply Grafana dashboard ConfigMaps
# ============================================================
DASHBOARDS_DIR="${SCRIPT_DIR}/logging/grafana-dashboards"
if [[ -d "${DASHBOARDS_DIR}" ]] && ls "${DASHBOARDS_DIR}"/*.yaml &>/dev/null 2>&1; then
    info "Applying Grafana dashboard ConfigMaps..."
    kubectl apply -n logging -f "${DASHBOARDS_DIR}/"
    info "Dashboards applied"
else
    warn "No dashboard ConfigMaps found in ${DASHBOARDS_DIR}, skipping"
fi

# ============================================================
# 6. Wait for all pods to be ready
# ============================================================
info "Waiting for logging pods to be ready..."
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=loki     -n logging --timeout=180s 2>/dev/null || warn "Some Loki pods not ready yet"
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=promtail -n logging --timeout=180s 2>/dev/null || warn "Some Promtail pods not ready yet"
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=grafana  -n logging --timeout=180s 2>/dev/null || warn "Some Grafana pods not ready yet"

# ============================================================
# 7. Print access info
# ============================================================
GRAFANA_PASSWORD=$(kubectl get secret grafana -n logging -o jsonpath="{.data.admin-password}" 2>/dev/null | base64 -d 2>/dev/null || echo "<not yet available>")

echo ""
echo "============================================"
echo -e "${GREEN}  Logging Stack Deployed${NC}"
echo "============================================"
echo ""
kubectl get pods -n logging
echo ""
echo "Grafana access:"
echo "  URL:      http://grafana.localhost (via Caddy ingress)"
echo "  User:     admin"
echo "  Password: ${GRAFANA_PASSWORD}"
echo ""
echo "Port-forward for direct access:"
echo "  kubectl port-forward -n logging svc/grafana 3000:80"
echo "  Then open http://localhost:3000"
echo ""
