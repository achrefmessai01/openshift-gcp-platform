# Entry points of the delivery chain. Every target maps to a pipeline job so what runs in CI
# can be reproduced from a workstation.
.DEFAULT_GOAL := help
SHELL := /usr/bin/env bash

PY       ?= python3
ENV      ?= dev
IMAGE    ?= ghcr.io/achrefmessai01/subscriber-api
TAG      ?= dev
BASE_URL ?= http://localhost:8080
API_KEY  ?=
TF_DIR   := terraform
KUBECONFORM_SCHEMAS := https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json

help: ## List targets
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

# --- quality -------------------------------------------------------------------------------
lint: lint-python lint-terraform lint-manifests lint-ansible ## Run every linter

lint-python: ## ruff, yamllint, flow matrix consistency
	ruff check .
	yamllint -c .yamllint.yml .
	$(PY) tools/flowmatrix.py check

lint-terraform: ## terraform fmt + validate
	terraform -chdir=$(TF_DIR) fmt -check -recursive -diff
	terraform -chdir=$(TF_DIR) init -backend=false -input=false >/dev/null
	terraform -chdir=$(TF_DIR) validate

lint-manifests: ## kustomize build + kubeconform for every overlay
	@for env in dev staging prod; do \
	  echo "== $$env"; \
	  kubectl kustomize deploy/overlays/$$env | kubeconform -strict -summary -schema-location default -schema-location '$(KUBECONFORM_SCHEMAS)'; \
	done

lint-ansible: ## ansible syntax check + ansible-lint
	cd ansible && ansible-playbook --syntax-check site.yml
	ansible-lint

test: ## Unit tests of the sample application
	pytest app/subscriber-api

docs: ## Regenerate generated documents (flow matrix)
	$(PY) tools/flowmatrix.py render

# --- application ---------------------------------------------------------------------------
build: ## Build the container image locally
	docker build -t $(IMAGE):$(TAG) -f app/subscriber-api/Containerfile app/subscriber-api

run: ## Run the image locally as an arbitrary UID with a read-only root filesystem
	docker run --rm -p 8080:8080 --user 1000810000:0 --read-only --tmpfs /tmp -e API_KEY=$(API_KEY) -e APP_ENV=local $(IMAGE):$(TAG)

acceptance: ## Robot Framework acceptance against BASE_URL (writes reports/<ENV>/)
	$(PY) tools/acceptance.py --base-url $(BASE_URL) --env $(ENV) --api-key "$(API_KEY)"

bruno: ## Bruno collection against the local environment
	cd tests/bruno && npx --yes @usebruno/cli run --env local --env-var apiKey=$(API_KEY)

perf: ## JMeter smoke load against BASE_URL host (20 users, 60 s) + thresholds
	jmeter -n -t tests/jmeter/subscriber-api-smoke.jmx -Jhost=$$(echo $(BASE_URL) | sed -E 's#https?://([^:/]+).*#\1#') \
	  -Jport=$$(echo $(BASE_URL) | sed -nE 's#https?://[^:/]+:([0-9]+).*#\1#p') -JapiKey=$(API_KEY) \
	  -l reports/$(ENV)/jmeter.jtl -e -o reports/$(ENV)/jmeter-html
	$(PY) tools/jmeter_gate.py reports/$(ENV)/jmeter.jtl

# --- infrastructure ------------------------------------------------------------------------
plan: ## terraform plan (expects terraform/terraform.tfvars and an initialised backend)
	terraform -chdir=$(TF_DIR) plan -input=false -out=tfplan

apply: ## terraform apply of the last plan
	terraform -chdir=$(TF_DIR) apply -input=false tfplan

install: ## Render install-config.yaml and create the OpenShift cluster
	install/render-install-config.sh --create

day2: ## Day-2 configuration with Ansible
	cd ansible && ansible-playbook site.yml

# --- deployment chain ----------------------------------------------------------------------
deploy: ## Deploy overlay ENV (and image TAG) then run the acceptance suites
	scripts/deploy.sh $(ENV) $(TAG) --acceptance

rollback: ## Roll ENV back to the previous revision and re-run smoke tests
	scripts/rollback.sh $(ENV)

netcheck: ## Network diagnostics (API_HOST and ROUTE_HOST variables)
	tools/netcheck.sh $(API_HOST) $(ROUTE_HOST)

.PHONY: help lint lint-python lint-terraform lint-manifests lint-ansible test docs build run acceptance bruno perf plan apply install day2 deploy rollback netcheck
