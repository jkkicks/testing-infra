ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
KUBECONFIG ?= $(ROOT)/kubeconfig.pve1-testing1
HELM ?= helm

.PHONY: terraform-init terraform-plan terraform-apply terraform-apply-auto terraform-destroy terraform-destroy-auto helm-check helm-repos helm-headlamp helm-infisical helm-infisical-operator

terraform-init:
	cd "$(ROOT)/environments/pve1-testing1/terraform" && "$(ROOT)/scripts/with-proxmox-env.sh" terraform init

terraform-plan:
	cd "$(ROOT)/environments/pve1-testing1/terraform" && "$(ROOT)/scripts/with-proxmox-env.sh" terraform plan

terraform-apply:
	cd "$(ROOT)/environments/pve1-testing1/terraform" && "$(ROOT)/scripts/with-proxmox-env.sh" terraform apply

terraform-apply-auto:
	cd "$(ROOT)/environments/pve1-testing1/terraform" && "$(ROOT)/scripts/with-proxmox-env.sh" terraform apply -auto-approve

terraform-destroy:
	cd "$(ROOT)/environments/pve1-testing1/terraform" && "$(ROOT)/scripts/with-proxmox-env.sh" terraform destroy

terraform-destroy-auto:
	cd "$(ROOT)/environments/pve1-testing1/terraform" && "$(ROOT)/scripts/with-proxmox-env.sh" terraform destroy -auto-approve

helm-check:
	@command -v "$(HELM)" >/dev/null 2>&1 || { printf '%s\n' 'helm not found. Install Helm 3 (macOS: brew install helm). https://helm.sh/docs/intro/install/' >&2; exit 1; }

helm-repos: helm-check
	$(HELM) repo add headlamp https://kubernetes-sigs.github.io/headlamp/ 2>/dev/null || true
	$(HELM) repo add infisical https://dl.cloudsmith.io/public/infisical/helm-charts/helm/charts/ 2>/dev/null || true
	$(HELM) repo update

helm-headlamp: helm-repos
	$(HELM) upgrade --install headlamp headlamp/headlamp \
		--kubeconfig "$(KUBECONFIG)" --namespace kube-system --create-namespace \
		-f "$(ROOT)/gitops/environments/pve1-testing1/headlamp-values.yaml"

helm-infisical: helm-repos
	$(HELM) upgrade --install infisical infisical/infisical-standalone \
		--kubeconfig "$(KUBECONFIG)" --namespace infisical --create-namespace \
		-f "$(ROOT)/gitops/environments/pve1-testing1/infisical-values.yaml"

helm-infisical-operator: helm-repos
	$(HELM) upgrade --install infisical-secrets-operator infisical/secrets-operator \
		--kubeconfig "$(KUBECONFIG)" --namespace infisical-system --create-namespace \
		-f "$(ROOT)/gitops/environments/pve1-testing1/infisical-operator-values.yaml"
