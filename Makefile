# ============================================================
# K8s Cluster Makefile
# ============================================================

SHELL := /bin/bash
.DEFAULT_GOAL := help

# === Variables ===
REGISTRY := registry.localhost:5000
APPS := checkmate wandermind eden req-helper master-agent ai-tooling munchkin-td citizen-dev polisim agentic-offering profile idea-maschine learning-games companion admin-ui
SCRIPT_DIR := $(shell cd "$(dir $(lastword $(MAKEFILE_LIST)))" && pwd)
PARENT_DIR := $(shell dirname $(SCRIPT_DIR))

# Map app names to source directories
dir_checkmate     := $(PARENT_DIR)/checkmate
dir_wandermind    := $(PARENT_DIR)/wandermind
dir_eden          := $(PARENT_DIR)/EDEN
dir_req-helper    := $(PARENT_DIR)/requirement_helper
dir_master-agent  := $(PARENT_DIR)/master-agent
dir_ai-tooling    := $(PARENT_DIR)/ai-tooling
dir_munchkin-td   := $(PARENT_DIR)/munchkin-td
dir_citizen-dev   := $(PARENT_DIR)/citizen-dev-platform
dir_polisim       := $(PARENT_DIR)/polisim
dir_agentic-offering := $(PARENT_DIR)/agentic-offering
dir_profile       := $(PARENT_DIR)/profile
dir_idea-maschine := $(PARENT_DIR)/idea_maschine
dir_learning-games := $(PARENT_DIR)/learning-games
dir_companion     := $(PARENT_DIR)/companion
dir_admin-ui      := $(PARENT_DIR)/admin-ui

# ============================================================
# Cluster Setup
# ============================================================

.PHONY: bootstrap setup-logging setup-caddy setup-all

bootstrap: ## Run bootstrap.sh to install k3s and set up the cluster
	sudo $(SCRIPT_DIR)/bootstrap.sh

setup-logging: ## Deploy Loki + Promtail + Grafana logging stack
	$(SCRIPT_DIR)/deploy-logging.sh

setup-caddy: ## Deploy Caddy ingress controller
	kubectl apply -f $(SCRIPT_DIR)/caddy-system/

setup-all: bootstrap setup-logging setup-caddy ## Full cluster setup (bootstrap + logging + caddy)

# ============================================================
# Build Individual Apps
# ============================================================

.PHONY: build-checkmate build-wandermind build-eden build-req-helper build-master-agent build-ai-tooling build-munchkin-td build-citizen-dev build-polisim build-agentic-offering build-profile build-idea-maschine build-learning-games build-companion build-admin-ui

build-checkmate:
	docker build -t $(REGISTRY)/checkmate:latest $(dir_checkmate)

build-wandermind:
	docker build -t $(REGISTRY)/wandermind:latest $(dir_wandermind)

build-eden:
	docker build -t $(REGISTRY)/eden:latest -f $(dir_eden)/web/Dockerfile $(dir_eden)/web

build-req-helper:
	docker build -t $(REGISTRY)/req-helper:latest $(dir_req-helper)

build-master-agent:
	docker build -t $(REGISTRY)/master-agent-frontend:latest -f $(dir_master-agent)/frontend/Dockerfile $(dir_master-agent)/frontend
	docker build -t $(REGISTRY)/master-agent-backend:latest  -f $(dir_master-agent)/backend/Dockerfile  $(dir_master-agent)/backend

build-ai-tooling:
	docker build -t $(REGISTRY)/ai-tooling:latest $(dir_ai-tooling)

build-munchkin-td:
	docker build -t $(REGISTRY)/munchkin-td:latest $(dir_munchkin-td)

build-citizen-dev:
	docker build -t $(REGISTRY)/citizen-dev-base:latest     -f $(dir_citizen-dev)/docker/Dockerfile.base     $(dir_citizen-dev)
	docker build -t $(REGISTRY)/citizen-dev-run:latest      -f $(dir_citizen-dev)/docker/Dockerfile.run      $(dir_citizen-dev)
	docker build -t $(REGISTRY)/citizen-dev-edit:latest     -f $(dir_citizen-dev)/docker/Dockerfile.edit     $(dir_citizen-dev)
	docker build -t $(REGISTRY)/citizen-dev-mock-sap:latest -f $(dir_citizen-dev)/docker/Dockerfile.mock-sap $(dir_citizen-dev)

build-polisim:
	docker build -t $(REGISTRY)/polisim:latest $(dir_polisim)

build-agentic-offering:
	docker build -t $(REGISTRY)/agentic-offering:latest $(dir_agentic-offering)

build-profile:
	docker build -t $(REGISTRY)/profile:latest $(dir_profile)

build-idea-maschine:
	docker build -t $(REGISTRY)/idea-maschine:latest $(dir_idea-maschine)

build-learning-games:
	docker build -t $(REGISTRY)/learning-games:latest $(dir_learning-games)

build-companion:
	docker build -t $(REGISTRY)/companion:latest $(dir_companion)

build-admin-ui:
	docker build -t $(REGISTRY)/admin-ui:latest $(dir_admin-ui)

# ============================================================
# Push Individual Apps
# ============================================================

.PHONY: push-checkmate push-wandermind push-eden push-req-helper push-master-agent push-ai-tooling push-munchkin-td push-citizen-dev push-polisim push-agentic-offering push-profile push-idea-maschine push-learning-games push-companion push-admin-ui

push-checkmate:
	docker push $(REGISTRY)/checkmate:latest

push-wandermind:
	docker push $(REGISTRY)/wandermind:latest

push-eden:
	docker push $(REGISTRY)/eden:latest

push-req-helper:
	docker push $(REGISTRY)/req-helper:latest

push-master-agent:
	docker push $(REGISTRY)/master-agent-frontend:latest
	docker push $(REGISTRY)/master-agent-backend:latest

push-ai-tooling:
	docker push $(REGISTRY)/ai-tooling:latest

push-munchkin-td:
	docker push $(REGISTRY)/munchkin-td:latest

push-citizen-dev:
	docker push $(REGISTRY)/citizen-dev-base:latest
	docker push $(REGISTRY)/citizen-dev-run:latest
	docker push $(REGISTRY)/citizen-dev-edit:latest
	docker push $(REGISTRY)/citizen-dev-mock-sap:latest

push-polisim:
	docker push $(REGISTRY)/polisim:latest

push-agentic-offering:
	docker push $(REGISTRY)/agentic-offering:latest

push-profile:
	docker push $(REGISTRY)/profile:latest

push-idea-maschine:
	docker push $(REGISTRY)/idea-maschine:latest

push-learning-games:
	docker push $(REGISTRY)/learning-games:latest

push-companion:
	docker push $(REGISTRY)/companion:latest

push-admin-ui:
	docker push $(REGISTRY)/admin-ui:latest

# ============================================================
# Deploy Individual Apps
# ============================================================

.PHONY: $(addprefix deploy-,$(APPS))

deploy-%:
	kubectl apply -f $(SCRIPT_DIR)/apps/$*/

# ============================================================
# All-in-one per app (build + push + deploy)
# ============================================================

.PHONY: $(addprefix all-,$(APPS))

all-%: build-% push-% deploy-%
	@echo "==> $* built, pushed, and deployed"

# ============================================================
# Restart
# ============================================================

.PHONY: $(addprefix restart-,$(APPS))

restart-%:
	kubectl rollout restart deployment/$* -n apps 2>/dev/null || true

# ============================================================
# Bulk Operations
# ============================================================

.PHONY: build-all push-all deploy-all all

build-all: $(addprefix build-,$(APPS)) ## Build all app images

push-all: $(addprefix push-,$(APPS)) ## Push all app images to local registry

deploy-all: $(addprefix deploy-,$(APPS)) ## Deploy all apps to the cluster

all: build-all push-all deploy-all ## Build, push, and deploy everything

# ============================================================
# Utility
# ============================================================

.PHONY: status logs-% shell-% port-forward-% clean-% clean-all help

status: ## Show all pods, services, and PVCs across all namespaces
	@echo "=== Nodes ==="
	@kubectl get nodes -o wide
	@echo ""
	@echo "=== Pods (all namespaces) ==="
	@kubectl get pods -A
	@echo ""
	@echo "=== Services (all namespaces) ==="
	@kubectl get svc -A
	@echo ""
	@echo "=== PVCs (all namespaces) ==="
	@kubectl get pvc -A 2>/dev/null || true

logs-%: ## Show logs for an app (usage: make logs-checkmate)
	@POD=$$(kubectl get pods -n apps -l "app=$*" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null); \
	if [ -n "$$POD" ]; then \
		kubectl logs -n apps "$$POD" --tail=100 -f; \
	else \
		echo "No running pod found for $*"; \
	fi

shell-%: ## Open a shell in an app pod (usage: make shell-checkmate)
	@POD=$$(kubectl get pods -n apps -l "app=$*" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null); \
	if [ -n "$$POD" ]; then \
		kubectl exec -it -n apps "$$POD" -- /bin/sh; \
	else \
		echo "No pod found for $*"; \
	fi

port-forward-%: ## Port-forward to an app (usage: make port-forward-checkmate)
	@SVC=$$(kubectl get svc -n apps -o name 2>/dev/null | grep "$*" | head -1); \
	if [ -n "$$SVC" ]; then \
		PORT=$$(kubectl get "$$SVC" -n apps -o jsonpath='{.spec.ports[0].port}'); \
		echo "Forwarding localhost:$$PORT -> $$SVC:$$PORT"; \
		kubectl port-forward -n apps "$$SVC" "$$PORT:$$PORT"; \
	else \
		echo "No service found for $*"; \
	fi

clean-%: ## Delete an app's k8s resources (usage: make clean-checkmate)
	kubectl delete -f $(SCRIPT_DIR)/apps/$*/ --ignore-not-found

clean-all: ## Delete all app resources (with confirmation)
	@echo "This will delete ALL application resources from the cluster."
	@read -p "Are you sure? [y/N] " confirm && [ "$$confirm" = "y" ] || (echo "Aborted." && exit 1)
	@for app in $(APPS); do \
		echo "==> Cleaning $$app..."; \
		kubectl delete -f $(SCRIPT_DIR)/apps/$$app/ --ignore-not-found 2>/dev/null || true; \
	done
	@echo "All app resources deleted."

help: ## Show this help
	@grep -E '^[a-zA-Z_%-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'
