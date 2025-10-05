#!/usr/bin/env bash
set -euo pipefail

SECRET_NAME="cipher-gemini-api-key"

# Load helper
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/podman/secret_utils.sh"

echo "🔐 Creating Podman secret (idempotent, non-interactive): $SECRET_NAME"

# Priority of secret value sources (non-interactive):
# 1) First script argument
# 2) Environment variable GEMINI_API_KEY
# 3) macOS KeyChain lookup (security) if available

if [ $# -ge 1 ] && [ -n "$1" ]; then
    API_KEY="$1"
elif [ -n "${GEMINI_API_KEY:-}" ]; then
    API_KEY="$GEMINI_API_KEY"
else
    API_KEY=$(retrieve_from_keychain "kieran@rossollc.com" "GEMINI_API_KEY" || true)
fi

if [ -z "${API_KEY:-}" ]; then
    echo "❌ No GEMINI API key provided. Provide as first argument or via GEMINI_API_KEY env var."
    exit 2
fi

# Create or replace the secret idempotently
create_or_replace_secret_from_value "$SECRET_NAME" "$API_KEY"

echo "✅ Podman secret ensured: $SECRET_NAME"