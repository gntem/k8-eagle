.PHONY: help build docker-build deploy deploy-k8s deploy-tf logs status clean clean-k8s clean-tf token add-watcher tf-init tf-plan tf-apply tf-destroy

WATCHER_NAME ?= new-watcher
DEPLOYMENT_NAME ?= target-app
NAMESPACE ?= default
WEBHOOK_URL ?= https://webhook.example.com/k8s-events
AUTH_TOKEN_KEY ?= webhook-token
AUTH_TOKEN ?= your-webhook-token-here
IMAGE_NAME ?= k8-eagle
IMAGE_TAG ?= latest

help: ## Show this help message
	@echo "K8-Eagle Makefile Commands:"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

build: ## Build the Rust application
	cargo build --release

docker-build: build ## Build Docker image
	docker build -f dockerfiles/Dockerfile -t $(IMAGE_NAME):$(IMAGE_TAG) .

token: ## Generate base64 encoded token (use AUTH_TOKEN and AUTH_TOKEN_KEY vars)
	@echo -n "$(AUTH_TOKEN)" | base64

tf-init: ## Initialize OpenTofu
	cd terraform && tofu init

tf-plan: ## Plan OpenTofu deployment
	cd terraform && tofu plan

tf-apply: ## Apply OpenTofu deployment
	cd terraform && tofu apply

tf-destroy: ## Destroy OpenTofu deployment
	cd terraform && tofu destroy

deploy-tf: tf-init tf-apply ## Deploy K8-Eagle using OpenTofu (recommended)

clean-tf: ## Remove K8-Eagle using OpenTofu
	cd terraform && tofu destroy -auto-approve

deploy: deploy-tf ## Deploy K8-Eagle (uses OpenTofu by default)
clean: clean-tf ## Remove K8-Eagle (uses OpenTofu by default)

logs: ## View K8-Eagle logs
	kubectl logs -l app=k8-eagle -f

status: ## Check K8-Eagle deployment status
	kubectl get pods -l app=k8-eagle
	kubectl get deployment k8-eagle
	kubectl get configmap k8-eagle-config -o yaml

install: docker-build deploy ## Build image and deploy (full installation)
install-tf: docker-build deploy-tf ## Build image and deploy with OpenTofu

restart: ## Restart K8-Eagle deployment
	kubectl rollout restart deployment/k8-eagle

describe: ## Describe K8-Eagle resources
	kubectl describe deployment k8-eagle
	kubectl describe pods -l app=k8-eagle
	kubectl describe configmap k8-eagle-config
	kubectl describe secret k8-eagle-secret

edit-config: ## Edit ConfigMap interactively
	kubectl edit configmap k8-eagle-config

edit-secret: ## Edit Secret interactively
	kubectl edit secret k8-eagle-secret

show-config: ## Display current configuration in a readable format
	kubectl get configmap k8-eagle-config -o jsonpath='{.data.config\.yaml}' | yq eval '.' -
	kubectl get secret k8-eagle-secret -o jsonpath='{.data}' | jq -r 'keys[]'

validate-config: ## Validate the current configuration
	kubectl get configmap k8-eagle-config -o jsonpath='{.data.config\.yaml}' | yq eval '.' - > /dev/null && echo "✓ Configuration is valid YAML" || echo "✗ Configuration has YAML syntax errors"

tf-validate: ## Validate OpenTofu configuration
	cd terraform && tofu validate

tf-fmt: ## Format OpenTofu files
	cd terraform && tofu fmt -recursive

tf-show: ## Show OpenTofu state
	cd terraform && tofu show

tf-output: ## Show OpenTofu outputs
	cd terraform && tofu output

example-config: ## Show example configuration
	@cat terraform/terraform.tfvars.example
