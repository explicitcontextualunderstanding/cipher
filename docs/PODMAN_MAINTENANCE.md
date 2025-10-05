Podman maintenance and image slimming
====================================

This document collects the recommended steps to keep the Podman client and
the Podman machine (VM) in sync, shrink the VM footprint, and prevent
unnecessary image growth.

1) Align Podman client and server versions
-----------------------------------------

When the client and server versions diverge (for example client v5.6.x and
VM server v5.3.x) the easiest safe step is to recreate the VM. The scripts
in `/scripts/podman` automate this process:

- `scripts/podman/recreate_machine.sh` — stops and removes the machine,
  re-initializes it with a specified image (defaults to `alpine:latest`),
  starts it, and runs an initial prune.

Usage example from the project root:

```
./scripts/podman/recreate_machine.sh podman-machine-default alpine:latest
```

2) Slim the VM image
---------------------

By default Podman on macOS uses a Fedora-based VM image. You can choose a
smaller base image during `podman machine init`. The `recreate_machine.sh`
script above defaults to `alpine:latest` which reduces base footprint.

3) Prune unused data inside the VM and on host
----------------------------------------------

Use the helper script to prune dangling images, stopped containers, and
unused volumes both inside the VM and on the host:

```
./scripts/podman/prune_vm.sh
```

Or run the single command directly:

```
podman machine ssh -- podman system prune --all --volumes --force
podman system prune --all --volumes --force
```

4) Prevent image bloat (best practices)
--------------------------------------

- Use multi-stage builds so only the final artifacts land in the production
  image.
- Prefer minimal final base images where possible (Alpine, Debian Slim,
  or Distroless).
- Replace large libraries that bundle their own binaries with lightweight
  alternatives when feasible (e.g., `puppeteer-core` + system `chromium`
  instead of `puppeteer` which can pull a Chromium binary).
- Run package manager cleanups during the build (`pnpm prune --prod`,
  `pnpm store prune`, `npm ci --production`, `apk del` build dependencies,
  and clear caches).

Example slimming Dockerfile pattern (NodeJS + system Chromium):

```
FROM node:20 AS builder
WORKDIR /app
COPY package*.json pnpm-lock.yaml ./
RUN npm install -g pnpm && pnpm install --frozen-lockfile
COPY . .
RUN pnpm run build

FROM alpine:3.18
RUN apk add --no-cache chromium ca-certificates nss freetype
ENV PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium-browser
WORKDIR /app
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/node_modules ./node_modules
USER 1001
CMD ["node","dist/src/app/index.cjs"]
```

Notes:

- Consider moving from `puppeteer` to `puppeteer-core` and switching code to
  use the system-installed Chromium. This eliminates the Chromium binary
  from `node_modules` and significantly reduces image size.
- If you need even smaller images, investigate `gcr.io/distroless/nodejs`
  or other distroless images. These often require switching to glibc-based
  builds and careful dependency management.

Compose secrets and podman-compose behavior
------------------------------------------

Note: `podman-compose` has limited support for the Compose `secrets:` syntax. In
particular, `source`/`target` mappings are not supported and are ignored by
`podman-compose`. To ensure that a secret is mounted inside a container at
`/run/secrets/<name>` use the simple list form:

```
secrets:
  - cipher-gemini-api-key
  - cipher-zai-api-key
```

If you need to provide secrets in environments where Podman secrets cannot be
created (for example, CI runners that do not run a Podman VM), add a fallback
to read values from environment variables. In `scripts/load-secret.sh` the
project attempts to read `/run/secrets/<name>` first and then falls back to
checking environment variables such as `GEMINI_API_KEY` or
`ANTHROPIC_API_KEY` / `ANTHROPIC_AUTH_TOKEN`.

Use `podman secret inspect <name>` to verify that the secret exists in the
Podman machine before starting your compose stack.

5) Automating maintenance
-------------------------

Schedule a monthly job on your machine (cron) to recreate the machine and
prune caches. Example crontab entry (run as your user):

```
# Monthly: 1st of month at 02:30
30 2 1 * * /Users/you/workspace/cipher/scripts/podman/recreate_machine.sh podman-machine-default alpine:latest >> /var/log/podman-maintenance.log 2>&1
```

Alternatively, you can add a dispatchable GitHub Action or a self-hosted
runner workflow to trigger these scripts from CI if you operate a machine
tagged `self-hosted`.

6) Quick checklist to reduce current images
-------------------------------------------

- Recreate Podman machine with `alpine:latest`.
- Run `./scripts/podman/prune_vm.sh` after builds/tests.
- Replace heavy runtime deps (Chromium, model weights) with system
  installations where possible or mount them from host volumes.
- Use `make build-slim` to build a squashed image and then prune.
