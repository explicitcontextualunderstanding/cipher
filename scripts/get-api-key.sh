#!/bin/bash

# Retrieve API key from macOS KeyChain
# Usage: ./scripts/get-api-key.sh google-api-key

SERVICE_NAME=$1

if [ -z "$SERVICE_NAME" ]; then
    echo "Usage: $0 <service-name>"
    echo "Example: $0 google-api-key"
    exit 1
fi

# Retrieve the API key from KeyChain
API_KEY=$(security find-generic-password \
    -a "$SERVICE_NAME" \
    -s "cipher-$SERVICE_NAME" \
    -w 2>/dev/null)

if [ -z "$API_KEY" ]; then
    echo "❌ API key not found for service: $SERVICE_NAME"
    echo "Run ./scripts/store-api-key.sh $SERVICE_NAME \"your-api-key\" first"
    exit 1
fi

echo "$API_KEY"