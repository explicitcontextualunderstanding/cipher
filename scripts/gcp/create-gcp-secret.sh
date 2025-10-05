#!/usr/bin/env bash
set -euo pipefail

ADC_FILE="${1:-$HOME/.config/gcloud/application_default_credentials.json}"
SECRET_NAME="cipher-gcp-adc"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/podman/secret_utils.sh"

echo "🔐 Ensuring Podman secret for GCP ADC: $SECRET_NAME"

if [ ! -f "$ADC_FILE" ]; then
    echo "❌ ADC file not found: $ADC_FILE" >&2
    exit 2
fi

create_or_replace_secret_from_file "$SECRET_NAME" "$ADC_FILE"

echo "✅ Podman secret ensured: $SECRET_NAME"

echo "📋 Secret details:"
podman secret inspect "$SECRET_NAME" || true

echo "🚀 Next step: ./scripts/start-cipher-with-gcp.sh"