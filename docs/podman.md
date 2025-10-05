# Podman on macOS and gvproxy

This document explains common Podman VM/networking behaviors on macOS and
how to avoid `gvproxy` port conflicts when running the Cipher API locally.

Key points

- Podman runs inside a VM on macOS. Each VM (machine) provides an isolated
  container runtime and its own set of images, secrets and containers.

- `gvproxy` is a host-side helper used by some Podman machines to forward host
  ports into the VM. If more than one Podman machine exists, an older machine's
  gvproxy process can bind host ports and block a new machine from taking the
  same ports.

Recommended workflow

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

Troubleshooting

- If `curl http://localhost:3000/health` times out: check
  `lsof -nP -iTCP:3000` to see which process is binding the host port.

- If an old machine's gvproxy owns the port, stop/remove that machine:

  ```bash
  podman machine stop podman-machine-default
  podman machine rm podman-machine-default
  ```

See also: `docs/vscode-ports.md` and `docs/ssh-tunnel.md`.
