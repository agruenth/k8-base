#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Deploy App Helper
# Usage: ./deploy-app.sh <app-name>
# Builds, pushes, and deploys a single application.
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REGISTRY="registry.localhost:5000"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }
step()  { echo -e "${CYAN}[STEP]${NC}  $*"; }

if [[ $# -lt 1 ]]; then
    error "Usage: $0 <app-name>"
fi

APP="$1"
PARENT_DIR="$(dirname "${SCRIPT_DIR}")"

# ============================================================
# Map app names to source directories
# ============================================================
declare -A APP_DIR_MAP=(
    [checkmate]="checkmate"
    [wandermind]="wandermind"
    [eden]="EDEN"
    [req-helper]="requirement_helper"
    [master-agent]="master-agent"
    [ai-tooling]="ai-tooling"
    [munchkin-td]="munchkin-td"
    [citizen-dev]="citizen-dev-platform"
    [polisim]="polisim"
    [agentic-offering]="agentic-offering"
    [profile]="profile"
    [learning-games]="learning-games"
    [companion]="companion"
    [admin-ui]="admin-ui"
)

if [[ -z "${APP_DIR_MAP[$APP]+x}" ]]; then
    error "Unknown app: ${APP}. Valid apps: ${!APP_DIR_MAP[*]}"
fi

SRC_DIR="${PARENT_DIR}/${APP_DIR_MAP[$APP]}"

if [[ ! -d "${SRC_DIR}" ]]; then
    error "Source directory not found: ${SRC_DIR}"
fi

echo ""
echo "============================================"
echo -e "${CYAN}  Deploying: ${APP}${NC}"
echo "============================================"
echo ""

# ============================================================
# Build
# ============================================================
step "Building Docker image(s) for ${APP}..."

case "${APP}" in
    master-agent)
        docker build -t "${REGISTRY}/master-agent-frontend:latest" -f "${SRC_DIR}/frontend/Dockerfile" "${SRC_DIR}/frontend"
        docker build -t "${REGISTRY}/master-agent-backend:latest"  -f "${SRC_DIR}/backend/Dockerfile"  "${SRC_DIR}/backend"
        info "Built master-agent-frontend and master-agent-backend"
        ;;
    citizen-dev)
        docker build -t "${REGISTRY}/citizen-dev-base:latest"     -f "${SRC_DIR}/docker/Dockerfile.base"     "${SRC_DIR}"
        docker build -t "${REGISTRY}/citizen-dev-run:latest"      -f "${SRC_DIR}/docker/Dockerfile.run"      "${SRC_DIR}"
        docker build -t "${REGISTRY}/citizen-dev-edit:latest"     -f "${SRC_DIR}/docker/Dockerfile.edit"     "${SRC_DIR}"
        docker build -t "${REGISTRY}/citizen-dev-mock-sap:latest" -f "${SRC_DIR}/docker/Dockerfile.mock-sap" "${SRC_DIR}"
        info "Built citizen-dev-base, citizen-dev-run, citizen-dev-edit, citizen-dev-mock-sap"
        ;;
    eden)
        docker build -t "${REGISTRY}/eden:latest" -f "${SRC_DIR}/web/Dockerfile" "${SRC_DIR}/web"
        info "Built eden"
        ;;
    *)
        docker build -t "${REGISTRY}/${APP}:latest" "${SRC_DIR}"
        info "Built ${APP}"
        ;;
esac

# ============================================================
# Push
# ============================================================
step "Pushing image(s) to local registry..."

case "${APP}" in
    master-agent)
        docker push "${REGISTRY}/master-agent-frontend:latest"
        docker push "${REGISTRY}/master-agent-backend:latest"
        ;;
    citizen-dev)
        docker push "${REGISTRY}/citizen-dev-base:latest"
        docker push "${REGISTRY}/citizen-dev-run:latest"
        docker push "${REGISTRY}/citizen-dev-edit:latest"
        docker push "${REGISTRY}/citizen-dev-mock-sap:latest"
        ;;
    *)
        docker push "${REGISTRY}/${APP}:latest"
        ;;
esac

info "Push complete"

# ============================================================
# Deploy
# ============================================================
MANIFESTS_DIR="${SCRIPT_DIR}/apps/${APP}"

if [[ ! -d "${MANIFESTS_DIR}" ]]; then
    error "No Kubernetes manifests found at ${MANIFESTS_DIR}"
fi

step "Applying Kubernetes manifests from ${MANIFESTS_DIR}..."
kubectl apply -f "${MANIFESTS_DIR}/"
info "Manifests applied"

# Restart deployments to pick up new images
step "Restarting deployment(s)..."
for deploy in $(kubectl get deployments -n apps -l "app=${APP}" -o name 2>/dev/null; kubectl get deployments -n apps -l "app.kubernetes.io/name=${APP}" -o name 2>/dev/null); do
    kubectl rollout restart "${deploy}" -n apps
done
# Also try direct name match
kubectl rollout restart "deployment/${APP}" -n apps 2>/dev/null || true

info "Deployment complete"

echo ""
echo "============================================"
echo -e "${GREEN}  ${APP} deployed successfully${NC}"
echo "============================================"
echo ""
kubectl get pods -n apps -l "app=${APP}" 2>/dev/null || kubectl get pods -n apps | grep "${APP}" || true
echo ""
