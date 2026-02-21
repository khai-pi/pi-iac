# ============================================================
# Makefile – Terraform operations helper
# Usage: make <target> ENV=prod
# ============================================================

ENV        ?= dev
TF_DIR     := environments/$(ENV)
TF         := terraform -chdir=$(TF_DIR)
PLAN_FILE  := $(TF_DIR)/tfplan.binary

.PHONY: help init validate plan apply destroy fmt lint clean

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
	  awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

init: ## Initialize Terraform for ENV
	$(TF) init -upgrade

validate: init ## Validate Terraform configuration
	$(TF) validate

fmt: ## Format all Terraform files
	terraform fmt -recursive .

lint: ## Run tflint
	@command -v tflint >/dev/null 2>&1 || (echo "Install tflint: brew install tflint"; exit 1)
	tflint --recursive

plan: init ## Run terraform plan for ENV (usage: make plan ENV=prod)
	$(TF) plan -out=$(PLAN_FILE) -var-file=terraform.tfvars

apply: ## Apply the last terraform plan for ENV
	$(TF) apply $(PLAN_FILE)

apply-auto: init ## Plan + apply without approval (CI use only)
	$(TF) apply -auto-approve -var-file=terraform.tfvars

destroy: ## Destroy all resources for ENV (requires confirmation)
	$(TF) destroy -var-file=terraform.tfvars

output: ## Show terraform outputs for ENV
	$(TF) output

state-list: ## List all resources in state for ENV
	$(TF) state list

docs: ## Generate terraform docs (requires terraform-docs)
	@command -v terraform-docs >/dev/null 2>&1 || (echo "Install: brew install terraform-docs"; exit 1)
	terraform-docs markdown . > TERRAFORM.md

security-scan: ## Run tfsec security scanner
	@command -v tfsec >/dev/null 2>&1 || (echo "Install: brew install tfsec"; exit 1)
	tfsec .

costs: ## Estimate costs with infracost
	@command -v infracost >/dev/null 2>&1 || (echo "Install: brew install infracost"; exit 1)
	infracost breakdown --path=$(TF_DIR)

clean: ## Remove local Terraform cache and plan files
	find . -name ".terraform" -type d -exec rm -rf {} + 2>/dev/null || true
	find . -name "*.tfplan" -o -name "tfplan.binary" | xargs rm -f 2>/dev/null || true
	find . -name ".terraform.lock.hcl" | xargs rm -f 2>/dev/null || true

bootstrap: ## Run the one-time bootstrap script
	bash scripts/bootstrap.sh
