#!/usr/bin/env bash
set -euo pipefail

# Backward-compatible wrapper: if the image contains /usr/local/bin/entrypoint.sh use it,
# otherwise perform the export inline and then exec the provided command (or a sensible default).
if [[ -x "/usr/local/bin/entrypoint.sh" ]]; then
  exec "/usr/local/bin/entrypoint.sh" "$@"
fi

# Fallback export logic (same behaviour as entrypoint.sh)
if command -v compgen >/dev/null 2>&1; then
  file_vars=$(compgen -e | grep '_API_KEY_FILE$' || true)
else
  file_vars=$(env | awk -F= '/_API_KEY_FILE$/{print $1}' || true)
fi

for file_var in $file_vars; do
  key_var="${file_var%_FILE}"
  file_path="${!file_var:-}"
  if [[ -n "$file_path" && -f "$file_path" ]]; then
    value="$(cat "$file_path")"
    printf -v "$key_var" '%s' "$value"
    export "$key_var"
  else
    echo "Warning: secret file for $key_var not found at ${file_path:-'<unset>'}" >&2
  fi
done

# If a command was provided, run it; otherwise fall back to the default Node start used in compose
if [[ $# -gt 0 ]]; then
  exec "$@"
else
  exec node dist/src/app/index.cjs --mode api --port 3000 --host 0.0.0.0 --agent /app/memAgent/cipher.yml --mcp-transport-type sse
fi
#!/bin/sh

# Load Podman secrets and start Cipher
# This script reads the secret files and sets environment variables

echo "🔑 Loading API keys from Podman secrets..."

# Load GEMINI_API_KEY (file secret first, then environment fallback)
if [ -f "/run/secrets/cipher-gemini-api-key" ]; then
    export GEMINI_API_KEY=$(cat /run/secrets/cipher-gemini-api-key)
    echo "✅ GEMINI_API_KEY loaded from secret file (${#GEMINI_API_KEY} characters)"
elif [ -n "${GEMINI_API_KEY:-}" ]; then
    echo "⚠️  Secret file not found; using GEMINI_API_KEY from environment (${#GEMINI_API_KEY} characters)"
else
    echo "❌ GEMINI_API_KEY not found."
    echo "Please run: ./scripts/secure-gemini-workflow.sh or set GEMINI_API_KEY in the environment"
    exit 1
fi

# Load ANTHROPIC_API_KEY (Z.ai) — support file secret, ANTHROPIC_API_KEY env,
# or ANTHROPIC_AUTH_TOKEN env (common naming alternatives).
if [ -f "/run/secrets/cipher-zai-api-key" ]; then
    export ANTHROPIC_API_KEY=$(cat /run/secrets/cipher-zai-api-key)
    echo "✅ ANTHROPIC_API_KEY (Z.ai) loaded from secret file (${#ANTHROPIC_API_KEY} characters)"
elif [ -n "${ANTHROPIC_API_KEY:-}" ]; then
    echo "⚠️  Secret file not found; using ANTHROPIC_API_KEY from environment (${#ANTHROPIC_API_KEY} characters)"
elif [ -n "${ANTHROPIC_AUTH_TOKEN:-}" ]; then
    export ANTHROPIC_API_KEY="$ANTHROPIC_AUTH_TOKEN"
    echo "⚠️  Secret file not found; using ANTHROPIC_AUTH_TOKEN from environment (${#ANTHROPIC_API_KEY} characters)"
else
    echo "❌ ANTHROPIC API key not found."
    echo "Please run: ./scripts/secure-zai-workflow.sh or set ANTHROPIC_API_KEY / ANTHROPIC_AUTH_TOKEN in the environment"
    exit 1
fi

echo "🚀 Starting Cipher with secure API keys in aggregator mode..."
exec node dist/src/app/index.cjs --mode api --port 3000 --host 0.0.0.0 --agent /app/memAgent/cipher.yml --mcp-transport-type sse