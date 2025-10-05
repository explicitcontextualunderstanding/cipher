#!/bin/bash

# Generate cipher .env file from macOS KeyChain
# Usage: ./scripts/generate-env.sh

set -e

CIPHER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$CIPHER_DIR/.env"

echo "🔐 Generating $ENV_FILE from macOS KeyChain..."

# Backup existing .env if it exists
if [ -f "$ENV_FILE" ]; then
    cp "$ENV_FILE" "$ENV_FILE.backup.$(date +%Y%m%d_%H%M%S)"
    echo "📋 Backed up existing .env file"
fi

# Start with header
cat > "$ENV_FILE" << 'EOF'
# Cipher Environment Configuration
# Generated from macOS KeyChain - DO NOT EDIT MANUALLY
# Run ./scripts/generate-env.sh to regenerate

# ====================
# API Configuration
# ====================
EOF

# Function to retrieve key from KeyChain and add to .env
add_key_to_env() {
    local account="$1"
    local service="$2"
    local env_var="$3"
    local description="$4"

    echo "🔑 Retrieving $description..." >&2

    local key_value
    key_value=$(security find-generic-password -a "$account" -s "$service" -w 2>/dev/null || echo "")

    if [ -n "$key_value" ]; then
        echo "$env_var=$key_value" >> "$ENV_FILE"
        echo "✅ $env_var loaded" >&2
    else
        echo "# $env_var=not-found-in-keychain" >> "$ENV_FILE"
        echo "⚠️  $env_var not found in KeyChain (account: $account, service: $service)" >&2
    fi
}

# Add API keys from KeyChain
add_key_to_env "kieran@rossollc.com" "GEMINI_API_KEY" "GEMINI_API_KEY" "Google Gemini API Key"
add_key_to_env "kieran@rossollc.com" "ANTHROPIC_API_KEY" "ANTHROPIC_API_KEY" "Anthropic API Key"
add_key_to_env "kieran@rossollc.com" "OPENAI_API_KEY" "OPENAI_API_KEY" "OpenAI API Key"
add_key_to_env "kieran@rossollc.com" "OPENROUTER_API_KEY" "OPENROUTER_API_KEY" "OpenRouter API Key"
add_key_to_env "kieran@rossollc.com" "QWEN_API_KEY" "QWEN_API_KEY" "Qwen API Key"
add_key_to_env "kieran@rossollc.com" "VOYAGE_API_KEY" "VOYAGE_API_KEY" "Voyage AI API Key"
add_key_to_env "kieran@rossollc.com" "DEEPSEEK_API_KEY" "DEEPSEEK_API_KEY" "DeepSeek API Key"

# Add static configuration
cat >> "$ENV_FILE" << 'EOF'

# ====================
# Static Configuration
# ====================
ANTHROPIC_BASE_URL=https://api.z.ai/api/anthropic

# ====================
# Embedding Configuration
# ====================
# Disable embeddings until we configure them properly
DISABLE_EMBEDDINGS=true

# ====================
# Application Settings
# ====================
NODE_ENV=development
CIPHER_LOG_LEVEL=info
REDACT_SECRETS=true

# ====================
# Storage Configuration
# ====================
STORAGE_CACHE_TYPE=in-memory
STORAGE_DATABASE_TYPE=in-memory

# ====================
# Web Search Configuration
# ====================
WEB_SEARCH_ENABLE=true
WEB_SEARCH_ENGINE=duckduckgo
WEB_SEARCH_SAFETY_MODE=strict
WEB_SEARCH_MAX_RESULTS=2
WEB_SEARCH_RATE_LIMIT=10

CIPHER_MULTI_BACKEND=1

# ====================
# Memory Search Configuration
# ====================
SEARCH_MEMORY_TYPE=both

# ====================
# Vector Store Configuration
# ====================
VECTOR_STORE_TYPE=in-memory
VECTOR_STORE_COLLECTION=knowledge_memory
VECTOR_STORE_DIMENSION=1536
VECTOR_STORE_DISTANCE=Cosine
VECTOR_STORE_ON_DISK=false

# ====================
# Reflection Memory Configuration
# ====================
REFLECTION_VECTOR_STORE_COLLECTION=reflection_memory
DISABLE_REFLECTION_MEMORY=true

# ====================
# Knowledge Graph Configuration
# ====================
# NEO4J disabled by default

# ====================
# Event Management
# ====================
ENABLE_QUERY_REFINEMENT=true
EOF

echo "✅ Environment file generated successfully"
echo "📍 Location: $ENV_FILE"
echo ""
echo "📝 Next steps:"
echo "1. Review the generated .env file"
echo "2. Start cipher with: podman-compose up -d"
echo "3. Or regenerate anytime with: ./scripts/generate-env.sh"