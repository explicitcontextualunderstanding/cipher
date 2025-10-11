#!/usr/bin/env bash
set -euo pipefail

# Wrapper to bring up the Cipher compose stack with Podman in a safe,
# repeatable way. Ensures required secrets exist (and can create
# non-secure placeholders for optional providers), then starts the stack
# with the minimal compose file and an optional override for extra providers.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Load helper (detects PODMAN_BIN)
source "$SCRIPT_DIR/secret_utils.sh"

# Defaults
CREATE_PLACEHOLDERS=false
INCLUDE_OPTIONAL=false
RECREATE=false
DO_BUILD=false
WAIT_SECONDS=60
CHECK_LISTENERS=false

usage() {
  cat <<'USAGE'
Usage: compose-up.sh [options]

Options:
  --create-placeholders   Create non-secure placeholder secrets for optional providers
  --include-optional      Include optional provider compose overrides when bringing stack up
  --recreate              Run compose down (remove orphan volumes) before starting
  --build                 Run a compose build for the configured compose files before starting
  --wait-seconds N        How long (seconds) to wait for a healthy HTTP /health (default: 60)
  --check-listeners       Show host listener state for ports 3000/3001 (may prompt for sudo)
  -h, --help              Show this help

Examples:
  # Ensure secrets (creates placeholders for missing optional providers) and start
  ./scripts/podman/compose-up.sh --create-placeholders --include-optional

  # Start only minimal stack and wait 30s for health
  ./scripts/podman/compose-up.sh --wait-seconds 30
USAGE
}

# Parse args
while [ "$#" -gt 0 ]; do
  case "$1" in
    --create-placeholders)
      CREATE_PLACEHOLDERS=true; shift ;;
    --include-optional)
      INCLUDE_OPTIONAL=true; shift ;;
    --recreate)
      RECREATE=true; shift ;;
    --build)
      DO_BUILD=true; shift ;;
    --wait-seconds)
      WAIT_SECONDS="$2"; shift 2 ;;
    --check-listeners)
      CHECK_LISTENERS=true; shift ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      echo "Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

cd "$REPO_ROOT"

echo "Using Podman binary: $PODMAN_BIN"

# Show machine / connection state for context
echo "Podman machines:"; "$PODMAN_BIN" machine ls || true
echo "Podman system connections:"; "$PODMAN_BIN" system connection list || true

# Ensure secrets exist
if [ "$CREATE_PLACEHOLDERS" = true ]; then
  echo "Ensuring secrets (with placeholders for missing optional providers)..."
  "$REPO_ROOT/scripts/podman/create-podman-secrets.sh" --create-placeholders
else
  echo "Ensuring secrets (non-interactive)..."
  "$REPO_ROOT/scripts/podman/create-podman-secrets.sh"
fi

# Compose files
COMPOSE_FILES=("$REPO_ROOT/docker-compose.podman-secrets.yml")
if [ "$INCLUDE_OPTIONAL" = true ]; then
  COMPOSE_FILES+=("$REPO_ROOT/docker-compose.podman-secrets-optional.yml")
fi

if [ "$RECREATE" = true ]; then
  echo "Recreating stack: bringing down existing stack (if any)"
  COMPOSE_ARGS=()
  for f in "${COMPOSE_FILES[@]}"; do
    COMPOSE_ARGS+=(-f "$f")
  done
  "$PODMAN_BIN" compose "${COMPOSE_ARGS[@]}" down -v || true
fi

# Bring up stack
echo "Bringing up stack: ${COMPOSE_FILES[*]}"
# Optionally build images for the selected compose files
if [ "$DO_BUILD" = true ]; then
  echo "Building images for: ${COMPOSE_FILES[*]}"
  BUILD_ARGS=()
  for f in "${COMPOSE_FILES[@]}"; do
    BUILD_ARGS+=(-f "$f")
  done
  "$PODMAN_BIN" compose "${BUILD_ARGS[@]}" build || echo "Warning: compose build failed" 
fi
# podman compose uses the external provider podman-compose under the hood on macOS in some installs
COMPOSE_ARGS=()
for f in "${COMPOSE_FILES[@]}"; do
  COMPOSE_ARGS+=(-f "$f")
done
"$PODMAN_BIN" compose "${COMPOSE_ARGS[@]}" up -d --remove-orphans

# Show containers
echo
echo "Containers:"
"$PODMAN_BIN" ps --format 'table {{.ID}}\t{{.Image}}\t{{.Names}}\t{{.Status}}\t{{.Ports}}' || true

# Wait for health
if [ "$WAIT_SECONDS" -gt 0 ]; then
  echo "Waiting up to $WAIT_SECONDS seconds for a healthy /health endpoint..."
  end=$((SECONDS + WAIT_SECONDS))
  HEALTH_OK=false
  while [ $SECONDS -lt $end ]; do
    # Try likely host ports in order
    for P in 3001 3000; do
      if curl -sS --max-time 3 "http://127.0.0.1:$P/health" >/dev/null 2>&1; then
        echo "Health check passed on http://127.0.0.1:$P/health"
        HEALTH_OK=true
        break 2
      fi
    done
    sleep 2
  done
  if [ "$HEALTH_OK" = false ]; then
    echo "Timed out waiting for health; inspect container logs with: $PODMAN_BIN logs -f <container>"
  fi
fi

# Optional: show host listeners
if [ "$CHECK_LISTENERS" = true ]; then
  echo "Host listeners for ports 3001 and 3000 (may prompt for sudo):"
  sudo lsof -nP -iTCP:3001 -sTCP:LISTEN || true
  sudo lsof -nP -iTCP:3000 -sTCP:LISTEN || true
fi

# Final status
echo
echo "Done. Use '$PODMAN_BIN' ps and '$PODMAN_BIN' logs -f <container> to inspect the stack."
