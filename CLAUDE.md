# k8s

> Global guidelines: see `/home/claude_worker/.claude/CLAUDE.md`

## Project
Kubernetes manifests for all deployed apps, network policies, and secrets.

## Key Details
- App manifests live in `apps/<app-name>/`
- All deployments use `imagePullPolicy: Never` (containerd-imported images)
- Namespace: `apps` for all application workloads
- PVCs used by: checkmate, eden, req-helper, wandermind (sqlite databases)
- Production deployments use `-prod` suffix for service names
