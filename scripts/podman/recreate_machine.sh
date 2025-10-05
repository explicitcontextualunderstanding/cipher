#!/usr/bin/env bash
set -euo pipefail

# Recreate a Podman machine with a minimal image to align client/server versions
# Usage: recreate_machine.sh [MACHINE_NAME] [IMAGE]
# Example: recreate_machine.sh podman-machine-default alpine:latest

MACHINE_NAME=${1:-podman-machine-default}
# By default, don't pass an --image to podman so Podman will use its
# built-in, supported VM image. If you want a custom VM, pass a path to a
# bootable QCOW2 file as the second argument. Container image tags like
# 'alpine:latest' are NOT valid VM disk images and will fail.
IMAGE=${2:-}

echo "Stopping Podman machine '${MACHINE_NAME}' if it exists..."
podman machine stop "${MACHINE_NAME}" || true

echo "Removing Podman machine '${MACHINE_NAME}' if it exists..."
podman machine rm -f "${MACHINE_NAME}" || true

echo "Initializing Podman machine '${MACHINE_NAME}' with image '${IMAGE}'..."

if [[ -z "${IMAGE}" ]]; then
	echo "No custom image provided — using Podman's default VM image."
	podman machine init "${MACHINE_NAME}"
else
	if [[ -f "${IMAGE}" ]] || [[ "${IMAGE}" =~ \.qcow2$ ]]; then
		echo "Using local QCOW2 image: ${IMAGE}"
		podman machine init --image "${IMAGE}" "${MACHINE_NAME}"
	else
		echo "ERROR: The provided image '${IMAGE}' is not a local QCOW2 file."
		echo "Provide a path to a bootable QCOW2 disk image, or omit the image"
		echo "argument to let Podman use its default VM image. Container tags"
		echo "(e.g. alpine:latest) are not valid VM images. See docs/PODMAN_MAINTENANCE.md"
		echo "for information on creating custom QCOW2 images."
		exit 1
	fi
fi

echo "Starting Podman machine '${MACHINE_NAME}'..."
podman machine start "${MACHINE_NAME}"

echo "Running an initial prune inside the machine to free space..."
podman machine ssh -- podman system prune --all --volumes --force || true

echo "Done. Podman machine '${MACHINE_NAME}' recreated and pruned."
