#!/usr/bin/env zsh
# autossh_start.sh
# Launch script for autossh reverse tunnel to Jetson Orin.
# Designed to be run by launchd (do NOT use -f when run under launchd).

set -euo pipefail

# Configuration — edit these values or export environment variables before loading the plist
: ${CIPHER_AUTOSSH_USER:="amazon1148"}
: ${CIPHER_AUTOSSH_HOST:="<jetson-ip>"}
: ${CIPHER_AUTOSSH_LOCAL_PORT:=3001}
: ${CIPHER_AUTOSSH_REMOTE_PORT:=3001}
: ${CIPHER_AUTOSSH_BIND_ADDR:="127.0.0.1"}  # remote bind on Jetson; use 0.0.0.0 if GatewayPorts enabled
: ${CIPHER_AUTOSSH_TARGET_PORT:=3000}         # port on mac to which remote connections should be delivered (container port)
: ${CIPHER_AUTOSSH_IDENTITY:=""}             # optional: path to private key

LOGFILE="$HOME/Library/Logs/cipher-autossh.log"
mkdir -p "$(dirname "$LOGFILE")"

# Ensure autossh debug/logging environment defaults when run under launchd
: ${AUTOSSH_DEBUG:=1}
: ${AUTOSSH_LOGFILE:=/tmp/autossh.log}
: ${AUTOSSH_GATETIME:=0}

# Ensure AUTOSSH_LOGFILE exists and is writable
touch "$AUTOSSH_LOGFILE" 2>/dev/null || true
chmod 600 "$AUTOSSH_LOGFILE" 2>/dev/null || true

# Find autossh binary in common locations (Homebrew on Apple Silicon and Intel) or in PATH
AUTOSSH_BIN="/opt/homebrew/bin/autossh"
if [[ ! -x "$AUTOSSH_BIN" ]]; then
  AUTOSSH_BIN="/usr/local/bin/autossh"
fi
if [[ ! -x "$AUTOSSH_BIN" ]]; then
  AUTOSSH_BIN="$(command -v autossh 2>/dev/null || true)"
fi
if [[ -z "$AUTOSSH_BIN" || ! -x "$AUTOSSH_BIN" ]]; then
  echo "ERROR: autossh not found in PATH or common locations. Install via Homebrew: brew install autossh" | tee -a "$LOGFILE"
  exit 1
fi

# Build autossh arguments
ARGS=(
  "$AUTOSSH_BIN"
  -M 0                         # use SSH keepalives, not monitoring port
  -N                           # do not execute remote commands
  -o ExitOnForwardFailure=yes
  -o ServerAliveInterval=30
  -o ServerAliveCountMax=3
  -o StrictHostKeyChecking=accept-new
)

# Optional identity file
if [[ -n "$CIPHER_AUTOSSH_IDENTITY" ]]; then
  ARGS+=( -i "$CIPHER_AUTOSSH_IDENTITY" )
fi

# Remote-forward spec: forward remote port -> mac target port (container)
REMOTE_SPEC="${CIPHER_AUTOSSH_BIND_ADDR}:${CIPHER_AUTOSSH_REMOTE_PORT}:127.0.0.1:${CIPHER_AUTOSSH_TARGET_PORT}"
ARGS+=( -R "$REMOTE_SPEC" )
ARGS+=( "${CIPHER_AUTOSSH_USER}@${CIPHER_AUTOSSH_HOST}" )

# Log header
echo "--- autossh start: $(date -u +%Y-%m-%dT%H:%M:%SZ) ---" >> "$LOGFILE"

echo "Starting autossh with: ${ARGS[*]}" >> "$LOGFILE"

# Also emit a short header into the autossh logfile (autossh writes extra
# debugging info when AUTOSSH_DEBUG=1 and AUTOSSH_LOGFILE is set in the env)
echo "--- autossh wrapper start: $(date -u +%Y-%m-%dT%H:%M:%SZ) ---" >> "$AUTOSSH_LOGFILE"

# Export autossh-specific env so child process sees them when job runs under launchd
export AUTOSSH_DEBUG AUTOSSH_LOGFILE AUTOSSH_GATETIME

# Exec autossh (don't -f when running under launchd)
# Redirect stdout/stderr to the logfile as an extra safety
exec >>"$LOGFILE" 2>&1
exec "${(Q)ARGS[@]}"
