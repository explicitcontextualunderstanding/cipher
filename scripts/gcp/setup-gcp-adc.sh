#!/bin/bash

# Setup Google Cloud Application Default Credentials for Cipher
# Usage: ./scripts/setup-gcp-adc.sh

set -e

echo "🔐 Setting up Google Cloud Application Default Credentials..."

# Check if gcloud is installed
if ! command -v gcloud &> /dev/null; then
    echo "❌ gcloud CLI not found. Please install Google Cloud SDK first."
    echo "Visit: https://cloud.google.com/sdk/docs/install"
    exit 1
fi

# Check if already authenticated
ADC_FILE="$HOME/.config/gcloud/application_default_credentials.json"

if [ -f "$ADC_FILE" ]; then
    echo "✅ ADC file already exists at $ADC_FILE"
    echo "Current account:"
    gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null || echo "No active account found"
else
    echo "🔑 Setting up Google Cloud authentication..."
    echo "This will open a browser for authentication."

    # Authenticate with gcloud
    gcloud auth application-default login

    echo "✅ Google Cloud authentication completed"
fi

# Verify ADC works
echo "🔍 Verifying ADC configuration..."
if [ -f "$ADC_FILE" ]; then
    echo "✅ ADC file exists: $ADC_FILE"
    echo "📁 File permissions: $(ls -la "$ADC_FILE" | cut -d' ' -f1)"
    echo "📊 File size: $(wc -c < "$ADC_FILE") bytes"
else
    echo "❌ ADC file not found after authentication"
    exit 1
fi

# List available projects
echo ""
echo "📋 Available Google Cloud projects:"
gcloud projects list --format="value(projectId)" | head -5

# Show current project
echo ""
echo "🎯 Current project:"
gcloud config list project --format="value(core.project)" 2>/dev/null || echo "No project set"

echo ""
echo "✅ Google Cloud ADC setup completed!"
echo ""
echo "🚀 Next steps:"
echo "1. Ensure your project has the Generative Language API enabled"
echo "2. Run: ./scripts/create-gcp-secret.sh"
echo "3. Start Cipher with: ./scripts/start-cipher-with-gcp.sh"