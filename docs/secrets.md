# Secrets management (macOS Keychain, Podman secrets, .env and compose)

This document explains how Cipher manages secrets for local development and secure deployments on macOS. It describes the different storage options (macOS Keychain, environment variables, Podman secrets and Docker/Podman Compose secrets), the scripts provided in `scripts/` to create/load secrets, and recommended workflows.

## Scope

- local developer workflows on macOS
- Podman-based development (macOS VM machines)
- secure deployment helpers and GCP ADC integration

## Goals

- avoid committing secrets to the repository
- prefer secure OS key stores (macOS Keychain) for interactive development
- provide idempotent, non-interactive helpers for CI / reproducible setup
- ensure secrets are injected into containers securely (mounted as files under `/run/secrets`)

## Terminology

- KeyChain: macOS Keychain (accessed via the `security` CLI)
- Podman secret: Podman-managed secret stored inside a Podman machine (accessible to containers via `/run/secrets/<name>`)
- env/.env: environment variables and the local `.env` file used as an override for development (NOT recommended for production)

## Overview of available scripts

All helper scripts live under `scripts/`.

### Idempotent utilities

- `scripts/podman/secret_utils.sh`
  - Utility functions used by other scripts to create, replace and track podman secrets safely.
  - Stores SHA256 hashes in `$HOME/.local/share/cipher/secrets` to avoid recreating secrets when content is unchanged.

### KeyChain ↔ Podman secret helpers (interactive / non-interactive)

- `scripts/secure-gemini-workflow.sh`
  - Interactive workflow: read GEMINI_API_KEY from macOS Keychain (or environment), write to a temporary file with restrictive permissions, create/replace a Podman secret `cipher-gemini-api-key` and securely remove the temp file.

- `scripts/secure-zai-workflow.sh`
  - Similar workflow for Z.ai / Anthropic keys. Tolerant of different KeyChain service names and environment fallbacks.

- `scripts/create-gemini-secret.sh`, `scripts/create-podman-secrets.sh`, `scripts/create-gcp-secret.sh`
  - Non-interactive helpers to create single or bulk Podman secrets from KeyChain or environment variables.

- `scripts/manage-podman-secrets.sh`
  - High-level wrapper to `create`, `recreate`, `delete` or `list` cipher-related Podman secrets.

### KeyChain ↔ Environment helpers

- `scripts/generate-env.sh`
  - Generates a `.env` file from KeyChain entries (useful for local dev). Backs up an existing `.env` before overwriting.

- `scripts/set-env-from-keychain.sh`
  - Minimal helper to export a small set of environment variables from KeyChain into the current shell.

- `scripts/get-api-key.sh`, `scripts/store-api-key.sh`
  - Small utilities to read and write a specific KeyChain entry. Example usage to add a key:

    ```bash
    ./scripts/store-api-key.sh google-api-key "<the-key>"
    ```

### Podman / Compose deployment helpers

- `scripts/secure-cipher-start.sh`, `scripts/start-with-secrets.sh`, `scripts/start-with-secret.sh`
  - Start scripts that load secrets from Podman secrets (or KeyChain) and start the Cipher service with secrets available in the container.

- `scripts/deploy-with-secrets.sh`
  - Convenience script that retrieves keys from KeyChain, creates temp secret files and runs `podman-compose` to build and bring up the stack.

- `scripts/start-cipher-with-gcp.sh`, `scripts/create-gcp-secret.sh`, `scripts/setup-gcp-adc.sh`
  - Helpers to integrate Google Cloud Application Default Credentials into Cipher (create Podman secret `cipher-gcp-adc` and start compose stacks that mount it).

### Monitoring / diagnostics

- `scripts/podman_cipher_diag.sh` — collects Podman & host networking information and basic health checks.
- `scripts/check_autossh_forward.sh` — verifies remote reverse SSH forwards and performs quick remote curl checks.

## Where secrets end up

- macOS KeyChain: strongly recommended for developer machines. Use `security add-generic-password` to create entries and `security find-generic-password -w` to read them.

- Environment variables: convenient for ephemeral shells or CI. Use the `scripts/generate-env.sh` to create a `.env` for local testing, but do not commit this file.

- Podman secrets: the preferred method for running containers under Podman on macOS; secrets appear as files in containers under `/run/secrets/<name>`.

- Docker Compose `secrets:`: Compose files in this repo include variants showing both env-file and Compose secrets. For Podman, use the simple `secrets: [cipher-...]` list form (podman-compose has limited support for the full `source/target` syntax).

## Example secret names used in the repo

- Required for the recommended local development flow (minimal):
  - `cipher-gemini-api-key` — Gemini (Google Generative) — used for embeddings only
  - `cipher-zai-api-key` — Anthropic / Z.ai — used for the LLM (inference) only

- Optional / integration keys (not required for the minimal dev flow):
  - `cipher-openai-api-key`, `cipher-openrouter-api-key`, `cipher-qwen-api-key`, `cipher-voyage-api-key`, `cipher-deepseek-api-key`

Why so many keys are listed?

- Flexibility / multi-backend support: the codebase and compose files include plumbing to support multiple LLM and embedding providers so teams can swap providers or run fallbacks. That support is why the docs and scripts enumerate many provider-specific secret names.
- Compose and scripts convenience: `docker-compose.podman-secrets.yml` and the secret helper scripts list a broad set of secrets so automated helpers can create or validate any provider-specific secret if you choose to use it.
- Historical/optional integrations: other projects in this workspace (for example `SurfSense`) and shared tooling include support for TTS/STT and other provider integrations; the presence of provider names in other repos explains why the examples include them.

Do you actually need all of them to run Cipher locally?

- No. For a standard local development setup that exercises embedding + LLM functionality you only need Gemini for embeddings and Anthropic (Z.ai) for LLM calls. The other keys are optional and only required if you want to enable those specific provider integrations.

How to reduce the required keys when using Podman / podman-compose

Podman-compose requires declared top-level secrets and will fail if an `external` secret is listed but not present. To avoid failures when you don't have all provider keys locally, use one of these approaches:

1. Use the minimal compose variant that references only Gemini + Z.ai. The default `docker-compose.podman-secrets.yml` now declares only these two required secrets.

2. When you need optional provider integrations, either:
   - Create the provider secrets using the secure workflows, or
   - Include the optional override file once you have created the matching secrets:

     podman compose -f docker-compose.podman-secrets.yml -f docker-compose.podman-secrets-optional.yml up -d

3. For quick testing without real credentials, create non-secure placeholder secrets for optional providers (replace them with real secrets later):

   ./scripts/podman/create-podman-secrets.sh --create-placeholders

How we determined this (audit of container feedback and scripts)

- The compose file used for Podman (`docker-compose.podman-secrets.yml`) lists many provider secret environment variables and service `secrets:` entries — podman-compose will refuse to start services if an external secret listed there does not exist (which is why you may have seen errors earlier during `podman compose up`).
- The secret helper scripts (`scripts/podman/create-podman-secrets.sh`, `scripts/podman/secure-*`) attempt to create a broad set of provider secrets by default for convenience; they are idempotent and will skip secrets that have no data in KeyChain or env.
- Application code and related repos show multi-provider support (examples / enums referencing OPENAI, ANTHROPIC, OPENROUTER, etc.) — this explains why the project documents and scripts enumerate many possible secret names even though a minimal dev run only needs two.

Recommendation

- For everyday local development: create only the Gemini and Anthropic secrets (use `scripts/podman/secure-gemini-workflow.sh` and `scripts/podman/secure-zai-workflow.sh`) and use the compose variant that only requires those secrets.
- If you need support for an additional provider later, add that provider's KeyChain entry and run the matching `secure-*` script or create the Podman secret from a file or env variable.
- `cipher-gcp-adc` (Google Application Default Credentials file)

Note: to make bringing the stack up repeatable we provide a wrapper script:

```bash
./scripts/podman/compose-up.sh --create-placeholders --include-optional --wait-seconds 60
```

This wrapper ensures required secrets (optionally creating placeholders), starts the compose stack (including optional provider overrides when requested), and waits for the service health endpoint.

## Environment Variables for Cipher MCP SSE Service

When running Cipher as an MCP SSE service with Podman secrets, the following environment variables are required:

```bash
# MCP Server Mode (required for aggregator mode)
MCP_SERVER_MODE=aggregator

# API Key File Paths (point to secrets mounted in container)
GEMINI_API_KEY_FILE=/run/secrets/cipher-gemini-api-key
ANTHROPIC_API_KEY_FILE=/run/secrets/cipher-zai-api-key

# Optional: Additional configuration
CIPHER_LOG_LEVEL=debug
```

## Podman Secrets Creation

Create and use Podman secrets for secure API key storage:

```bash
# Create secrets from files containing your API keys
podman secret create cipher-gemini-api-key path/to/gemini.key
podman secret create cipher-zai-api-key path/to/zai.key

# Verify secrets are available in the VM
podman secret ls
```

## Docker Compose Integration

Use secrets in your `docker-compose.yml` for secure key injection:

```yaml
version: "3.8"

services:
  cipher-api:
    image: cipher-api
    environment:
      - CIPHER_LOG_LEVEL=debug
      - MCP_SERVER_MODE=aggregator
      - GEMINI_API_KEY_FILE=/run/secrets/cipher-gemini-api-key
      - ANTHROPIC_API_KEY_FILE=/run/secrets/cipher-zai-api-key
    secrets:
      - cipher-gemini-api-key
      - cipher-zai-api-key
    command:
      - '/tmp/load-secret.sh'
    volumes:
      - ./scripts/run/load-secret.sh:/tmp/load-secret.sh:ro

secrets:
  cipher-gemini-api-key:
    external: true
  cipher-zai-api-key:
    external: true
```

## Load Script Usage

The `scripts/load-secret.sh` script automatically loads secrets into environment variables at container startup:

```bash
#!/bin/bash
# This script loads Podman secrets into environment variables

echo "🔑 Loading API keys from Podman secrets..."
if [ -f "/run/secrets/cipher-gemini-api-key" ]; then
  export GEMINI_API_KEY=$(cat /run/secrets/cipher-gemini-api-key)
  echo "✅ GEMINI_API_KEY loaded from secret file"
fi

if [ -f "/run/secrets/cipher-zai-api-key" ]; then
  export ANTHROPIC_API_KEY=$(cat /run/secrets/cipher-zai-api-key)
  echo "✅ ANTHROPIC_API_KEY (Z.ai) loaded from secret file"
fi

# Start Cipher with secure API keys
echo "🚀 Starting Cipher with secure API keys in aggregator mode..."
exec node dist/src/app/index.cjs --mode api --port 3000 --host 0.0.0.0
```

## MCP Connectivity Validation

Use the `baseline-mcp-validation.sh` script to test connectivity and secret loading:

```bash
#!/bin/bash
# MCP connectivity and secret validation script

echo "🔍 Validating MCP service setup..."

# Test health endpoint
curl -s http://localhost:3000/health | jq .

# Test SSE endpoint
curl -s http://localhost:3000/mcp/sse --max-time 5

# Verify MCP client can connect
claude mcp list
```

This script validates:

- Container health status
- SSE endpoint accessibility
- MCP client connectivity
- Secret loading functionality

## Recommended development workflows

### 1) Interactive developer (recommended)

- Store secrets in KeyChain once, for example:

    ```bash
    security add-generic-password -a "kieran@rossollc.com" -s "GEMINI_API_KEY" -w "<key>"
    ```

- Use `scripts/secure-gemini-workflow.sh` (or `scripts/create-gemini-secret.sh`) to create a Podman secret from the KeyChain value:

    ```bash
    ./scripts/secure-gemini-workflow.sh
    ```

- Ensure your client is connected to the intended Podman machine (secrets are per-machine):

    ```bash
    podman system connection default <your-machine>
    ```

- Start the stack using Podman Compose variants that mount the secrets, e.g.:

    ```bash
    podman compose -f docker-compose.podman-secrets.yml up -d
    ```

- Inside the running container secrets will be available at `/run/secrets/<name>` and helper scripts in this repo expect them there.

### 2) Quick local dev using environment variables

- If you prefer environment variables for quick iterations, either export keys in your shell or use `scripts/set-env-from-keychain.sh` to load keys into the current shell.

- Start the service using `podman-compose` or `podman compose` with `docker-compose-with-secrets.yml` or `docker-compose.secure.yml` depending on whether you want env-file vs secrets.

- Remember: environment variables are visible to other processes on the machine and are not as secure as KeyChain + Podman secrets.

### 3) CI / automated (non-interactive)

- Use `scripts/create-podman-secrets.sh` and `scripts/create-gcp-secret.sh` in CI runners that have access to the required secret values via environment variables or mounted ADC files.

- For non-Podman CI (e.g., Docker-based runners), inject secrets via your CI provider's secrets mechanism and mount them as files or environment variables at runtime.

## Compose file patterns and examples

- `docker-compose.podman-secrets.yml` and `docker-compose.gcp.yml` demonstrate the `secrets:` mapping and `ANTHROPIC_API_KEY_FILE` style env var pointing at `/run/secrets/<name>`.

- `docker-compose-with-secrets.yml` shows an example that uses env_file + mapped env var fallbacks for development.

## Idempotency and safety

- All secret-creation helpers are designed to be idempotent: `create_or_replace_secret_from_file` will compute a SHA256 of the content and only replace a Podman secret if the content changed.

- Temporary files created during secret creation are written with `chmod 600` and cleaned up immediately.

## Security features

- KeyChain Storage: API keys stored in macOS KeyChain with proper encryption.
- Temporary Files: Keys written to temporary files with 600 permissions and removed immediately after creating secrets.
- No Plaintext in Git: No API keys stored in repository or configuration files.
- Container Isolation: Keys injected via Podman/Docker secrets or environment variables according to the deployment model.
- Audit Trail: KeyChain access is logged by macOS.

## Best practices and hardening

- Prefer KeyChain → Podman secret workflow over plain `.env` files for local dev.
- Never commit `.env` files containing real keys. `.env.example` can show variable names but must not contain secrets.
- Rotate keys regularly and invalidate old credentials in provider consoles.
- Limit scope of API keys (least privilege) and avoid long lived broad-scope keys where possible.
- Use Podman machine-specific secrets carefully: secrets are stored per Podman machine. If you switch default machines, re-create the secrets on the new machine.

## Troubleshooting

- Podman secret not visible in container:
  - Ensure you created the secret in the active Podman machine (`podman system connection default <machine>`).
  - Run `podman secret list` and `podman secret inspect <name>` on the machine.

- Compose shows containers but service cannot read secret:
  - Confirm the Compose file includes `secrets:` and that the service uses the expected env var or reads `/run/secrets/<name>`.

- KeyChain lookups failing in scripts:
  - Confirm the `security` CLI returns the secret value manually first:

    ```bash
    security find-generic-password -a "kieran@rossollc.com" -s "GEMINI_API_KEY" -w
    ```

- Podman host port conflicts when testing locally:
  - See `docs/podman.md` — ensure only the intended Podman machine's gvproxy is binding host ports.

## Quick commands

- Create a KeyChain entry (example):

    ```bash
    security add-generic-password -a "kieran@rossollc.com" -s "GEMINI_API_KEY" -w "<key>"
    ```

- Create a Podman secret from a KeyChain value (non-interactive):

    ```bash
    ./scripts/create-gemini-secret.sh
    ```

- List Podman secrets:

    ```bash
    podman secret list
    ```

- Inspect a specific Podman secret:

    ```bash
    podman secret inspect cipher-gemini-api-key
    ```

- Generate `.env` from KeyChain (local dev):

    ```bash
    ./scripts/generate-env.sh
    ```

## Appendix: where to look in the repo

- `scripts/` — all secret creation, loading, and management helpers
- `scripts/podman/secret_utils.sh` — idempotent secret creation primitives
- `docker-compose.podman-secrets.yml`, `docker-compose.gcp.yml`, `docker-compose-with-secrets.yml` — compose examples showing secret wiring
- `docs/podman.md` — Podman/macOS network and gvproxy notes that are useful when verifying remote access to local services

If you want, I can add a short "quickstart" or cheatsheet file for README references.
