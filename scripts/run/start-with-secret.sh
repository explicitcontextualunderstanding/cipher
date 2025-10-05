#!/bin/bash

# Start Cipher with Podman secret properly loaded
# Usage: ./scripts/start-with-secret.sh

set -e

echo "🚀 Starting Cipher with Podman secret..."

# Check if secret exists
if ! podman secret inspect cipher-gemini-api-key &>/dev/null; then
    echo "❌ Podman secret 'cipher-gemini-api-key' not found"
    echo "Please run: ./scripts/secure-gemini-workflow.sh"
    exit 1
fi

echo "✅ Podman secret found"

# Create a custom startup script
cat > /tmp/cipher-startup.sh << 'EOF'
#!/bin/sh
# Read the secret file and set environment variable
if [ -f "/run/secrets/cipher-gemini-api-key" ]; then
    echo "🔑 Loading GEMINI_API_KEY from Podman secret"
    export GEMINI_API_KEY=$(cat /run/secrets/cipher-gemini-api-key)
    echo "✅ GEMINI_API_KEY loaded (${#GEMINI_API_KEY} characters)"
else
    echo "❌ Secret file not found: /run/secrets/cipher-gemini-api-key"
    exit 1
fi

# Start the actual application
echo "🚀 Starting Cipher application..."
exec node dist/src/app/index.cjs --mode api --port 3000 --host 0.0.0.0 --agent /app/memAgent/cipher.yml --mcp-transport-type sse
EOF

chmod +x /tmp/cipher-startup.sh

echo "🏗️  Building and starting Cipher..."

cd "$(dirname "$0")/.."

# Stop existing container
podman-compose down cipher-api 2>/dev/null || true

# Update docker-compose to use our startup script
cp docker-compose.yml docker-compose.yml.backup

# Create override for the startup command
cat > docker-compose.override.yml << 'EOF'
version: '3.8'
services:
  cipher-api:
    command: ['/tmp/cipher-startup.sh']
    volumes:
      - /tmp/cipher-startup.sh:/tmp/cipher-startup.sh:ro
EOF

# Build and start
podman-compose build cipher-api
podman-compose -f docker-compose.yml -f docker-compose.override.yml up -d

# Clean up
rm -f /tmp/cipher-startup.sh docker-compose.override.yml
mv docker-compose.yml.backup docker-compose.yml

echo ""
echo "✅ Cipher started with Podman secret!"
echo ""
echo "📊 Check status:"
echo "  podman-compose ps"
echo ""
echo "📋 View logs:"
echo "  podman-compose logs -f cipher-api"
echo ""
echo "🔐 Security status:"
echo "  - Secret loaded from Podman secure store"
echo "  - Not exposed via environment variables"
echo "  - Available only inside container as file"