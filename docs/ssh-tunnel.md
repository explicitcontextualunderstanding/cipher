# Troubleshooting checklist — reproduce & fix a broken MCP connection

When `claude mcp list` shows the SSE entry as ✗ Failed to connect, follow this concise, repeatable checklist to determine whether the problem is the local Podman host mapping, the reverse SSH tunnel, or a remote port conflict (for example, VS Code auto-forwards or leftover diagnostics processes).

1. Confirm the Cipher API on macOS is healthy (host)

```bash
# Should return HTTP/200 and JSON
curl -v --max-time 5 http://127.0.0.1:3000/health
# Confirm a TCP accept on the host
nc -vz 127.0.0.1 3000
# Which host process owns the listening port?
sudo lsof -nP -iTCP:3000 -sTCP:LISTEN
```

Expected: HTTP 200 and `lsof` shows either `gvproxy` (Podman VM forward) or the container runtime process. If the host health check fails, fix the Podman host mapping first (see `docs/podman.md`) — common actions: restart the Podman machine or recreate the container using a slirp4netns-backed machine.

1. Attempt a one-off manual reverse SSH forward (mac → Jetson) to prove the bind and forwarding path

```bash
# Stop autossh to avoid a race
launchctl bootout gui/$UID ~/Library/LaunchAgents/com.cipher.autossh.plist 2>/dev/null || true
# Run manual verbose SSH so you can capture and inspect debug lines
ssh -vv -o ExitOnForwardFailure=yes -N -R 127.0.0.1:3001:127.0.0.1:3000 amazon1148@<JETSON_IP> 2>&1 | tee /tmp/manual_ssh.log
```

What to look for in `/tmp/manual_ssh.log`:

- `remote forward success for: listen 127.0.0.1:3001` — bind succeeded
- `connect_next: connect host 127.0.0.1 ([127.0.0.1]:3000) in progress` and `channel X: connected to 127.0.0.1 port 3000` — remote requests are being forwarded into the local service

1. On the Jetson, verify the listener and test the forwarded endpoint

```bash
# On Jetson (interactive)
ss -ltnp | grep :3001 || true
sudo lsof -i :3001 || true
curl -v --max-time 5 http://127.0.0.1:3001/health || true
```

Expected: `ss` shows `LISTEN 127.0.0.1:3001` and `curl` returns the JSON you saw from the mac-side health check.

1. If the manual test works but `claude mcp list` still fails with autossh loaded

```bash
tail -n 200 ~/Library/Logs/cipher-autossh.log
ps aux | egrep 'autossh|ssh .* -R' | grep -v grep
```

If the autossh log shows repeated `remote port forwarding failed for listen port 3001` then a remote process is racing to own 3001 (often a VS Code server auto-forward). See step 5.

1. If the Jetson shows a process bound to 3001 (for example `code-server`), prefer the non-destructive persistent fix:

```bash
# Apply Remote Machine settings on the Jetson (Insiders path shown)
mkdir -p ~/.vscode-server-insiders/data/Machine
cp ~/.vscode-server-insiders/data/Machine/settings.json ~/.vscode-server-insiders/data/Machine/settings.json.bak 2>/dev/null || true
cat > ~/.vscode-server-insiders/data/Machine/settings.json <<'JSON'
{
  "remote.autoForwardPorts": false,
  "remote.portsAttributes": {
    "3000": { "onAutoForward": "ignore" },
    "3001": { "onAutoForward": "ignore" }
  }
}
JSON
# Reconnect your Remote-SSH client so the change takes effect (or restart the remote server process)
pkill -f 'code-server-insiders.*server' || true

# Confirm the port is freed
sudo ss -ltnp | grep :3001 || true
```

If you cannot change the remote client immediately, use a non-disruptive fallback:

1. Quick fallback — try a different remote port (opt-in autossh fallback)

Set these environment variables (in the LaunchAgent or your shell) before reloading:

```bash
export CIPHER_AUTOSSH_ALT_REMOTE_PORT=3002
export CIPHER_AUTOSSH_ENABLE_ALT_ON_BLOCK=true
export CIPHER_AUTOSSH_WAIT_TIMEOUT=60
```

Then reload the LaunchAgent and re-check:

```bash
launchctl bootout gui/$UID ~/Library/LaunchAgents/com.cipher.autossh.plist 2>/dev/null || true
launchctl bootstrap gui/$UID ~/Library/LaunchAgents/com.cipher.autossh.plist
scripts/autossh/check_autossh_forward.sh amazon1148@<JETSON_IP>
claude mcp list
```

1. If host-side port mapping to the container (Podman / gvproxy) is the blocker

Inspect the host forwarding process (`gvproxy`) and consider restarting the Podman machine or recreating it with slirp4netns (see `docs/podman.md`). Quick test options:

```bash
# If gvproxy owns the port, inspect/stop the old machine
sudo lsof -nP -iTCP:3000 -sTCP:LISTEN
podman machine ls
```

1. When you have a successful manual-forward test and the host mapping is healthy, re-enable the autossh LaunchAgent to make the tunnel persistent (recommended):

```bash
launchctl bootout gui/$UID ~/Library/LaunchAgents/com.cipher.autossh.plist 2>/dev/null || true
launchctl bootstrap gui/$UID ~/Library/LaunchAgents/com.cipher.autossh.plist
scripts/autossh/check_autossh_forward.sh amazon1148@<JETSON_IP>
claude mcp list
```

Avoid killing `sshd` on the Jetson. Prefer disabling VS Code auto-forwards or restarting the remote server. Killing `sshd` will terminate all SSH sessions.

Capture SSH verbose logs to files (`ssh -vv`) for debugging and attach them when filing issues.

The `scripts/autossh/check_autossh_forward.sh` helper automates many of these steps and now prints the owning PID and relevant process details.

Using the diagnostic helper

This repository includes a helper script `scripts/diagnose/tunnel-replay.sh` that automates the checklist above: it stops the autossh LaunchAgent (to avoid bind races), attempts a one-off verbose manual reverse SSH forward, runs the remote listener and /health checks (via `scripts/autossh/check_autossh_forward.sh`), and can re-enable autossh when finished. The script is conservative and will not kill `sshd`.

Quick examples

- Run the full replay (stop autossh, start manual forward, re-enable autossh):

```bash
./scripts/diagnose/tunnel-replay.sh amazon1148@<JETSON_IP>
```

- Try an alternate remote bind port (temporary remediation if 3001 is blocked):

```bash
./scripts/diagnose/tunnel-replay.sh --alt-port 3002 amazon1148@<JETSON_IP>
```

- Run the manual SSH in the foreground for interactive debugging:

```bash
./scripts/diagnose/tunnel-replay.sh --foreground amazon1148@<JETSON_IP>
```

- Skip re-enabling autossh (useful when you want to investigate manually):

```bash
./scripts/diagnose/tunnel-replay.sh --no-reload amazon1148@<JETSON_IP>
```

- Start the replay and automatically cleanup the transient manual SSH afterwards:

```bash
./scripts/diagnose/tunnel-replay.sh --cleanup amazon1148@<JETSON_IP>
```

Important outputs and logs

- Manual SSH verbose log: /tmp/manual_ssh.log
- autossh wrapper log: ~/Library/Logs/cipher-autossh.log
- autossh debug log: /tmp/autossh.log

Suggested remediation flow

1. Run the replay script once to reproduce the failure and collect logs.
2. If the replay identifies a remote process (for example `code-server`) owning the bind, apply the Remote Machine settings from step 5 on the Jetson and restart the remote VS Code server.
3. If you cannot immediately change the remote client, re-run the replay with `--alt-port` to temporarily migrate the tunnel to a different remote port and then update your autossh LaunchAgent to use the new port permanently.
4. When the remote forwards are cleared and the host mapping is healthy, run the replay without `--no-reload` (or manually re-enable the LaunchAgent) to restore the persistent autossh tunnel.

If you want any additional checks (for example, automatic parsing of JSON health responses or a remote nc-based TCP check), I can extend the helper script accordingly.

Non-interactive owner collection (sudo-friendly)

When diagnosing intermittent port ownership issues it is useful to capture remote owner/process details non-interactively. Two new helpers assist with this:

1. `scripts/autossh/log_port_owner.sh user@host port [-n samples] [-i interval]` — captures timestamped samples of `ss`/`lsof`/process` output from the remote host and appends results to `$HOME/Library/Logs/cipher-port-owner-history.log` on the local machine.

2. `scripts/autossh/install_passwordless_lsof.sh <username>` — (run on the remote Jetson with sudo) installs a minimal `/etc/sudoers.d/cipher-lsof` fragment that allows the specified user to run `lsof` without a password. This enables `lsof` output to be collected non-interactively by `log_port_owner.sh` without requiring a password prompt.

Example workflow after disabling VS Code auto-forwarding (on the Jetson):

```bash
# On the Jetson (run once to allow non-interactive lsof for diagnostic user):
sudo ./scripts/autossh/install_passwordless_lsof.sh amazon1148

# From your Mac, run the owner collector to sample 3 times, 5s apart:
./scripts/autossh/log_port_owner.sh amazon1148@192.168.1.117 3001 -n 3 -i 5

# Inspect the captured history locally:
tail -n 200 ~/Library/Logs/cipher-port-owner-history.log
```

Important: the sudoers helper grants passwordless `lsof` rights to the named user — limit this to trusted operator accounts and review the created `/etc/sudoers.d/cipher-lsof` fragment for security compliance.

## Reverse SSH Tunnels and autossh

This document explains how to create a stable reverse SSH tunnel from a local machine (for example, macOS) to a remote host (for example, a Jetson) and how to manage it using `autossh` and macOS `launchd` (or systemd on Linux).

## Quick Recipe (macOS)

1. Create a basic reverse forward using `ssh`:

```bash
ssh -N -R 127.0.0.1:3001:127.0.0.1:3000 user@jetson
```

1. Use `autossh` to maintain the tunnel (reconnect on failure). The `scripts/autossh/autossh_start.sh` wrapper included in this repository adds resilience: it polls the remote host to ensure the remote port is free before attempting the bind and can optionally try an alternate remote port.

1. On macOS, create a LaunchAgent plist to manage `autossh` automatically (see `scripts/autossh/com.cipher.autossh.plist` for an example).

## Critical Pre-Flight Checks

### VS Code Remote SSH Port Conflicts

⚠️ VS Code's Remote SSH extension automatically forwards ports 3000–3002 and binds them to `127.0.0.1`. This creates conflicts with:

- Port 3000: direct gvproxy/Podman binding
- Port 3001: the reverse SSH tunnel target used by Cipher

Before starting the tunnel, check and remove VS Code port forwards:

1. In your Remote SSH window, open the Ports view (Ctrl+Shift+P → "Ports: Focus on Ports View").
1. Look for forwards on ports 3000 and 3001.
1. Remove any existing forwards or reassign them to different ports.
1. Confirm the ports are released:

```bash
netstat -an | grep -E ":(3000|3001)"
```

Inspect VS Code SSH port forwarding on the Jetson:

```bash
# On Jetson: Check what processes are listening on ports 3000-3002
sudo ss -tulpn | grep -E ":(3000|3001|3002)"

# Look for processes like:
# tcp   LISTEN  0      128      0.0.0.0:3001      0.0.0.0:*    users:(("code",pid=1234,fd=5))

# Check for VS Code server processes
ps aux | grep -E "code.*3001|Remote.*SSH" | grep -v grep

# If you find VS Code processes on port 3001, remove the port forward in VS Code before the tunnel can bind
```

Alternative VS Code port-forward removal (if you cannot access the UI):

```bash
# Find the exact VS Code process using port 3001
sudo lsof -i :3001

# If appropriate, kill the specific process (prefer targeted kill over killing sshd)
# sudo kill -9 <PID>
```

Verify port is free after removal:

```bash
sudo ss -tulpn | grep :3001 || true
```

### VS Code Remote SSH: port-forward race (diagnose & fix)

If `autossh` repeatedly logs "remote port forwarding failed for listen port 3001" the most common cause is a race with VS Code Remote SSH re-creating an auto-forward on the remote host. The forward may be re-applied whenever the Remote server or extension restarts.

Diagnosis steps (non-destructive):

- Check autossh log on macOS for repeated bind failures:

```bash
tail -n 200 ~/Library/Logs/cipher-autossh.log
```

- Confirm Jetson reachability and manual forward behavior:

```bash
# From Mac: attempt a temporary remote forward (will fail if remote port already bound)
ssh -f -o ExitOnForwardFailure=yes -N -R 127.0.0.1:3001:127.0.0.1:3000 amazon1148@jetson
# On Jetson: verify the forwarded service
ssh amazon1148@jetson "curl -v http://127.0.0.1:3001/health"
```

- On Jetson, identify who (if anyone) owns 3001:

```bash
ss -ltnp | grep :3001 || true
sudo lsof -i :3001 || true
```

Fixes:

1. Disable VS Code auto-forwarding (recommended): add these settings to the Remote Machine settings so VS Code will stop auto-creating those forwards:

```json
{
  "remote.autoForwardPorts": false,
  "remote.portsAttributes": {
    "3000": { "onAutoForward": "ignore" },
    "3001": { "onAutoForward": "ignore" }
  }
}
```

1. Alternative (non-disruptive): choose a dedicated tunnel port outside VS Code's auto-forward range (for example, 3002) and update both the autossh LaunchAgent and MCP client configuration.

1. Hardening: make the autossh start wrapper tolerant to short races by polling the remote host and waiting until the remote port is reported free before attempting the bind. This reduces repeated failures and log noise while the Remote server restarts.

Verification after fix:

```bash
# On Jetson
ss -ltnp | grep :3001
curl -s http://127.0.0.1:3001/health

# On Mac
tail -n 200 ~/Library/Logs/cipher-autossh.log
claude mcp list
```

### Orphaned Process Cleanup

Debugging sessions can leave orphaned processes that block port 3001 on the Jetson. Always audit for lingering diagnostics:

```bash
# On Jetson: Check what's bound to port 3001
sudo ss -tulpn | grep :3001

# Should only show sshd. If other processes appear, investigate:
# - Look for orphaned curl/nc/bash processes from testing
ps -eo pid,etime,cmd | grep -E "curl|nc|bash" | awk '$2~/^[0-9]+m/'

# Clean up any stale processes blocking the port
sudo pkill -f "curl.*3001"  # Example for orphaned curl processes
```

CAUTION: Do NOT kill `sshd` or other system services unless you understand the consequences. Killing `sshd` will drop all active SSH sessions (including any colleagues connected to the host) and may make the host temporarily inaccessible. Prefer the safer, persistent mitigations below.

Permanent fix (recommended)

1. Prevent VS Code from auto-creating port forwards for the ports you intend to reserve for your tunnel. On the Jetson, create or update the Remote Machine settings and explicitly disable auto-forwarding for those ports. Example (Insiders path shown):

```bash
mkdir -p ~/.vscode-server-insiders/data/Machine
cp ~/.vscode-server-insiders/data/Machine/settings.json ~/.vscode-server-insiders/data/Machine/settings.json.bak 2>/dev/null || true
cat > ~/.vscode-server-insiders/data/Machine/settings.json <<'JSON'
{
   "remote.autoForwardPorts": false,
   "remote.portsAttributes": {
      "3000": { "onAutoForward": "ignore" },
      "3001": { "onAutoForward": "ignore" }
   }
}
JSON

# Safely restart the remote VS Code server by disconnecting your Remote window and allowing the client to reconnect,
# or restart the remote server process from the host (this will close all remote editor sessions):
pkill -f 'code-server-insiders.*server' || true

# Confirm the port is no longer claimed by VS Code or sshd
sudo ss -ltnp | grep :3001 || true
```

1. If you cannot immediately change VS Code behavior, an alternative is to allocate a different remote port for your tunnel (e.g., 3002) and update the autossh LaunchAgent and MCP client configuration accordingly. See the autossh wrapper for an opt-in fallback to try an alternate port automatically.

## Health Checks and Diagnostics

### macOS (Local) Checks

- Check autossh logs: `tail -f /tmp/autossh.log` or LaunchAgent logs
- Monitor LaunchAgent status: `launchctl list | grep autossh`

### Validate MCP SSE (client checks)

In addition to using `curl` for basic health checks, validate the MCP Server-Sent Events (SSE) endpoint using the MCP client and simple streaming tools so you can confirm an active subscription.

1) Quick client status (Claude CLI)

```bash
# Quick connection state reported by the Claude MCP client
claude mcp list
# Expected line (when connected):
# cipher: http://localhost:3000/mcp/sse (SSE) - ✓ Connected
```

2) Active SSE test with curl

```bash
# Keep the connection open and show incoming SSE frames (no buffering)
curl -v --no-buffer --max-time 60 http://127.0.0.1:3000/mcp/sse
```

What to look for:
- HTTP/1.1 200 OK and a `Content-Type: text/event-stream` header.
- Lines beginning with `event:` and/or `data:`. A `data:` line containing JSON indicates the MCP service is publishing events.

3) Active SSE test with a small Python script (more robust parsing)

```python
#!/usr/bin/env python3
import requests

URL = 'http://127.0.0.1:3000/mcp/sse'
with requests.get(URL, stream=True, timeout=10) as r:
  r.raise_for_status()
  print('Status:', r.status_code, 'Content-Type:', r.headers.get('content-type'))
  # Read a few lines from the event stream
  for i, line in enumerate(r.iter_lines(decode_unicode=True)):
    if line:
      print(line)
    if i >= 20:
      break

# Install requirements: pip install requests
```

4) If your MCP client supports an explicit subscribe command

If the MCP client (for example the Claude CLI) provides an explicit subscribe or stream command, use that to observe the SSE lifecycle and incoming events. If not, the `curl` and Python examples above provide equivalent streaming validations.

Interpretation

- If `claude mcp list` reports the SSE endpoint as connected and `curl`/Python show incoming `data:` frames, the tunnel is functioning end-to-end and events are reaching the MCP client.
- If `claude mcp list` shows the endpoint as failed but `curl` on the Jetson (127.0.0.1:3001) returns the health JSON, the reverse tunnel may be intermittent or autossh is not running on the Mac. Use the diagnostic helpers to reproduce and collect logs.
- If `curl` returns `HTTP/000` or a connection error from the Mac host, confirm the local Podman/GVProxy host mapping (`lsof`/`podman ps`) and that the local service is reachable at `127.0.0.1:3000` before re-testing the tunnel.
