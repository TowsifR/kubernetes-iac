# Defaults
ENV ?= dev
CLUSTER_TYPE ?= services
CLUSTER_NAME ?= $(CLUSTER_TYPE)-$(ENV)

help:
	@echo "Terraform - KinD Cluster Management"
	@echo ""
	@echo "Usage: make <target> ENV=<env> CLUSTER_TYPE=<type>"
	@echo ""
	@echo "Targets:"
	@echo "  init          - Initialize Terraform"
	@echo "  cluster       - Create cluster + bootstrap Flux"
	@echo "  destroy       - Tear down cluster"
	@echo "  clean         - Remove all clusters and Terraform cache"
	@echo ""
	@echo "Shortcuts:"
	@echo "  dev-services  - Create dev services cluster"
	@echo ""
	@echo "Prerequisites:"
	@echo "  export TF_VAR_github_token=ghp_xxx"

init:
	cd main && terraform init

cluster:
	@test -f ../.env && . ../.env || true; \
	cd main && terraform apply \
		-var-file="tfvars/$(ENV).tfvars" \
		-var="cluster_name=$(CLUSTER_NAME)" \
		-var="cluster_type=$(CLUSTER_TYPE)" \
		-auto-approve
	@echo "Verify: kubectl get pods -n flux-system"

destroy:
	@test -f ../.env && . ../.env || true; \
	cd main && terraform destroy \
		-var-file="tfvars/$(ENV).tfvars" \
		-var="cluster_name=$(CLUSTER_NAME)" \
		-var="cluster_type=$(CLUSTER_TYPE)" \
		-auto-approve

clean:
	kind delete clusters --all
	rm -rf main/.terraform

# Shortcuts
dev-services:
	$(MAKE) cluster ENV=dev CLUSTER_TYPE=services
