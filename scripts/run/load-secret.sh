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