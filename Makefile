# Makefile - helper tasks for Podman maintenance and slim builds

.PHONY: podman-recreate podman-prune build-slim build tag run verify-context

PODMAN_MACHINE ?= podman-machine-default
IMAGE_NAME ?= localhost/cipher-api:latest

podman-recreate:
	@echo "Recreate podman machine '${PODMAN_MACHINE}' with Alpine default image"
	./scripts/podman/recreate_machine.sh $(PODMAN_MACHINE) alpine:latest

podman-prune:
	@echo "Run prune inside podman machine and on the host"
	./scripts/podman/prune_vm.sh $(PODMAN_MACHINE)

# Build a squashed, tagged image using the repository Dockerfile. This helps remove
# intermediate layers and can significantly reduce the on-disk footprint after
# removing unused images.
verify-context:
	@./scripts/build/verify_context.sh

build-slim: verify-context
	@echo "Building a squashed image: $(IMAGE_NAME)"
	podman build --squash -t $(IMAGE_NAME) -f Dockerfile .

# Convenience targets
build: verify-context
	podman build -t $(IMAGE_NAME) -f Dockerfile .

tag:
	@echo "Tagging local image"
	podman tag $(IMAGE_NAME) $(IMAGE_NAME)

run:
	@echo "Run the cipher API container (port 3000)"
	podman run --rm -p 3000:3000 --name cipher_api $(IMAGE_NAME)

.PHONY: secrets-create secrets-from-env secure-start

secrets-create:
	@echo "Creating Podman secrets from KeyChain (if available)..."
	./scripts/secure-gemini-workflow.sh || echo "gemini secret creation failed or skipped"
	./scripts/secure-zai-workflow.sh || echo "zai secret creation failed or skipped"

secrets-from-env:
	@echo "Creating Podman secrets from environment variables if present..."
	@if [ -n "$$GEMINI_API_KEY" ]; then \
		temp=$$(mktemp); echo "$$GEMINI_API_KEY" > $$temp; chmod 600 $$temp; podman secret inspect cipher-gemini-api-key >/dev/null 2>&1 || podman secret create cipher-gemini-api-key $$temp && echo "created gemini secret from env"; rm -f $$temp; \
	else \
		echo "GEMINI_API_KEY not set in environment, skipping"; \
	fi
	@if [ -n "$$ANTHROPIC_API_KEY" ] || [ -n "$$ANTHROPIC_AUTH_TOKEN" ]; then \
		val="$${ANTHROPIC_API_KEY:-$$ANTHROPIC_AUTH_TOKEN}"; temp=$$(mktemp); echo "$$val" > $$temp; chmod 600 $$temp; podman secret inspect cipher-zai-api-key >/dev/null 2>&1 || podman secret create cipher-zai-api-key $$temp && echo "created zai secret from env"; rm -f $$temp; \
	else \
		echo "ANTHROPIC_API_KEY/ANTHROPIC_AUTH_TOKEN not set in environment, skipping"; \
	fi

secure-start: secrets-create secrets-from-env
	@echo "Starting Cipher via podman-compose or podman compose..."
	@if command -v podman-compose >/dev/null 2>&1; then \
		podman-compose up -d cipher-api; \
	else \
		podman compose up -d cipher-api; \
	fi
