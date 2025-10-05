#!/bin/bash

# Start Cipher with Google Cloud ADC integration
# Usage: ./scripts/start-cipher-with-gcp.sh

set -e

echo "🚀 Starting Cipher with Google Cloud ADC..."

# Check prerequisites
ADC_FILE="$HOME/.config/gcloud/application_default_credentials.json"

if [ ! -f "$ADC_FILE" ]; then
    echo "❌ ADC file not found: $ADC_FILE"
    echo "Please run: ./scripts/setup-gcp-adc.sh"
    exit 1
fi

# Check if Podman secret exists
if ! podman secret inspect cipher-gcp-adc &>/dev/null; then
    echo "❌ Podman secret 'cipher-gcp-adc' not found"
    echo "Please run: ./scripts/create-gcp-secret.sh"
    exit 1
fi

echo "✅ Prerequisites checked"

# Create other secrets if needed (from KeyChain)
echo "🔐 Checking other API secrets..."

create_secret_if_needed() {
    local account="$1"
    local service="$2"
    local secret_name="$3"
    local env_var="$4"

    if ! podman secret inspect "$secret_name" &>/dev/null; then
        echo "🔑 Creating secret: $secret_name"
        local key_value
        key_value=$(security find-generic-password -a "$account" -s "$service" -w 2>/dev/null || echo "")

        if [ -n "$key_value" ]; then
            local temp_file="/tmp/${secret_name}.txt"
            echo "$key_value" > "$temp_file"
            chmod 600 "$temp_file"
            podman secret create "$secret_name" "$temp_file"
            rm -f "$temp_file"
            echo "✅ Created: $secret_name"
        else
            echo "⚠️  $secret_name not found in KeyChain"
        fi
    else
        echo "✅ Secret exists: $secret_name"
    fi
}

create_secret_if_needed "kieran@rossollc.com" "ANTHROPIC_API_KEY" "cipher-anthropic-api-key" "ANTHROPIC_API_KEY"
create_secret_if_needed "kieran@rossollc.com" "OPENAI_API_KEY" "cipher-openai-api-key" "OPENAI_API_KEY"
create_secret_if_needed "kieran@rossollc.com" "OPENROUTER_API_KEY" "cipher-openrouter-api-key" "OPENROUTER_API_KEY"
create_secret_if_needed "kieran@rossollc.com" "QWEN_API_KEY" "cipher-qwen-api-key" "QWEN_API_KEY"
create_secret_if_needed "kieran@rossollc.com" "VOYAGE_API_KEY" "cipher-voyage-api-key" "VOYAGE_API_KEY"
create_secret_if_needed "kieran@rossollc.com" "DEEPSEEK_API_KEY" "cipher-deepseek-api-key" "DEEPSEEK_API_KEY"

# Start Cipher with GCP configuration
echo "🏗️  Building and starting Cipher..."

cd "$(dirname "$0")/.."

# Build image
podman-compose build cipher-api

# Start with GCP configuration
podman-compose -f docker-compose.gcp.yml up -d

echo ""
echo "✅ Cipher started with Google Cloud ADC!"
echo ""
echo "📊 Check status:"
echo "  podman-compose -f docker-compose.gcp.yml ps"
echo ""
echo "📋 View logs:"
echo "  podman-compose -f docker-compose.gcp.yml logs -f cipher-api"
echo ""
echo "🧪 Test embeddings:"
echo "  The cipher_store_reasoning_memory tool should now be available via MCP"