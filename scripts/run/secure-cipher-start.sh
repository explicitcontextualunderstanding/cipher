#!/bin/bash

# Start Cipher with secure environment variables from KeyChain
# Usage: ./scripts/secure-cipher-start.sh

set -e

echo "🔐 Loading API keys from macOS KeyChain..."

# Function to load key from KeyChain
load_key() {
    local account="$1"
    local service="$2"
    local env_var="$3"

    local key_value
    key_value=$(security find-generic-password -a "$account" -s "$service" -w 2>/dev/null || echo "")

    if [ -n "$key_value" ]; then
        export "$env_var"="$key_value"
        echo "✅ $env_var loaded from KeyChain"
    else
        echo "⚠️  $env_var not found in KeyChain"
    fi
}

# Load API keys
load_key "kieran@rossollc.com" "GEMINI_API_KEY" "GEMINI_API_KEY"
load_key "kieran@rossollc.com" "ANTHROPIC_API_KEY" "ANTHROPIC_API_KEY"
load_key "kieran@rossollc.com" "OPENAI_API_KEY" "OPENAI_API_KEY"
load_key "kieran@rossollc.com" "OPENROUTER_API_KEY" "OPENROUTER_API_KEY"
load_key "kieran@rossollc.com" "QWEN_API_KEY" "QWEN_API_KEY"
load_key "kieran@rossollc.com" "VOYAGE_API_KEY" "VOYAGE_API_KEY"
load_key "kieran@rossollc.com" "DEEPSEEK_API_KEY" "DEEPSEEK_API_KEY"

# Set static environment variables
export ANTHROPIC_BASE_URL="https://api.z.ai/api/anthropic"
export DISABLE_EMBEDDINGS="true"
export NODE_ENV="development"
export CIPHER_LOG_LEVEL="info"
export REDACT_SECRETS="true"
export STORAGE_CACHE_TYPE="in-memory"
export STORAGE_DATABASE_TYPE="in-memory"
export WEB_SEARCH_ENABLE="true"
export WEB_SEARCH_ENGINE="duckduckgo"
export WEB_SEARCH_SAFETY_MODE="strict"
export WEB_SEARCH_MAX_RESULTS="2"
export WEB_SEARCH_RATE_LIMIT="10"
export CIPHER_MULTI_BACKEND="1"
export SEARCH_MEMORY_TYPE="both"
export VECTOR_STORE_TYPE="in-memory"
export VECTOR_STORE_COLLECTION="knowledge_memory"
export VECTOR_STORE_DIMENSION="1536"
export VECTOR_STORE_DISTANCE="Cosine"
export VECTOR_STORE_ON_DISK="false"
export REFLECTION_VECTOR_STORE_COLLECTION="reflection_memory"
export DISABLE_REFLECTION_MEMORY="true"
export ENABLE_QUERY_REFINEMENT="true"

echo "🚀 Starting Cipher with secure environment variables..."

# Start cipher
cd "$(dirname "$0")/.."
podman-compose up -d

echo "✅ Cipher started with secure environment variables"