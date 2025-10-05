#!/bin/bash

# Start Cipher with Podman secrets and set environment variables
# This script reads secrets from files and exports them as environment variables

set -e

echo "🔐 Starting Cipher with Podman secrets..."

# Check if the Podman secret exists
if ! podman secret inspect cipher-gemini-api-key &>/dev/null; then
    echo "❌ Podman secret 'cipher-gemini-api-key' not found"
    echo "Please run: ./scripts/create-gemini-secret.sh"
    exit 1
fi

echo "✅ Podman secret found"

# Create a startup script that reads the secret file
cat > /tmp/cipher-startup.sh << 'EOF'
#!/bin/sh
# Read secret from file and export as environment variable
if [ -f "/run/secrets/cipher-gemini-api-key" ]; then
    export GEMINI_API_KEY=$(cat /run/secrets/cipher-gemini-api-key)
    echo "✅ GEMINI_API_KEY loaded from secret file"
else
    echo "❌ Secret file not found: /run/secrets/cipher-gemini-api-key"
    exit 1
fi

# Start the actual application
exec node dist/src/app/index.cjs --mode api --port 3000 --host 0.0.0.0 --agent /app/memAgent/cipher.yml --mcp-transport-type sse
EOF

chmod +x /tmp/cipher-startup.sh

echo "🏗️  Building and starting Cipher with secrets..."

cd "$(dirname "$0")/.."

# Build image
podman-compose build cipher-api

# Update docker-compose to use our startup script temporarily
docker-compose.override.yml > /tmp/docker-compose.override.yml << 'EOF'
version: '3.8'
services:
  cipher-api:
    command:
      - 'sh'
      - '-c'
      - '/tmp/cipher-startup.sh'
    volumes:
      - /tmp/cipher-startup.sh:/tmp/cipher-startup.sh:ro
EOF

# Start with override
podman-compose -f docker-compose.yml -f /tmp/docker-compose.override.yml up -d

# Clean up
rm -f /tmp/cipher-startup.sh /tmp/docker-compose.override.yml

echo ""
echo "✅ Cipher started with Podman secrets!"
echo ""
echo "📊 Check status:"
echo "  podman-compose ps"
echo ""
echo "📋 View logs:"
echo "  podman-compose logs -f cipher-api"