# Podman on macOS and gvproxy

This document explains common Podman VM/networking behaviors on macOS and
how to avoid `gvproxy` port conflicts when running the Cipher API locally.

## Key Points

- Podman runs inside a VM on macOS. Each VM (machine) provides an isolated
  container runtime and its own set of images, secrets and containers.

- `gvproxy` is a host-side helper used by some Podman machines to forward host
  ports into the VM. If more than one Podman machine exists, an older machine's
  gvproxy process can bind host ports and block a new machine from taking the
  same ports.

- **Container Build Success**: Cipher now builds successfully with optimized
  memory settings and proper NodeNext module resolution via bundling.

## Recommended Workflow

1. Create / use a single Podman machine for development (use user-mode
   networking / slirp for predictable host port mapping):

   ```bash
   podman machine init --user-mode-networking --name podman-machine-slirp
   podman machine start podman-machine-slirp
   podman system connection default podman-machine-slirp
   ```

2. Create required secrets inside the target machine (see scripts/secure-*)

3. Deploy the stack with `podman compose` or `podman-compose` while the
   client is connected to the correct machine.

## Recent Build Improvements

The Cipher container build has been optimized to address memory constraints and
module resolution issues:

- **Memory Optimization**: Added `NODE_OPTIONS="--max-old-space-size=4096"` to Dockerfile
- **Build Configuration**: Optimized tsup config with reduced concurrency and no minification
- **Module Resolution**: Enabled bundling for proper NodeNext `.js` extension resolution
- **Container Success**: Container now builds and runs successfully with all services initialized

### Build Status

- ✅ TypeScript compilation (DTS build) - 386KB type definitions
- ✅ Core module bundling - 1.85MB CJS, 1.84MB ESM
- ✅ App module bundling - 2.14MB CJS
- ✅ Production image creation with all dependencies
- ✅ Container startup and API server initialization

## Cipher Container Setup

### Secrets Management

Create and mount secrets into the Podman VM for secure API key storage:

```bash
# Create secrets from files containing your API keys
podman secret create cipher-gemini-api-key path/to/gemini.key
podman secret create cipher-zai-api-key path/to/zai.key

# Verify secrets are available in the VM
podman secret ls
```

### Container Port Exposure

The Cipher container uses gvproxy to expose port 3000 from the VM to the host:

```bash
# gvproxy forwards host port 3000 to VM port 3000
*:3000 (host) → VM:3000 → container:3000

# Check if gvproxy is properly forwarding
lsof -i :3000
# Should show: gvproxy LISTEN *:3000
```

### Container Health Checks

The Cipher container includes health endpoints for monitoring:

```bash
# Standard health check
curl http://localhost:3000/health

# Fast health check (for container healthcheck)
curl http://localhost:3000/health/fast
```

### Validation Commands

Use these commands to validate your container setup:

```bash
# Check container status
podman ps
# Should show cipher_cipher-api_1 container as "Up" and healthy

# Verify port binding on host
ss -tulpn | grep :3000
# Should show gvproxy or similar process listening

# Test from within the VM (if needed)
podman machine ssh podman-machine-slirp
curl http://localhost:3000/health
```

### MCP SSE Endpoint Validation

After the container is running, validate the MCP SSE functionality:

```bash
# Test basic health endpoint
curl http://localhost:3000/health

# Test MCP SSE endpoint (should return streaming response)
curl --max-time 5 http://localhost:3000/mcp/sse
# Expected output: event: endpoint\ndata: /mcp?sessionId=<session-id>

# Verify MCP transport type is correctly configured
podman logs cipher_cipher-api_1 | grep "MCP server with transport type"
# Should show: "Setting up MCP server with transport type: sse"
```

### Docker Compose Integration

The `docker-compose.yml` automatically handles secrets mounting and MCP configuration:

```yaml
version: "3.8"

services:
  cipher-api:
    build: .
    image: cipher-api
    ports:
      - '3000:3000'
    environment:
      - CIPHER_API_PREFIX=""
      - CIPHER_LOG_LEVEL=debug
      - MCP_SERVER_MODE=aggregator
      - MCP_TRANSPORT_TYPE=sse
      - GEMINI_API_KEY_FILE=/run/secrets/cipher-gemini-api-key
      - ANTHROPIC_API_KEY_FILE=/run/secrets/cipher-zai-api-key
    secrets:
      - cipher-gemini-api-key
      - cipher-zai-api-key
    command:
      - 'sh', '-c', 'node dist/src/app/index.cjs --mode api --port $$PORT --host 0.0.0.0 --agent $$CONFIG_FILE --mcp-transport-type $$MCP_TRANSPORT_TYPE'

secrets:
  cipher-gemini-api-key:
    external: true
  cipher-zai-api-key:
    external: true
```

**Key Configuration Notes:**

- **MCP_TRANSPORT_TYPE**: Set to `sse` to enable Server-Sent Events transport
- **MCP_SERVER_MODE**: Set to `aggregator` for MCP server functionality
- **Secret Loading**: The built-in entrypoint handles secret loading automatically
- **Command Override**: The compose command explicitly passes the MCP transport type to ensure proper configuration

The container's built-in entrypoint (`/usr/local/bin/entrypoint.sh`) automatically loads secrets from `/run/secrets/` into environment variables at startup.

Troubleshooting

- If `curl http://localhost:3000/health` times out: check
  `lsof -nP -iTCP:3000` to see which process is binding the host port.

- If an old machine's gvproxy owns the port, stop/remove that machine:

  ```bash
  podman machine stop podman-machine-default
  podman machine rm podman-machine-default
  ```

SSH tunnel OK but host mapping failing

If you've validated the SSH reverse tunnel (for example, using
`scripts/diagnose/tunnel-replay.sh` or a manual `ssh -R` test) and the
remote side reports the health endpoint is reachable, but the macOS host
(`localhost:3000`) still returns connection errors, the problem is most
likely the host-side port forward (gvproxy) or an old Podman machine owning
the host port.

Checklist (non-destructive)

1. Confirm the tunnel: on the remote host (Jetson) the forwarded port should
  show a listener and return the service health:

```bash
ssh user@jetson 'ss -ltnp | grep :3001 || true'
ssh user@jetson 'curl -sS --max-time 5 http://127.0.0.1:3001/health || echo "remote-curl-failed"'
```

1. Confirm the container is healthy inside the Podman VM (run inside the VM):

```bash
podman machine ssh <your-machine> "curl -sS --max-time 5 http://localhost:3000/health || echo vm-curl-failed"
```

1. If the VM responds but the macOS host `localhost:3000` does not, inspect
  the host-side forward process and the Podman machines:

```bash
# Who owns host port 3000?
sudo lsof -nP -iTCP:3000 -sTCP:LISTEN

# Which Podman machines exist and their state
podman machine ls
```

1. If `lsof` shows `gvproxy` owning the port but the machine is an older
  machine (not the one you expect to be using), stop/remove the stale
  machine rather than killing processes directly:

```bash
podman machine stop <old-machine-name>
podman machine rm <old-machine-name>
```

1. Start or recreate the desired machine using user-mode networking (slirp)
  for predictable host mapping (recommended for local dev):

```bash
podman machine init --user-mode-networking --name podman-machine-slirp
podman machine start podman-machine-slirp
podman system connection default podman-machine-slirp
```

1. Restart your compose stack (or the single container) so gvproxy is created
  by the active machine and binds host ports correctly:

```bash
# From repo root
podman compose up -d
podman ps
```

1. Re-check the host binding and health endpoint on macOS:

```bash
sudo lsof -nP -iTCP:3000 -sTCP:LISTEN
curl -v --max-time 5 http://127.0.0.1:3000/health
```

If you still see a mismatch (VM responds, host does not) and `podman machine
ls` shows only the expected machine, consider restarting the Podman service
or rebooting the host to clear stale `gvproxy` processes created by removed
machines.

CAUTION: Avoid killing `gvproxy` or other system processes directly unless
you understand which Podman machine created them. Prefer stopping/removing
Podman machines and restarting the Podman-managed VM so the runtime recreates
`gvproxy` properly.

See also: `docs/vscode-ports.md` and `docs/ssh-tunnel.md`.

Remote owner capture helper

If the tunnel/forwarding behavior is intermittent and you need to capture who
is claiming the remote port (for example, VS Code server or an orphaned test
process), use `scripts/autossh/log_port_owner.sh` (local) to sample remote
port owner information and write it to `$HOME/Library/Logs/cipher-port-owner-history.log`.

To allow non-interactive `lsof` on the Jetson (so samples include the process
owner lines without prompting for sudo), run the helper on the Jetson to add
a minimal sudoers fragment:

```bash
# On Jetson (run as root or with sudo):
sudo ./scripts/autossh/install_passwordless_lsof.sh amazon1148
```

After installing passwordless `lsof` for the diagnostic user, run the owner
collector from your Mac and review the log to locate intermittent port steals.
