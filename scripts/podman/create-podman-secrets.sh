#!/usr/bin/env bash
set -euo pipefail

# Idempotent, non-interactive bulk secret creation helper.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/podman/secret_utils.sh"

echo "🔐 Ensuring Podman secrets (idempotent, non-interactive)..."

# Helper to obtain a secret value from multiple sources non-interactively.
# Order: 1) env var passed explicitly as parameter OR env var named, 2) macOS keychain lookup (if available)
ensure_secret_from_sources() {
    local env_var_name="$1"  # env var to consult
    local account="$2"
    local service="$3"
    local secret_name="$4"

    local val=""
    # if explicit env var provided, use it
    if [ -n "${!env_var_name:-}" ]; then
        val="${!env_var_name}"
    else
        # try macOS keychain if available
        val=$(retrieve_from_keychain "$account" "$service" || true)
    fi

    if [ -z "${val:-}" ]; then
        echo "[skip] No value for $secret_name (env $env_var_name or keychain $service)" >&2
        return 0
    fi

    create_or_replace_secret_from_value "$secret_name" "$val"
}

# Map secrets to env vars + keychain/service names. On Jetson, set the env vars before running.
ensure_secret_from_sources GEMINI_API_KEY "kieran@rossollc.com" GEMINI_API_KEY cipher-gemini-api-key
ensure_secret_from_sources ANTHROPIC_API_KEY "kieran@rossollc.com" ANTHROPIC_API_KEY cipher-anthropic-api-key
ensure_secret_from_sources OPENAI_API_KEY "kieran@rossollc.com" OPENAI_API_KEY cipher-openai-api-key
ensure_secret_from_sources OPENROUTER_API_KEY "kieran@rossollc.com" OPENROUTER_API_KEY cipher-openrouter-api-key
ensure_secret_from_sources QWEN_API_KEY "kieran@rossollc.com" QWEN_API_KEY cipher-qwen-api-key
ensure_secret_from_sources VOYAGE_API_KEY "kieran@rossollc.com" VOYAGE_API_KEY cipher-voyage-api-key
ensure_secret_from_sources DEEPSEEK_API_KEY "kieran@rossollc.com" DEEPSEEK_API_KEY cipher-deepseek-api-key

echo ""
echo "✅ Podman secrets ensured"
echo ""
echo "📋 List created secrets:"
podman secret list | grep cipher || true