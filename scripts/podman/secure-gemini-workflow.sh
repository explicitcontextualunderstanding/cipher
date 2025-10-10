#!/bin/bash

# Standard secure workflow: KeyChain → Temporary File → Podman Secret → Container
# Based on Podman best practices for macOS
# Usage: ./scripts/secure-gemini-workflow.sh

set -e

SECRET_NAME="cipher-gemini-api-key"
TEMP_FILE="/tmp/cipher-gemini-api-key.txt"

echo "🔐 Secure Podman secrets workflow for GEMINI_API_KEY"
echo "============================================="

# source helper to get PODMAN_BIN
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/secret_utils.sh"

# Step 1: Retrieve secret from macOS KeyChain
echo "🔑 Step 1: Retrieving GEMINI_API_KEY from KeyChain..."

API_KEY=$(security find-generic-password -a "kieran@rossollc.com" -s "GEMINI_API_KEY" -w 2>/dev/null)

if [ -z "$API_KEY" ]; then
    echo "❌ GEMINI_API_KEY not found in KeyChain"
    echo ""
    echo "Make sure it's set in your .zshrc:"
    echo "export GEMINI_API_KEY=\$(security find-generic-password -a kieran@rossollc.com -s GEMINI_API_KEY -w)"
    exit 1
fi

echo "✅ GEMINI_API_KEY retrieved from KeyChain (${#API_KEY} characters)"

# Step 2: Create temporary file with restricted permissions
echo ""
echo "📁 Step 2: Creating temporary file with secure permissions..."

echo "$API_KEY" > "$TEMP_FILE"
chmod 600 "$TEMP_FILE"

echo "✅ Temporary file created: $TEMP_FILE"
echo "   Permissions: $(ls -la "$TEMP_FILE" | cut -d' ' -f1)"

# Step 3: Remove existing Podman secret if it exists
echo ""
echo "🗑️  Step 3: Removing existing Podman secret (if any)..."

if "$PODMAN_BIN" secret inspect "$SECRET_NAME" &>/dev/null; then
    "$PODMAN_BIN" secret rm "$SECRET_NAME"
    echo "✅ Removed existing secret: $SECRET_NAME"
else
    echo "ℹ️  No existing secret to remove"
fi

# Step 4: Create Podman secret from temporary file
echo ""
echo "🔐 Step 4: Creating Podman secret from temporary file..."

"$PODMAN_BIN" secret create "$SECRET_NAME" "$TEMP_FILE"

if [ $? -eq 0 ]; then
    echo "✅ Podman secret created: $SECRET_NAME"
else
    echo "❌ Failed to create Podman secret"
    rm -f "$TEMP_FILE"
    exit 1
fi

# Step 5: Clean up temporary file immediately
echo ""
echo "🧹 Step 5: Cleaning up temporary file..."

rm -f "$TEMP_FILE"

if [ ! -f "$TEMP_FILE" ]; then
    echo "✅ Temporary file securely deleted"
else
    echo "⚠️  Warning: Temporary file still exists - please delete manually: $TEMP_FILE"
fi

# Step 6: Verify secret and show security info
echo ""
echo "📋 Step 6: Verification and Security Information"
echo "=============================================="

echo ""
echo "🔐 Secret details:"
"$PODMAN_BIN" secret inspect "$SECRET_NAME" | head -10

echo ""
echo "🔒 Security benefits:"
echo "  ✅ Secret stored in Podman's Linux VM (isolated from host)"
echo "  ✅ Not accessible via environment variables in container"
echo "  ✅ Not exposed in 'podman inspect' output"
echo "  ✅ Temporary file deleted immediately"
echo "  ✅ Read-only file access inside container"
echo "  ✅ Never part of container image"

echo ""
echo "🚀 Ready to start Cipher with secure secret!"
echo ""
echo "Usage:"
echo "  podman-compose up -d cipher-api"
echo ""
echo "Inside container, the secret will be available at:"
echo "  /run/secrets/$SECRET_NAME"