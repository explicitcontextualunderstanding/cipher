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

- `cipher-gemini-api-key` (Gemini / Google Generative API)
- `cipher-zai-api-key` (Anthropic / Z.ai)
- `cipher-openai-api-key`, `cipher-openrouter-api-key`, `cipher-qwen-api-key`, `cipher-voyage-api-key`, `cipher-deepseek-api-key`
- `cipher-gcp-adc` (Google Application Default Credentials file)

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
