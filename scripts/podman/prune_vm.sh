#!/usr/bin/env bash
set -euo pipefail

# Prune unused containers, images and volumes inside the Podman machine
# Usage: prune_vm.sh [MACHINE_NAME]
MACHINE_NAME=${1:-podman-machine-default}

echo "Pruning unused data inside Podman machine '${MACHINE_NAME}'..."
podman machine ssh -- podman system prune --all --volumes --force || true

echo "Also pruning unused images and caches on the host..."
podman system prune --all --volumes --force || true

echo "Done."
