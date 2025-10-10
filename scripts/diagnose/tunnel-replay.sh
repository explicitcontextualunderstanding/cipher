#!/usr/bin/env zsh
# tunnel-replay.sh
# Automate the "tunnel replay" checklist used during diagnostics:
#  - stop the autossh LaunchAgent
#  - attempt a one-off manual reverse SSH forward (background or foreground)
#  - run the remote listener + health checks (calls scripts/autossh/check_autossh_forward.sh)
#  - optionally re-enable the autossh LaunchAgent
#  - optionally cleanup (kill the manual SSH and re-enable autossh)
#
# Usage:
#   scripts/diagnose/tunnel-replay.sh [--no-reload] [--alt-port PORT] [--foreground] <user@jetson-host>
# Examples:
#   scripts/diagnose/tunnel-replay.sh amazon1148@192.168.1.117
#   scripts/diagnose/tunnel-replay.sh --alt-port 3002 --no-reload amazon1148@jetson
#
set -euo pipefail

show_help() {
  cat <<'USAGE'
Usage: tunnel-replay.sh [OPTIONS] <user@host>

Options:
  --no-reload        Do not re-enable the autossh LaunchAgent at the end (default: re-enable)
  --alt-port PORT    Use an alternate remote bind port instead of 3001
  --foreground       Run the manual ssh in the foreground (useful for interactive debugging)
  --cleanup          After checks, kill the manual ssh and re-enable autossh (if present)
  --auto-eval         Automatically evaluate the remote /health JSON and return non-zero on failure
  --tcp-check         Attempt a TCP probe from the remote host to the local bound port (additional verification)
  -h, --help         Show this help and exit

This script is non-destructive: it will NOT kill sshd. Use --cleanup to remove the transient manual ssh
that this script starts.
USAGE
}

if [[ ${#@} -eq 0 ]]; then
  show_help
  exit 2
fi

# Defaults
REMOTE_PORT=3001
TARGET_PORT=3000
NO_RELOAD=false
FOREGROUND=false
CLEANUP=false
AUTO_EVAL=false
TCP_CHECK=false

# Parse options
while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-reload)
      NO_RELOAD=true; shift;;
    --alt-port)
      REMOTE_PORT="$2"; shift 2;;
    --foreground)
      FOREGROUND=true; shift;;
    --auto-eval)
      AUTO_EVAL=true; shift;;
    --tcp-check)
      TCP_CHECK=true; shift;;
    --cleanup)
      CLEANUP=true; shift;;
    -h|--help)
      show_help; exit 0;;
    --)
      shift; break;;
    -* )
      echo "Unknown option: $1" >&2; show_help; exit 2;;
    *)
      # positional: must be the remote user@host
      REMOTE_ARG="$1"; shift; break;;
  esac
done

# If the user passed additional positional args after break, join them
if [[ ${#@} -gt 0 && -z "${REMOTE_ARG:-}" ]]; then
  REMOTE_ARG="$1"
fi

if [[ -z "${REMOTE_ARG:-}" ]]; then
  echo "ERROR: remote user@host required" >&2
  show_help
  exit 2
fi

REMOTE="$REMOTE_ARG"
LAUNCHD_PLIST="$HOME/Library/LaunchAgents/com.cipher.autossh.plist"
AUTOSSH_LABEL="com.cipher.autossh"
MANUAL_LOG="/tmp/manual_ssh.log"

# Helpers
timestamp() { date -u +%Y-%m-%dT%H:%M:%SZ; }
log() { printf "%s %s\n" "$(timestamp)" "$*"; }

if ! command -v ssh >/dev/null 2>&1; then
  echo "ERROR: ssh not found in PATH" >&2
  exit 1
fi

# 1) Stop autossh LaunchAgent to avoid race (non-fatal if not present)
log "Stopping autossh LaunchAgent (if loaded)"
if launchctl print gui/"$UID"/"$AUTOSSH_LABEL" >/dev/null 2>&1; then
  launchctl bootout gui/$UID "$LAUNCHD_PLIST" 2>/dev/null || true
  sleep 1
  log "autossh LaunchAgent requested to stop"
else
  log "No autossh LaunchAgent found in gui/$UID; continuing"
fi

# 2) Start manual verbose SSH reverse forward
SSH_CMD=(ssh -vv -o ExitOnForwardFailure=yes -N -R 127.0.0.1:${REMOTE_PORT}:127.0.0.1:${TARGET_PORT} "$REMOTE")

log "Starting manual SSH reverse forward to ${REMOTE} (remote:127.0.0.1:${REMOTE_PORT} -> local:127.0.0.1:${TARGET_PORT})"

# Ensure previous manual log is rotated
if [[ -f "$MANUAL_LOG" ]]; then
  mv -f "$MANUAL_LOG" "${MANUAL_LOG}.$(date +%s)" 2>/dev/null || true
fi

if [[ "$FOREGROUND" = true ]]; then
  log "Running ssh in foreground; CTRL-C will terminate the session"
  "${SSH_CMD[@]}"
  # In foreground mode the user can see logs directly; still run checks below
else
  # Start in background and capture pid
  ("${SSH_CMD[@]}" > "$MANUAL_LOG" 2>&1) &
  SSH_PID=$!
  sleep 3
  log "manual ssh pid: $SSH_PID"
  log "--- manual ssh log (head) ---"
  sed -n '1,200p' "$MANUAL_LOG" || true
fi

# 3) Run the existing remote check helper to verify listen and /health
log "Running remote listener + health checks"
if [[ -x "scripts/autossh/check_autossh_forward.sh" ]]; then
  # If caller requested strict checks, propagate them to the helper script so
  # it can enforce TCP and/or HTTP health and return a non-zero exit code.
  CHECK_ARGS=()
  if [[ "$TCP_CHECK" = true ]]; then
    CHECK_ARGS+=(--require-tcp)
  fi
  if [[ "$AUTO_EVAL" = true ]]; then
    CHECK_ARGS+=(--require-health)
  fi
  # When running in automated mode, also ask for compact JSON output for
  # downstream parsing. We still print the human-readable output above.
  if [[ "$AUTO_EVAL" = true || "$TCP_CHECK" = true ]]; then
    CHECK_ARGS+=(--json)
  fi

  if ! scripts/autossh/check_autossh_forward.sh "${CHECK_ARGS[@]}" "$REMOTE"; then
    log "check_autossh_forward.sh reported failing required checks"
    # If strict verification was requested, exit with failure now so automation
    # layers can act on it.
    exit 3
  fi
else
  log "Warning: check_autossh_forward.sh not found or not executable; skipping that check"
fi

# 4) Run claude mcp list if available (helps verify MCP-level connectivity)
if command -v claude >/dev/null 2>&1; then
  log "Running 'claude mcp list' to observe MCP connection state"
  claude mcp list || true
else
  log "'claude' CLI not found in PATH; skipping 'claude mcp list'"
fi

# 5) Show a trailing tail of the manual ssh log so the user can inspect failures
if [[ -f "$MANUAL_LOG" ]]; then
  log "--- manual ssh log (tail) ---"
  tail -n 200 "$MANUAL_LOG" || true
fi

# 5.1) Optional automatic health evaluation
if [[ "$AUTO_EVAL" = true || "$TCP_CHECK" = true ]]; then
  log "Running automatic evaluation: auto-eval=$AUTO_EVAL tcp-check=$TCP_CHECK"

  # Remote curl that also emits HTTP code marker
  REMOTE_HEALTH_RAW=$(ssh -o ConnectTimeout=5 "$REMOTE" "curl -sS -m 5 -w '||CODE:%{http_code}' http://127.0.0.1:${REMOTE_PORT}/health" 2>/dev/null || echo "CURL_FAILED||CODE:000")
  REMOTE_BODY=${REMOTE_HEALTH_RAW%%'||CODE:'*}
  REMOTE_CODE=${REMOTE_HEALTH_RAW##*'||CODE:'}

  eval_ok=true
  eval_reasons=()

  if [[ "$REMOTE_HEALTH_RAW" = "CURL_FAILED||CODE:000" ]]; then
    eval_ok=false
    eval_reasons+=("curl_failed")
  else
    if [[ "$REMOTE_CODE" != "200" ]]; then
      eval_ok=false
      eval_reasons+=("http_code=${REMOTE_CODE}")
    fi
    # Quick string check for the expected status token
    if [[ "$REMOTE_BODY" = *'"status":"healthy"'* ]]; then
      : # OK
    else
      # Try JSON parse if python3 available
      if command -v python3 >/dev/null 2>&1; then
        parsed_status=$(printf "%s" "$REMOTE_BODY" | python3 -c 'import sys, json
try:
    obj=json.load(sys.stdin)
    print(obj.get("status", ""))
except Exception:
    print("__PARSE_FAILED__")')
        if [[ "$parsed_status" = "healthy" ]]; then
          : # OK
        else
          eval_ok=false
          eval_reasons+=("status_parsed=${parsed_status}")
        fi
      else
        eval_ok=false
        eval_reasons+=("no_status_token_and_no_python3")
      fi
    fi
  fi

  # Optional TCP probe executed from the remote host back to the local bound address
  if [[ "$TCP_CHECK" = true ]]; then
    log "Attempting remote TCP probe from ${REMOTE} to 127.0.0.1:${REMOTE_PORT}"
    TCP_RESULT=$(ssh -o ConnectTimeout=5 "$REMOTE" "(command -v nc >/dev/null 2>&1 && nc -z 127.0.0.1 ${REMOTE_PORT} >/dev/null 2>&1 && echo OK) || (python3 -c \"import socket,sys\ntry:\n s=socket.socket(); s.settimeout(3); s.connect(('127.0.0.1', ${REMOTE_PORT})); print('OK')\nexcept Exception:\n print('FAIL')\n\" 2>/dev/null) || (ss -ltnp | grep -q ':${REMOTE_PORT}' && echo OK || echo FAIL)" 2>/dev/null || echo FAIL)
    if [[ "$TCP_RESULT" = *OK* ]]; then
      : # ok
    else
      eval_ok=false
      eval_reasons+=("tcp_probe_failed")
    fi
  fi

  if [[ "$eval_ok" = true ]]; then
    log "AUTO-EVAL RESULT: PASS"
    echo "AUTO-EVAL: PASS"
    # If only evaluating, exit success
    if [[ "$NO_RELOAD" = true ]]; then
      exit 0
    fi
  else
    log "AUTO-EVAL RESULT: FAIL (${(j:, :)eval_reasons})"
    echo "AUTO-EVAL: FAIL (${(j:, :)eval_reasons})"
    # Return non-zero to signal automated failure if the user requested auto-eval
    exit 3
  fi
fi

# 6) Optionally re-enable autossh (unless --no-reload) and run checks again
if [[ "$NO_RELOAD" = false ]]; then
  log "Re-enabling autossh LaunchAgent"
  launchctl bootstrap gui/$UID "$LAUNCHD_PLIST" 2>/dev/null || true
  sleep 2
  log "Re-run remote listener + health checks after reloading autossh"
  if [[ -x "scripts/autossh/check_autossh_forward.sh" ]]; then
    scripts/autossh/check_autossh_forward.sh "$REMOTE" || true
  fi
  if command -v claude >/dev/null 2>&1; then
    claude mcp list || true
  fi
else
  log "Skipped re-enabling autossh (user requested --no-reload)"
fi

# 7) Cleanup if requested
if [[ "$CLEANUP" = true ]]; then
  if [[ -n "${SSH_PID:-}" ]]; then
    log "Killing manual ssh (pid $SSH_PID)"
    kill "${SSH_PID}" 2>/dev/null || true
    sleep 1
  fi
  log "Re-enabling autossh LaunchAgent after cleanup"
  launchctl bootstrap gui/$UID "$LAUNCHD_PLIST" 2>/dev/null || true
fi

log "tunnel-replay: complete"

exit 0
