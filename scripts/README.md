# Scripts index for Cipher

This directory contains helper scripts used for local development, Podman workflows, diagnostics and secure secret management.

High-level guidance:

- Canonical operational guidance (workflows, examples, security best practices) is in `docs/secrets.md`.
- Use the individual scripts below for automation and ad-hoc operations. The scripts are intended to be runnable from the repository root (e.g. `./scripts/create-gemini-secret.sh`).

Key scripts (short summary):

- `create-gemini-secret.sh` — create/replace the `cipher-gemini-api-key` Podman secret (non-interactive; falls back to env/KeyChain).
- `create-podman-secrets.sh` — bulk idempotent secret creation helper; reads env or KeyChain and creates the `cipher-*` secrets.
- `secure-gemini-workflow.sh` / `secure-zai-workflow.sh` — interactive KeyChain → temporary file → Podman secret workflows.
- `create-gcp-secret.sh` / `start-cipher-with-gcp.sh` — helpers for Google ADC integration and starting the stack with GCP credentials.
- `generate-env.sh` / `set-env-from-keychain.sh` — generate or export a `.env` from KeyChain entries for local development.
- `load-secret.sh`, `start-with-secrets.sh`, `start-with-secret.sh` — runtime startup helpers that load Podman secrets into container startup environments.
- `podman_cipher_diag.sh`, `check_autossh_forward.sh` — diagnostics and network / IV forward checks useful for troubleshooting host/VM/Jetson networking.

Organization notes:

- For long-form operational guidance (security rationale, recommended workflows, compose patterns) refer to `docs/secrets.md` rather than individual script READMEs. The `scripts/` README is an index.
- Do not commit real secrets. Use KeyChain, Podman secrets or your CI provider's secret mechanism instead.

If you want me to move specific scripts into a `scripts/maintenance/` or `scripts/podman/` subfolder and update usages, tell me which scripts to relocate.
