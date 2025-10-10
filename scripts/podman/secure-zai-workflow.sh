#!/bin/bash

set -e

SECRET_NAME="cipher-zai-api-key"
TEMP_FILE="/tmp/cipher-zai-api-key.txt"

echo "🔐 Secure Podman secrets workflow for ANTHROPIC_API_KEY (Z.ai)"
echo "============================================="

# source helper to get PODMAN_BIN
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/secret_utils.sh"

echo "🔑 Step 1: Retrieving ANTHROPIC API key from KeyChain or environment..."

# Try multiple KeyChain service names to be tolerant of naming differences.
API_KEY=""
SERVICE_USED=""
for svc in "ANTHROPIC_API_KEY" "ZAI_ANTHROPIC_API_KEY"; do
    API_KEY=$(security find-generic-password -a "kieran@rossollc.com" -s "$svc" -w 2>/dev/null || echo "")
    if [ -n "$API_KEY" ]; then
        SERVICE_USED="$svc"
        break
    fi
done

# Fallback to environment variables if KeyChain lookup did not return a value
if [ -z "$API_KEY" ]; then
    if [ -n "${ANTHROPIC_API_KEY:-}" ]; then
        API_KEY="$ANTHROPIC_API_KEY"
        SERVICE_USED="ENV:ANTHROPIC_API_KEY"
    elif [ -n "${ANTHROPIC_AUTH_TOKEN:-}" ]; then
        API_KEY="$ANTHROPIC_AUTH_TOKEN"
        SERVICE_USED="ENV:ANTHROPIC_AUTH_TOKEN"
    fi
fi

if [ -z "$API_KEY" ]; then
    echo "❌ ANTHROPIC API key not found in KeyChain or environment"
    echo "Ensure KeyChain has service names ANTHROPIC_API_KEY or ZAI_ANTHROPIC_API_KEY, or set ANTHROPIC_API_KEY / ANTHROPIC_AUTH_TOKEN in your environment"
    exit 1
fi

echo "✅ ANTHROPIC API key retrieved (${#API_KEY} characters) from: ${SERVICE_USED}"

echo "📁 Step 2: Creating temporary file with secure permissions..."
echo "$API_KEY" > "$TEMP_FILE"
chmod 600 "$TEMP_FILE"

echo "✅ Temporary file created: $TEMP_FILE"

echo "🗑️  Step 3: Removing existing Podman secret (if any)..."
if "$PODMAN_BIN" secret inspect "$SECRET_NAME" &>/dev/null; then
    "$PODMAN_BIN" secret rm "$SECRET_NAME"
    echo "✅ Removed existing secret: $SECRET_NAME"
else
    echo "ℹ️  No existing secret to remove"
fi

echo "🔐 Step 4: Creating Podman secret from temporary file..."
"$PODMAN_BIN" secret create "$SECRET_NAME" "$TEMP_FILE"
if [ $? -eq 0 ]; then
    echo "✅ Podman secret created: $SECRET_NAME"
else
    echo "❌ Failed to create Podman secret"
    rm -f "$TEMP_FILE"
    exit 1
fi

echo "🧹 Step 5: Cleaning up temporary file..."
rm -f "$TEMP_FILE"
if [ ! -f "$TEMP_FILE" ]; then
    echo "✅ Temporary file securely deleted"
else
    echo "⚠️  Temporary file still exists - please delete manually: $TEMP_FILE"
fi

echo "📋 Verification"
 "$PODMAN_BIN" secret inspect "$SECRET_NAME" | head -n 20 || true

echo "🚀 Ready to start Cipher with secure Z.ai secret!"
echo "Usage: podman-compose up -d cipher-api"
