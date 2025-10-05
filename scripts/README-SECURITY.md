# Secure API Key Management for Cipher

## Overview

This setup provides secure API key storage using macOS KeyChain while maintaining compatibility with Docker/Podman containers.

## Quick Setup

### 1. Store API Keys in KeyChain

```bash
# Store Google API Key for embeddings
./scripts/store-api-key.sh google-api-key "your-google-api-key-here"

# Store other keys as needed
./scripts/store-api-key.sh anthropic-api-key "your-anthropic-api-key"
```

### 2. Start Services (Choose one method)

#### Method A: Secure Docker Compose (Recommended)
```bash
# Uses Docker secrets for maximum security
./scripts/deploy-with-secrets.sh
```

#### Method B: Environment Variables (Simpler)
```bash
# Load keys into environment
source ./scripts/set-env-from-keychain.sh

# Start services with environment variables
podman-compose -f docker-compose-with-secrets.yml up -d
```

#### Method C: Manual (Development)
```bash
# Load keys
source ./scripts/set-env-from-keychain.sh

# Start embedding service
cd embedding-service
export GOOGLE_API_KEY
go run main.go &

# Start Cipher
cd ..
podman-compose up -d cipher-api
```

## Security Features

- **KeyChain Storage**: API keys stored in macOS KeyChain with proper encryption
- **Temporary Files**: Keys written to temporary files with 600 permissions, immediately cleaned up
- **No Plaintext in Git**: No API keys stored in repository or configuration files
- **Container Isolation**: Keys injected via Docker secrets or environment variables
- **Audit Trail**: KeyChain access logged by macOS

## Verification

```bash
# Check if keys are properly loaded
podman logs cipher_cipher-api_1 | grep -i embedding

# Test embedding service
curl http://localhost:5000/health

# Verify memory tools are available
# Use Claude Code Extension to test cipher_store_reasoning_memory
```

## Adding New API Keys

1. Store in KeyChain:
   ```bash
   ./scripts/store-api-key.sh new-service "your-new-api-key"
   ```

2. Update `set-env-from-keychain.sh`:
   ```bash
   load_key "new-service" "NEW_SERVICE_API_KEY"
   ```

3. Add to docker-compose files as needed

## Security Best Practices

- ✅ Use KeyChain for local development
- ✅ Use Docker secrets in production
- ✅ Never commit API keys to git
- ✅ Use minimal key permissions
- ✅ Rotate keys regularly
- ❌ Don't use environment files for production secrets