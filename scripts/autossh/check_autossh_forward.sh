#!/usr/bin/env zsh
# check_autossh_forward.sh
# Verify that the remote forward exists on Jetson and test the health endpoint via the tunnel.
# Usage: ./check_autossh_forward.sh <jetson-user>@<jetson-host>

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <user@jetson-host>" >&2
  exit 2
fi

REMOTE="$1"

# Check remote listens
echo "Checking for listening socket on Jetson (port 3001):"
ssh -o ConnectTimeout=10 "$REMOTE" "ss -ltnp | grep ':3001' || true"

# Try curl via loopback on Jetson
echo "Testing HTTP via the forwarded port on Jetson (127.0.0.1:3001):"
ssh -o ConnectTimeout=10 "$REMOTE" "curl -s -S -m 5 http://127.0.0.1:3001/health || echo 'curl failed'"
