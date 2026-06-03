#!/usr/bin/env bash
# setup.sh — One-shot setup script for a new server.
# Run after bootstrap.sh. Copies secret templates, prompts for real values,
# then applies all k8s resources in order.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KUBECTL="KUBECONFIG=$HOME/.kube/config kubectl"

# ─── Colour helpers ───────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BOLD='\033[1m'; NC='\033[0m'
info()    { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
prompt()  { echo -e "${BOLD}$*${NC}"; }

# ─── Prerequisite check ───────────────────────────────────────────────────────
check_prereqs() {
  local missing=0
  for cmd in kubectl helm docker; do
    if ! command -v "$cmd" &>/dev/null; then
      warn "Missing: $cmd"
      missing=1
    fi
  done
  if ! sudo k3s kubectl get nodes &>/dev/null; then
    warn "k3s not running — run ./bootstrap.sh first"
    missing=1
  fi
  [[ $missing -eq 0 ]] || { echo -e "${RED}Fix missing prerequisites before continuing.${NC}"; exit 1; }
  info "Prerequisites OK"
}

# ─── Replace a placeholder token in a file interactively ─────────────────────
fill_placeholder() {
  local file="$1" token="$2" description="$3"
  if grep -q "$token" "$file"; then
    prompt "  → $description:"
    read -r -s value
    echo
    sed -i "s|$token|$value|g" "$file"
  fi
}

# ─── Copy example → real and fill in secrets ─────────────────────────────────
prepare_secrets() {
  local examples=(
    "caddy-system/secrets.example.yaml:caddy-system/secrets.yaml"
    "authelia/secrets.example.yaml:authelia/secrets.yaml"
    "apps/secrets.example.yaml:apps/secrets.yaml"
  )

  echo
  echo -e "${BOLD}=== Secret Configuration ===${NC}"
  echo "Fill in each secret. Input is hidden. Press Enter to confirm each value."
  echo

  for pair in "${examples[@]}"; do
    local src="${SCRIPT_DIR}/${pair%%:*}"
    local dst="${SCRIPT_DIR}/${pair##*:}"

    if [[ -f "$dst" ]]; then
      warn "$(basename "$dst") already exists — skipping (delete it to re-fill)"
      continue
    fi

    cp "$src" "$dst"
    info "Created $(basename "$dst")"

    case "$dst" in
      *caddy-system/secrets.yaml)
        echo "Paste your TLS certificate (PEM, end with a line containing only 'END'):"
        prompt "  → TLS certificate (tls.crt):"
        local cert="" line
        while IFS= read -r line; do
          cert+="$line\n"
          [[ "$line" == *"END CERTIFICATE"* ]] && break
        done
        sed -i "s|REPLACE_WITH_TLS_CERT_PEM|$cert|" "$dst"

        prompt "  → TLS private key (tls.key):"
        local key="" kline
        while IFS= read -r kline; do
          key+="$kline\n"
          [[ "$kline" == *"END"*"PRIVATE KEY"* ]] && break
        done
        sed -i "s|REPLACE_WITH_TLS_KEY_PEM|$key|" "$dst"
        ;;

      *authelia/secrets.yaml)
        fill_placeholder "$dst" "REPLACE_WITH_JWT_SECRET"        "Authelia JWT secret (random string, min 32 chars)"
        fill_placeholder "$dst" "REPLACE_WITH_SESSION_SECRET"    "Authelia session secret (random string, min 32 chars)"
        fill_placeholder "$dst" "REPLACE_WITH_ENCRYPTION_KEY"    "Authelia storage encryption key (random string, min 32 chars)"
        ;;

      *apps/secrets.yaml)
        fill_placeholder "$dst" "REPLACE_WITH_GROQ_API_KEY"      "GROQ API key"
        fill_placeholder "$dst" "REPLACE_WITH_OPENAI_API_KEY"    "OpenAI API key"
        fill_placeholder "$dst" "REPLACE_WITH_ANTHROPIC_API_KEY" "Anthropic API key"
        fill_placeholder "$dst" "REPLACE_WITH_INTERNAL_SECRET"   "Internal API secret (any random string)"
        ;;
    esac
  done
}

# ─── Domain configuration ─────────────────────────────────────────────────────
configure_domain() {
  echo
  echo -e "${BOLD}=== Domain Configuration ===${NC}"
  echo "The Caddy configmap and Authelia config reference the original domain."
  echo "Current values: adrian-gruenther.de / 142.132.204.173"
  echo
  prompt "Enter your domain (e.g. example.com) [leave blank to keep original]:"
  read -r new_domain
  prompt "Enter your server IP [leave blank to keep original]:"
  read -r new_ip

  if [[ -n "$new_domain" ]]; then
    sed -i "s|adrian-gruenther\.de|$new_domain|g" \
      "$SCRIPT_DIR/caddy-system/configmap.yaml" \
      "$SCRIPT_DIR/authelia/configuration.yaml"
    info "Domain updated to $new_domain"
  fi
  if [[ -n "$new_ip" ]]; then
    sed -i "s|142\.132\.204\.173|$new_ip|g" \
      "$SCRIPT_DIR/caddy-system/configmap.yaml" \
      "$SCRIPT_DIR/authelia/configuration.yaml"
    info "IP updated to $new_ip"
  fi
}

# ─── Apply resources ──────────────────────────────────────────────────────────
apply_resources() {
  echo
  echo -e "${BOLD}=== Applying Kubernetes Resources ===${NC}"

  info "1/5 Namespaces"
  eval "$KUBECTL apply -f $SCRIPT_DIR/namespaces.yaml"

  info "2/5 Caddy (reverse proxy)"
  eval "$KUBECTL apply -f $SCRIPT_DIR/caddy-system/"

  info "3/5 Authelia (authentication)"
  eval "$KUBECTL apply -f $SCRIPT_DIR/authelia/"

  info "4/5 Apps"
  eval "$KUBECTL apply -f $SCRIPT_DIR/apps/network-policy.yaml"
  eval "$KUBECTL apply -f $SCRIPT_DIR/apps/secrets.yaml"
  for app_dir in "$SCRIPT_DIR"/apps/*/; do
    [[ -d "$app_dir" ]] && eval "$KUBECTL apply -f $app_dir" 2>/dev/null || true
  done

  info "5/5 Logging (Loki + Promtail + Grafana via Helm)"
  echo "  Run ./deploy-logging.sh to install the logging stack (requires Helm)."

  echo
  info "Done! Check status with: KUBECONFIG=\$HOME/.kube/config kubectl get pods -A"
}

# ─── Main ─────────────────────────────────────────────────────────────────────
echo -e "${BOLD}k8-base cluster setup${NC}"
echo "=========================================="
check_prereqs
prepare_secrets
configure_domain
apply_resources
