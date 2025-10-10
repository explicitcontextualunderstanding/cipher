#!/usr/bin/env zsh
# check_autossh_forward.sh
# Verify that the remote forward exists on Jetson and test the health endpoint via the tunnel.
# Usage: ./check_autossh_forward.sh <jetson-user>@<jetson-host>

set -euo pipefail

REQUIRE_TCP=false
REQUIRE_HEALTH=false
JSON_OUTPUT=false

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 [--require-tcp] [--require-health] [--json] <user@jetson-host>" >&2
  exit 2
fi

while [[ $# -gt 1 ]]; do
  case "$1" in
    --require-tcp)
      REQUIRE_TCP=true; shift;;
    --require-health)
      REQUIRE_HEALTH=true; shift;;
    --json)
      JSON_OUTPUT=true; shift;;
    *)
      break;;
  esac
done

REMOTE="$1"

PORT=3001

# Check remote listens
echo "Checking for listening socket on Jetson (port ${PORT}):"
ss_out=$(ssh -o ConnectTimeout=10 "$REMOTE" "ss -ltnp | grep ':${PORT}' || true" 2>/dev/null || true)
echo "$ss_out"

# If we can extract a PID from the ss output, show the process on the remote host
pid=$(echo "$ss_out" | sed -n 's/.*pid=\([0-9]\+\).*/\1/p' | head -n1 || true)
if [[ -n "$pid" ]]; then
  echo "Remote process owning port ${PORT}: PID=${pid}"
  echo "Remote process details:"
  ssh -o ConnectTimeout=10 "$REMOTE" "ps -p ${pid} -o pid,uid,cmd,etime || true"
fi

# Also show lsof output for additional detail
echo "Remote lsof for port ${PORT}:"
ssh -o ConnectTimeout=10 "$REMOTE" "sudo lsof -i :${PORT} 2>/dev/null || true"

# Report any VS Code / code-server processes (common cause of auto-forwarding)
echo "Remote VS Code / code-server processes (if any):"
ssh -o ConnectTimeout=10 "$REMOTE" "ps aux | egrep 'code|code-server|vscode' | egrep -v 'egrep|grep' || true"

# Check specifically whether any VS Code server process explicitly forwards our target PORT
echo "Checking whether VS Code server processes explicitly forward port ${PORT}:"
forwarded_to_target=$(ssh -o ConnectTimeout=10 "$REMOTE" "ps -eo pid,cmd -ww | egrep 'code-insiders|code-server|code ' 2>/dev/null || true" 2>/dev/null | grep -- '--on-port=${PORT}' >/dev/null 2>&1 && echo true || echo false)
if [[ "$forwarded_to_target" = true ]]; then
  echo "VS Code server is explicitly forwarding port ${PORT}"
else
  echo "No explicit VS Code server forward for port ${PORT} detected"
fi
# Check Remote Machine settings (Insiders and stable paths) for remote.autoForwardPorts and portsAttributes
echo "Checking Remote Machine settings for VS Code (auto-forward configuration):"
REMOTE_SETTINGS_PATH="~/.vscode-server-insiders/data/Machine/settings.json"
REMOTE_SETTINGS_PATH_STABLE="~/.vscode-server/data/Machine/settings.json"
settings_found="false"
settings_path_found=""
settings_excerpt=""
auto_forward_disabled="unknown"
port3000_ignored="unknown"
port3001_ignored="unknown"

for p in "$REMOTE_SETTINGS_PATH" "$REMOTE_SETTINGS_PATH_STABLE"; do
  # Expand and test remote path
  if ssh -o ConnectTimeout=5 "$REMOTE" "test -f ${p} && echo exists" 2>/dev/null | grep -q exists; then
    settings_found="true"
    settings_path_found="$p"
    # capture a short excerpt
    settings_excerpt=$(ssh -o ConnectTimeout=5 "$REMOTE" "sed -n '1,200p' ${p} 2>/dev/null || true" 2>/dev/null | tr -d '\n' | sed -E 's/"/\\"/g' | cut -c1-800)
    # Try to parse values with python3 on remote side if available; else fallback to grep
    if ssh -o ConnectTimeout=5 "$REMOTE" "command -v python3 >/dev/null 2>&1" 2>/dev/null; then
      auto_forward_disabled=$(ssh -o ConnectTimeout=5 "$REMOTE" "python3 -c 'import json,sys,os
try:
  obj=json.load(open(os.path.expanduser(\"${p}\")))
  v=obj.get(\"remote.autoForwardPorts\", None)
  print(str(v).lower() if v is not None else \"null\")
except Exception:
  print(\"null\")'" 2>/dev/null || echo null)
      port3000_ignored=$(ssh -o ConnectTimeout=5 "$REMOTE" "python3 -c 'import json,sys,os
try:
  obj=json.load(open(os.path.expanduser(\"${p}\")))
  pa=obj.get(\"remote.portsAttributes\", {})
  v=pa.get(\"3000\", {}).get(\"onAutoForward\", None)
  print(v if v is not None else \"null\")
except Exception:
  print(\"null\")'" 2>/dev/null || echo null)
      port3001_ignored=$(ssh -o ConnectTimeout=5 "$REMOTE" "python3 -c 'import json,sys,os
try:
  obj=json.load(open(os.path.expanduser(\"${p}\")))
  pa=obj.get(\"remote.portsAttributes\", {})
  v=pa.get(\"3001\", {}).get(\"onAutoForward\", None)
  print(v if v is not None else \"null\")
except Exception:
  print(\"null\")'" 2>/dev/null || echo null)
    else
      # Fallback grep checks
      auto_forward_disabled=$(ssh -o ConnectTimeout=5 "$REMOTE" "grep -E 'remote\.autoForwardPorts\"\s*:\s*false' ${p} 2>/dev/null >/dev/null && echo true || echo false" 2>/dev/null || echo unknown)
      port3000_ignored=$(ssh -o ConnectTimeout=5 "$REMOTE" "grep -E '\"3000\"\s*:\s*\{[^}]*onAutoForward\"\s*:\s*\"ignore\"' ${p} 2>/dev/null >/dev/null && echo ignore || echo not_ignored" 2>/dev/null || echo unknown)
      port3001_ignored=$(ssh -o ConnectTimeout=5 "$REMOTE" "grep -E '\"3001\"\s*:\s*\{[^}]*onAutoForward\"\s*:\s*\"ignore\"' ${p} 2>/dev/null >/dev/null && echo ignore || echo not_ignored" 2>/dev/null || echo unknown)
    fi
    break
  fi
done

echo "Remote settings found: ${settings_found} (path: ${settings_path_found})"
if [[ -n "$settings_excerpt" ]]; then
  echo "Remote settings excerpt: ${settings_excerpt}"
fi
echo "remote.autoForwardPorts disabled: ${auto_forward_disabled}"
echo "portsAttributes[3000].onAutoForward: ${port3000_ignored}"
echo "portsAttributes[3001].onAutoForward: ${port3001_ignored}"

# Try curl via loopback on Jetson and capture HTTP code + body
echo "Testing HTTP via the forwarded port on Jetson (127.0.0.1:${PORT}):"
REMOTE_HEALTH_RAW=$(ssh -o ConnectTimeout=10 "$REMOTE" "curl -sS -m 5 -w '||CODE:%{http_code}' http://127.0.0.1:${PORT}/health" 2>/dev/null || echo "CURL_FAILED||CODE:000")
REMOTE_HEALTH_BODY=${REMOTE_HEALTH_RAW%%'||CODE:'*}
REMOTE_HEALTH_CODE=${REMOTE_HEALTH_RAW##*'||CODE:'}
if [[ "$JSON_OUTPUT" = true ]]; then
  # keep short excerpt to avoid massive output in JSON
  REMOTE_HEALTH_EXCERPT=$(printf "%s" "$REMOTE_HEALTH_BODY" | tr -d '\n' | sed -E 's/"/\\"/g' | cut -c1-400)
  echo "HTTP code=${REMOTE_HEALTH_CODE}  body_excerpt=${REMOTE_HEALTH_EXCERPT}"
else
  if [[ "$REMOTE_HEALTH_RAW" = "CURL_FAILED||CODE:000" ]]; then
    echo "curl failed"
  else
    printf '%s\n' "$REMOTE_HEALTH_BODY"
  fi
fi

echo "Testing TCP accept on remote loopback (127.0.0.1:${PORT}) from Jetson:"
tcp_out=$(ssh -o ConnectTimeout=10 "$REMOTE" bash -s <<REMOTE 2>/dev/null || echo 'TCP_PROBE: SSH_FAILED'
# Prefer nc for a real TCP connect test
if command -v nc >/dev/null 2>&1; then
  if nc -z -w 3 127.0.0.1 ${PORT} >/dev/null 2>&1; then
    echo 'TCP_PROBE: OK (nc)'
  else
    echo 'TCP_PROBE: FAIL (nc)'
  fi
elif command -v python3 >/dev/null 2>&1; then
  python3 - <<PY
import socket
try:
    s=socket.socket()
    s.settimeout(3)
    s.connect(('127.0.0.1', ${PORT}))
    s.close()
    print('TCP_PROBE: OK (python3)')
except Exception:
    print('TCP_PROBE: FAIL (python3)')
PY
elif command -v python >/dev/null 2>&1; then
  python - <<PY
import socket
try:
    s=socket.socket()
    s.settimeout(3)
    s.connect(('127.0.0.1', ${PORT}))
    s.close()
    print('TCP_PROBE: OK (python)')
except Exception:
    print('TCP_PROBE: FAIL (python)')
PY
else
  # Last-resort: report if anything is listening on the port
  if ss -ltnp | grep -q ":${PORT}"; then
    echo 'TCP_PROBE: OK (listener detected via ss)'
  else
    echo 'TCP_PROBE: FAIL (no listener detected)'
  fi
fi
REMOTE
)
echo "$tcp_out"

# Evaluate health requirements if requested
overall_ok=true
reasons=()

if [[ "$REQUIRE_HEALTH" = true ]]; then
  if [[ "$REMOTE_HEALTH_RAW" = "CURL_FAILED||CODE:000" ]]; then
    overall_ok=false
    reasons+=("curl_failed")
  else
    if [[ "$REMOTE_HEALTH_CODE" != "200" ]]; then
      overall_ok=false
      reasons+=("http_code=${REMOTE_HEALTH_CODE}")
    fi
    if [[ "$REMOTE_HEALTH_BODY" != *'"status":"healthy"'* ]]; then
      # try basic JSON parse if python3 available
      if command -v python3 >/dev/null 2>&1; then
        parsed_status=$(printf "%s" "$REMOTE_HEALTH_BODY" | python3 -c 'import sys, json
try:
  obj=json.load(sys.stdin)
  print(obj.get("status", ""))
except Exception:
  print("__PARSE_FAILED__")')
        if [[ "$parsed_status" != "healthy" ]]; then
          overall_ok=false
          reasons+=("status_parsed=${parsed_status}")
        fi
      else
        overall_ok=false
        reasons+=("no_status_token_and_no_python3")
      fi
    fi
  fi
fi

# If user requested strict TCP success, fail the script when TCP probe fails
if [[ "$REQUIRE_TCP" = true ]]; then
  if [[ "$tcp_out" != *"TCP_PROBE: OK"* ]]; then
    overall_ok=false
    reasons+=("tcp_probe_failed")
  fi
fi

if [[ "$JSON_OUTPUT" = true ]]; then
  # Emit a compact JSON summary
  ss_excerpt=$(printf "%s" "$ss_out" | tr -d '\n' | sed -E 's/"/\\"/g' | cut -c1-400)
  lsof_excerpt=$(ssh -o ConnectTimeout=10 "$REMOTE" "sudo lsof -i :${PORT} 2>/dev/null || true" 2>/dev/null | tr -d '\n' | sed -E 's/"/\\"/g' | cut -c1-400)
  pidval=${pid:-}
  # forwarded_match mirrors the lightweight forwarded_to_target boolean
  forwarded_match=${forwarded_to_target:-false}

  printf '{"ss":"%s","pid":%s,"lsof":"%s","http_code":%s,"http_excerpt":"%s","tcp_probe":"%s","settings_found":%s,"settings_path":"%s","auto_forward_disabled":"%s","port3000_ignored":"%s","port3001_ignored":"%s","settings_excerpt":"%s","forwarded_to_target":%s,"overall_ok":%s,"reasons":"%s"}\n' \
    "$ss_excerpt" "${pidval:-null}" "$lsof_excerpt" "$REMOTE_HEALTH_CODE" "$REMOTE_HEALTH_EXCERPT" "$(echo "$tcp_out" | tr -d '\n')" "$settings_found" "$settings_path_found" "$auto_forward_disabled" "$port3000_ignored" "$port3001_ignored" "$settings_excerpt" "$forwarded_to_target" "${overall_ok}" "$(IFS=,; echo "${reasons[*]}")"
fi

if [[ "$REQUIRE_TCP" = true || "$REQUIRE_HEALTH" = true ]]; then
  if [[ "$overall_ok" = false ]]; then
    echo "ERROR: check_autossh_forward: failing required checks: ${reasons[*]}" >&2
    exit 3
  fi
fi

echo "If port ${PORT} is owned by code-server or another process, disable VS Code auto-forwarding or remove the forward via the 'Ports' UI. As a last-resort short test you can kill the owning PID, but this will drop active SSH sessions."
