PROJECT_NAME ?= s3ollama
DOCKER_IMAGE ?= $(PROJECT_NAME)-dev
PYTHON ?= python3

.DEFAULT_GOAL := help

.PHONY: help
help: ## Show available make targets
@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

.PHONY: install
install: ## Install Python dependencies locally
$(PYTHON) -m pip install --upgrade pip
$(PYTHON) -m pip install -r requirements-dev.txt

.PHONY: test
test: ## Run unit tests
pytest --cov=lambda --cov=job --cov-report=term-missing

.PHONY: lint
lint: ## Run basic static checks
$(PYTHON) -m compileall lambda job

.PHONY: docker-build
docker-build: ## Build the development Docker image
docker build -t $(DOCKER_IMAGE) .

.PHONY: docker-shell
docker-shell: ## Start an interactive shell inside the development container
docker run --rm -it -v $(PWD):/workspace -w /workspace $(DOCKER_IMAGE)

.PHONY: terraform-fmt
terraform-fmt: ## Format Terraform configuration
cd infrastructure/terraform && terraform fmt

.PHONY: terraform-plan
terraform-plan: ## Run terraform plan using the infrastructure code
cd infrastructure/terraform && terraform plan

.PHONY: terraform-apply
terraform-apply: ## Apply terraform configuration (requires approval)
cd infrastructure/terraform && terraform apply

