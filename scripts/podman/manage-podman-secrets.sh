#!/bin/bash

# Manage Podman secrets for Cipher
# Usage: ./scripts/manage-podman-secrets.sh [create|delete|list|recreate]

set -e

COMMAND=${1:-"list"}

case "$COMMAND" in
  "create")
    echo "🔐 Creating Podman secrets from KeyChain..."
    ./scripts/create-podman-secrets.sh
    ;;

  "recreate")
    echo "🔄 Recreating Podman secrets..."
    echo "🗑️  Deleting existing secrets..."
    podman secret list | grep cipher | awk '{print $2}' | xargs -I {} podman secret rm {} 2>/dev/null || true
    echo "🔐 Creating new secrets..."
    ./scripts/create-podman-secrets.sh
    ;;

  "delete")
    echo "🗑️  Deleting Podman secrets..."
    podman secret list | grep cipher | awk '{print $2}' | xargs -I {} podman secret rm {} 2>/dev/null || true
    echo "✅ Secrets deleted"
    ;;

  "list")
    echo "📋 Current Podman secrets:"
    podman secret list | grep cipher || echo "No cipher secrets found"
    ;;

  *)
    echo "Usage: $0 [create|delete|list|recreate]"
    echo ""
    echo "Commands:"
    echo "  create   - Create secrets from KeyChain"
    echo "  delete   - Delete all cipher secrets"
    echo "  list     - List current cipher secrets"
    echo "  recreate - Delete and recreate all secrets"
    exit 1
    ;;
esac