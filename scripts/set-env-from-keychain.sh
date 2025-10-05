#!/bin/bash

# Simple script to set environment variables from KeyChain
# Add to .zshrc or run before starting services

echo "🔐 Loading API keys from macOS KeyChain into environment..."

# Function to load key from KeyChain
load_key() {
    local service_name=$1
    local env_var_name=$2

    local key_value=$(security find-generic-password \
        -a "$service_name" \
        -s "cipher-$service_name" \
        -w 2>/dev/null)

    if [ -n "$key_value" ]; then
        export "$env_var_name"="$key_value"
        echo "✅ $env_var_name loaded from KeyChain"
    else
        echo "⚠️  $env_var_name not found in KeyChain"
        echo "   Store it with: ./scripts/store-api-key.sh $service_name \"your-key\""
    fi
}

# Load required keys
load_key "google-api-key" "GOOGLE_API_KEY"
load_key "anthropic-api-key" "ANTHROPIC_API_KEY"
load_key "openai-api-key" "OPENAI_API_KEY"

echo "🚀 Environment variables loaded. Ready to start services."