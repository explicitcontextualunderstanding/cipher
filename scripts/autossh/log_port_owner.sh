#!/usr/bin/env zsh
set -euo pipefail

# Record remote owner/process details for a given TCP port on a remote host.
# Usage: log_port_owner.sh user@host port [-n samples] [-i interval]
# Default: samples=1, interval=10

TARGET=${1:-}
PORT=${2:-3001}
shift 2 || true

SAMPLES=1
INTERVAL=10

while [[ $# -gt 0 ]]; do
  case "$1" in
    -n)
      shift
      SAMPLES=${1:-1}
      ;;
    -i)
      shift
      INTERVAL=${1:-10}
      ;;
    *)
      echo "Unknown arg: $1" >&2
      exit 2
      ;;
  esac
  shift || true
done

if [[ -z "$TARGET" ]]; then
  echo "Usage: $0 user@host port [-n samples] [-i interval]" >&2
  exit 2
fi

LOGFILE="$HOME/Library/Logs/cipher-port-owner-history.log"
mkdir -p "$(dirname "$LOGFILE")"

echo "Starting port owner capture: target=$TARGET port=$PORT samples=$SAMPLES interval=${INTERVAL}s" | tee -a "$LOGFILE"

for ((i=1;i<=SAMPLES;i++)); do
  ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  echo "--- SAMPLE $i - $ts - $TARGET:$PORT ---" >> "$LOGFILE"
  ssh -o BatchMode=yes -o ConnectTimeout=7 "$TARGET" "echo HOST:\\$(hostname); date -u; ss -ltnp | grep -E ':${PORT}\\b' || true; sudo lsof -nP -iTCP:${PORT} -sTCP:LISTEN || true; ps aux | egrep 'code-server|code-insiders|Remote.*SSH' | sed -n '1,200p' || true" >> "$LOGFILE" 2>&1 || echo "ssh to $TARGET failed for sample $i" >> "$LOGFILE"
  echo >> "$LOGFILE"
  if (( i < SAMPLES )); then
    sleep "$INTERVAL"
  fi
done

echo "Log written to: $LOGFILE"

exit 0
