#!/usr/bin/env zsh
# autossh_watchdog.sh
# Periodically run by launchd to ensure the autossh forward is established.

set -euo pipefail

WATCHDOG_LOG="$HOME/Library/Logs/cipher-autossh-watchdog.log"
AUTOSSH_LOG="/tmp/autossh.log"
LAUNCHD_LABEL="com.cipher.autossh"
UIDSTR=$(id -u)

# Allow plist to provide these; otherwise fall back to sensible defaults
: ${CIPHER_AUTOSSH_USER:=amazon1148}
: ${CIPHER_AUTOSSH_HOST:=192.168.1.117}
: ${CIPHER_AUTOSSH_REMOTE_PORT:=3001}

mkdir -p "$(dirname "$WATCHDOG_LOG")"

timestamp() { date -u +%Y-%m-%dT%H:%M:%SZ; }

echo "$(timestamp) watchdog: running check" >> "$WATCHDOG_LOG"

# Helper: consider forward healthy if autossh log contains success lines
if [[ -f "$AUTOSSH_LOG" ]]; then
  if tail -n 500 "$AUTOSSH_LOG" | grep -E "remote forward success|forwarding_success" >/dev/null 2>&1; then
    echo "$(timestamp) watchdog: forward success found in autossh log" >> "$WATCHDOG_LOG"
    # Extra validation: try a short-run health check from the Jetson side
    echo "$(timestamp) watchdog: performing strict remote health + TCP probe via check_autossh_forward.sh" >> "$WATCHDOG_LOG"
    # Use the stricter helper to validate both TCP accept and HTTP health. This
    # provides a single exit code that indicates a fully functional forward.
    if scripts/autossh/check_autossh_forward.sh --require-tcp --require-health "${CIPHER_AUTOSSH_USER}@${CIPHER_AUTOSSH_HOST}" >/dev/null 2>>"$WATCHDOG_LOG"; then
      echo "$(timestamp) watchdog: remote health+tcp check OK" >> "$WATCHDOG_LOG"
      # Reset consecutive restart counter to 0 on success
      STATE_DIR="$HOME/Library/Application Support/cipher"
      STATE_FILE="$STATE_DIR/watchdog-restarts.count"
      mkdir -p "$STATE_DIR"
      echo 0 > "$STATE_FILE"
      echo "$(timestamp) watchdog: reset consecutive restarts to 0" >> "$WATCHDOG_LOG"
      exit 0
    else
      echo "$(timestamp) watchdog: remote health+tcp check FAILED" >> "$WATCHDOG_LOG"
      # fall through to restart below
    fi
  fi
fi

## At this point, either autossh log did not show success, or remote health failed.
# Maintain a consecutive restart counter and alert after a threshold
: ${WATCHDOG_ALERT_THRESHOLD:=3}
STATE_DIR="$HOME/Library/Application Support/cipher"
STATE_FILE="$STATE_DIR/watchdog-restarts.count"
mkdir -p "$STATE_DIR"

current_count=0
if [[ -f "$STATE_FILE" ]]; then
  current_count=$(cat "$STATE_FILE" 2>/dev/null || echo 0)
  current_count=${current_count:-0}
fi

if pgrep -af "autossh .*127.0.0.1:${CIPHER_AUTOSSH_REMOTE_PORT}" >/dev/null 2>&1; then
  echo "$(timestamp) watchdog: autossh process exists but no successful forward; will restart job" >> "$WATCHDOG_LOG"
else
  echo "$(timestamp) watchdog: autossh process not running; will start job" >> "$WATCHDOG_LOG"
fi

# increment consecutive restart counter and persist
current_count=$((current_count + 1))
echo "$current_count" > "$STATE_FILE"
echo "$(timestamp) watchdog: consecutive restarts = $current_count (threshold=$WATCHDOG_ALERT_THRESHOLD)" >> "$WATCHDOG_LOG"

# If threshold exceeded, send macOS user notification
notify_if_needed() {
  if [[ "$current_count" -ge "$WATCHDOG_ALERT_THRESHOLD" ]]; then
    TITLE="cipher autossh watchdog"
    SUBJ="autossh restarted $current_count times"
    BODY="autossh has been restarted $current_count times by the watchdog. Please investigate."
    echo "$(timestamp) watchdog: alert threshold reached ($current_count) - notifying user" >> "$WATCHDOG_LOG"
    # Use AppleScript to show a user notification in the GUI session
    /usr/bin/osascript -e "display notification \"${BODY}\" with title \"${TITLE}\" subtitle \"${SUBJ}\""
    # Also write an extra persistent log entry
    echo "$(timestamp) watchdog: user notified (threshold $WATCHDOG_ALERT_THRESHOLD)" >> "$WATCHDOG_LOG"
  fi
}

# Attempt to restart the launchd job for the user gui session.
if launchctl kickstart -k "gui/$UIDSTR/$LAUNCHD_LABEL" >/dev/null 2>&1; then
  echo "$(timestamp) watchdog: launchctl kickstart invoked" >> "$WATCHDOG_LOG"
else
  echo "$(timestamp) watchdog: kickstart failed, trying unload/load" >> "$WATCHDOG_LOG"
  launchctl unload ~/Library/LaunchAgents/${LAUNCHD_LABEL}.plist 2>/dev/null || true
  sleep 1
  launchctl load ~/Library/LaunchAgents/${LAUNCHD_LABEL}.plist
  echo "$(timestamp) watchdog: unload/load attempted" >> "$WATCHDOG_LOG"
fi

# Fire notification if needed
notify_if_needed

echo "$(timestamp) watchdog: check complete" >> "$WATCHDOG_LOG"

exit 0
