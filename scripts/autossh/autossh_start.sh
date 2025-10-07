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
: ${CIPHER_AUTOSSH_ALT_REMOTE_PORT:=""}
: ${CIPHER_AUTOSSH_ENABLE_ALT_ON_BLOCK:=false}
: ${CIPHER_AUTOSSH_MAX_BACKOFF:=300}
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

# Wait for remote port to be free to avoid races with Remote SSH auto-forwards.
# If the remote (Jetson) currently has something bound to the requested
# remote port, autossh would repeatedly fail with "remote port forwarding failed".
# This loop queries the remote host and waits until the remote port is free
# before attempting to establish the reverse forward.
: ${CIPHER_AUTOSSH_WAIT_INTERVAL:=10}   # seconds between checks (initial interval; exponential backoff applied)
: ${CIPHER_AUTOSSH_WAIT_TIMEOUT:=0}     # 0 = wait forever
if [[ -n "${CIPHER_AUTOSSH_HOST:-}" && -n "${CIPHER_AUTOSSH_USER:-}" ]]; then
  start_ts=$(date +%s)
  interval=${CIPHER_AUTOSSH_WAIT_INTERVAL}
  while true; do
    out=$(ssh -o BatchMode=yes -o ConnectTimeout=5 "${CIPHER_AUTOSSH_USER}@${CIPHER_AUTOSSH_HOST}" "ss -ltnp | grep -q ':${CIPHER_AUTOSSH_REMOTE_PORT}' && echo busy || echo free" 2>/dev/null || true)
    if [[ "$out" = "free" ]]; then
      echo "Remote port ${CIPHER_AUTOSSH_REMOTE_PORT} appears free on ${CIPHER_AUTOSSH_HOST}, proceeding" >> "$LOGFILE"
      break
    fi
    echo "Remote port ${CIPHER_AUTOSSH_REMOTE_PORT} busy on ${CIPHER_AUTOSSH_HOST}, sleeping ${interval}s" >> "$LOGFILE"
    # When the remote port is busy, capture owner / process details to aid diagnosis instead of auto-switching.
    owner_info=$(ssh -o BatchMode=yes -o ConnectTimeout=5 "${CIPHER_AUTOSSH_USER}@${CIPHER_AUTOSSH_HOST}" "ss -ltnp | grep ':${CIPHER_AUTOSSH_REMOTE_PORT}' || true; sudo lsof -nP -iTCP:${CIPHER_AUTOSSH_REMOTE_PORT} -sTCP:LISTEN || true" 2>/dev/null || true)
    echo "Remote port ${CIPHER_AUTOSSH_REMOTE_PORT} busy on ${CIPHER_AUTOSSH_HOST}, owner details:" >> "$LOGFILE"
    echo "$owner_info" >> "$LOGFILE"
    echo "Sleeping ${interval}s before retrying" >> "$LOGFILE"
    if [[ "${CIPHER_AUTOSSH_WAIT_TIMEOUT}" -gt 0 ]]; then
      now=$(date +%s)
      if (( now - start_ts >= CIPHER_AUTOSSH_WAIT_TIMEOUT )); then
        if [[ "${CIPHER_AUTOSSH_ENABLE_ALT_ON_BLOCK}" = "true" && -n "${CIPHER_AUTOSSH_ALT_REMOTE_PORT}" ]]; then
          echo "Timeout waiting for port ${CIPHER_AUTOSSH_REMOTE_PORT}; switching to alternate remote port ${CIPHER_AUTOSSH_ALT_REMOTE_PORT}" >> "$LOGFILE"
          CIPHER_AUTOSSH_REMOTE_PORT="${CIPHER_AUTOSSH_ALT_REMOTE_PORT}"
          break
        fi
        echo "Waited long enough for remote port to free; proceeding anyway (no alternate port configured)" >> "$LOGFILE"
        break
      fi
    fi
    sleep "${interval}"
    # exponential backoff for subsequent checks
    interval=$(( interval * 2 ))
    if (( interval > CIPHER_AUTOSSH_MAX_BACKOFF )); then
      interval=${CIPHER_AUTOSSH_MAX_BACKOFF}
    fi
  done
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
