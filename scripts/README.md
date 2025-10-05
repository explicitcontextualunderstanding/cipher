# Scripts index for Cipher

This directory contains helper scripts used for local development, Podman workflows, diagnostics and secure secret management.

High-level guidance:

- Canonical operational guidance (workflows, examples, security best practices) is in `docs/secrets.md`.
- Use the individual scripts below for automation and ad-hoc operations. The scripts are intended to be runnable from the repository root (e.g. `./scripts/create-gemini-secret.sh`).

Key scripts (short summary) and locations after reorganization:

- `scripts/podman/` — Podman-related helpers and idempotent secret primitives:
  - `create-gemini-secret.sh` — create/replace the `cipher-gemini-api-key` Podman secret (non-interactive; falls back to env/KeyChain).
  - `create-podman-secrets.sh` — bulk idempotent secret creation helper; reads env or KeyChain and creates the `cipher-*` secrets.
  - `manage-podman-secrets.sh`, `secure-gemini-workflow.sh`, `secure-zai-workflow.sh`, `podman_cipher_diag.sh`.

- `scripts/gcp/` — Google Cloud ADC and GCP-related helpers:
  - `create-gcp-secret.sh`, `setup-gcp-adc.sh`, `start-cipher-with-gcp.sh`.

- `scripts/run/` — runtime/startup helpers for local dev and container startup scripts:
  - `load-secret.sh`, `start-with-secret.sh`, `start-with-secrets.sh`, `secure-cipher-start.sh`, `deploy-with-secrets.sh`.

- `scripts/autossh/` — autossh helpers and launchd plists:
  - `autossh_start.sh`, `autossh_watchdog.sh`, `check_autossh_forward.sh`, `com.cipher.autossh.plist`, `com.cipher.autossh.watchdog.plist`.

- Other utilities in `scripts/` remain (e.g. `generate-env.sh`, `get-api-key.sh`, `store-api-key.sh`, `derive_vscode_ssh_remote_ip.sh`).

Organization notes:

- For long-form operational guidance (security rationale, recommended workflows, compose patterns) refer to `docs/secrets.md` rather than individual script READMEs. The `scripts/` README is an index.
- Do not commit real secrets. Use KeyChain, Podman secrets or your CI provider's secret mechanism instead.

If you want me to move specific scripts into a `scripts/maintenance/` or `scripts/podman/` subfolder and update usages, tell me which scripts to relocate.
