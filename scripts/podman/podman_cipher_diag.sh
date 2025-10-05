#!/usr/bin/env zsh
# podman_cipher_diag.sh
# Run a set of Podman checks for the `cipher` container on macOS, collect outputs,
# and provide a short analysis to help diagnose remote connectivity (e.g. from a Jetson).
# Usage: ./podman_cipher_diag.sh [container-name-or-id] [remote-ip-to-test]

setopt errexit
setopt nounset
setopt pipefail

OUTDIR="./podman_cipher_diag_$(date +%Y%m%dT%H%M%S)"
mkdir -p "$OUTDIR"

CONTAINER=${1:-}
REMOTE_IP=${2:-}

# Helper: run a command and capture stdout+stderr to a file
run() {
  local name="$1"; shift
  echo "--- Running: $name ---"
  {
    echo "# $*";
    "$@" 2>&1
  } > "$OUTDIR/$name.txt" || true
}

# Find a cipher container if none provided
if [[ -z "$CONTAINER" ]]; then
  echo "No container specified; attempting to find a container named 'cipher'..."
  CONTAINER=$(podman ps -a --format '{{.Names}}' | grep -E 'cipher' | head -n1 || true)
  if [[ -z "$CONTAINER" ]]; then
    echo "No container with a name matching 'cipher' found in 'podman ps -a'."
    echo "You can re-run with the container name or id as the first argument." > "$OUTDIR/README.txt"
  else
    echo "Found container: $CONTAINER"
  fi
else
  echo "Using container: $CONTAINER"
fi

# Collect Podman state and container metadata
run podman_ps podman ps -a --no-trunc
run podman_ps_filter podman ps -a --filter name=cipher --no-trunc || true

if [[ -n "$CONTAINER" ]]; then
  run inspect podman inspect "$CONTAINER"
  run port podman port "$CONTAINER" 2>&1 || true
fi

# Podman machine (macOS) checks
run podman_machine_list podman machine list --format json || true
# Try to detect default machine name
MACHINE_NAME=$(podman machine list --format '{{.Name}}' | head -n1 || true)
if [[ -n "$MACHINE_NAME" ]]; then
  run podman_machine_inspect podman machine inspect "$MACHINE_NAME" || true
  # try ssh into the podman VM to list listening sockets
  run vm_listen_ports podman machine ssh -- "(ss -ltnp 2>/dev/null || netstat -an) | grep 3000 || true" || true
else
  echo "No podman machine detected; skipping VM SSH checks." > "$OUTDIR/vm_skip.txt"
fi

# Host-level net checks
run lsof lsof -i :3000 || true
run netstat netstat -an | grep LISTEN | grep 3000 || true

# Try to find primary host IP (macOS heuristics)
HOST_IP=""
HOST_IP=$(ipconfig getifaddr en0 2>/dev/null || true)
if [[ -z "$HOST_IP" ]]; then
  HOST_IP=$(ipconfig getifaddr en1 2>/dev/null || true)
fi
if [[ -z "$HOST_IP" ]]; then
  # Fallback: parse first non-loopback inet from ifconfig
  HOST_IP=$(ifconfig 2>/dev/null | awk '/inet / && $2 != "127.0.0.1" { print $2; exit }' || true)
fi
if [[ -n "$HOST_IP" ]]; then
  echo "Detected host IP: $HOST_IP" > "$OUTDIR/host_ip.txt"
else
  echo "Could not reliably detect host LAN IP; remote tests may need explicit IP." > "$OUTDIR/host_ip.txt"
fi

# Quick HTTP health checks from macOS host
run curl_local curl -s -S -m 5 http://localhost:3000/health || true
if [[ -n "$HOST_IP" ]]; then
  run curl_host curl -s -S -m 5 http://$HOST_IP:3000/health || true
fi

# If REMOTE_IP provided, attempt a few remote connectivity checks from this mac host perspective
if [[ -n "$REMOTE_IP" ]]; then
  run ping_remote ping -c 4 "$REMOTE_IP" || true
  run nmap_remote nmap -p 3000 "$REMOTE_IP" || true
  run curl_remote curl -s -S -m 5 http://$REMOTE_IP:3000/health || true
fi

# Basic analysis
SUMMARY="$OUTDIR/summary.txt"
echo "Podman cipher diagnostic summary" > "$SUMMARY"
echo "Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$SUMMARY"

# Was a container discovered?
if [[ -z "$CONTAINER" ]]; then
  echo "Result: no 'cipher' container found by name. Provide container name/id as first arg." >> "$SUMMARY"
else
  echo "Container: $CONTAINER" >> "$SUMMARY"
  # Check podman port output
  PORTFILE="$OUTDIR/port.txt"
  if [[ -f "$PORTFILE" ]]; then
    PORT_OUTPUT=$(cat "$PORTFILE")
    echo "podman port output:" >> "$SUMMARY"
    echo "$PORT_OUTPUT" >> "$SUMMARY"
    if echo "$PORT_OUTPUT" | grep -q '127.0.0.1'; then
      echo "Analysis: container port is published only on loopback (127.0.0.1). Remote hosts cannot reach it." >> "$SUMMARY"
      echo "Remedy: re-run container with a public bind like '-p 0.0.0.0:3000:3000' or update podman-compose to use '3000:3000' mapping." >> "$SUMMARY"
    elif echo "$PORT_OUTPUT" | grep -q '0.0.0.0'; then
      echo "Analysis: container port is published on 0.0.0.0 (should be reachable from LAN in theory)." >> "$SUMMARY"
    else
      echo "Analysis: podman port output uncertain or empty. See $PORTFILE for details." >> "$SUMMARY"
    fi
  else
    echo "No podman port output collected." >> "$SUMMARY"
  fi

  # Check host listening sockets
  if grep -q "LISTEN" "$OUTDIR/netstat.txt" 2>/dev/null || grep -q "LISTEN" "$OUTDIR/lsof.txt" 2>/dev/null; then
    # Look for listening address patterns
    if grep -E '127\.0\.0\.1[: ]*\.3000|127\.0\.0\.1' "$OUTDIR/netstat.txt" "$OUTDIR/lsof.txt" 2>/dev/null | grep -q .; then
      echo "Analysis: there is a LISTEN on loopback (127.0.0.1) for port 3000 on the mac host." >> "$SUMMARY"
      echo "This will block remote hosts from connecting. Use host-level socat or rebind podman to 0.0.0.0." >> "$SUMMARY"
    elif grep -E '0\.0\.0\.0[: ]*3000|:::3000' "$OUTDIR/netstat.txt" "$OUTDIR/lsof.txt" 2>/dev/null | grep -q .; then
      echo "Analysis: host shows listening on 0.0.0.0 for port 3000 (should be reachable)." >> "$SUMMARY"
    else
      echo "Analysis: no clear LISTEN entry for port 3000 found in collected netstat/lsof outputs." >> "$SUMMARY"
    fi
  else
    echo "No LISTEN entries for port 3000 found." >> "$SUMMARY"
  fi

  # Podman machine NAT suspicion
  if [[ -n "$MACHINE_NAME" ]]; then
    echo "Podman machine detected: $MACHINE_NAME" >> "$SUMMARY"
    # Check if vm_listen_ports shows process listening inside VM only on loopback
    if grep -q '127.0.0.1' "$OUTDIR/vm_listen_ports.txt" 2>/dev/null; then
      echo "Analysis: inside Podman VM, service may be bound to loopback. That prevents LAN reachability even if podman port shows a mapping." >> "$SUMMARY"
      echo "Suggestion: ensure the service inside container binds to 0.0.0.0, or configure the VM to forward the port on the host LAN, or run socat on the mac host to forward LAN -> VM:container." >> "$SUMMARY"
    fi
  fi
fi

# Final advice block
cat >> "$SUMMARY" <<EOF
Quick next steps (ordered):
1) If the port is published as 127.0.0.1 only, change publish to 0.0.0.0: podman run -p 0.0.0.0:3000:3000 ... or update podman-compose.
2) If Podman runs inside a VM and the VM uses NAT, use socat on mac host to forward LAN IP->VM:port, or create an SSH reverse tunnel.
3) Temporarily disable macOS firewall to test connectivity and then add a permanent allow rule if firewall blocks the port.
4) If you want, re-run this script with the Jetson IP as the second argument to perform remote-targeted tests from this host perspective.
EOF

# Create tarball of full output for easy sharing
TARBALL="$OUTDIR.tar.gz"
tar -czf "$TARBALL" "$OUTDIR" || true

echo
echo "Diagnostic data collected in: $OUTDIR"
echo "Summary: $SUMMARY"
echo "Tarball: $TARBALL"

echo "Done. Review the summary file and the collected logs."
