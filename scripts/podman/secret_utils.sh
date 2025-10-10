#!/usr/bin/env bash
set -euo pipefail

# Utility functions to help create Podman secrets idempotently and non-interactively.

STATE_DIR="$HOME/.local/share/cipher/secrets"
mkdir -p "$STATE_DIR"

# Detect podman binary reliably in non-login shells. Prefer PATH lookup but
# fall back to the common Homebrew location on macOS. Scripts should use
# "$PODMAN_BIN" when invoking Podman to avoid silent failures when PATH is
# different for non-interactive shells (for example when run by editors).
if command -v podman >/dev/null 2>&1; then
  PODMAN_BIN="$(command -v podman)"
elif [ -x "/opt/homebrew/bin/podman" ]; then
  PODMAN_BIN="/opt/homebrew/bin/podman"
else
  PODMAN_BIN=podman
fi

sha256_of_string() {
  local s="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    printf '%s' "$s" | sha256sum | awk '{print $1}'
  else
    # macOS fallback
    printf '%s' "$s" | shasum -a 256 | awk '{print $1}'
  fi
}

sha256_of_file() {
  local f="$1"
  if [ ! -f "$f" ]; then
    return 1
  fi
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$f" | awk '{print $1}'
  else
    shasum -a 256 "$f" | awk '{print $1}'
  fi
}

stored_hash_path() {
  local secret_name="$1"
  printf '%s/%s.sha256' "$STATE_DIR" "$secret_name"
}

read_stored_hash() {
  local secret_name="$1"
  local p
  p=$(stored_hash_path "$secret_name")
  if [ -f "$p" ]; then cat "$p"; fi
}

store_hash() {
  local secret_name="$1"; shift
  local h="$1"
  local p
  p=$(stored_hash_path "$secret_name")
  printf '%s' "$h" > "$p"
  chmod 600 "$p"
}

podman_secret_exists() {
  local secret_name="$1"
  "$PODMAN_BIN" secret inspect "$secret_name" >/dev/null 2>&1
}

create_or_replace_secret_from_file() {
  local secret_name="$1"
  local file_path="$2"
  local new_hash
  new_hash=$(sha256_of_file "$file_path") || return 1
  local stored
  stored=$(read_stored_hash "$secret_name" || true)
  if podman_secret_exists "$secret_name" && [ -n "$stored" ] && [ "$stored" = "$new_hash" ]; then
    echo "[skip] Podman secret '$secret_name' already exists and content unchanged"
    return 0
  fi
  if podman_secret_exists "$secret_name"; then
    echo "[replace] Podman secret '$secret_name' exists but content changed — replacing"
  "$PODMAN_BIN" secret rm "$secret_name" || true
  else
    echo "[create] Podman secret '$secret_name' does not exist — creating"
  fi
  "$PODMAN_BIN" secret create "$secret_name" "$file_path"
  store_hash "$secret_name" "$new_hash"
}

create_or_replace_secret_from_value() {
  local secret_name="$1"
  local value="$2"
  local tmpf
  tmpf=$(mktemp -t podman-secret-XXXXXX)
  printf '%s' "$value" > "$tmpf"
  chmod 600 "$tmpf"
  create_or_replace_secret_from_file "$secret_name" "$tmpf"
  rm -f "$tmpf"
}

retrieve_from_keychain() {
  # macOS only: attempt to read generic password from security(1)
  local account="$1" service="$2"
  if command -v security >/dev/null 2>&1; then
    security find-generic-password -a "$account" -s "$service" -w 2>/dev/null || true
  fi
}
