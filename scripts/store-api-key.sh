#!/bin/bash

# Store API key in macOS KeyChain securely
# Usage: ./scripts/store-api-key.sh google-api-key "your-google-api-key"

SERVICE_NAME=$1
API_KEY_VALUE=$2

if [ -z "$SERVICE_NAME" ] || [ -z "$API_KEY_VALUE" ]; then
    echo "Usage: $0 <service-name> <api-key>"
    echo "Example: $0 google-api-key your-google-api-key-here"
    exit 1
fi

# Check if key already exists
if security find-generic-password -a "$SERVICE_NAME" -s "cipher-$SERVICE_NAME" >/dev/null 2>&1; then
    echo "Key for $SERVICE_NAME already exists. Updating..."
    security delete-generic-password -a "$SERVICE_NAME" -s "cipher-$SERVICE_NAME"
fi

# Store the API key in KeyChain
security add-generic-password \
    -a "$SERVICE_NAME" \
    -s "cipher-$SERVICE_NAME" \
    -w "$API_KEY_VALUE" \
    -U \
    -j "API key for Cipher service: $SERVICE_NAME"

echo "✅ API key stored securely in macOS KeyChain"
echo "Service: $SERVICE_NAME"
echo "Account: cipher-$SERVICE_NAME"