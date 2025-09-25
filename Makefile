PROJECT_NAME ?= s3ollama
DOCKER_IMAGE ?= $(PROJECT_NAME)-dev
PYTHON ?= python3
DOCKER_RUN_FLAGS ?= --rm -t -v $(PWD):/workspace -w /workspace
DOCKER_RUN ?= docker run $(DOCKER_RUN_FLAGS) $(DOCKER_IMAGE)
PYTEST_SCRIPT ?= ./scripts/run_pytest.sh

.DEFAULT_GOAL := help

.PHONY: help
help: ## Show available make targets
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*## / {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

.PHONY: install
install: ## Install Python dependencies locally
	$(PYTHON) -m pip install --upgrade pip
	$(PYTHON) -m pip install -r requirements-dev.txt

.PHONY: install-docker
install-docker: ensure-image ## Install dependencies inside Docker image (rebuilds image)
	@echo "Dependencies are baked into the Docker image during build."

.PHONY: ensure-image
ensure-image: ## Ensure the development Docker image exists
	@if command -v docker >/dev/null 2>&1; then \
		docker image inspect $(DOCKER_IMAGE) > /dev/null 2>&1 || $(MAKE) docker-build; \
	else \
		echo "Docker CLI not available; skipping image inspection"; \
	fi

.PHONY: test
test: ensure-image ## Run unit tests inside Docker
	@if command -v docker >/dev/null 2>&1; then \
		$(DOCKER_RUN) $(PYTEST_SCRIPT); \
	else \
		echo "Docker CLI not available; running tests on the host"; \
		$(PYTEST_SCRIPT); \
	fi

.PHONY: test-local
test-local: ## Run unit tests locally without Docker
	$(PYTEST_SCRIPT)

.PHONY: lint
lint: ensure-image ## Run basic static checks inside Docker
	@if command -v docker >/dev/null 2>&1; then \
		$(DOCKER_RUN) python -m compileall lambda job; \
	else \
		echo "Docker CLI not available; running lint on the host"; \
		$(MAKE) lint-local; \
	fi

.PHONY: lint-local
lint-local: ## Run basic static checks locally without Docker
	$(PYTHON) -m compileall lambda job

.PHONY: docker-build
docker-build: ## Build the development Docker image
	docker build -t $(DOCKER_IMAGE) .

.PHONY: docker-shell
docker-shell: ensure-image ## Start an interactive shell inside the development container
	docker run --rm -it -v $(PWD):/workspace -w /workspace $(DOCKER_IMAGE)

.PHONY: terraform-init
terraform-init: ensure-image ## Initialize Terraform working directory inside Docker
	$(DOCKER_RUN) terraform -chdir=infrastructure/terraform init

.PHONY: terraform-fmt
terraform-fmt: ensure-image ## Format Terraform configuration inside Docker
	$(DOCKER_RUN) terraform -chdir=infrastructure/terraform fmt

.PHONY: terraform-plan
terraform-plan: ensure-image ## Run terraform plan inside Docker
	$(DOCKER_RUN) terraform -chdir=infrastructure/terraform plan

.PHONY: terraform-apply
terraform-apply: ensure-image ## Apply terraform configuration inside Docker (requires approval)
	$(DOCKER_RUN) terraform -chdir=infrastructure/terraform apply

.PHONY: terraform-destroy
terraform-destroy: ensure-image ## Destroy terraform-managed infrastructure inside Docker (requires approval)
	$(DOCKER_RUN) terraform -chdir=infrastructure/terraform destroy
