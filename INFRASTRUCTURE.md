# Infrastructure Overview

Single-node **K3s** cluster on a Hetzner VPS (`142.132.204.173`), serving multiple web applications behind a reverse proxy with centralized authentication and observability.

**Domain:** `adrian-gruenther.de` (wildcard cert via Sectigo, also accessible via IP)

---

## Architecture

```
Internet
  |
  | HTTPS :443
  v
Caddy (reverse proxy, caddy-system namespace)
  |
  |-- forward_auth --> Authelia (authelia namespace)
  |                      |
  |                      v
  |                    SQLite (user DB, session DB)
  |
  |-- /checkmate          --> checkmate:3000       (apps)
  |-- /wandermind         --> wandermind:3001       (apps)
  |-- /eden               --> eden:3002             (apps)
  |-- /requirement_helper --> req-helper:3003       (apps)
  |-- /master-agent       --> master-agent:3004     (apps)
  |-- /ai-tooling         --> ai-tooling:3005       (apps)
  |-- /munchkin-td        --> munchkin-td:3006      (apps)
  |-- /citizen-dev        --> citizen-dev:3007       (apps)
  |-- /admin              --> admin-ui:3100          (apps)
  |-- /grafana            --> grafana:80             (logging)
  |-- /authelia           --> authelia:9091          (authelia)
  |-- /                   --> landing page (static)
  |
  v (stdout JSON access logs)
Promtail (DaemonSet) --> Loki --> Grafana
```

---

## Namespaces

| Namespace | Purpose |
|-----------|---------|
| `caddy-system` | Reverse proxy, TLS termination, landing page |
| `authelia` | Authentication (SSO portal) |
| `apps` | All application workloads |
| `logging` | Loki, Promtail, Grafana |
| `kube-system` | K3s system components, local container registry |

---

## Authentication & Access Control

**Provider:** Authelia 4.39.16 with file-based user store and SQLite session/storage backend.

**Auth flow:** Every request to Caddy triggers a `forward_auth` subrequest to Authelia. On success, Authelia returns `Remote-User`, `Remote-Groups`, `Remote-Name`, and `Remote-Email` headers which Caddy forwards to upstream services.

### Users

| Username | Groups | Access |
|----------|--------|--------|
| `admin` | `admins` | All services |
| `mhp_user` | `users` | wandermind, master-agent, ai-tooling only |

### Access Policy

| Policy | Services |
|--------|----------|
| **Admin-only** (group: `admins`) | checkmate, eden, requirement_helper, munchkin-td, citizen-dev, grafana, admin |
| **Shared** (groups: `admins` + `users`) | wandermind, master-agent, ai-tooling |
| **Bypass** (no auth) | /authelia (portal itself) |
| **Default** | deny |

**Auth level:** `one_factor` (username + password). TOTP 2FA is configured but not enforced on any route.

### Session Management

- Cookie-based, same-site: lax
- Inactivity timeout: 4 hours
- Absolute expiration: 24 hours
- Separate cookies for domain (`adrian-gruenther.de`) and IP (`142.132.204.173`) access

---

## TLS / HTTPS

- **Certificate:** Wildcard `*.adrian-gruenther.de` (Sectigo, valid until 2026-09-25)
- **Termination:** At Caddy (TLS cert + key mounted from Kubernetes Secret `caddy-tls`)
- **Internal traffic:** Plain HTTP between Caddy and backend services (cluster-internal)

### Security Headers

| Header | Value |
|--------|-------|
| Strict-Transport-Security | max-age=63072000; includeSubDomains; preload |
| X-Content-Type-Options | nosniff |
| X-Frame-Options | SAMEORIGIN |
| Referrer-Policy | strict-origin-when-cross-origin |
| X-XSS-Protection | 1; mode=block |
| Server | (removed) |

---

## Applications

### Overview

| App | Port | Image | Storage | External APIs | Access |
|-----|------|-------|---------|---------------|--------|
| checkmate | 3000 | registry.localhost:5000/checkmate:latest | SQLite (1Gi PVC) | - | admin |
| wandermind | 3001 | registry.localhost:5000/wandermind:latest | SQLite (1Gi PVC) | Groq | shared |
| eden | 3002 | registry.localhost:5000/eden:latest | SQLite (1Gi PVC) | - | admin |
| req-helper | 3003 | registry.localhost:5000/req-helper:latest | SQLite (1Gi PVC) | - | admin |
| master-agent | 3004/5001 | frontend + backend (2 containers) | - | Groq | shared |
| ai-tooling | 3005 | registry.localhost:5000/ai-tooling:latest | - | - | shared |
| munchkin-td | 3006 | registry.localhost:5000/munchkin-td:latest | - | - | admin |
| citizen-dev | 3007 | 4 containers (mock-sap, editor, runtime, portal) | - | - | admin |
| admin-ui | 3100 | registry.localhost:5000/admin-ui:latest | - | K8s API | admin |

All apps use `imagePullPolicy: Never` (images built locally and imported into containerd).

### Resource Limits (per container)

| Tier | Requests | Limits |
|------|----------|--------|
| Standard app | 128Mi / 100m CPU | 256Mi / 250m CPU |
| Lightweight (admin-ui, mock-sap, portal) | 64Mi / 50m CPU | 128Mi-256Mi / 100m-250m CPU |
| Authelia | 64Mi / 50m CPU | 256Mi / 250m CPU |

### Database Pattern

Apps using SQLite follow this pattern:
1. **PersistentVolumeClaim** (1Gi, `local-path` storage class) mounted at `/pvc` or `/app/data`
2. **Init container** runs Prisma migrations (`prisma migrate deploy` or `prisma db push`)
3. **Main container** uses the SQLite file via `DATABASE_URL=file:///path/to/dev.db`

---

## Observability

### Logging Stack

| Component | Type | Purpose |
|-----------|------|---------|
| **Promtail** | DaemonSet | Collects container logs from `/var/log/pods`, ships to Loki |
| **Loki** | StatefulSet (SingleBinary) | Log aggregation and querying (10Gi storage, 7-day retention) |
| **Grafana** | Deployment | Dashboards and log exploration |

### Log Collection

Promtail discovers all Kubernetes pods and attaches labels: `app`, `namespace`, `pod`, `container`.

For Caddy pods specifically, a pipeline stage parses JSON access logs and extracts:
- `status` (HTTP status code)
- `request_method` (GET, POST, etc.)
- `service` (extracted from URI path, e.g. `/checkmate/foo` -> `checkmate`)

### Grafana

- **URL:** `https://adrian-gruenther.de/grafana/`
- **Auth:** Proxy authentication via Authelia `Remote-User` header (auto sign-up, Admin role)
- **Datasource:** Loki (pre-provisioned)

### Dashboards

| Dashboard | UID | Content |
|-----------|-----|---------|
| **Apps Overview** | `apps-overview` | Per-service log volume, error rates, live log stream |
| **Access Logs** | `access-logs` | HTTP requests per service, status codes, errors, top paths, unique visitors, live access stream. Filterable by service and HTTP method. |

---

## Networking

### External

- **Single entry point:** TCP port 443 via Caddy `hostPort` binding
- **DNS:** `adrian-gruenther.de` and `www.adrian-gruenther.de` -> A record -> `142.132.204.173`

### Internal Service Mesh

All services use Kubernetes ClusterIP services. No service mesh or mTLS between pods. Communication is plain HTTP within the cluster network.

| Service | Namespace | ClusterIP Port |
|---------|-----------|----------------|
| caddy | caddy-system | 80 |
| authelia | authelia | 9091 |
| checkmate | apps | 3000 |
| wandermind | apps | 3001 |
| eden | apps | 3002 |
| req-helper | apps | 3003 |
| master-agent | apps | 3004 |
| ai-tooling | apps | 3005 |
| munchkin-td | apps | 3006 |
| citizen-dev | apps | 3007 |
| admin-ui | apps | 3100 |
| grafana | logging | 80 |
| loki | logging | 3100 |
| registry | kube-system | 5000 (NodePort 30500) |

---

## Storage

All persistent storage uses the `local-path` storage class (Rancher Local Path Provisioner, included with K3s). Data is stored on the host filesystem.

| PVC | Namespace | Size | Purpose |
|-----|-----------|------|---------|
| checkmate-data | apps | 1Gi | Checkmate SQLite DB |
| wandermind-data | apps | 1Gi | Wandermind SQLite DB |
| eden-data | apps | 1Gi | Eden SQLite DB |
| req-helper-data | apps | 1Gi | Requirement Helper SQLite DB |
| authelia-data | authelia | 1Gi | Authelia SQLite DB + notification file |
| loki storage | logging | 10Gi | Log data (7-day retention) |
| grafana storage | logging | 1Gi | Grafana config/dashboards |

---

## Secrets

| Secret | Namespace | Keys | Used By |
|--------|-----------|------|---------|
| `caddy-tls` | caddy-system | tls.crt, tls.key | Caddy (TLS termination) |
| `app-secrets` | apps | GROQ_API_KEY, OPENAI_API_KEY, ANTHROPIC_API_KEY, INTERNAL_API_SECRET | wandermind, master-agent |
| `caddy-basic-auth` | caddy-system | (legacy, unused since Authelia migration) | - |

Authelia secrets (JWT secret, session secret, storage encryption key) are embedded in the Authelia configuration file, mounted via ConfigMap.

---

## Container Registry

A local Docker registry runs inside the cluster:

- **Image:** `registry:2`
- **Internal:** `registry.localhost:5000` (via /etc/hosts + k3s registries.yaml mirror)
- **NodePort:** `localhost:30500`
- **Storage:** emptyDir (non-persistent, images must be re-pushed after registry pod restart)

### Build & Deploy Flow

```
docker build -t registry.localhost:5000/<app>:latest .
docker push localhost:30500/<app>:latest        # push via NodePort
docker save ... | k3s ctr images import -        # import into containerd
kubectl rollout restart deployment <app> -n apps
```

---

## Deployment Scripts

| Script | Purpose |
|--------|---------|
| `k8s/bootstrap.sh` | Install K3s, deploy registry, create namespaces |
| `k8s/deploy-app.sh` | Build, push, and deploy a single app |
| `k8s/deploy-logging.sh` | Helm install Loki + Promtail + Grafana |
| `k8s/Makefile` | Orchestration targets (`build-all`, `push-all`, `deploy-all`, `setup-logging`, `setup-caddy`) |

---

## File Structure

```
k8s/
  namespaces.yaml
  bootstrap.sh
  deploy-app.sh
  deploy-logging.sh
  Makefile
  caddy-system/
    deployment.yaml
    configmap.yaml          # Caddyfile
    service.yaml
    secret.yaml
  authelia/
    deployment.yaml         # Deployment + PVC + Service
    configuration.yaml      # Authelia config
    users.yaml              # User database
  apps/
    secrets.yaml            # Shared API keys
    checkmate/              # deployment, service, pvc
    wandermind/             # deployment, service, pvc
    eden/                   # deployment, service, pvc
    req-helper/             # deployment, service, pvc
    master-agent/           # deployment (2 containers), service
    ai-tooling/             # deployment, service
    munchkin-td/            # deployment, service
    citizen-dev/            # deployment (4 containers), service
    admin-ui/               # deployment, service
  logging/
    loki-values.yaml
    promtail-values.yaml
    grafana-values.yaml
    grafana-dashboards/
      apps-overview.json
      access-logs.json
  landing/
    index.html
```
