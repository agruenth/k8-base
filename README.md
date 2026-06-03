# k8-base

Complete Kubernetes infrastructure for a single-node k3s cluster. Includes:

- **Caddy** reverse proxy with TLS termination and rate limiting
- **Authelia** authentication gateway (forward-auth for all apps)
- **Loki + Promtail + Grafana** observability stack
- **20+ Next.js app deployments** behind auth
- **Boilerplate** for scaffolding new apps (`boilerplate/`)

---

## Architecture

```
Internet → HTTPS :443 → Caddy (hostPort)
  → forward_auth → Authelia (user/group check)
  → uri strip_prefix → reverse_proxy → App (ClusterIP)

Logs: App stdout → Promtail (DaemonSet) → Loki → Grafana
```

All apps run in the `apps` namespace. Caddy handles TLS. Authelia manages users and access policies via `authelia/configuration.yaml` and `authelia/users.yaml`.

---

## Setting Up a New Server

### Prerequisites

- Ubuntu/Debian VPS (single node)
- Docker installed: `curl -fsSL https://get.docker.com | sh`
- Helm installed: `curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash`
- A domain pointing to the server's IP
- A TLS certificate + key (see [TLS Certificate](#tls-certificate))

### Step 1: Bootstrap k3s

```sh
git clone git@github.com:agruenth/k8-base.git
cd k8-base
./bootstrap.sh
```

This installs k3s (with Traefik disabled), sets up kubeconfig, and deploys a local container registry.

### Step 2: Configure and apply

```sh
./setup.sh
```

The script will:
1. Check prerequisites
2. Prompt for all secrets (TLS cert/key, API keys, Authelia secrets) — input is hidden
3. Ask for your domain + IP to update the Caddy/Authelia configs
4. Apply namespaces, Caddy, Authelia, and all app manifests

### Step 3: Deploy logging stack

```sh
./deploy-logging.sh
```

Installs Loki + Promtail + Grafana via Helm.

### Step 4: Build and deploy app images

App images are **not** stored in this repo — they live in the source repos under `/REPOS_PRIVAT/<app>`. On a new server, build and import each app:

```sh
# Build + import a single app
./deploy-app.sh <app-name>

# Or use make to build all
make build-all
make push-all
```

---

## TLS Certificate

Caddy expects a TLS cert + key as a Kubernetes Secret (`caddy-tls` in `caddy-system`).

**Option A: Let's Encrypt via certbot (recommended)**

```sh
sudo apt install certbot
sudo certbot certonly --standalone -d <your-domain>
# Cert: /etc/letsencrypt/live/<domain>/fullchain.pem
# Key:  /etc/letsencrypt/live/<domain>/privkey.pem
```

Then paste the PEM contents when `setup.sh` prompts for them.

**Option B: Self-signed (for testing)**

```sh
openssl req -x509 -newkey rsa:4096 -keyout key.pem -out cert.pem -days 365 -nodes \
  -subj "/CN=<your-domain>"
```

---

## Domain and IP Substitution

Two files are hardcoded with the original domain/IP. `setup.sh` handles this automatically, but for manual edits:

| File | What to change |
|------|---------------|
| `caddy-system/configmap.yaml` | TLS hostname, `tls` directive |
| `authelia/configuration.yaml` | `domain:` in session and cookies config |

---

## Secrets

**Never commit real secrets.** Each secrets file has an `.example.yaml` counterpart:

| Example file | Real file (gitignored) | Contents |
|---|---|---|
| `caddy-system/secrets.example.yaml` | `caddy-system/secrets.yaml` | TLS cert + key |
| `authelia/secrets.example.yaml` | `authelia/secrets.yaml` | JWT/session/encryption keys |
| `apps/secrets.example.yaml` | `apps/secrets.yaml` | API keys (Groq, OpenAI, Anthropic) |

`setup.sh` copies examples → real files and fills in values interactively.

**Generating Authelia secrets:**
```sh
openssl rand -hex 32   # run 3 times for jwt_secret, session_secret, encryption_key
```

---

## Adding a New App

See **`boilerplate/agent.md`** for the complete 13-step deployment playbook.

**Quick summary:**

```sh
# 1. Scaffold
cp -r boilerplate/ /REPOS_PRIVAT/<app-name>
cd /REPOS_PRIVAT/<app-name>
rm -rf .git node_modules .next

# 2. Configure
#    - package.json: name + port
#    - next.config.ts: basePath → /exp/<app-name>
#    - app/layout.tsx: title/description
npm install

# 3. Build + import
docker build --no-cache -t registry.localhost:5000/<app-name>:latest .
docker save registry.localhost:5000/<app-name>:latest | sudo k3s ctr images import -

# 4. Create k8s manifests
mkdir -p apps/<app-name>
# Create apps/<app-name>/deployment.yaml and service.yaml
# See boilerplate/agent.md Step 5 for the exact templates

# 5. Deploy
KUBECONFIG=$HOME/.kube/config kubectl apply -f apps/<app-name>/

# 6. Add Authelia access rule (boilerplate/agent.md Step 7)
# 7. Add Caddy route (boilerplate/agent.md Step 8)
# 8. Add to Makefile APPS list and deploy-app.sh APP_DIR_MAP
```

Critical gotchas (all in `boilerplate/agent.md`):
- `imagePullPolicy: Never` — images are imported into containerd, not pulled from registry
- Readiness probe path must be `/`, not `/<base-path>/`
- Caddy uses `hostPort: 443` — scale down/up instead of rolling restart when updating config

---

## Day-to-Day Operations

```sh
# Status
KUBECONFIG=$HOME/.kube/config kubectl get pods -A

# Restart an app
KUBECONFIG=$HOME/.kube/config kubectl rollout restart deployment/<app> -n apps

# Tail logs
KUBECONFIG=$HOME/.kube/config kubectl logs -n apps -l app=<app> -f

# Rebuild and redeploy an app
./deploy-app.sh <app-name>

# Or via make
make all-<app-name>     # build + push + deploy
make restart-<app-name> # rollout restart only
make logs-<app-name>    # tail logs
make status             # show all pods/svcs/pvcs
```

---

## Namespaces

| Namespace | Purpose |
|-----------|---------|
| `caddy-system` | Caddy reverse proxy, TLS secret |
| `authelia` | Authelia auth gateway |
| `apps` | All application workloads |
| `logging` | Loki, Promtail, Grafana |

---

## Users and Access

Users are defined in `authelia/users.yaml`. Passwords are argon2id hashes.

Access rules are in `authelia/configuration.yaml` under `access_control.rules`. The Admin UI at `/admin/` can manage users and groups via the web interface (preferred over manual YAML edits).

**Generate a new password hash:**
```sh
docker run --rm authelia/authelia:latest authelia crypto hash generate argon2 --password 'yourpassword'
```
