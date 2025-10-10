#!/usr/bin/env zsh
# Quick macOS diagnostics for Claude MCP / local tunnel
# Safe: avoids printing secrets; only inspects config keys and service endpoints.

echo "=== Environment ==="
echo "Shell: $SHELL"
echo "User: $(whoami)"
echo "NVM_DIR: ${NVM_DIR:-<unset>}"
if command -v nvm >/dev/null 2>&1; then echo "nvm: available"; else echo "nvm: not available"; fi
if command -v claude >/dev/null 2>&1; then
  echo "claude: $(which claude)"
  claude --version 2>/dev/null || true
else
  echo "claude: not found in PATH"
fi

echo
echo "=== Pre-sourcing: claude mcp list ==="
if command -v claude >/dev/null 2>&1; then
  claude mcp list || echo "(claude returned non-zero exit)"
else
  echo "(claude not available to list MCPs)"
fi

echo
echo "=== RC files present ==="
for rc in ~/.zshrc ~/.bashrc ~/.profile; do
  if [ -f "$rc" ]; then echo "Found: $rc"; else echo "Missing: $rc"; fi
done

echo
echo "=== Claude config (safe preview) ==="
if [ -f ~/.claude/mcps.json ]; then
  echo "File: ~/.claude/mcps.json (permissions: $(stat -f%Lp ~/.claude/mcps.json))"
  if command -v jq >/dev/null 2>&1; then
    jq '.[] | {name, transport, url}' ~/.claude/mcps.json || true
  else
    grep -E '"name"|"transport"|"url"' ~/.claude/mcps.json || true
  fi
else
  echo "~/.claude/mcps.json: not found"
fi

echo
echo "=== Network / tunnel checks ==="
echo "Listening on ports (3000, 3001):"
if command -v lsof >/dev/null 2>&1; then
  lsof -nP -iTCP -sTCP:LISTEN 2>/dev/null | egrep ":(3000|3001)\\b" || echo "No listeners found on 3000/3001"
else
  echo "lsof: not available"
fi

echo "curl 127.0.0.1:3001/health (max-time 3s):"
if command -v curl >/dev/null 2>&1; then
  curl -sS --max-time 3 http://127.0.0.1:3001/health || echo "(health probe failed/timeout)"
else
  echo "curl: not available"
fi

echo "Attempt MCP SSE HEAD (short):"
if command -v curl >/dev/null 2>&1; then
  curl -sS --max-time 3 http://127.0.0.1:3001/mcp/sse | head -n 3 || echo "(sse probe failed/timeout)"
else
  echo "curl: not available"
fi

echo
echo "=== Node / NPM / Docker / System ==="
if command -v node >/dev/null 2>&1; then
  node --version && npm --version || true
else
  echo "node: not available"
fi

echo "Docker containers (if docker available):"
if command -v docker >/dev/null 2>&1; then
  docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Ports}}"
else
  echo "docker: not available"
fi

echo
echo "=== Quick guidance ==="
echo "1) If 'claude' was found but 'mcp list' showed nothing, try sourcing your shell rc then rerun:"
echo "   source ~/.zshrc && claude mcp list"
echo "2) If ~/.claude/mcps.json exists, verify 'transport' is 'sse' and the url is a loopback tunnel (e.g. http://127.0.0.1:3001/mcp/sse)"
echo "3) Re-add the MCP (example):"
echo "   claude mcp remove cipher-mcp || true"
echo "   claude mcp add -t sse -s user cipher-mcp http://127.0.0.1:3001/mcp/sse"

echo
echo "Done."
