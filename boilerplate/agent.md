# Deployment Agent — New App to K8s Cluster

This document is an operational playbook for deploying a new Next.js application
to the K8s cluster at `142.132.204.173`. Follow every step in order.
**Do not skip steps. Every step exists because skipping it broke a deployment.**

## Architecture Overview

```
Internet → HTTPS :443 → Caddy (hostPort)
  → forward_auth → Authelia (user/group check)
  → uri strip_prefix → reverse_proxy → App (ClusterIP)

Logs: App stdout → Promtail (DaemonSet) → Loki → Grafana
```

All apps run in the `apps` namespace behind Authelia forward_auth.
Caddy handles TLS termination with a wildcard cert. No basic auth — Authelia
manages users, groups, and access policies.

## Prerequisites

- k3s cluster running (verify: `KUBECONFIG=$HOME/.kube/config kubectl get nodes`)
- Caddy ingress deployed in `caddy-system` namespace
- Authelia deployed in `authelia` namespace
- Loki + Promtail + Grafana deployed in `logging` namespace
- Docker installed on the host
- Local registry running at `registry.localhost:5000`
- **kubectl** uses `KUBECONFIG=$HOME/.kube/config kubectl` (the claude_worker user has a kubeconfig copy)

## Inputs (gather before starting)

| Variable | Description | Example |
|----------|-------------|---------|
| `APP_NAME` | Lowercase, hyphenated identifier | `my-new-app` |
| `PORT` | Port the app listens on | `3020` |
| `ENV` | Environment prefix: `exp` (experimental) or `prod` (production) | `exp` |
| `BASE_PATH` | Full URL prefix: `/<ENV>/<APP_NAME>` | `/exp/my-new-app` |
| `SOURCE_DIR` | Directory name under `/REPOS_PRIVAT/` | `my-new-app` |
| `AUTH_GROUPS` | Authelia groups: `admins` only, or `admins` + `users` | `admins` |

**Environment routing pattern:**
All apps use the same routing: `import app_route /<ENV>/<APP_NAME> ...`
- Experimental apps: `/exp/<APP_NAME>` — dev/testing, may break
- Production apps: `/prod/<APP_NAME>` — stable, user-facing
- Infrastructure (grafana, admin, authelia): no prefix, shared across environments

The `app_route` Caddy snippet handles: Authelia forward_auth → strip prefix → reverse_proxy.
Next.js `basePath` must be set to the full prefix (e.g., `/exp/my-new-app`).

For production deployments of an existing experimental app, use a `-prod` suffix for the
k8s deployment name and service (e.g., `my-app-prod.apps.svc.cluster.local`).

---

## Step 1: Scaffold from boilerplate

```bash
cp -r /REPOS_PRIVAT/nextjs-caddy-boilerplate /REPOS_PRIVAT/<SOURCE_DIR>
cd /REPOS_PRIVAT/<SOURCE_DIR>
rm -rf .git node_modules .next
```

**IMPORTANT:** Verify ALL boilerplate files were copied. The `cp -r` can fail silently
if the target directory already exists (it merges instead of replacing). Check that
these files exist in the new directory:
```bash
ls -la Dockerfile .dockerignore Caddyfile.template middleware.ts lib/logger.ts
```
If any are missing, copy them individually from the boilerplate.

Update these files:
- `package.json` — set `"name": "<APP_NAME>"`, port in `dev` and `start` scripts to `<PORT>`
- `next.config.ts` — set `basePath: "/<ENV>/<APP_NAME>"` (e.g., `/exp/my-new-app`)
- `app/layout.tsx` — set `title` and `description` in metadata
- `Caddyfile.template` — replace `/exp/my-app` with `/<ENV>/<APP_NAME>` and port `3010` with `<PORT>`

Then install dependencies and **regenerate the lockfile**:
```bash
npm install
```

**CRITICAL:** Do NOT skip `npm install`. The boilerplate's `package-lock.json` is for
the boilerplate's dependencies. After you add new dependencies, the lockfile must be
regenerated or `npm ci` will fail inside Docker with "package.json and package-lock.json
are in sync" errors.

## Step 2: Integrate the logger

The boilerplate ships with a structured logger at `lib/logger.ts`. Use it everywhere:

```typescript
import { logger } from "@/lib/logger";
const log = logger.child("my-module");

// In server actions, API routes, lib functions:
log.info("Processing request", { userId: "abc" });
log.error("Failed to fetch data", { err: error.message, endpoint: "/api/foo" });
```

**Rules:**
- Never use bare `console.log()` — always use the logger
- Always pass structured data as the second argument (key-value object)
- Use `.child("context")` to create scoped loggers per module/route
- Set `APP_NAME` env var in the K8s deployment to match the k8s `app` label

**Log levels:**
| Level | When to use |
|-------|-------------|
| `debug` | Verbose diagnostic info, loop iterations, intermediate values |
| `info` | Normal operations: startup, request served, job completed |
| `warn` | Recoverable issues: retry, fallback used, deprecated API called |
| `error` | Failures: unhandled exception, external service down, data corruption |

**Request logging** is automatic via `middleware.ts` (Edge Runtime) — every HTTP request is logged as a JSON line with method, path, status, and latency.

## Step 3: Build the Docker image

```bash
cd /REPOS_PRIVAT/<SOURCE_DIR>
docker build --no-cache -t registry.localhost:5000/<APP_NAME>:latest .
```

**NOTE:** Use `--no-cache` when you need to ensure fresh builds (e.g., after changing
seed data or dependencies). Omit it for faster iterative builds when only source changed.

**Known issues and fixes:**

### `npm ci` fails: "package.json and package-lock.json are in sync"
You added dependencies but didn't regenerate the lockfile. Run `npm install` locally
first (Step 1), then rebuild.

### CSS / JS assets load without the path prefix (broken styling in production)
`next start` reads `next.config.ts` at runtime to apply `assetPrefix`. If the file
is missing from the Docker image the prefix is silently ignored and all assets load
from `/_next/...` instead of `/<ENV>/<APP_NAME>/_next/...`.

The boilerplate Dockerfile already handles this:
```dockerfile
COPY --from=builder /app/next.config.ts ./
```
If you replaced the Dockerfile, ensure `next.config.ts` is copied to the runner stage.

### Build context is huge (hundreds of MB)
Check that `.dockerignore` exists and contains at minimum:
```
node_modules
.git
```

## Step 4: Import image into k3s containerd

k3s uses containerd, NOT Docker. Images built with `docker build` are in Docker's
storage but invisible to k3s. You **must** import them into containerd.

```bash
docker save registry.localhost:5000/<APP_NAME>:latest | sudo k3s ctr images import -
```

Verify the image is available to k3s:
```bash
sudo crictl images | grep <APP_NAME>
```

**Why not push to the registry?** The in-cluster registry at `registry.localhost:5000`
uses HTTP internally. Docker defaults to HTTPS and will fail with "http: server gave
HTTP response to HTTPS client". The `docker save | k3s ctr images import` pipeline
bypasses the registry entirely and is the most reliable method.

## Step 5: Create K8s manifests

```bash
mkdir -p /REPOS_PRIVAT/k8s/apps/<APP_NAME>
```

### deployment.yaml

Create `/REPOS_PRIVAT/k8s/apps/<APP_NAME>/deployment.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: <APP_NAME>
  namespace: apps
  labels:
    app: <APP_NAME>
spec:
  replicas: 1
  selector:
    matchLabels:
      app: <APP_NAME>
  template:
    metadata:
      labels:
        app: <APP_NAME>
    spec:
      containers:
        - name: <APP_NAME>
          imagePullPolicy: Never
          image: registry.localhost:5000/<APP_NAME>:latest
          ports:
            - containerPort: <PORT>
              protocol: TCP
          command: ["npm", "start", "--", "--port", "<PORT>"]
          env:
            - name: APP_NAME
              value: "<APP_NAME>"
            - name: NODE_ENV
              value: "production"
            - name: LOG_LEVEL
              value: "info"
          resources:
            requests:
              memory: "128Mi"
              cpu: "100m"
            limits:
              memory: "256Mi"
              cpu: "250m"
          readinessProbe:
            httpGet:
              port: <PORT>
              path: /<ENV>/<APP_NAME>
            initialDelaySeconds: 5
            periodSeconds: 10
          livenessProbe:
            httpGet:
              port: <PORT>
              path: /<ENV>/<APP_NAME>
            initialDelaySeconds: 10
            periodSeconds: 30
```

**CRITICAL NOTES:**
- `imagePullPolicy: Never` — because we imported the image directly into containerd
  (Step 4). Do NOT use `IfNotPresent` — k3s will try to pull from the registry and
  fail because the registry uses HTTP.
- `readinessProbe.path: /` — **always use `/`, NOT `/<BASE_PATH>/`**. Next.js apps
  with `basePath` serve their content at `/` when accessed directly (the basePath is
  for URL rewriting by the reverse proxy). Using `/<BASE_PATH>/` will return 404 and
  the pod will never become ready.
- `command: ["npm", "start", "--", "--port", "<PORT>"]` — overrides the port from
  package.json to match the K8s service port.

### service.yaml

Create `/REPOS_PRIVAT/k8s/apps/<APP_NAME>/service.yaml`:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: <APP_NAME>
  namespace: apps
  labels:
    app: <APP_NAME>
spec:
  type: ClusterIP
  selector:
    app: <APP_NAME>
  ports:
    - port: <PORT>
      targetPort: <PORT>
      protocol: TCP
```

**SQLite + Prisma:** The Dockerfile automatically detects `prisma/schema.prisma` and bakes
a seeded database into the image (`prisma db push` + `npm run db:seed`). This keeps dev
and k8s databases in sync from the same `prisma/seed.ts` source of truth. No PVC needed
for read-only data. If the app needs write persistence, also create a `pvc.yaml` — see
`k8s/apps/checkmate/` for reference.

## Step 6: Deploy to cluster

```bash
KUBECONFIG=$HOME/.kube/config kubectl apply -f /REPOS_PRIVAT/k8s/apps/<APP_NAME>/
```

Verify:
```bash
KUBECONFIG=$HOME/.kube/config kubectl get pods -n apps -l app=<APP_NAME>
KUBECONFIG=$HOME/.kube/config kubectl logs -n apps -l app=<APP_NAME> --tail=20
```

Wait for `1/1 Running` before proceeding. If the pod shows `ErrImageNeverPull`,
you forgot Step 4 (import into containerd). If it shows `CrashLoopBackOff`, check
logs for the error.

## Step 7: Add Authelia access policy

**Do this BEFORE adding the Caddy route.** If the Caddy route exists but Authelia
has no policy, all requests will get 403 Forbidden.

**Option A: Via Admin UI (preferred)**

Go to `https://adrian-gruenther.de/admin/users`, switch to the **Groups** tab,
and edit the group that should have access to the new app. The admin UI will update
the Authelia config and restart it automatically.

**Option B: Manual edit**

Edit `/REPOS_PRIVAT/k8s/authelia/configuration.yaml` — add a new rule under
`access_control.rules`:

**Admin-only:**
```yaml
    - domain: ['adrian-gruenther.de', '142.132.204.173']
      resources: ['^/<ENV>/<APP_NAME>([/?].*)?$']
      policy: one_factor
      subject:
        - 'group:admins'
```

**Shared (admins + users):**
```yaml
    - domain: ['adrian-gruenther.de', '142.132.204.173']
      resources: ['^/<ENV>/<APP_NAME>([/?].*)?$']
      policy: one_factor
      subject:
        - 'group:admins'
        - 'group:users'
```

Update the configmap and restart Authelia:
```bash
KUBECONFIG=$HOME/.kube/config kubectl create configmap authelia-config \
  --from-file=configuration.yaml=/REPOS_PRIVAT/k8s/authelia/configuration.yaml \
  -n authelia --dry-run=client -o yaml | KUBECONFIG=$HOME/.kube/config kubectl apply -f -
KUBECONFIG=$HOME/.kube/config kubectl rollout restart deployment/authelia -n authelia
```

Wait for Authelia to be ready:
```bash
KUBECONFIG=$HOME/.kube/config kubectl get pods -n authelia -w
```

## Step 8: Add Caddy route

Edit `/REPOS_PRIVAT/k8s/caddy-system/configmap.yaml` — add a new `handle` block
inside the `:443` server block.

**All apps use the same pattern with environment prefix:**
```
      handle /<ENV>/<APP_NAME>* {
        import app_route /<ENV>/<APP_NAME> <APP_NAME>.apps.svc.cluster.local:<PORT>
      }
```

For production deployments, use the `-prod` suffixed service name:
```
      handle /prod/<APP_NAME>* {
        import app_route /prod/<APP_NAME> <APP_NAME>-prod.apps.svc.cluster.local:<PORT>
      }
```

The `app_route` snippet handles: Authelia forward_auth → strip prefix → reverse_proxy.
Next.js `basePath` only affects URL generation in HTML — the server routes on `/`, not
`/<ENV>/<APP_NAME>/`. Caddy must strip the full prefix before proxying.

Apply the configmap:
```bash
KUBECONFIG=$HOME/.kube/config kubectl apply -f /REPOS_PRIVAT/k8s/caddy-system/configmap.yaml
```

**Restart Caddy — IMPORTANT: Caddy uses `hostPort`, so only one pod can run at a time.**
The rolling restart will create a new pod, but it will stay `Pending` until the old pod
is deleted (port conflict). You must delete the old pod manually:

```bash
# Get the current pod name
KUBECONFIG=$HOME/.kube/config kubectl get pods -n caddy-system

# Delete the OLD pod (the one that's Running, not the new Pending one)
KUBECONFIG=$HOME/.kube/config kubectl delete pod <old-caddy-pod-name> -n caddy-system

# Wait for the new pod to start and become ready
KUBECONFIG=$HOME/.kube/config kubectl get pods -n caddy-system -w
```

Alternatively, scale down then up:
```bash
KUBECONFIG=$HOME/.kube/config kubectl scale deployment/caddy -n caddy-system --replicas=0
sleep 5
KUBECONFIG=$HOME/.kube/config kubectl scale deployment/caddy -n caddy-system --replicas=1
```

## Step 9: Add to landing page

Edit `/REPOS_PRIVAT/k8s/landing/index.html` — add a card inside the correct
environment grid section (Experimental or Production):

```html
  <a class="card" href="/<ENV>/<APP_NAME>/">
    <div class="card-header">
      <div class="card-icon">&#ICON;</div>
      <div class="card-title">App Title</div>
    </div>
    <div class="card-desc">Short description of what the app does.</div>
    <div class="card-tag exp">experimental</div>
  </a>
```

Tag options: `exp` (amber, experimental), `prod` (green, production), `infra` (green, infrastructure).

Update the landing page configmap and restart Caddy:
```bash
KUBECONFIG=$HOME/.kube/config kubectl create configmap landing-page -n caddy-system \
  --from-file=index.html=/REPOS_PRIVAT/k8s/landing/index.html \
  --dry-run=client -o yaml | KUBECONFIG=$HOME/.kube/config kubectl apply -f -
```

Caddy needs to restart to pick up the new configmap volume. Use the scale down/up
approach from Step 8 if it hasn't been restarted yet.

## Step 10: Add to Makefile and deploy script

### Makefile (`/REPOS_PRIVAT/k8s/Makefile`)

1. Add to `APPS` list:
   ```
   APPS := checkmate wandermind ... <APP_NAME> admin-ui
   ```
   (keep `admin-ui` last)

2. Add directory mapping:
   ```
   dir_<APP_NAME> := $(PARENT_DIR)/<SOURCE_DIR>
   ```

3. Add to `.PHONY` for build and push (find the existing lines and append):
   ```
   .PHONY: build-checkmate ... build-<APP_NAME> build-admin-ui
   .PHONY: push-checkmate ... push-<APP_NAME> push-admin-ui
   ```

4. Add build target:
   ```makefile
   build-<APP_NAME>:
   	docker build -t $(REGISTRY)/<APP_NAME>:latest $(dir_<APP_NAME>)
   ```

5. Add push target:
   ```makefile
   push-<APP_NAME>:
   	docker push $(REGISTRY)/<APP_NAME>:latest
   ```

The generic `deploy-%`, `all-%`, `restart-%`, `clean-%`, `logs-%`, `shell-%`,
and `port-forward-%` targets work automatically for any app in the `APPS` list.

### Deploy script (`/REPOS_PRIVAT/k8s/deploy-app.sh`)

Add to the `APP_DIR_MAP` associative array:
```bash
    [<APP_NAME>]="<SOURCE_DIR>"
```

## Step 11: Verify end-to-end

```bash
# 1. Pod is running
KUBECONFIG=$HOME/.kube/config kubectl get pods -n apps -l app=<APP_NAME>

# 2. App responds inside the cluster
KUBECONFIG=$HOME/.kube/config kubectl exec -n caddy-system deploy/caddy -- \
  wget -q -O- http://<APP_NAME>.apps.svc.cluster.local:<PORT>/ | head -3

# 3. App responds through Caddy (external)
curl -k https://localhost/<ENV>/<APP_NAME>/ -H "Host: adrian-gruenther.de" | head -3

# 4. Logs are structured JSON
KUBECONFIG=$HOME/.kube/config kubectl logs -n apps -l app=<APP_NAME> --tail=5
```

## Step 12: Verify logging pipeline

1. **Check app logs are structured JSON:**
   ```bash
   KUBECONFIG=$HOME/.kube/config kubectl logs -n apps -l app=<APP_NAME> --tail=5
   ```
   Each line should be a JSON object with `ts`, `level`, `msg`, `app`, and `ctx` fields.

2. **Query in Grafana** (https://adrian-gruenther.de/grafana/):
   ```
   {namespace="apps", app="<APP_NAME>"}
   ```

3. **Filter by level:**
   ```
   {namespace="apps", app="<APP_NAME>"} | json | level="error"
   ```

4. **Filter by context:**
   ```
   {namespace="apps", app="<APP_NAME>"} | json | ctx=~"api:.*"
   ```

## Step 13: Update Grafana dashboard

Add the new app name to the Grafana dashboard's service dropdown:
- Edit `/REPOS_PRIVAT/k8s/logging/grafana-dashboards/apps-overview.json`
- Add `<APP_NAME>` to the service variable options
- Re-apply: `KUBECONFIG=$HOME/.kube/config kubectl create configmap grafana-dashboards -n logging --from-file=... --dry-run=client -o yaml | KUBECONFIG=$HOME/.kube/config kubectl apply -f -`

---

## Deployment checklist

- [ ] App scaffolded from boilerplate — **all files present** (Dockerfile, .dockerignore, middleware.ts, lib/logger.ts)
- [ ] Configs updated (package.json name/port, next.config.ts basePath=`/<ENV>/<APP_NAME>`, layout.tsx metadata, Caddyfile.template)
- [ ] `npm install` run to regenerate package-lock.json
- [ ] Logger integrated, no bare `console.log()`
- [ ] Docker image built successfully (no SWC/Turbopack errors)
- [ ] Image imported into k3s containerd (`docker save | sudo k3s ctr images import`)
- [ ] K8s manifests created in `/REPOS_PRIVAT/k8s/apps/<APP_NAME>/`
- [ ] Deployment manifest has: `imagePullPolicy: Never`, readiness probe path `/`, correct port
- [ ] Pod deployed and `1/1 Running`
- [ ] **Authelia** access policy added and Authelia restarted
- [ ] **Caddy** route added, configmap applied, Caddy restarted (old pod deleted for hostPort)
- [ ] **Landing page** card added, configmap updated
- [ ] **Makefile** targets added (APPS list, dir mapping, build, push)
- [ ] **Deploy script** APP_DIR_MAP entry added
- [ ] App accessible at `https://adrian-gruenther.de/<ENV>/<APP_NAME>/`
- [ ] Logs visible in Grafana

---

## Troubleshooting

### 403 Forbidden
Authelia has no access policy for this path. Add the rule in Step 7 and restart Authelia.

### 404 Not Found (through Caddy)
Caddy route is missing or wrong. Check:
- Route exists in configmap for `/<ENV>/<APP_NAME>*`
- Caddy pod has been restarted with the new config
- basePath in next.config.ts matches the full Caddy prefix (`/<ENV>/<APP_NAME>`)

### ErrImageNeverPull
Image not in containerd. Run Step 4: `docker save ... | sudo k3s ctr images import -`

### ErrImagePull / ImagePullBackOff
`imagePullPolicy` is set to `IfNotPresent` or `Always` and the registry is unreachable.
Change to `Never` and use `docker save | k3s ctr images import` instead.

### Pod Running but 0/1 Ready
Readiness probe is failing. **Most common cause:** probe path is `/<BASE_PATH>/` instead
of `/`. Next.js serves content at `/` when accessed directly — the basePath is only for
URL construction. Change the probe path to `/`.

### Caddy new pod stuck in Pending
Caddy uses `hostPort: 443`. Only one pod can bind to port 443 at a time. Delete the old
pod or scale down/up: `KUBECONFIG=$HOME/.kube/config kubectl scale deploy/caddy -n caddy-system --replicas=0 && sleep 5 && KUBECONFIG=$HOME/.kube/config kubectl scale deploy/caddy -n caddy-system --replicas=1`

### CSS loads without path prefix (unstyled page)
`next start` reads `next.config.ts` at runtime for `assetPrefix`. The config file must
be present in the runner image. Check the Dockerfile runner stage has:
```dockerfile
COPY --from=builder /app/next.config.ts ./
```

### npm ci fails: lockfile out of sync
Run `npm install` locally to regenerate `package-lock.json`, then rebuild the Docker image.

---

## Log format reference

### Production (JSON lines to stdout — Loki ingests these)
```json
{"ts":"2026-03-28T12:00:00.000Z","level":"info","msg":"Server started","app":"my-app","ctx":"server","port":3020}
{"ts":"2026-03-28T12:00:01.123Z","level":"info","msg":"GET /my-app/ 200","app":"my-app","ctx":"http","method":"GET","path":"/my-app/","status":200,"latency":12}
{"ts":"2026-03-28T12:00:02.456Z","level":"error","msg":"Database connection failed","app":"my-app","ctx":"db","err":"SQLITE_CANTOPEN","retries":3}
```

### Development (colored console output)
```
[INFO ] (server) Server started {"port":3020}
[INFO ] (http) GET /my-app/ 200 {"method":"GET","path":"/my-app/","status":200,"latency":12}
[ERROR] (db) Database connection failed {"err":"SQLITE_CANTOPEN","retries":3}
```

### Loki LogQL queries
| Goal | Query |
|------|-------|
| All logs for app | `{app="my-app"}` |
| Errors only | `{app="my-app"} \| json \| level="error"` |
| Specific module | `{app="my-app"} \| json \| ctx=~"api:.*"` |
| Slow requests | `{app="my-app"} \| json \| ctx="http" \| latency > 500` |
| Search text | `{app="my-app"} \|= "connection failed"` |
