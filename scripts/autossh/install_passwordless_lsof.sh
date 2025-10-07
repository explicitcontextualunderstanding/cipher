#!/usr/bin/env bash
set -euo pipefail

# install_passwordless_lsof.sh
# Installs a minimal sudoers.d entry to allow the specified user to run lsof
# without a password. This enables non-interactive remote collection of
# listening port owner details during diagnostics.
#
# Usage (run on the remote Jetson as a user with sudo privileges):
#   sudo ./scripts/autossh/install_passwordless_lsof.sh <username>
# Example:
#   sudo ./scripts/autossh/install_passwordless_lsof.sh amazon1148

if [[ "$#" -lt 1 ]]; then
  echo "Usage: $0 <username>" >&2
  exit 2
fi

USERNAME="$1"

LSOF_PATH="$(command -v lsof || true)"
if [[ -z "$LSOF_PATH" ]]; then
  echo "ERROR: lsof not found on this system. Install lsof first (e.g. sudo apt install lsof)" >&2
  exit 1
fi

SUDOERS_FILE="/etc/sudoers.d/cipher-lsof"
TMPFILE="/tmp/cipher-lsof.sudo.tmp"

echo "Writing sudoers entry for user '$USERNAME' to allow running: $LSOF_PATH"

cat > "$TMPFILE" <<EOF
# Allow $USERNAME to run lsof without a password for diagnostics
$USERNAME ALL=(root) NOPASSWD: $LSOF_PATH
EOF

# Validate sudoers fragment
if visudo -cf "$TMPFILE" >/dev/null 2>&1; then
  sudo install -m 0440 "$TMPFILE" "$SUDOERS_FILE"
  rm -f "$TMPFILE"
  echo "Installed $SUDOERS_FILE (mode 0440). $USERNAME can now run: sudo $LSOF_PATH" >&2
  echo "Note: this change allows passwordless lsof only. Review sudoers entry for security." >&2
else
  echo "visudo validation failed for $TMPFILE; aborting." >&2
  rm -f "$TMPFILE"
  exit 1
fi

exit 0
