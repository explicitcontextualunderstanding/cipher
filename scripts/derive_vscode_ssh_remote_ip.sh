#!/usr/bin/env zsh
# derive_vscode_ssh_remote_ip.sh
# Heuristics to derive the target host/IP used by VS Code Remote - SSH.
# Usage: ./derive_vscode_ssh_remote_ip.sh

set -euo pipefail

out() { printf "%s\n" "$@"; }
sep() { out "----------------------------------------"; }

out "1) Look for an active SSH process that VS Code uses"
sep
ps aux | egrep --line-number 'ssh .*@' | egrep -v 'egrep|derive_vscode_ssh_remote_ip' || true

out "\n2) Try to extract host from running ssh command lines"
sep
ps aux | egrep 'ssh .*@' | awk '{for(i=11;i<=NF;i++) printf "%s ", $i; print ""}' | sed -n 's/.*\([[:alnum:]._-]\+@\)\([^ ]\+\).*/\2/p' | sort -u || true

out "\n3) Inspect ~/.ssh/config for Host / HostName mappings"
sep
if [[ -r "$HOME/.ssh/config" ]]; then
  awk '/^Host /{host=$2} /^\t?HostName /{print host " -> " $2}' "$HOME/.ssh/config" || true
else
  out "No ~/.ssh/config found or not readable"
fi

out "\n4) Use 'ssh -G' to resolve HostName for each Host in ~/.ssh/config"
sep
if [[ -r "$HOME/.ssh/config" ]]; then
  awk '/^Host /{print $2}' "$HOME/.ssh/config" | while read -r h; do
    # skip wildcard hosts
    if [[ "$h" == "*" ]]; then continue; fi
    resolved=$(ssh -G "$h" 2>/dev/null | awk '/^hostname /{print $2}' || true)
    if [[ -n "$resolved" ]]; then
      out "$h resolves to: $resolved"
    fi
  done
fi

out "\n5) Grep VS Code Remote-SSH logs for the last connection command"
sep
# Find extension folder
EXT_DIRS=("$HOME/.vscode/extensions" "$HOME/.vscode-insiders/extensions")
for d in "${EXT_DIRS[@]}"; do
  if [[ -d "$d" ]]; then
    find "$d" -maxdepth 2 -type f -name "*.log" -o -name "*out*" 2>/dev/null | xargs -I{} grep -H "Running.*ssh\|SSH Resolver" {} 2>/dev/null || true
  fi
done

out "\n6) Search known_hosts for IP-looking entries for likely hostnames"
sep
if [[ -r "$HOME/.ssh/known_hosts" ]]; then
  # show entries; note some hosts may be hashed
  grep --line-number -E '([0-9]{1,3}\.){3}[0-9]{1,3}' "$HOME/.ssh/known_hosts" || true
else
  out "No known_hosts file or not readable"
fi

sep
out "Candidate hostnames/IPs found above. If you see a hostname alias (e.g. 'jetson') use 'ssh -G <alias>' to find the resolved HostName/IP."
out "If you want, I can run this script for you now and then inject the detected IP into the autossh plist and load it."
