#!/bin/bash

# Secure deployment script that retrieves API keys from KeyChain
# Usage: ./scripts/deploy-with-secrets.sh

set -e

echo "🔐 Retrieving API keys from macOS KeyChain..."

# Retrieve Google API Key
GOOGLE_API_KEY=$(./scripts/get-api-key.sh google-api-key)

if [ -z "$GOOGLE_API_KEY" ]; then
    echo "❌ Failed to retrieve Google API Key"
    echo "Please store it first: ./scripts/store-api-key.sh google-api-key \"your-key\""
    exit 1
fi

# Create temporary secret file
echo "$GOOGLE_API_KEY" > /tmp/cipher-google-api-key.txt
chmod 600 /tmp/cipher-google-api-key.txt

echo "✅ API keys retrieved securely"

# Build and deploy
echo "🏗️  Building and starting Cipher with secrets..."

# Build the image
podman-compose build cipher-api

# Start with secrets
podman-compose up -d cipher-api

# Clean up temporary file
rm -f /tmp/cipher-google-api-key.txt

echo "✅ Cipher deployed with secure API keys"
echo "📊 Check logs: podman logs -f cipher_cipher-api_1"